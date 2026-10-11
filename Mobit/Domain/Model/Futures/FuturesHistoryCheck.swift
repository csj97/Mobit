import Foundation

struct FuturesFundingReceipt: Codable, Equatable {
  let event: FuturesFundingEvent
  let amount: Decimal
}

struct FuturesLiquidationRecord: Codable, Equatable {
  let intervalStart: Int64
  let intervalEndExclusive: Int64
  // 청산을 확인한 과거 가격 또는 실시간 가격이다.
  let observedLiquidationPrice: Decimal
  let settledAt: Date
  var observedAt: Int64? = nil
  // 사용자에게 노출할 청산 발생 시각이며 초·밀리초는 저장하지 않는다.
  let occurredMinute: Int64

  init(
	intervalStart: Int64,
	intervalEndExclusive: Int64,
	observedLiquidationPrice: Decimal,
	settledAt: Date,
	observedAt: Int64? = nil
  ) {
	self.intervalStart = intervalStart
	self.intervalEndExclusive = intervalEndExclusive
	self.observedLiquidationPrice = observedLiquidationPrice
	self.settledAt = settledAt
	self.observedAt = observedAt
	// 실시간 청산은 수신 시각, 과거 청산은 최초 발생 구간을 분 단위로 보관한다.
	let occurrence = observedAt ?? intervalStart
	self.occurredMinute = occurrence - occurrence % 60_000
  }

  init(from decoder: Decoder) throws {
	// 기존 청산 기록에 분 단위 필드가 없어도 같은 발생 시각으로 복원한다.
	let values = try decoder.container(keyedBy: CodingKeys.self)
	intervalStart = try values.decode(Int64.self, forKey: .intervalStart)
	intervalEndExclusive = try values.decode(Int64.self, forKey: .intervalEndExclusive)
	observedLiquidationPrice = try values.decode(Decimal.self, forKey: .observedLiquidationPrice)
	settledAt = try values.decode(Date.self, forKey: .settledAt)
	observedAt = try values.decodeIfPresent(Int64.self, forKey: .observedAt)
	// 과거 앱이 저장한 청산도 초를 추정하지 않고 발생 분으로 표시한다.
	let occurrence = observedAt ?? intervalStart
	occurredMinute = try values.decodeIfPresent(Int64.self, forKey: .occurredMinute) ?? (occurrence - occurrence % 60_000)
  }

  private enum CodingKeys: String, CodingKey {
    case intervalStart, intervalEndExclusive, settledAt, observedAt, occurredMinute
    case observedLiquidationPrice = "witnessMarkPrice"
  }
}

struct FuturesBoundaryFallback: Codable, Equatable {
  let start: Int64
  let endExclusive: Int64
}

struct FuturesHistoryCheckState: Codable, Equatable {
  let positionID: UUID
  var verifiedThrough: Int64
  var netFunding: Decimal
  var fundingReceipts: [FuturesFundingReceipt]
  var lastVerifiedMark: Decimal?
  var liquidation: FuturesLiquidationRecord?
  var entryCloseFallbacks: [FuturesBoundaryFallback]? = nil

  static func initial(for position: FuturesPosition) throws -> Self {
	Self(
	  positionID: position.id,
	  verifiedThrough: try milliseconds(position.order.executedAt),
	  netFunding: 0,
	  fundingReceipts: [],
	  lastVerifiedMark: nil,
	  liquidation: nil
	)
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

enum FuturesHistoryCheckHold: String, Equatable {
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
  let state: FuturesHistoryCheckState
  let hold: FuturesHistoryCheckHold?
}

enum FuturesHistoryCheckError: Error {
  case invalidHistory
  case invalidState
}

struct FuturesTransactionRecord: Equatable, Identifiable {
  enum Kind: String {
	case opening, addition, closing, liquidation
	var rank: Int {
	  switch self {
	  case .opening: return 0;
	  case .addition: return 1;
	  case .closing: return 2;
	  case .liquidation: return 3
	  }
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
  // 부분 종료 손익률을 계산할 때 사용할 해당 종료 수량의 원금이다.
  var margin: Decimal? = nil
  // 이후 추가 진입과 무관하게 해당 종료 당시의 평균 진입가를 표시한다.
  var entryPrice: Decimal? = nil
  // 청산 내역의 표시·공유에 사용할 분 단위 발생 시각이다.
  var occurredMinute: Int64? = nil
}

struct FuturesAccountValuation: Equatable {
  let availableBalance: Decimal
  let reservedMargin: Decimal
  let unrealizedPnL: Decimal
  let realizedPnL: Decimal
  let totalEquity: Decimal
  // 주문가능 현금을 제외한 보유 포지션의 증거금과 평가손익 합계다.
  var positionsEquity: Decimal {
    get throws { try FuturesDecimal.add(reservedMargin, unrealizedPnL) }
  }
  let verifiedThrough: Int64?
  // 미검증 가격 구간이나 청산 가능성이 있어 추가 검증이 필요한지 나타낸다.
  let needsHistoryCheck: Bool
}

extension FuturesAccountSnapshot {
  // 청산과 검증 시점이 저장된 같은 스냅샷에서 내역·PNL을 파생해 중복 정산을 막는다.
  func transactionHistory(for account: TradingAccountID) throws -> [FuturesTransactionRecord] {
	var records: [FuturesTransactionRecord] = []
	for position in positions where position.order.account == account {
	  guard let state = historyCheckStates.first(where: { $0.positionID == position.id }) else {
		throw FuturesHistoryCheckError.invalidState
	  }
	  try FuturesReplayCalculator.validate(state, position: position)
	  let order = position.order
	  for (index, execution) in position.executions.enumerated() {
		let fill = try FuturesCalculator.storedFill(execution)
		records.append(
		  FuturesTransactionRecord(
			eventID: execution.requestID,
			positionID: position.id,
			kind: index == 0 ? .opening : .addition,
			instrument: order.instrument,
			side: order.side,
			leverage: order.leverage,
			quantity: fill.quantity,
			intervalStart: try FuturesHistoryCheckState.milliseconds(execution.executedAt),
			intervalEndExclusive: nil,
			recordedAt: execution.executedAt,
			price: execution.executionPrice,
			realizedPnL: nil
		  )
		)
	  }
	  if let closed = closedPositions.first(where: { $0.order.positionID == position.id }) {
		records.append(
		  FuturesTransactionRecord(
			eventID: closed.order.requestID,
			positionID: position.id,
			kind: .closing,
			instrument: order.instrument,
			side: order.side,
			leverage: order.leverage,
			quantity: position.quantity,
			intervalStart: try FuturesHistoryCheckState.milliseconds(closed.order.executedAt),
			intervalEndExclusive: nil,
			recordedAt: closed.settledAt,
			price: closed.order.executionPrice,
			realizedPnL: closed.realizedPnL
		  )
		)
	  }
      for closed in position.partialClosings ?? [] {
        guard let quantity = closed.order.quantity else { throw FuturesHistoryCheckError.invalidState }
        // 부분 종료의 실현 손익으로 당시 수량의 평균 진입가를 복원한다.
        let priceChange = try FuturesDecimal.divide(closed.realizedPnL, quantity)
        records.append(
          FuturesTransactionRecord(
            eventID: closed.order.requestID,
            positionID: position.id,
            kind: .closing,
            instrument: order.instrument,
            side: order.side,
            leverage: order.leverage,
            quantity: quantity,
            intervalStart: try FuturesHistoryCheckState.milliseconds(closed.order.executedAt),
            intervalEndExclusive: nil,
            recordedAt: closed.settledAt,
            price: closed.order.executionPrice,
            realizedPnL: closed.realizedPnL,
            margin: try FuturesDecimal.subtract(closed.returnedMargin, closed.realizedPnL),
            entryPrice: try order.side == .long
              ? FuturesDecimal.subtract(closed.order.executionPrice, priceChange)
              : FuturesDecimal.add(closed.order.executionPrice, priceChange)
          )
        )
      }
	  if let liquidation = state.liquidation {
		guard let price = try FuturesCalculator.estimatedLiquidationPrice(position, netFunding: state.netFunding) else {
		  throw FuturesHistoryCheckError.invalidState
		}
		records.append(
		  FuturesTransactionRecord(
			eventID: position.id,
			positionID: position.id,
			kind: .liquidation,
			instrument: order.instrument,
			side: order.side,
			leverage: order.leverage,
			quantity: position.quantity,
			intervalStart: liquidation.intervalStart,
			intervalEndExclusive: liquidation.intervalEndExclusive,
			recordedAt: liquidation.settledAt,
			price: price,
			realizedPnL: try FuturesDecimal.subtract(0, position.margin),
			occurredMinute: liquidation.occurredMinute
		  )
		)
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
	// 평가 표시는 수신 가격을 사용하되, 정산용 계산은 가격 시각까지 검증한다.
	forDisplay: Bool = false
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
	// 미검증 가격 구간이나 청산 가능성이 있어 추가 검증이 필요한지 나타낸다.
	var needsHistoryCheck = false
	let timestamp = try FuturesHistoryCheckState.milliseconds(now)
	let history = try transactionHistory(for: account)
	let realized = try history.compactMap(\.realizedPnL).reduce(Decimal(0), FuturesDecimal.add)
	for position in positions where position.order.account == account {
	  guard let state = historyCheckStates.first(where: { $0.positionID == position.id }) else {
		throw FuturesHistoryCheckError.invalidState
	  }
	  if !isActive(position) { continue }
	  guard let quote = quotes[position.order.instrument], quote.instrument == position.order.instrument else {
		throw FuturesMarketDataError.incompleteHistory
	  }
	  guard forDisplay || (quote.timestamp > 0 && quote.timestamp <= timestamp
		&& quote.timestamp >= timestamp - TradingRules.Futures.HistoryCheck.quoteMaximumAgeMilliseconds)
	  else {
		throw FuturesOrderCheckError.staleQuote
	  }
	  let price = quote.price
	  let value = try FuturesCalculator.evaluate(position, markPrice: price, netFunding: state.netFunding)
	  reserved = try FuturesDecimal.add(reserved, position.margin)
	  unrealized = try FuturesDecimal.add(unrealized, value.displayedPnL)
	  needsHistoryCheck =
		needsHistoryCheck || state.verifiedThrough < quote.timestamp || value.shouldLiquidate
	  // 평가값은 확정 정산이 아니다. UI는 함께 반환한 검증 시점을 확인한다.
	  total = try FuturesDecimal.add(total, value.displayedEquity)
	  verifiedThrough = min(verifiedThrough ?? state.verifiedThrough, state.verifiedThrough)
	}
	return FuturesAccountValuation(
	  availableBalance: cash.availableBalance,
	  reservedMargin: reserved,
	  unrealizedPnL: unrealized,
	  realizedPnL: realized,
	  totalEquity: total,
	  verifiedThrough: verifiedThrough,
	  needsHistoryCheck: needsHistoryCheck
	)
  }
}
