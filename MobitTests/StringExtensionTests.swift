//
//  StringExtensionTests.swift
//  MobitTests
//
//  Created by Codex on 7/9/26.
//

import XCTest
@testable import Mobit

final class StringExtensionTests: XCTestCase {
  override func setUp() {
    super.setUp()
    ExchangeSelectionStore.currentExchange = .upbit
  }

  override func tearDown() {
    ExchangeSelectionStore.currentExchange = .upbit
    super.tearDown()
  }

  func testMarketForCandleRequestUsesUpbitFormatByDefault() {
    XCTAssertEqual("BTC/KRW".marketForCandleRequest, "KRW-BTC")
    XCTAssertEqual("ETH/BTC".marketForCandleRequest, "BTC-ETH")
  }

  func testMarketForCandleRequestUsesBithumbFormatWhenExchangeChanges() {
    ExchangeSelectionStore.currentExchange = .bithumb

    XCTAssertEqual("BTC/KRW".marketForCandleRequest, "KRW-BTC")
    XCTAssertEqual("ETH/BTC".marketForCandleRequest, "BTC-ETH")
  }
}
