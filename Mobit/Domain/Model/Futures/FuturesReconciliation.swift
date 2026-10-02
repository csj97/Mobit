import Foundation

struct FuturesFundingReceipt: Codable, Equatable {
  let event: FuturesFundingEvent
  let amount: Decimal
}

struct FuturesLiquidationRecord: Codable, Equatable {
  let intervalStart: Int64
  let intervalEndExclusive: Int64
  let witnessMarkPrice: Decimal
  let settledAt: Date
}

struct FuturesBoundaryFallback: Codable, Equatable {
  let start: Int64
  let endExclusive: Int64
}

struct FuturesReconciliationState: Codable, Equatable {
  let positionID: UUID
  var verifiedThrough: Int64
  var netFunding: Decimal
  var fundingReceipts: [FuturesFundingReceipt]
  var lastVerifiedMark: Decimal?
  var liquidation: FuturesLiquidationRecord?
  var entryCloseFallbacks: [FuturesBoundaryFallback]? = nil

  static func initial(for position: FuturesPosition) throws -> Self {
    Self(positionID: position.id, verifiedThrough: try milliseconds(position.order.executedAt),
         netFunding: 0, fundingReceipts: [], lastVerifiedMark: nil, liquidation: nil)
  }

  static func milliseconds(_ date: Date) throws -> Int64 {
    let milliseconds = date.timeIntervalSince1970 * 1000
    // Date의 이진 표현 오차로 정수 밀리초가 1ms 앞당겨지지 않게 한다.
    let nearest = milliseconds.rounded()
    let value = abs(milliseconds - nearest) < 0.001 ? nearest : milliseconds.rounded(.up)
    guard value.isFinite, value > 0, value <= 253_402_300_799_000 else {
      throw FuturesCalculationError.invalidTimestamp
    }
    return Int64(value)
  }
}

// 해당 범위의 모든 API 페이지를 조회한 자료만 전달한다. 미래 펀딩을 추정하지 않는다.
struct FuturesReplayBatch {
  let instrument: TradingInstrumentID
  let start: Int64
  let endExclusive: Int64
  let candles: [FuturesMarkCandle]
  let funding: [FuturesFundingEvent]
  var detailed: Bool = false
  var entryCloseFallback: Bool = false
}

enum FuturesReconciliationHold: String, Equatable {
  case ambiguousEntryCandle
  case ambiguousFundingOrder
  case currentInterval
  case missingHistory
  case staleQuote
  case revisionChanged
  case requestFailed
  case storageFailed
  case workLimit
  case unsupportedInstrument
}

struct FuturesReplayResult {
  let state: FuturesReconciliationState
  let hold: FuturesReconciliationHold?
}

enum FuturesReconciliationError: Error {
  case invalidHistory
  case invalidState
}

struct FuturesTransactionRecord: Equatable, Identifiable {
  enum Kind: String {
    case opening, addition, closing, liquidation
    var rank: Int {
      switch self { case .opening: return 0; case .addition: return 1; case .closing: return 2; case .liquidation: return 3 }
    }
  }

  let eventID: UUID
  var id: String { "\(kind.rawValue):\(eventID.uuidString)" }
  let positionID: UUID
  let kind: Kind
  let instrument: TradingInstrumentID
  let side: FuturesSide
  let leverage: Int
  let quantity: Decimal
  let intervalStart: Int64
  let intervalEndExclusive: Int64?
  let recordedAt: Date
  let price: Decimal
  let realizedPnL: Decimal?
}

struct FuturesAccountValuation: Equatable {
  let availableBalance: Decimal
  let reservedMargin: Decimal
  let unrealizedPnL: Decimal
  let realizedPnL: Decimal
  let totalEquity: Decimal
  let verifiedThrough: Int64?
  let requiresReconciliation: Bool
}

extension FuturesAccountSnapshot {
  // 청산과 검증 시점이 저장된 같은 스냅샷에서 내역·PNL을 파생해 중복 정산을 막는다.
  func transactionHistory(for account: TradingAccountID) throws -> [FuturesTransactionRecord] {
    var records: [FuturesTransactionRecord] = []
    for position in positions where position.order.account == account {
      guard let state = reconciliations.first(where: { $0.positionID == position.id }) else {
        throw FuturesReconciliationError.invalidState
      }
      try FuturesReplayCalculator.validate(state, position: position)
      let order = position.order
      for (index, execution) in position.executions.enumerated() {
        let fill = try FuturesCalculator.storedFill(execution)
        records.append(FuturesTransactionRecord(eventID: execution.requestID, positionID: position.id,
          kind: index == 0 ? .opening : .addition, instrument: order.instrument,
          side: order.side, leverage: order.leverage, quantity: fill.quantity,
          intervalStart: try FuturesReconciliationState.milliseconds(execution.executedAt), intervalEndExclusive: nil,
          recordedAt: execution.executedAt, price: execution.executionPrice, realizedPnL: nil))
      }
      if let closed = closedPositions.first(where: { $0.order.positionID == position.id }) {
        records.append(FuturesTransactionRecord(eventID: closed.order.requestID, positionID: position.id, kind: .closing,
          instrument: order.instrument, side: order.side, leverage: order.leverage, quantity: position.quantity,
          intervalStart: try FuturesReconciliationState.milliseconds(closed.order.executedAt), intervalEndExclusive: nil,
          recordedAt: closed.settledAt, price: closed.order.executionPrice, realizedPnL: closed.realizedPnL))
      }
      if let liquidation = state.liquidation {
        guard let price = try FuturesCalculator.estimatedLiquidationPrice(position, netFunding: state.netFunding) else {
          throw FuturesReconciliationError.invalidState
        }
        records.append(FuturesTransactionRecord(eventID: position.id, positionID: position.id, kind: .liquidation, instrument: order.instrument,
          side: order.side, leverage: order.leverage, quantity: position.quantity,
          intervalStart: liquidation.intervalStart, intervalEndExclusive: liquidation.intervalEndExclusive,
          recordedAt: liquidation.settledAt, price: price,
          realizedPnL: try FuturesDecimal.subtract(0, position.margin)))
      }
    }
    return records.sorted {
      if $0.intervalStart != $1.intervalStart { return $0.intervalStart < $1.intervalStart }
      if $0.positionID != $1.positionID { return $0.positionID.uuidString < $1.positionID.uuidString }
      if $0.kind != $1.kind { return $0.kind.rank < $1.kind.rank }
      return $0.id < $1.id
    }
  }

  func valuation(
	for account: TradingAccountID,
	quotes: [TradingInstrumentID: FuturesMarkQuote],
	now: Date,
	allowStaleQuotes: Bool = false
  ) throws -> FuturesAccountValuation {
    guard let cash = accounts.first(where: { $0.id == account }) else {
      throw FuturesCalculationError.invalidAccount
    }
    try FuturesDecimal.finite(cash.availableBalance)
    guard cash.availableBalance >= 0 else { throw FuturesCalculationError.invalidNumber }
    var reserved: Decimal = 0
    var unrealized: Decimal = 0
    var total = cash.availableBalance
    var verifiedThrough: Int64?
    var requiresReconciliation = false
    let timestamp = try FuturesReconciliationState.milliseconds(now)
    let history = try transactionHistory(for: account)
    let realized = try history.compactMap(\.realizedPnL).reduce(Decimal(0), FuturesDecimal.add)
    for position in positions where position.order.account == account {
      guard let state = reconciliations.first(where: { $0.positionID == position.id }) else {
        throw FuturesReconciliationError.invalidState
      }
      if !isActive(position) { continue }
      guard let quote = quotes[position.order.instrument], quote.instrument == position.order.instrument else {
        throw FuturesMarketDataError.incompleteHistory
      }
      guard quote.timestamp > 0, quote.timestamp <= timestamp, (allowStaleQuotes || quote.timestamp >= timestamp - 30_000) else {
        throw FuturesOrderPreflightError.staleQuote
      }
      let price = quote.price
      let value = try FuturesCalculator.evaluate(position, markPrice: price, netFunding: state.netFunding)
      reserved = try FuturesDecimal.add(reserved, position.margin)
      unrealized = try FuturesDecimal.add(unrealized, value.displayedPnL)
      requiresReconciliation = requiresReconciliation || state.verifiedThrough < quote.timestamp || value.shouldLiquidate
      // 평가값은 확정 정산이 아니다. UI는 함께 반환한 검증 시점을 확인한다.
      total = try FuturesDecimal.add(total, value.displayedEquity)
      verifiedThrough = min(verifiedThrough ?? state.verifiedThrough, state.verifiedThrough)
    }
    return FuturesAccountValuation(availableBalance: cash.availableBalance, reservedMargin: reserved,
      unrealizedPnL: unrealized, realizedPnL: realized, totalEquity: total, verifiedThrough: verifiedThrough, requiresReconciliation: requiresReconciliation)
  }
}
