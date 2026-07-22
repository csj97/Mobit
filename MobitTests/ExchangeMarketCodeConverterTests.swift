//
//  ExchangeMarketCodeConverterTests.swift
//  MobitTests
//
//  Created by Codex on 7/8/26.
//

import XCTest
@testable import Mobit

final class ExchangeMarketCodeConverterTests: XCTestCase {
  func testUpbitRawMarketConvertsToDisplayMarket() {
    XCTAssertEqual(
      ExchangeMarketCodeConverter.displayMarket(
        fromRawMarketCode: "KRW-BTC",
        exchange: .upbit
      ),
      "BTC/KRW"
    )
  }

  func testBithumbRawMarketConvertsToDisplayMarket() {
    XCTAssertEqual(
      ExchangeMarketCodeConverter.displayMarket(
        fromRawMarketCode: "KRW-BTC",
        exchange: .bithumb
      ),
      "BTC/KRW"
    )
  }

  func testBithumbLegacyRawMarketConvertsToDisplayMarket() {
    XCTAssertEqual(
      ExchangeMarketCodeConverter.displayMarket(
        fromRawMarketCode: "BTC_KRW",
        exchange: .bithumb
      ),
      "BTC/KRW"
    )
  }

  func testBithumbDisplayMarketConvertsToRawMarket() {
    XCTAssertEqual(
      ExchangeMarketCodeConverter.rawMarketCode(
        fromDisplayMarket: "ETH/KRW",
        exchange: .bithumb
      ),
      "KRW-ETH"
    )
  }

  func testLegacyBithumbRawMarketConvertsToUpbitRawMarket() {
    XCTAssertEqual(
      ExchangeMarketCodeConverter.rawMarketCode(
        fromDisplayMarket: "BTC_KRW",
        exchange: .upbit
      ),
      "KRW-BTC"
    )
  }

  func testBithumbRawMarketRemainsNormalizedWhenConvertingToUpbitRawMarket() {
    XCTAssertEqual(
      ExchangeMarketCodeConverter.rawMarketCode(
        fromDisplayMarket: "KRW-XRP",
        exchange: .upbit
      ),
      "KRW-XRP"
    )
  }

  func testExchangePairIDBuildsRoundTripDisplayMarket() {
    let pairID = ExchangeMarketCodeConverter.pairID(
      fromDisplayMarket: "XRP/KRW",
      exchange: .bithumb
    )

    XCTAssertEqual(pairID.rawValue, "bithumb:KRW-XRP")
    XCTAssertEqual(pairID.exchange, .bithumb)
    XCTAssertEqual(pairID.rawMarketCode, "KRW-XRP")
    XCTAssertEqual(pairID.displayMarket, "XRP/KRW")
  }

  func testUnknownFormatReturnsOriginalValue() {
    XCTAssertEqual(
      ExchangeMarketCodeConverter.displayMarket(
        fromRawMarketCode: "BTCUSDT",
        exchange: .binance
      ),
      "BTCUSDT"
    )
    XCTAssertEqual(
      ExchangeMarketCodeConverter.rawMarketCode(
        fromDisplayMarket: "BTCUSDT",
        exchange: .binance
      ),
      "BTCUSDT"
    )
  }
}
