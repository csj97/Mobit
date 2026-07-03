//
//  PortfolioCalculatorTests.swift
//  MobitTests
//
//  Created by Codex on 6/29/26.
//

import XCTest
@testable import Mobit

final class PortfolioCalculatorTests: XCTestCase {
  func testExecutedAmountFloorsFractionalValue() {
    let amount = PortfolioCalculator.executedAmount(price: 12.34, quantity: 3.2)

    XCTAssertEqual(amount, 39)
  }

  func testProfitRateTruncatesToTwoDigits() {
    let rate = PortfolioCalculator.profitRate(
      currentPrice: 123,
      averageBuyPrice: 100
    )

    XCTAssertEqual(rate, 23)
  }

  func testProfitRateReturnsZeroWhenAverageBuyPriceIsZero() {
    let rate = PortfolioCalculator.profitRate(
      currentPrice: 123,
      averageBuyPrice: 0
    )

    XCTAssertEqual(rate, 0)
  }

  func testEvaluationValues() {
    let evaluationPrice = PortfolioCalculator.evaluationPrice(
      currentPrice: 11.123456789,
      holdingQuantity: 2
    )
    let profitLoss = PortfolioCalculator.evaluationProfitLoss(
      currentPrice: 120,
      holdingQuantity: 3,
      averageBuyPrice: 100
    )

    XCTAssertEqual(evaluationPrice, 22.24691357)
    XCTAssertEqual(profitLoss, 60)
  }

  func testPortfolioTotals() {
    let cryptos = [
      makeCrypto(evaluationPrice: 1_200, evaluationProfitLoss: 200, buyAmount: 1_000),
      makeCrypto(evaluationPrice: 500, evaluationProfitLoss: -100, buyAmount: 600)
    ]

    let totalAsset = PortfolioCalculator.totalAssetValue(
      availableBalance: 300,
      cryptos: cryptos
    )
    let totalProfitLoss = PortfolioCalculator.totalEvaluationProfitLoss(cryptos: cryptos)
    let totalEvaluationPrice = PortfolioCalculator.totalEvaluationPrice(cryptos: cryptos)
    let totalBuyAmount = PortfolioCalculator.totalBuyAmount(cryptos: cryptos)
    let totalProfitRate = PortfolioCalculator.totalProfitRate(
      totalProfitLoss: totalProfitLoss,
      totalAssetValue: totalAsset
    )

    XCTAssertEqual(totalAsset, 2_000)
    XCTAssertEqual(totalProfitLoss, 100)
    XCTAssertEqual(totalEvaluationPrice, 1_700)
    XCTAssertEqual(totalBuyAmount, 1_600)
    XCTAssertEqual(totalProfitRate, 5)
  }

  private func makeCrypto(
    evaluationPrice: Double,
    evaluationProfitLoss: Double,
    buyAmount: Double
  ) -> CryptoTransactionDataModel {
    CryptoTransactionDataModel(
      staticData: .init(
        marketName: "BTC/KRW",
        cryptoName: "비트코인",
        holdingQuantity: 1,
        averageBuyPrice: buyAmount,
        buyAmount: buyAmount
      ),
      dynamicData: .init(
        marketName: "BTC/KRW",
        profitRate: 0,
        evaluationProfitLoss: evaluationProfitLoss,
        evaluationPrice: evaluationPrice
      )
    )
  }
}
