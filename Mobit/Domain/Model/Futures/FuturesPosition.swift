import Foundation

enum FuturesSide: String, Codable {
  case long
  case short
}

struct FuturesContractRules: Codable, Equatable {
  let maximumLeverage: Int
  let quantityStep: Decimal
  let minimumQuantity: Decimal
  let minimumNotional: Decimal
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
  let entryNotional: Decimal
  let entryFee: Decimal
  let ruleVersion: RuleVersion

  var additionalOrders: [FuturesOpeningOrder]? = nil
  var executions: [FuturesOpeningOrder] { [order] + (additionalOrders ?? []) }
  var margin: Decimal { get throws { try executions.map(\.margin).reduce(0, FuturesDecimal.add) } }
  var averageEntryPrice: Decimal { get throws { try FuturesDecimal.divide(entryNotional, quantity) } }
  var lastExecutionAt: Date { executions.last?.executedAt ?? order.executedAt }

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
  let collateralDelta: Decimal
  let feePaid: Decimal
}

struct FuturesValuation: Equatable {
  let tradingPnL: Decimal
  let collateral: Decimal
  let equity: Decimal
  let netPnL: Decimal
  let roePercent: Decimal
  let shouldLiquidate: Bool

  // 청산 근거의 원시 손실은 보존하되 표시 손실은 예약 증거금까지만 반영한다.
  var displayedEquity: Decimal { max(0, equity) }
  var displayedROEPercent: Decimal { max(-100, roePercent) }
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
  case insufficientCollateral
  case inconsistentPosition
  case arithmeticFailure
  case notLiquidatable
}

struct FuturesClosingOrder: Codable, Equatable {
  let requestID: UUID
  let positionID: UUID
  let executionPrice: Decimal
  let executedAt: Date
}

struct FuturesClosedPosition: Codable, Equatable {
  let order: FuturesClosingOrder
  let returnedMargin: Decimal
  let realizedPnL: Decimal
  let settledAt: Date
}
