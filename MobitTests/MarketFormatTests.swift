//
//  MarketFormatTests.swift
//  MobitTests
//
//  Created by Codex on 6/29/26.
//

import XCTest
@testable import Mobit

final class MarketFormatTests: XCTestCase {
  func testDisplayMarketFromAPIMarket() {
    XCTAssertEqual(
      MarketFormat.displayMarket(fromAPIMarket: "KRW-BTC"),
      "BTC/KRW"
    )
  }

  func testAPIMarketFromDisplayMarket() {
    XCTAssertEqual(
      MarketFormat.apiMarket(fromDisplayMarket: "ETH/BTC"),
      "BTC-ETH"
    )
  }

  func testInvalidMarketFormatReturnsOriginalValue() {
    XCTAssertEqual(
      MarketFormat.displayMarket(fromAPIMarket: "BTC"),
      "BTC"
    )
    XCTAssertEqual(
      MarketFormat.apiMarket(fromDisplayMarket: "BTC"),
      "BTC"
    )
  }

  func testHoldTabSubscribesOnlyHeldMarkets() {
    let totalList = [
      makeCell(market: "BTC/KRW"),
      makeCell(market: "ETH/KRW"),
      makeCell(market: "XRP/BTC")
    ]
    let userCryptos = [
      makeTransaction(market: "ETH/KRW"),
      makeTransaction(market: "XRP/BTC")
    ]

    let markets = MarketFormat.apiMarketsForSubscription(
      tab: .hold,
      totalList: totalList,
      userCryptos: userCryptos,
      favorites: []
    )

    XCTAssertEqual(markets, ["BTC-XRP", "KRW-ETH"])
  }

  func testFavoriteTabSubscribesOnlyFavoriteMarkets() {
    let totalList = [
      makeCell(market: "BTC/KRW"),
      makeCell(market: "ETH/KRW")
    ]

    let markets = MarketFormat.apiMarketsForSubscription(
      tab: .favorite,
      totalList: totalList,
      userCryptos: [],
      favorites: ["BTC/KRW"]
    )

    XCTAssertEqual(markets, ["KRW-BTC"])
  }

  private func makeCell(market: String) -> CryptoCellInfo {
    CryptoCellInfo(
      cryptoName: market,
      market: market,
      marketEvent: nil,
      prevPrice: nil,
      tradePrice: nil,
      changePrice: nil,
      signedChangeRate: nil,
      change: nil,
      accTradePrice24h: nil,
      accTradeVolume24h: nil,
      highest52WeekPrice: nil,
      lowest52WeekPrice: nil
    )
  }

  private func makeTransaction(market: String) -> CryptoTransactionDataModel {
    CryptoTransactionDataModel(
      staticData: .init(
        marketName: market,
        cryptoName: market,
        holdingQuantity: 1,
        averageBuyPrice: 100,
        buyAmount: 100
      ),
      dynamicData: .init(
        marketName: market,
        profitRate: 0,
        evaluationProfitLoss: 0,
        evaluationPrice: 100
      )
    )
  }
}
