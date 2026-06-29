//
//  PortfolioCalculator.swift
//  Mobit
//
//  Created by Codex on 6/29/26.
//

import Foundation

enum PortfolioCalculator {
  static func executedAmount(price: Double, quantity: Double) -> Double {
    floor(price * quantity)
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
    quantity: Double
  ) -> Double {
    previousBuyAmount + executedAmount(price: price, quantity: quantity)
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

  static func totalAssetValue(
    availableBalance: Double,
    cryptos: [CryptoTransactionDataModel]
  ) -> Double {
    availableBalance + cryptos.reduce(0) { $0 + $1.dynamicData.evaluationPrice }
  }

  static func totalEvaluationProfitLoss(
    cryptos: [CryptoTransactionDataModel]
  ) -> Double {
    cryptos.reduce(0) { $0 + $1.dynamicData.evaluationProfitLoss }
  }

  static func totalBuyAmount(
    cryptos: [CryptoTransactionDataModel]
  ) -> Double {
    cryptos.reduce(0) { $0 + $1.staticData.buyAmount }
  }

  static func totalProfitRate(
    totalProfitLoss: Double,
    totalAssetValue: Double
  ) -> Double {
    guard totalAssetValue != 0 else { return 0 }
    return (totalProfitLoss / totalAssetValue) * 100
  }
}
