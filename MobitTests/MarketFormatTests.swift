//
//  MarketFormatTests.swift
//  MobitTests
//
//  Created by Codex on 6/29/26.
//

import XCTest
@testable import Mobit

final class MarketFormatTests: XCTestCase {
  override func setUp() {
    super.setUp()
    ExchangeSelectionStore.currentExchange = .upbit
  }

  override func tearDown() {
    ExchangeSelectionStore.currentExchange = .upbit
    super.tearDown()
  }

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

  func testBithumbAPIMarketFromDisplayMarket() {
    XCTAssertEqual(
      MarketFormat.apiMarket(
        fromDisplayMarket: "ETH/KRW",
        exchange: .bithumb
      ),
      "KRW-ETH"
    )
  }

  func testTradingViewSymbolUsesCurrentExchangeSelection() {
    ExchangeSelectionStore.currentExchange = .bithumb

    XCTAssertEqual(
      MarketFormat.tradingViewSymbol(fromDisplayMarket: "BTC/KRW"),
      "BITHUMB:BTCKRW"
    )
  }

  func testTradingViewSymbolUsesDisplayMarketOrderForUpbit() {
    XCTAssertEqual(
      MarketFormat.tradingViewSymbol(
        fromDisplayMarket: "BTC/KRW",
        exchange: .upbit
      ),
      "UPBIT:BTCKRW"
    )
    XCTAssertEqual(
      MarketFormat.tradingViewSymbol(
        fromDisplayMarket: "ETH/BTC",
        exchange: .upbit
      ),
      "UPBIT:ETHBTC"
    )
  }

  func testExchangeAdapterRegistryUsesCurrentExchangeSelection() {
    ExchangeSelectionStore.currentExchange = .bithumb

    XCTAssertEqual(ExchangeAdapterRegistry.default.exchange, .bithumb)
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
      favorites: [FavoritePair(displayMarket: "BTC/KRW", exchange: .upbit)]
    )

    XCTAssertEqual(markets, ["KRW-BTC"])
  }

  func testFavoriteTabSkipsFavoritesFromOtherExchange() {
    let totalList = [
      makeCell(market: "BTC/KRW"),
      makeCell(market: "ETH/KRW")
    ]

    let markets = MarketFormat.apiMarketsForSubscription(
      tab: .favorite,
      totalList: totalList,
      userCryptos: [],
      favorites: [FavoritePair(displayMarket: "BTC/KRW", exchange: .bithumb)],
      exchange: .upbit
    )

    XCTAssertEqual(markets, [])
  }

  func testHoldTabSkipsHoldingsFromOtherExchange() {
    let totalList = [
      makeCell(market: "BTC/KRW"),
      makeCell(market: "ETH/KRW")
    ]
    let userCryptos = [
      makeTransaction(market: "BTC/KRW", exchange: .bithumb),
      makeTransaction(market: "ETH/KRW", exchange: .upbit)
    ]

    let markets = MarketFormat.apiMarketsForSubscription(
      tab: .hold,
      totalList: totalList,
      userCryptos: userCryptos,
      favorites: [],
      exchange: .upbit
    )

    XCTAssertEqual(markets, ["KRW-ETH"])
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

  private func makeTransaction(
    market: String,
    exchange: Exchange = .upbit
  ) -> CryptoTransactionDataModel {
    CryptoTransactionDataModel(
      staticData: .init(
        exchange: exchange,
        marketName: market,
        cryptoName: market,
        holdingQuantity: 1,
        averageBuyPrice: 100,
        buyAmount: 100
      ),
      dynamicData: .init(
        exchange: exchange,
        marketName: market,
        profitRate: 0,
        evaluationProfitLoss: 0,
        evaluationPrice: 100
      )
    )
  }
}
