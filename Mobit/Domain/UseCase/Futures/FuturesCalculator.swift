import Foundation

enum FuturesCalculator {
  static func open(_ order: FuturesOpeningOrder) throws -> FuturesPosition {
    try buildPosition(order, preservingStoredPosition: false)
  }

  private static func buildPosition(_ order: FuturesOpeningOrder, preservingStoredPosition: Bool) throws -> FuturesPosition {
    guard order.account.supports(order.instrument, preservingStoredPosition: preservingStoredPosition) else {
      throw FuturesCalculationError.invalidAccount
    }
    try FuturesDecimal.positive(order.margin)
    try FuturesDecimal.positive(order.executionPrice)
    try validateFeeRate(order.entryFeeRate)
    guard order.executedAt.timeIntervalSince1970.isFinite, order.executedAt.timeIntervalSince1970 > 0 else {
      throw FuturesCalculationError.invalidTimestamp
    }
    if !preservingStoredPosition, order.instrument.usesDomesticSpotPrice {
      guard order.entryFeeRate == 0 else { throw FuturesCalculationError.invalidContract }
      guard let maximum = order.instrument.maximumPaperLeverage, order.leverage <= maximum else {
        throw FuturesCalculationError.invalidLeverage
      }
    }
    let rules = order.contractRules
    guard rules.maximumLeverage >= 1, order.leverage >= 1, order.leverage <= rules.maximumLeverage else {
      throw FuturesCalculationError.invalidLeverage
    }
    guard !rules.quantityStep.isNaN, rules.quantityStep > 0,
          !rules.minimumQuantity.isNaN, rules.minimumQuantity > 0,
          !rules.minimumNotional.isNaN, rules.minimumNotional >= 0 else {
      throw FuturesCalculationError.invalidContract
    }
    let targetNotional = try FuturesDecimal.multiply(order.margin, Decimal(order.leverage))
    let stepNotional = try FuturesDecimal.multiply(order.executionPrice, rules.quantityStep)
    // 양수 계약 단위 수를 내림하여 순환소수 나눗셈이 주문 금액을 올리지 못하게 한다.
    var units = try FuturesDecimal.divide(targetNotional, stepNotional, rounding: .down)
    var wholeUnits = Decimal()
    NSDecimalRound(&wholeUnits, &units, 0, .down)
    let quantity = try FuturesDecimal.multiply(wholeUnits, rules.quantityStep)
    let notional = try FuturesDecimal.multiply(quantity, order.executionPrice)
    guard quantity > 0, quantity >= rules.minimumQuantity, notional >= rules.minimumNotional else {
      throw FuturesCalculationError.belowMinimumOrder
    }
    guard notional <= targetNotional else { throw FuturesCalculationError.arithmeticFailure }
    let entryFee = try FuturesDecimal.multiply(notional, order.entryFeeRate)
    guard try FuturesDecimal.subtract(order.margin, entryFee) > 0 else {
      throw FuturesCalculationError.insufficientCollateral
    }
    return FuturesPosition(order: order, quantity: quantity, entryNotional: notional,
                           entryFee: entryFee, ruleVersion: .simpleMarginV1)
  }

  static func storedFill(_ order: FuturesOpeningOrder) throws -> FuturesPosition {
    try buildPosition(order, preservingStoredPosition: true)
  }

  static func adding(_ order: FuturesOpeningOrder, to position: FuturesPosition) throws -> FuturesPosition {
    try validate(position)
    let added = try open(order)
    guard position.order.account == order.account, position.order.instrument == order.instrument,
          position.order.side == order.side, position.order.leverage == order.leverage,
          order.executedAt >= position.lastExecutionAt,
          !position.executions.contains(where: { $0.requestID == order.requestID }) else {
      throw FuturesCalculationError.inconsistentPosition
    }
    var result = FuturesPosition(order: position.order,
      quantity: try FuturesDecimal.add(position.quantity, added.quantity),
      entryNotional: try FuturesDecimal.add(position.entryNotional, added.entryNotional),
      entryFee: try FuturesDecimal.add(position.entryFee, added.entryFee), ruleVersion: position.ruleVersion)
    result.additionalOrders = (position.additionalOrders ?? []) + [order]
    try validate(result)
    return result
  }

  static func validate(_ position: FuturesPosition) throws {
    var quantity: Decimal = 0
    var notional: Decimal = 0
    var fee: Decimal = 0
    var previous = position.order.executedAt
    var identifiers = Set<UUID>()
    for order in position.executions {
      guard identifiers.insert(order.requestID).inserted, order.account == position.order.account,
            order.instrument == position.order.instrument, order.side == position.order.side,
            order.leverage == position.order.leverage, order.executedAt >= previous else {
        throw FuturesCalculationError.inconsistentPosition
      }
      let value = try buildPosition(order, preservingStoredPosition: true)
      quantity = try FuturesDecimal.add(quantity, value.quantity)
      notional = try FuturesDecimal.add(notional, value.entryNotional)
      fee = try FuturesDecimal.add(fee, value.entryFee)
      previous = order.executedAt
    }
    guard quantity == position.quantity, notional == position.entryNotional, fee == position.entryFee else {
      throw FuturesCalculationError.inconsistentPosition
    }
    _ = try position.margin
  }

  static func openingLedgerEntry(for position: FuturesPosition) throws -> FuturesLedgerEntry {
    try validate(position)
    guard position.executions.count == 1 else { throw FuturesCalculationError.inconsistentPosition }
    return FuturesLedgerEntry(id: position.id, positionID: position.id, account: position.order.account,
                              occurredAt: position.order.executedAt, kind: .open,
                              cashDelta: try FuturesDecimal.subtract(0, position.order.margin),
                              collateralDelta: try FuturesDecimal.subtract(position.order.margin, position.entryFee),
                              feePaid: position.entryFee)
  }

  static func evaluate(_ position: FuturesPosition, markPrice: Decimal, netFunding: Decimal = 0) throws -> FuturesValuation {
    try validate(position)
    try FuturesDecimal.positive(markPrice)
    let pnl = try tradingPnL(position, price: markPrice)
    try validateFunding(position, netFunding: netFunding)
    let collateral = try FuturesDecimal.subtract(FuturesDecimal.add(position.margin, netFunding), position.entryFee)
    let equity = try FuturesDecimal.add(collateral, pnl)
    let netPnL = try FuturesDecimal.subtract(equity, position.margin)
    let roe = try FuturesDecimal.multiply(FuturesDecimal.divide(netPnL, position.margin), 100)
    // 수익률 표시 반올림과 무관하게 실제 자본으로 청산 경계를 판단한다.
    return FuturesValuation(tradingPnL: pnl, collateral: collateral, equity: equity, netPnL: netPnL,
                            roePercent: roe, shouldLiquidate: equity <= 0)
  }

  static func estimatedLiquidationPrice(_ position: FuturesPosition, netFunding: Decimal = 0) throws -> Decimal? {
    try validate(position)
    try validateFunding(position, netFunding: netFunding)
    let collateral = try FuturesDecimal.subtract(FuturesDecimal.add(position.margin, netFunding), position.entryFee)
    let numerator = position.order.side == .long
      ? try FuturesDecimal.subtract(position.entryNotional, collateral)
      : try FuturesDecimal.add(position.entryNotional, collateral)
    let price = try FuturesDecimal.divide(numerator, position.quantity)
    return price > 0 ? price : nil
  }

  static func fundingPayment(_ position: FuturesPosition, markPrice: Decimal, rate: Decimal) throws -> Decimal {
    try validate(position)
    try FuturesDecimal.positive(markPrice)
    try FuturesDecimal.finite(rate)
    guard !position.order.instrument.usesDomesticSpotPrice || rate == 0 else {
      throw FuturesCalculationError.invalidContract
    }
    let payment = try FuturesDecimal.multiply(FuturesDecimal.multiply(position.quantity, markPrice), rate)
    return position.order.side == .long ? try FuturesDecimal.subtract(0, payment) : payment
  }

  // 과거 청산과 최신 Mark Price 검증은 W6에서 수행한 뒤 이 종료 견적을 사용한다.
  static func closingQuote(_ position: FuturesPosition, executionPrice: Decimal,
                           exitFeeRate: Decimal, netFunding: Decimal = 0) throws -> FuturesSettlementQuote {
    try validate(position)
    try FuturesDecimal.positive(executionPrice)
    try validateFeeRate(exitFeeRate)
    guard !position.order.instrument.usesDomesticSpotPrice || exitFeeRate == 0 else {
      throw FuturesCalculationError.invalidContract
    }
    let pnl = try tradingPnL(position, price: executionPrice)
    try validateFunding(position, netFunding: netFunding)
    let collateral = try FuturesDecimal.subtract(FuturesDecimal.add(position.margin, netFunding), position.entryFee)
    let equity = try FuturesDecimal.add(collateral, pnl)
    let requestedFee = try FuturesDecimal.multiply(FuturesDecimal.multiply(position.quantity, executionPrice), exitFeeRate)
    let available = max(Decimal(0), equity)
    let chargedFee = min(requestedFee, available)
    let returned = try FuturesDecimal.subtract(available, chargedFee)
    return FuturesSettlementQuote(tradingPnL: pnl, netFunding: netFunding, entryFee: position.entryFee,
                                  requestedExitFee: requestedFee, chargedExitFee: chargedFee,
                                  absorbedLoss: equity < 0 ? try FuturesDecimal.subtract(0, equity) : 0,
                                  returnedMargin: returned,
                                  realizedPnL: try FuturesDecimal.subtract(returned, position.margin))
  }

  static func liquidationQuote(_ position: FuturesPosition, markPrice: Decimal,
                               netFunding: Decimal = 0) throws -> FuturesSettlementQuote {
    let valuation = try evaluate(position, markPrice: markPrice, netFunding: netFunding)
    guard valuation.shouldLiquidate else { throw FuturesCalculationError.notLiquidatable }
    return FuturesSettlementQuote(tradingPnL: valuation.tradingPnL, netFunding: netFunding, entryFee: position.entryFee,
                                  requestedExitFee: 0, chargedExitFee: 0,
                                  absorbedLoss: try FuturesDecimal.subtract(0, valuation.equity), returnedMargin: 0,
                                  realizedPnL: try FuturesDecimal.subtract(0, position.margin))
  }

  private static func tradingPnL(_ position: FuturesPosition, price: Decimal) throws -> Decimal {
    let pnl = try FuturesDecimal.subtract(FuturesDecimal.multiply(position.quantity, price), position.entryNotional)
    return position.order.side == .long ? pnl : try FuturesDecimal.subtract(0, pnl)
  }

  private static func validateFunding(_ position: FuturesPosition, netFunding: Decimal) throws {
    try FuturesDecimal.finite(netFunding)
    // 국내 모의 펀딩 정책이 정해지기 전에는 해외 펀딩을 섞지 않는다.
    guard !position.order.instrument.usesDomesticSpotPrice || netFunding == 0 else {
      throw FuturesCalculationError.invalidContract
    }
  }

  private static func validateFeeRate(_ rate: Decimal) throws {
    guard !rate.isNaN, rate >= 0, rate < 1 else { throw FuturesCalculationError.invalidNumber }
  }
}

// 선물 계산과 원자 저장에서 같은 오류·정밀도 기준을 사용한다.
enum FuturesDecimal {
  private static let supportedExponent = -128...127

  static func finite(_ value: Decimal) throws {
    guard !value.isNaN else { throw FuturesCalculationError.invalidNumber }
  }

  static func positive(_ value: Decimal) throws {
    try finite(value)
    guard value > 0 else { throw FuturesCalculationError.invalidNumber }
  }

  static func add(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
    try calculate(lhs, rhs) { NSDecimalAdd(&$0, &$1, &$2, .plain) }
  }

  static func subtract(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
    try calculate(lhs, rhs) { NSDecimalSubtract(&$0, &$1, &$2, .plain) }
  }

  static func multiply(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
    // Foundation이 극단적인 지수 합을 정상 결과로 감싸는 경우를 연산 전에 차단한다.
    guard lhs == 0 || rhs == 0 || supportedExponent.contains(lhs.exponent + rhs.exponent) else {
      throw FuturesCalculationError.arithmeticFailure
    }
    return try calculate(lhs, rhs) { NSDecimalMultiply(&$0, &$1, &$2, .plain) }
  }

  static func divide(_ lhs: Decimal, _ rhs: Decimal, rounding: Decimal.RoundingMode = .plain) throws -> Decimal {
    guard !rhs.isNaN, rhs != 0 else { throw FuturesCalculationError.invalidNumber }
    guard lhs == 0 || supportedExponent.contains(lhs.exponent - rhs.exponent) else {
      throw FuturesCalculationError.arithmeticFailure
    }
    return try calculate(lhs, rhs, allowsRoundedDivision: true) { NSDecimalDivide(&$0, &$1, &$2, rounding) }
  }

  private static func calculate(_ lhs: Decimal, _ rhs: Decimal, allowsRoundedDivision: Bool = false,
                                operation: (inout Decimal, inout Decimal, inout Decimal) -> Decimal.CalculationError) throws -> Decimal {
    try finite(lhs)
    try finite(rhs)
    var lhs = lhs
    var rhs = rhs
    var result = Decimal()
    let error = operation(&result, &lhs, &rhs)
    guard error == .noError || (allowsRoundedDivision && error == .lossOfPrecision), !result.isNaN else {
      throw FuturesCalculationError.arithmeticFailure
    }
    return result
  }
}
