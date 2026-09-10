//
//  PortfolioCalculator.swift
//  Mobit
//
//  Created by 조성재 on 6/29/26.
//

import Foundation

enum PortfolioCalculator {
  /// 수량 비교 허용 오차. 소수점 아래가 잘린 입력값 때문에 생기는 미세 잔량을 보유로 취급하지 않기 위한 기준이다.
  static let quantityTolerance: Double = 0.00000001

  static func executedAmount(
    price: Double,
    quantity: Double,
    currency: SettlementCurrency = .krw
  ) -> Double {
    (price * quantity).formatDigits(digits: currency.amountFractionDigits)
  }

  /// 매도 대금으로 받은 결제 자산의 취득원가를 가중평균으로 갱신한다.
  static func weightedAverageBuyPrice(
    previousQuantity: Double,
    previousAveragePrice: Double,
    addedQuantity: Double,
    addedPrice: Double
  ) -> Double {
    let totalQuantity = previousQuantity + addedQuantity
    guard totalQuantity > 0 else { return addedPrice }

    let totalAmount = (previousQuantity * previousAveragePrice) + (addedQuantity * addedPrice)
    return totalAmount / totalQuantity
  }

  static func isFullySold(holdingQuantity: Double, sellQuantity: Double) -> Bool {
    decimal(holdingQuantity) - decimal(sellQuantity) < decimal(quantityTolerance)
  }

  static func cumulativeHoldingQuantity(
    previousQuantity: Double,
    newQuantity: Double
  ) -> Double {
    previousQuantity + newQuantity
  }

  static func cumulativeBuyAmount(
    previousBuyAmount: Double,
    price: Double,
    quantity: Double,
    currency: SettlementCurrency = .krw
  ) -> Double {
    previousBuyAmount + executedAmount(
      price: price,
      quantity: quantity,
      currency: currency
    )
  }

  static func profitRate(
    currentPrice: Double,
    averageBuyPrice: Double
  ) -> Double {
    guard averageBuyPrice != 0 else { return 0 }
    return (((currentPrice - averageBuyPrice) / averageBuyPrice) * 100).formatDigits(digits: 2)
  }

  static func evaluationPrice(
    currentPrice: Double,
    holdingQuantity: Double
  ) -> Double {
    guard holdingQuantity >= 0 else { return 0 }
    return (currentPrice * holdingQuantity).formatDigits(digits: 8)
  }

  static func evaluationProfitLoss(
    currentPrice: Double,
    holdingQuantity: Double,
    averageBuyPrice: Double
  ) -> Double {
    (currentPrice - averageBuyPrice) * holdingQuantity
  }

  static func realizedProfitLoss(
    entryPrice: Double,
    exitPrice: Double,
    quantity: Double
  ) -> Double {
    (exitPrice - entryPrice) * quantity
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
      return amount * btcKRWPrice
    }
  }

  struct Valuation {
    let costBasisKRW: Double?
    let evaluationKRW: Double?
    let profitLossKRW: Double?
    let profitRate: Double?
    let averagePriceKRW: Double?
  }

  static func decimal(_ value: Double) -> Decimal {
    Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) ?? .nan
  }

  static func double(_ value: Decimal) -> Double {
    NSDecimalNumber(decimal: value).doubleValue
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
      guard let rate, rate.isFinite, rate > 0,
            crypto.dynamicData.evaluationPrice.isFinite,
            crypto.dynamicData.evaluationPrice >= 0 else { return nil }
      return decimal(crypto.dynamicData.evaluationPrice) * decimal(rate)
    }()
    let profit = evaluation.flatMap { value in cost.map { value - $0 } }
    return Valuation(
      costBasisKRW: cost.map(double),
      evaluationKRW: evaluation.map(double),
      profitLossKRW: profit.map(double),
      profitRate: cost.flatMap { cost in
        guard cost > 0, let profit else { return nil }
        return double(profit / cost * 100)
      },
      averagePriceKRW: cost.flatMap { cost in
        guard data.holdingQuantity.isFinite, data.holdingQuantity > 0 else { return nil }
        return double(cost / decimal(data.holdingQuantity))
      }
    )
  }

  private static func total(
    cryptos: [CryptoTransactionDataModel],
    btcKRWPrice: Double?,
    value: (Valuation) -> Double?
  ) -> Double? {
    var sum: Decimal = 0
    for crypto in cryptos {
      guard let amount = value(valuation(of: crypto, btcKRWPrice: btcKRWPrice)),
            amount.isFinite else { return nil }
      sum += decimal(amount)
    }
    return double(sum)
  }

  static func orderedBefore(_ lhs: Double?, _ rhs: Double?, ascending: Bool) -> Bool {
    switch (lhs, rhs) {
    case let (left?, right?): return ascending ? left < right : left > right
    case (_?, nil): return true
    default: return false
    }
  }

  static func totalAssetValue(
    availableBalance: Double,
    cryptos: [CryptoTransactionDataModel],
    btcKRWPrice: Double?
  ) -> Double? {
    guard let evaluationPrice = self.totalEvaluationPrice(
      cryptos: cryptos,
      btcKRWPrice: btcKRWPrice
    ) else {
      return nil
    }

    return availableBalance + evaluationPrice
  }

  static func totalEvaluationProfitLoss(
    cryptos: [CryptoTransactionDataModel],
    btcKRWPrice: Double?
  ) -> Double? {
    self.total(cryptos: cryptos, btcKRWPrice: btcKRWPrice) {
      $0.profitLossKRW
    }
  }

  static func totalEvaluationPrice(
    cryptos: [CryptoTransactionDataModel],
    btcKRWPrice: Double?
  ) -> Double? {
    self.total(cryptos: cryptos, btcKRWPrice: btcKRWPrice) {
      $0.evaluationKRW
    }
  }

  static func totalBuyAmount(
    cryptos: [CryptoTransactionDataModel],
    btcKRWPrice: Double?
  ) -> Double? {
    self.total(cryptos: cryptos, btcKRWPrice: btcKRWPrice) {
      $0.costBasisKRW
    }
  }

  static func totalProfitRate(
    totalProfitLoss: Double,
    totalAssetValue: Double
  ) -> Double {
    guard totalAssetValue != 0 else { return 0 }
    return (totalProfitLoss / totalAssetValue) * 100
  }
}
