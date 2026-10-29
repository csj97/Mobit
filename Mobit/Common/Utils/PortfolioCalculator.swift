//
//  PortfolioCalculator.swift
//  Mobit
//
//  Created by 조성재 on 6/29/26.
//

import Foundation

enum PortfolioCalculator {
  /// 수량 비교 허용 오차. 소수점 아래가 잘린 입력값 때문에 생기는 미세 잔량을 보유로 취급하지 않기 위한 기준이다.
  static let quantityTolerance = TradingRules.Spot.quantityTolerance

  static func executedAmount(
    price: Double,
    quantity: Double,
    currency: SettlementCurrency = .krw
  ) -> Double {
    guard let decimalPrice = arithmeticDecimal(price),
          let decimalQuantity = arithmeticDecimal(quantity) else {
      return (price * quantity).formatDigits(digits: currency.amountFractionDigits)
    }
    // 부동소수 곱셈 오차로 결제 금액이 한 단위 더 절삭되지 않게 한다.
    let amount = decimalPrice * decimalQuantity
    guard !amount.isNaN else { return (price * quantity).formatDigits(digits: currency.amountFractionDigits) }
    return double(roundDown(amount, digits: currency.amountFractionDigits))
  }

  /// 매도 대금으로 받은 결제 자산의 취득원가를 가중평균으로 갱신한다.
  static func weightedAverageBuyPrice(
    previousQuantity: Double,
    previousAveragePrice: Double,
    addedQuantity: Double,
    addedPrice: Double
  ) -> Double {
    guard let previousQuantityDecimal = arithmeticDecimal(previousQuantity),
          let previousPriceDecimal = arithmeticDecimal(previousAveragePrice),
          let addedQuantityDecimal = arithmeticDecimal(addedQuantity),
          let addedPriceDecimal = arithmeticDecimal(addedPrice) else {
      let totalQuantity = previousQuantity + addedQuantity
      guard totalQuantity > 0 else { return addedPrice }
      return ((previousQuantity * previousAveragePrice) + (addedQuantity * addedPrice)) / totalQuantity
    }
    // 기존 보유분과 추가 체결분의 원가를 같은 십진수 기준으로 합산한다.
    let totalQuantity = previousQuantityDecimal + addedQuantityDecimal
    guard totalQuantity > 0 else { return addedPrice }
    // 가중평균 중간값을 십진수로 유지하고 저장 경계에서만 Double로 변환한다.
    let totalAmount = previousQuantityDecimal * previousPriceDecimal + addedQuantityDecimal * addedPriceDecimal
    let average = totalAmount / totalQuantity
    guard !average.isNaN else {
      let fallbackQuantity = previousQuantity + addedQuantity
      guard fallbackQuantity > 0 else { return addedPrice }
      return ((previousQuantity * previousAveragePrice) + (addedQuantity * addedPrice)) / fallbackQuantity
    }
    return double(average)
  }

  static func isFullySold(holdingQuantity: Double, sellQuantity: Double) -> Bool {
    decimal(holdingQuantity) - decimal(sellQuantity) < decimal(quantityTolerance)
  }

  static func cumulativeHoldingQuantity(
    previousQuantity: Double,
    newQuantity: Double
  ) -> Double {
    guard let previous = finiteDecimal(previousQuantity), let added = finiteDecimal(newQuantity) else {
      return previousQuantity + newQuantity
    }
    // 추가 진입을 반복해도 이진 부동소수 덧셈 오차가 수량에 누적되지 않게 한다.
    let quantity = previous + added
    return quantity.isNaN ? previousQuantity + newQuantity : double(quantity)
  }

  static func cumulativeBuyAmount(
    previousBuyAmount: Double,
    price: Double,
    quantity: Double,
    currency: SettlementCurrency = .krw
  ) -> Double {
    // 체결별 결제 통화 절삭 규칙은 기존과 같이 합산 전에 적용한다.
    let amount = executedAmount(
      price: price,
      quantity: quantity,
      currency: currency
    )
    guard let previous = finiteDecimal(previousBuyAmount), let added = finiteDecimal(amount) else {
      return previousBuyAmount + amount
    }
    // 체결별 매수금액의 합산은 십진수로 유지한다.
    let total = previous + added
    return total.isNaN ? previousBuyAmount + amount : double(total)
  }

  static func profitRate(
    currentPrice: Double,
    averageBuyPrice: Double
  ) -> Double {
    guard averageBuyPrice != 0 else { return 0 }
    guard let price = arithmeticDecimal(currentPrice), let average = arithmeticDecimal(averageBuyPrice) else {
      return (((currentPrice - averageBuyPrice) / averageBuyPrice) * 100).formatDigits(digits: TradingRules.Spot.profitRateFractionDigits)
    }
    // 음수 수익률도 기존 내림 정책을 유지하면서 십진수로 계산한다.
    let rate = (price - average) / average * 100
    guard !rate.isNaN else { return (((currentPrice - averageBuyPrice) / averageBuyPrice) * 100).formatDigits(digits: TradingRules.Spot.profitRateFractionDigits) }
    return double(roundDown(rate, digits: TradingRules.Spot.profitRateFractionDigits))
  }

  static func evaluationPrice(
    currentPrice: Double,
    holdingQuantity: Double
  ) -> Double {
    guard holdingQuantity >= 0 else { return 0 }
    guard let price = arithmeticDecimal(currentPrice), let quantity = arithmeticDecimal(holdingQuantity) else {
      return (currentPrice * holdingQuantity).formatDigits(digits: TradingRules.Spot.evaluationFractionDigits)
    }
    // 평가금액도 기존 소수점 절삭 전에 십진수로 곱한다.
    let amount = price * quantity
    guard !amount.isNaN else { return (currentPrice * holdingQuantity).formatDigits(digits: TradingRules.Spot.evaluationFractionDigits) }
    return double(roundDown(amount, digits: TradingRules.Spot.evaluationFractionDigits))
  }

  static func evaluationProfitLoss(
    currentPrice: Double,
    holdingQuantity: Double,
    averageBuyPrice: Double
  ) -> Double {
    guard let price = arithmeticDecimal(currentPrice), let average = arithmeticDecimal(averageBuyPrice),
          let quantity = arithmeticDecimal(holdingQuantity) else {
      return (currentPrice - averageBuyPrice) * holdingQuantity
    }
    // 평단과 현재가의 차이를 먼저 십진수로 계산한다.
    let profitLoss = (price - average) * quantity
    return profitLoss.isNaN ? (currentPrice - averageBuyPrice) * holdingQuantity : double(profitLoss)
  }

  static func realizedProfitLoss(
    entryPrice: Double,
    exitPrice: Double,
    quantity: Double
  ) -> Double {
    guard let entry = arithmeticDecimal(entryPrice), let exit = arithmeticDecimal(exitPrice),
          let quantityDecimal = arithmeticDecimal(quantity) else {
      return (exitPrice - entryPrice) * quantity
    }
    // 현물 거래 손익의 차감과 곱셈을 십진수로 계산한다.
    let profitLoss = (exit - entry) * quantityDecimal
    return profitLoss.isNaN ? (exitPrice - entryPrice) * quantity : double(profitLoss)
  }

  /// 결제 통화 금액을 원화로 환산한다.
  /// BTC 환산에 필요한 시세가 없으면 nil을 돌려 '0원'과 '환산 불가'를 구분하게 한다.
  static func krwValue(
    amount: Double,
    currency: SettlementCurrency,
    btcKRWPrice: Double?
  ) -> Double? {
    switch currency {
    case .krw:
      return amount

    case .btc:
      guard let btcKRWPrice, btcKRWPrice.isFinite, btcKRWPrice > 0 else { return nil }
      guard let decimalAmount = arithmeticDecimal(amount), let rate = arithmeticDecimal(btcKRWPrice) else {
        return amount * btcKRWPrice
      }
      // BTC 금액을 체결 기준 원화 시세로 환산한다.
      let value = decimalAmount * rate
      return value.isNaN ? amount * btcKRWPrice : double(value)
    }
  }

  struct Valuation {
    let costBasisKRW: Decimal?
    let evaluationKRW: Decimal?
    let profitLossKRW: Decimal?
    let profitRate: Double?
    let averagePriceKRW: Decimal?
  }

  static func decimal(_ value: Double) -> Decimal {
    Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) ?? .nan
  }

  static func double(_ value: Decimal) -> Double {
    // 십진수 문자열에서 가장 가까운 Double로 반올림한다.
    let number = NSDecimalNumber(decimal: value)
    return Double(number.stringValue) ?? number.doubleValue
  }

  private static func finiteDecimal(_ value: Double) -> Decimal? {
    guard value.isFinite else { return nil }
    // 십진수가 표현할 수 없는 기존 값은 호출자가 기존 Double 경로로 처리한다.
    let converted = decimal(value)
    return converted.isNaN ? nil : converted
  }

  private static func arithmeticDecimal(_ value: Double) -> Decimal? {
    // 극단 지수의 Decimal 곱셈은 Foundation에서 오류 없이 잘못된 값을 반환할 수 있다.
    guard value == 0 || (abs(value) >= 1e-20 && abs(value) <= 1e20) else { return nil }
    return finiteDecimal(value)
  }

  private static func roundDown(_ value: Decimal, digits: Int) -> Decimal {
    // 음수에도 기존 floor와 같은 내림 방향을 적용한다.
    var source = value
    // 지정된 자릿수에서 내림한 결과다.
    var rounded = Decimal()
    NSDecimalRound(&rounded, &source, digits, .down)
    return rounded
  }

  static func costBasisKRW(of data: CryptoTransactionDataModel.CryptoTransactionStaticData) -> Decimal? {
    if let cost = data.costBasisKRW {
      return cost.isNaN || cost < 0 ? nil : cost
    }
    // 구형 BTC 원가는 체결 환율을 알 수 없으므로 현재 환율로 복원하지 않는다.
    guard ExchangeMarketCodeConverter.settlementCurrency(
      fromDisplayMarket: data.marketName, exchange: data.exchange
    ) == .krw, data.buyAmount.isFinite, data.buyAmount >= 0 else { return nil }
    return decimal(data.buyAmount)
  }

  static func valuation(
    of crypto: CryptoTransactionDataModel,
    btcKRWPrice: Double?
  ) -> Valuation {
    valuation(of: crypto, quoteKRWPrices: btcKRWPrice.map { ["BTC": $0] } ?? [:])
  }

  static func valuation(
    of crypto: CryptoTransactionDataModel,
    quoteKRWPrices: [String: Double]
  ) -> Valuation {
    let data = crypto.staticData
    let rawMarket = ExchangeMarketCodeConverter.rawMarketCode(
      fromDisplayMarket: data.marketName, exchange: data.exchange
    )
    let market = ExchangeMarketCodeConverter.displayMarket(
      fromRawMarketCode: rawMarket, exchange: data.exchange
    )
    let components = market.split(separator: "/")
    let quote = components.count == 2 ? String(components[1]).uppercased() : ""
    let rate = quote == "KRW" ? 1 : quoteKRWPrices[quote]
    let cost = costBasisKRW(of: data)
    let evaluation: Decimal? = {
      // 구버전 BTC 마켓은 BTC 가격을 원화처럼 계산했으므로 정산 전까지 기존 표시 금액을 유지한다.
      if quote == SettlementCurrency.btc.rawValue,
         data.costBasisKRW == nil,
         crypto.dynamicData.evaluationPrice.isFinite,
         crypto.dynamicData.evaluationPrice >= 0 {
        return decimal(crypto.dynamicData.evaluationPrice)
      }
      guard let rate, rate.isFinite, rate > 0,
            crypto.dynamicData.evaluationPrice.isFinite,
            crypto.dynamicData.evaluationPrice >= 0 else { return nil }
      // 지수 합이 범위를 벗어나면 Foundation 곱셈 결과가 잘못될 수 있다.
      guard let amount = finiteDecimal(crypto.dynamicData.evaluationPrice), let decimalRate = finiteDecimal(rate) else { return nil }
      if amount != 0, decimalRate != 0, amount.exponent + decimalRate.exponent < -128 {
        return finiteDecimal(crypto.dynamicData.evaluationPrice * rate)
      }
      // 환산 결과를 표시할 수 없는 경우에는 알 수 없는 금액으로 처리한다.
      let converted = amount * decimalRate
      return converted.isNaN ? nil : converted
    }()
    let profit = evaluation.flatMap { value in cost.map { value - $0 } }
    return Valuation(
      costBasisKRW: cost,
      evaluationKRW: evaluation,
      profitLossKRW: profit,
      profitRate: cost.flatMap { cost in
        guard cost > 0, let profit else { return nil }
        return double(profit / cost * 100)
      },
      averagePriceKRW: cost.flatMap { cost in
        guard data.holdingQuantity.isFinite, data.holdingQuantity > 0 else { return nil }
        return cost / decimal(data.holdingQuantity)
      }
    )
  }

  private static func total(
    cryptos: [CryptoTransactionDataModel],
    btcKRWPrice: Double?,
    value: (Valuation) -> Decimal?
  ) -> Decimal? {
    var sum: Decimal = 0
    for crypto in cryptos {
      guard let amount = value(valuation(of: crypto, btcKRWPrice: btcKRWPrice)),
            !amount.isNaN else { return nil }
      sum += amount
    }
    return sum.isNaN ? nil : sum
  }

  static func orderedBefore(_ lhs: Double?, _ rhs: Double?, ascending: Bool) -> Bool {
    switch (lhs, rhs) {
    case let (left?, right?): return ascending ? left < right : left > right
    case (_?, nil): return true
    default: return false
    }
  }

  static func totalAssetValueDecimal(
    availableBalance: Double,
    cryptos: [CryptoTransactionDataModel],
    btcKRWPrice: Double?
  ) -> Decimal? {
    guard let balance = finiteDecimal(availableBalance),
          let evaluation = totalEvaluationPriceDecimal(cryptos: cryptos, btcKRWPrice: btcKRWPrice) else { return nil }
    // 평가금액과 주문가능 잔고는 표시 직전까지 십진수로 합산한다.
    let total = balance + evaluation
    return total.isNaN ? nil : total
  }

  static func totalAssetValue(
    availableBalance: Double,
    cryptos: [CryptoTransactionDataModel],
    btcKRWPrice: Double?
  ) -> Double? {
    if let total = totalAssetValueDecimal(
      availableBalance: availableBalance,
      cryptos: cryptos,
      btcKRWPrice: btcKRWPrice
    ) { return double(total) }
    guard let evaluation = totalEvaluationPrice(cryptos: cryptos, btcKRWPrice: btcKRWPrice) else { return nil }
    return availableBalance + evaluation
  }

  static func totalEvaluationProfitLossDecimal(
    cryptos: [CryptoTransactionDataModel],
    btcKRWPrice: Double?
  ) -> Decimal? {
    total(cryptos: cryptos, btcKRWPrice: btcKRWPrice) { $0.profitLossKRW }
  }

  static func totalEvaluationProfitLoss(
    cryptos: [CryptoTransactionDataModel],
    btcKRWPrice: Double?
  ) -> Double? {
    totalEvaluationProfitLossDecimal(cryptos: cryptos, btcKRWPrice: btcKRWPrice).map(double)
  }

  static func totalEvaluationPriceDecimal(
    cryptos: [CryptoTransactionDataModel],
    btcKRWPrice: Double?
  ) -> Decimal? {
    total(cryptos: cryptos, btcKRWPrice: btcKRWPrice) { $0.evaluationKRW }
  }

  static func totalEvaluationPrice(
    cryptos: [CryptoTransactionDataModel],
    btcKRWPrice: Double?
  ) -> Double? {
    totalEvaluationPriceDecimal(cryptos: cryptos, btcKRWPrice: btcKRWPrice).map(double)
  }

  static func totalBuyAmountDecimal(
    cryptos: [CryptoTransactionDataModel],
    btcKRWPrice: Double?
  ) -> Decimal? {
    total(cryptos: cryptos, btcKRWPrice: btcKRWPrice) { $0.costBasisKRW }
  }

  static func totalBuyAmount(
    cryptos: [CryptoTransactionDataModel],
    btcKRWPrice: Double?
  ) -> Double? {
    totalBuyAmountDecimal(cryptos: cryptos, btcKRWPrice: btcKRWPrice).map(double)
  }

  static func totalProfitRate(
    totalProfitLoss: Double,
    totalAssetValue: Double
  ) -> Double {
    guard totalAssetValue != 0 else { return 0 }
    guard let profitLoss = arithmeticDecimal(totalProfitLoss), let assets = arithmeticDecimal(totalAssetValue) else {
      return (totalProfitLoss / totalAssetValue) * 100
    }
    // 전체 손익률도 먼저 십진수로 계산해 합산 결과의 오차를 줄인다.
    let rate = profitLoss / assets * 100
    return rate.isNaN ? (totalProfitLoss / totalAssetValue) * 100 : double(rate)
  }
}
