//
//  PortfolioCalculator.swift
//  Mobit
//
//  Created by 조성재 on 6/29/26.
//

import Foundation

enum PortfolioCalculator {
  /// 수량 비교 허용 오차. 소수점 아래가 잘린 입력값 때문에 생기는 미세 잔량을 보유로 취급하지 않기 위한 기준이다.
  static let quantityTolerance: Double = 0.000001

  static func executedAmount(price: Double, quantity: Double) -> Double {
    floor(price * quantity)
  }

  static func isFullySold(holdingQuantity: Double, sellQuantity: Double) -> Bool {
    holdingQuantity - sellQuantity < quantityTolerance
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

  static func totalEvaluationPrice(
    cryptos: [CryptoTransactionDataModel]
  ) -> Double {
    cryptos.reduce(0) { $0 + $1.dynamicData.evaluationPrice }
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
