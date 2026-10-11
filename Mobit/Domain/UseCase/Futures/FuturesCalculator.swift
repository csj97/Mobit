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
      guard order.entryFeeRate == TradingRules.DomesticFutures.feeRate else { throw FuturesCalculationError.invalidContract }
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
          !rules.minimumOrderAmount.isNaN, rules.minimumOrderAmount >= 0 else {
      throw FuturesCalculationError.invalidContract
    }
    // 입력 증거금에 레버리지를 적용한 목표 거래금액이다.
    let targetTradeAmount = try FuturesDecimal.multiply(order.margin, Decimal(order.leverage))
    // 수량의 최소 증가 단위에 해당하는 거래금액이다.
    let tradeAmountPerStep = try FuturesDecimal.multiply(order.executionPrice, rules.quantityStep)
    // 양수 계약 단위 수를 내림하여 순환소수 나눗셈이 주문 금액을 올리지 못하게 한다.
    var units = try FuturesDecimal.divide(targetTradeAmount, tradeAmountPerStep, rounding: .down)
    var wholeUnits = Decimal()
    NSDecimalRound(&wholeUnits, &units, 0, .down)
    let quantity = try FuturesDecimal.multiply(wholeUnits, rules.quantityStep)
    // 수량을 최소 단위로 내림한 뒤의 실제 거래금액이다.
    let tradeAmount = try FuturesDecimal.multiply(quantity, order.executionPrice)
    guard quantity > 0, quantity >= rules.minimumQuantity, tradeAmount >= rules.minimumOrderAmount else {
      throw FuturesCalculationError.belowMinimumOrder
    }
    guard tradeAmount <= targetTradeAmount else { throw FuturesCalculationError.arithmeticFailure }
    let entryFee = try FuturesDecimal.multiply(tradeAmount, order.entryFeeRate)
    guard try FuturesDecimal.subtract(order.margin, entryFee) > 0 else {
      throw FuturesCalculationError.insufficientMargin
    }
    return FuturesPosition(order: order, quantity: quantity, entryTradeAmount: tradeAmount,
                           entryFee: entryFee, ruleVersion: .simpleMarginV1)
  }

  static func storedFill(_ order: FuturesOpeningOrder) throws -> FuturesPosition {
    try buildPosition(order, preservingStoredPosition: true)
  }

  static func adding(_ order: FuturesOpeningOrder, to position: FuturesPosition) throws -> FuturesPosition {
    try validate(position)
    // 추가 진입 전에 종료했던 시각과 겹치지 않아 저장 이력의 순서를 확정할 수 있다.
    guard order.executedAt >= position.lastExecutionAt,
      position.partialClosings?.last.map({ order.executedAt > $0.order.executedAt }) ?? true,
      !position.executions.contains(where: { $0.requestID == order.requestID }),
      !(position.partialClosings ?? []).contains(where: { $0.order.requestID == order.requestID })
    else { throw FuturesCalculationError.inconsistentPosition }
    // 기존 포지션에 합산할 이번 진입의 수량과 원가다.
    let result = try merge(try open(order), into: position)
    try validate(result)
    return result
  }

  private static func merge(_ added: FuturesPosition, into position: FuturesPosition) throws -> FuturesPosition {
    guard TradingRules.canCombine(added.order, with: position.order)
    else { throw FuturesCalculationError.inconsistentPosition }
    // 남은 원가에 신규 체결 원가만 더하고 이전 부분 종료 기록은 보존한다.
    var result = FuturesPosition(
      order: position.order,
      quantity: try FuturesDecimal.add(position.quantity, added.quantity),
      entryTradeAmount: try FuturesDecimal.add(position.entryTradeAmount, added.entryTradeAmount),
      entryFee: try FuturesDecimal.add(position.entryFee, added.entryFee),
      ruleVersion: position.ruleVersion
    )
    result.additionalOrders = (position.additionalOrders ?? []) + [added.order]
    result.partialClosings = position.partialClosings
    return result
  }

  static func validate(_ position: FuturesPosition) throws {
    // 진입·부분 종료를 시간순으로 재계산해 수량과 원금이 임의 변경되지 않았는지 확인한다.
    let openings = position.executions
    // 원금 반환과 실현 손익을 대조할 부분 종료 기록이다.
    let closings = position.partialClosings ?? []
    guard Set(openings.map(\.requestID) + closings.map { $0.order.requestID }).count == openings.count + closings.count,
      closings.isEmpty || TradingRules.Futures.allowsPartialClosing(for: position.order.instrument)
    else { throw FuturesCalculationError.inconsistentPosition }
    // 원래 진입 시각과 첫 체결은 종료 이후에도 유지한다.
    var rebuilt = try storedFill(position.order)
    // 다음 부분 종료 전에 합산해야 하는 추가 진입의 위치다.
    var openingIndex = 1
    // 같은 시각의 종료는 배열 순서대로 처리하고 진입은 종료보다 앞서야 한다.
    var previousClose = position.order.executedAt
    for closed in closings {
      _ = try FuturesHistoryCheckState.milliseconds(closed.order.executedAt)
      _ = try FuturesHistoryCheckState.milliseconds(closed.settledAt)
      guard closed.order.positionID == position.id, closed.order.executedAt >= previousClose,
        closed.settledAt >= closed.order.executedAt, let quantity = closed.order.quantity
      else { throw FuturesCalculationError.inconsistentPosition }
      while openingIndex < openings.count, openings[openingIndex].executedAt <= closed.order.executedAt {
        guard openings[openingIndex].executedAt >= rebuilt.lastExecutionAt,
          rebuilt.partialClosings?.last.map({ openings[openingIndex].executedAt > $0.order.executedAt }) ?? true
        else { throw FuturesCalculationError.inconsistentPosition }
        rebuilt = try merge(try storedFill(openings[openingIndex]), into: rebuilt)
        openingIndex += 1
      }
      guard closed.order.executedAt >= rebuilt.lastExecutionAt, quantity < rebuilt.quantity,
        closed.order.expectedQuantity == nil || closed.order.expectedQuantity == rebuilt.quantity
      else { throw FuturesCalculationError.inconsistentPosition }
      // 저장된 정산 금액은 해당 종료 직전 원가와 종료 시세로 재현할 수 있어야 한다.
      let quote = try makeClosingQuote(
        rebuilt,
        executionPrice: closed.order.executionPrice,
        exitFeeRate: TradingRules.Futures.closingFeeRate(for: rebuilt.order.instrument),
        netFunding: 0,
        quantity: quantity
      )
      guard quote.returnedMargin > 0, quote.returnedMargin == closed.returnedMargin,
        quote.realizedPnL == closed.realizedPnL
      else { throw FuturesCalculationError.inconsistentPosition }
      rebuilt = try reduce(rebuilt, closing: closed)
      previousClose = closed.order.executedAt
    }
    while openingIndex < openings.count {
      guard openings[openingIndex].executedAt >= rebuilt.lastExecutionAt,
        rebuilt.partialClosings?.last.map({ openings[openingIndex].executedAt > $0.order.executedAt }) ?? true
      else { throw FuturesCalculationError.inconsistentPosition }
      rebuilt = try merge(try storedFill(openings[openingIndex]), into: rebuilt)
      openingIndex += 1
    }
    guard rebuilt.quantity == position.quantity, rebuilt.entryTradeAmount == position.entryTradeAmount,
      rebuilt.entryFee == position.entryFee, position.ruleVersion == .simpleMarginV1
    else { throw FuturesCalculationError.inconsistentPosition }
    try FuturesDecimal.positive(position.margin)
  }

  // 종료 수량을 최소 단위로 내리되 전량 선택은 보유 수량을 정확히 보존한다.
  static func closingQuantity(_ proposed: Decimal, position: FuturesPosition) throws -> Decimal {
    try FuturesDecimal.finite(proposed)
    guard proposed > 0, proposed <= position.quantity else { throw FuturesCalculationError.invalidNumber }
    if proposed == position.quantity { return proposed }
    // 초과 체결을 막기 위해 종료 가능한 최소 수량 단위 수를 내린다.
    var units = try FuturesDecimal.divide(proposed, position.order.contractRules.quantityStep, rounding: .down)
    // 실제 체결 가능한 정수 단위 수다.
    var rounded = Decimal()
    NSDecimalRound(&rounded, &units, 0, .down)
    // 최소 단위에 맞춘 종료 수량이다.
    let quantity = try FuturesDecimal.multiply(rounded, position.order.contractRules.quantityStep)
    guard quantity > 0 else { throw FuturesCalculationError.invalidNumber }
    return quantity
  }

  // 종료 수량 비율만큼 원가를 배분하고 남은 값은 차감해 마지막 원금까지 보존한다.
  private static func portion(_ value: Decimal, quantity: Decimal, totalQuantity: Decimal) throws -> Decimal {
    if quantity == totalQuantity { return value }
    // 가격 8자리 × 수량 8자리 정밀도를 유지하고 배분 차액은 남은 포지션에 보존한다.
    var allocated = try FuturesDecimal.divide(FuturesDecimal.multiply(value, quantity), totalQuantity, rounding: .down)
    // 순환소수가 이후 잔액 연산의 정밀도 한도를 소진하지 않도록 확정한 몫이다.
    var result = Decimal()
    NSDecimalRound(&result, &allocated, 16, .down)
    return result
  }

  // 종료 화면과 실제 정산이 같은 원금 배분·반올림 기준을 사용한다.
  static func calculateClosingMargin(_ position: FuturesPosition, quantity: Decimal) throws -> Decimal {
    if quantity == 0 { return 0 }
    guard try closingQuantity(quantity, position: position) == quantity else {
      throw FuturesCalculationError.invalidNumber
    }
    return try portion(position.margin, quantity: quantity, totalQuantity: position.quantity)
  }

  static func reduce(_ position: FuturesPosition, closing: FuturesClosedPosition) throws -> FuturesPosition {
    guard let quantity = closing.order.quantity, quantity > 0, quantity < position.quantity else {
      throw FuturesCalculationError.invalidNumber
    }
    // 부분 종료 후에도 최초 진입과 원래 개별 체결 이력은 그대로 보존한다.
    var result = FuturesPosition(
      order: position.order,
      quantity: try FuturesDecimal.subtract(position.quantity, quantity),
      entryTradeAmount: try FuturesDecimal.subtract(position.entryTradeAmount, portion(position.entryTradeAmount, quantity: quantity, totalQuantity: position.quantity)),
      entryFee: try FuturesDecimal.subtract(position.entryFee, portion(position.entryFee, quantity: quantity, totalQuantity: position.quantity)),
      ruleVersion: position.ruleVersion
    )
    result.additionalOrders = position.additionalOrders
    result.partialClosings = (position.partialClosings ?? []) + [closing]
    return result
  }

  static func openingLedgerEntry(for position: FuturesPosition) throws -> FuturesLedgerEntry {
    try validate(position)
    guard position.executions.count == 1 else { throw FuturesCalculationError.inconsistentPosition }
    return FuturesLedgerEntry(id: position.id, positionID: position.id, account: position.order.account,
                              occurredAt: position.order.executedAt, kind: .open,
                              cashDelta: try FuturesDecimal.subtract(0, position.order.margin),
                              reservedMarginChange: try FuturesDecimal.subtract(position.order.margin, position.entryFee),
                              feePaid: position.entryFee)
  }

  static func evaluate(_ position: FuturesPosition, markPrice: Decimal, netFunding: Decimal = 0) throws -> FuturesValuation {
    try validate(position)
    try FuturesDecimal.positive(markPrice)
    let pnl = try tradingPnL(position, price: markPrice)
    try validateFunding(position, netFunding: netFunding)
    // 진입 증거금에 펀딩을 반영하고 진입 수수료를 뺀 금액으로, 가격 손익은 제외한다.
    let remainingMargin = try FuturesDecimal.subtract(FuturesDecimal.add(position.margin, netFunding), position.entryFee)
    let equity = try FuturesDecimal.add(remainingMargin, pnl)
    let netPnL = try FuturesDecimal.subtract(equity, position.margin)
    let roe = try FuturesDecimal.multiply(FuturesDecimal.divide(netPnL, position.margin), 100)
    // 수익률 표시 반올림과 무관하게 실제 자본으로 청산 경계를 판단한다.
    return FuturesValuation(
      tradingPnL: pnl,
      remainingMargin: remainingMargin,
      equity: equity,
      netPnL: netPnL,
      roePercent: roe,
      shouldLiquidate: TradingRules.liquidationRule(for: position.order.account.product).shouldLiquidate(remainingEquity: equity)
    )
  }

  static func estimatedLiquidationPrice(_ position: FuturesPosition, netFunding: Decimal = 0) throws -> Decimal? {
    try validate(position)
    try validateFunding(position, netFunding: netFunding)
    // 진입 증거금에 펀딩을 반영하고 진입 수수료를 뺀 금액으로, 가격 손익은 제외한다.
    let remainingMargin = try FuturesDecimal.subtract(FuturesDecimal.add(position.margin, netFunding), position.entryFee)
    let numerator = position.order.side == .long
      ? try FuturesDecimal.subtract(position.entryTradeAmount, remainingMargin)
      : try FuturesDecimal.add(position.entryTradeAmount, remainingMargin)
    let price = try FuturesDecimal.divide(numerator, position.quantity)
    return price > 0 ? price : nil
  }

  static func fundingPayment(_ position: FuturesPosition, markPrice: Decimal, rate: Decimal) throws -> Decimal {
    try validate(position)
    try FuturesDecimal.positive(markPrice)
    try FuturesDecimal.finite(rate)
    guard TradingRules.Futures.allowsFunding(for: position.order.instrument) || rate == TradingRules.DomesticFutures.fundingRate else {
      throw FuturesCalculationError.invalidContract
    }
    let payment = try FuturesDecimal.multiply(FuturesDecimal.multiply(position.quantity, markPrice), rate)
    return position.order.side == .long ? try FuturesDecimal.subtract(0, payment) : payment
  }

  // 과거 청산과 최신 시세 검증을 마친 뒤 종료할 수량만큼의 반환액을 계산한다.
  static func closingQuote(
    _ position: FuturesPosition,
    executionPrice: Decimal,
    exitFeeRate: Decimal,
    netFunding: Decimal = 0,
    quantity: Decimal? = nil
  ) throws -> FuturesSettlementQuote {
    try validate(position)
    return try makeClosingQuote(position, executionPrice: executionPrice, exitFeeRate: exitFeeRate, netFunding: netFunding, quantity: quantity ?? position.quantity)
  }

  private static func makeClosingQuote(
    _ position: FuturesPosition,
    executionPrice: Decimal,
    exitFeeRate: Decimal,
    netFunding: Decimal,
    quantity: Decimal
  ) throws -> FuturesSettlementQuote {
    try FuturesDecimal.positive(executionPrice)
    try validateFeeRate(exitFeeRate)
    try validateFunding(position, netFunding: netFunding)
    guard !position.order.instrument.usesDomesticSpotPrice || exitFeeRate == TradingRules.DomesticFutures.feeRate,
      quantity == position.quantity || (TradingRules.Futures.allowsPartialClosing(for: position.order.instrument)
        && exitFeeRate == TradingRules.Futures.closingFeeRate(for: position.order.instrument) && netFunding == 0),
      try closingQuantity(quantity, position: position) == quantity
    else { throw FuturesCalculationError.invalidContract }
    // 이번에 종료하는 수량에 배분할 진입 원금이다.
    let margin = try calculateClosingMargin(position, quantity: quantity)
    // 종료 수량에 배분할 진입 거래금액이다.
    let entryAmount = try portion(position.entryTradeAmount, quantity: quantity, totalQuantity: position.quantity)
    // 이미 낸 진입 수수료 중 종료 수량에 해당하는 몫이다.
    let entryFee = try portion(position.entryFee, quantity: quantity, totalQuantity: position.quantity)
    // 롱·숏에 따라 부호를 반영하기 전의 가격 차이 손익이다.
    let priceDifference = try FuturesDecimal.subtract(FuturesDecimal.multiply(quantity, executionPrice), entryAmount)
    // 종료 수량만의 가격 손익이다.
    let pnl = position.order.side == .long ? priceDifference : try FuturesDecimal.subtract(0, priceDifference)
    // 종료 시 반환할 증거금과 손익의 합계다.
    let equity = try FuturesDecimal.add(FuturesDecimal.subtract(FuturesDecimal.add(margin, netFunding), entryFee), pnl)
    // 정책에 따른 종료 수수료로, 국내 모의거래에서는 0이다.
    let requestedFee = try FuturesDecimal.multiply(FuturesDecimal.multiply(quantity, executionPrice), exitFeeRate)
    // 반환 가능한 금액보다 수수료를 더 차감하지 않는다.
    let available = max(Decimal(0), equity)
    // 실제로 차감할 종료 수수료다.
    let chargedFee = min(requestedFee, available)
    // 계좌 잔액으로 돌려줄 원금과 손익이다.
    let returned = try FuturesDecimal.subtract(available, chargedFee)
    return FuturesSettlementQuote(
      tradingPnL: pnl,
      netFunding: netFunding,
      entryFee: entryFee,
      requestedExitFee: requestedFee,
      chargedExitFee: chargedFee,
      absorbedLoss: equity < 0 ? try FuturesDecimal.subtract(0, equity) : 0,
      returnedMargin: returned,
      realizedPnL: try FuturesDecimal.subtract(returned, margin)
    )
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
    let pnl = try FuturesDecimal.subtract(FuturesDecimal.multiply(position.quantity, price), position.entryTradeAmount)
    return position.order.side == .long ? pnl : try FuturesDecimal.subtract(0, pnl)
  }

  private static func validateFunding(_ position: FuturesPosition, netFunding: Decimal) throws {
    try FuturesDecimal.finite(netFunding)
    // 국내 모의 펀딩 정책이 정해지기 전에는 해외 펀딩을 섞지 않는다.
    guard TradingRules.Futures.allowsFunding(for: position.order.instrument) || netFunding == 0 else {
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

// 종료 원금·수량·비율은 보유 원금 기준으로 변환하며 시세에 따라 바뀌지 않는다.
enum FuturesCloseSelection: Equatable {
  case percent(Int)
  case amount(Decimal)
  case quantity(Decimal)

  func calculateQuantity(position: FuturesPosition) throws -> Decimal {
    // 입력 방식을 실제 종료할 수량으로 변환한다.
    let proposed: Decimal
    switch self {
    case .percent(let percent):
      guard (0...100).contains(percent) else { throw FuturesCalculationError.invalidNumber }
      if percent == 0 { return 0 }
      if percent == 100 { return position.quantity }
      proposed = try FuturesDecimal.divide(FuturesDecimal.multiply(position.quantity, Decimal(percent)), 100)
    case .amount(let amount):
      try FuturesDecimal.finite(amount)
      guard amount >= 0 else { throw FuturesCalculationError.invalidNumber }
      if amount == 0 { return 0 }
      // 레버리지와 평가손익을 제외한 남은 원금으로 종료 비율을 결정한다.
      let total = try position.margin
      try FuturesDecimal.positive(total)
      guard amount <= total else { throw FuturesCalculationError.invalidNumber }
      if amount == total { return position.quantity }
      proposed = try FuturesDecimal.divide(FuturesDecimal.multiply(position.quantity, amount), total, rounding: .down)
    case .quantity(let quantity):
      if quantity == 0 { return 0 }
      proposed = quantity
    }
    return try FuturesCalculator.closingQuantity(proposed, position: position)
  }
}
