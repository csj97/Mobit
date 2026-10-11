import Foundation

enum FuturesSide: String, Codable {
  case long
  case short
}

struct FuturesContractRules: Codable, Equatable {
  let maximumLeverage: Int
  let quantityStep: Decimal
  let minimumQuantity: Decimal
  // 주문에 필요한 최소 거래금액으로, 증거금과 구분한다.
  let minimumOrderAmount: Decimal

  private enum CodingKeys: String, CodingKey {
    case maximumLeverage, quantityStep, minimumQuantity
    case minimumOrderAmount = "minimumNotional"
  }
}

struct FuturesOpeningOrder: Codable, Equatable {
  let requestID: UUID
  let account: TradingAccountID
  let instrument: TradingInstrumentID
  let side: FuturesSide
  let margin: Decimal
  let leverage: Int
  let executionPrice: Decimal
  let entryFeeRate: Decimal
  let executedAt: Date
  let contractRules: FuturesContractRules
}

struct FuturesPosition: Codable, Equatable {
  enum RuleVersion: String, Codable {
    case simpleMarginV1
  }

  let order: FuturesOpeningOrder
  let quantity: Decimal
  // 남은 수량에 해당하는 진입 원가의 합계로, 부분 종료한 원가는 제외한다.
  let entryTradeAmount: Decimal
  let entryFee: Decimal
  let ruleVersion: RuleVersion

  var additionalOrders: [FuturesOpeningOrder]? = nil
  // 원래 진입 이력을 보존하면서 이미 종료한 수량과 정산 결과를 기록한다.
  var partialClosings: [FuturesClosedPosition]? = nil

  private enum CodingKeys: String, CodingKey {
    case order, quantity, entryFee, ruleVersion, additionalOrders, partialClosings
    case entryTradeAmount = "entryNotional"
  }

  var executions: [FuturesOpeningOrder] { [order] + (additionalOrders ?? []) }
  var margin: Decimal {
    get throws {
      // 전체 진입 증거금에서 부분 종료로 돌려준 원금을 제외한다.
      let openedMargin = try executions.map(\.margin).reduce(0, FuturesDecimal.add)
      return try (partialClosings ?? []).reduce(openedMargin) {
        try FuturesDecimal.subtract($0, FuturesDecimal.subtract($1.returnedMargin, $1.realizedPnL))
      }
    }
  }
  var averageEntryPrice: Decimal { get throws { try FuturesDecimal.divide(entryTradeAmount, quantity) } }
  var lastExecutionAt: Date {
    max(executions.last?.executedAt ?? order.executedAt, partialClosings?.last?.order.executedAt ?? order.executedAt)
  }

  var id: UUID { order.requestID }
  var leverageAtExecution: Int { order.leverage }
}

struct FuturesLedgerEntry: Codable, Equatable {
  enum Kind: String, Codable { case open, close }

  let id: UUID
  let positionID: UUID
  let account: TradingAccountID
  let occurredAt: Date
  let kind: Kind
  let cashDelta: Decimal
  // 체결 시 포지션에 묶이는 증거금의 증감액이다.
  let reservedMarginChange: Decimal
  let feePaid: Decimal

  private enum CodingKeys: String, CodingKey {
    case id, positionID, account, occurredAt, kind, cashDelta, feePaid
    case reservedMarginChange = "collateralDelta"
  }
}

struct FuturesValuation: Equatable {
  let tradingPnL: Decimal
  // 진입 증거금에 펀딩을 반영하고 진입 수수료를 뺀 금액으로, 가격 손익은 제외한다.
  let remainingMargin: Decimal
  let equity: Decimal
  let netPnL: Decimal
  let roePercent: Decimal
  let shouldLiquidate: Bool

  // 청산 근거의 원시 손실은 보존하되 표시 손실은 예약 증거금까지만 반영한다.
  var displayedEquity: Decimal { max(TradingRules.Futures.minimumDisplayedEquity, equity) }
  var displayedROEPercent: Decimal { max(TradingRules.Futures.minimumDisplayedReturnPercent, roePercent) }
  var displayedPnL: Decimal {
    get throws { try FuturesDecimal.subtract(displayedEquity, FuturesDecimal.subtract(equity, netPnL)) }
  }
}

struct FuturesSettlementQuote: Equatable {
  let tradingPnL: Decimal
  let netFunding: Decimal
  let entryFee: Decimal
  let requestedExitFee: Decimal
  let chargedExitFee: Decimal
  let absorbedLoss: Decimal
  let returnedMargin: Decimal
  let realizedPnL: Decimal
}

enum FuturesCalculationError: Error, Equatable {
  case invalidAccount
  case invalidNumber
  case invalidLeverage
  case invalidContract
  case invalidTimestamp
  case belowMinimumOrder
  // 주문에 필요한 증거금이나 수수료를 충당할 잔액이 부족하다.
  case insufficientMargin
  case inconsistentPosition
  case arithmeticFailure
  case notLiquidatable
}

struct FuturesClosingOrder: Codable, Equatable {
  let requestID: UUID
  let positionID: UUID
  let executionPrice: Decimal
  let executedAt: Date
  // nil인 기존 주문은 전량 종료하며, 값이 있으면 해당 수량만 종료한다.
  var quantity: Decimal? = nil
  // 사용자가 확인한 보유 수량으로, 주문 준비 중 포지션이 바뀌면 종료를 거절한다.
  var expectedQuantity: Decimal? = nil
}

struct FuturesClosedPosition: Codable, Equatable {
  let order: FuturesClosingOrder
  let returnedMargin: Decimal
  let realizedPnL: Decimal
  let settledAt: Date
}
