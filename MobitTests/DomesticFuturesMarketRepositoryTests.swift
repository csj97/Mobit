import XCTest
import Moya
import RxSwift
@testable import Mobit

final class DomesticFuturesMarketRepositoryTests: XCTestCase {
  private let base: Int64 = 1_780_272_000_000
  private func instrument(_ exchange: Exchange = .upbit) -> TradingInstrumentID {
    .init(exchange: exchange, product: .perpetual, rawSymbol: "KRW-BTC", settlementCurrency: .krw)
  }
  private func text(_ time: Int64, format: String = "yyyy-MM-dd'T'HH:mm:ss") -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = format
    return formatter.string(from: Date(timeIntervalSince1970: Double(time) / 1000))
  }
  private func candle(_ time: Int64, close: Int = 100, seconds: Bool = false) -> String {
    "{\"market\":\"KRW-BTC\",\"candle_date_time_utc\":\"\(text(time))\",\"opening_price\":100,\"high_price\":120,\"low_price\":80,\"trade_price\":\(close)\(seconds ? "" : ",\"unit\":1")}"
  }
  private func repository(status: Int = 200, serverTime: Int64? = nil,
                          body: @escaping (DomesticFuturesNetworkService) -> String) -> DomesticFuturesMarketRepository {
    let time = serverTime ?? base + 40_000_000
    let header = text(time, format: "EEE, dd MMM yyyy HH:mm:ss 'GMT'")
    let provider = MoyaProvider<DomesticFuturesNetworkService>(endpointClosure: { target in
      let url = target.baseURL.appendingPathComponent(target.path)
      let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Date": header])!
      return Endpoint(url: url.absoluteString, sampleResponseClosure: { .response(response, Data(body(target).utf8)) },
        method: target.method, task: target.task, httpHeaderFields: target.headers)
    }, stubClosure: MoyaProvider.immediatelyStub)
    return DomesticFuturesMarketRepository(provider: provider,
      now: { Date(timeIntervalSince1970: Double(time) / 1000) }, requestDelay: .milliseconds(0))
  }
  private func value<T>(_ single: Single<T>) throws -> T {
    let finished = expectation(description: "domestic request")
    var result: Result<T, Error>?
    let disposable = single.observe(on: MainScheduler.instance).subscribe(onSuccess: { result = .success($0); finished.fulfill() },
      onFailure: { result = .failure($0); finished.fulfill() })
    defer { disposable.dispose() }
    wait(for: [finished], timeout: 20)
    return try XCTUnwrap(result).get()
  }

  func testExchangeTimeAndParameterNamesAreSeparated() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      let target = DomesticFuturesNetworkService(exchange: exchange, market: "KRW-BTC", query: .candles(seconds: false, to: base, count: 200))
      guard case .requestParameters(let params, _) = target.task else { return XCTFail("Missing parameters") }
      let to = try XCTUnwrap(params["to"] as? String)
      XCTAssertEqual(to, exchange == .upbit ? text(base) + "Z" : text(base + 9 * 3_600_000))
      let trades = DomesticFuturesNetworkService(exchange: exchange, market: "KRW-BTC", query: .trades(to: "123456", daysAgo: 3, cursor: "999"))
      guard case .requestParameters(let tradeParams, _) = trades.task else { return XCTFail("Missing parameters") }
      XCTAssertEqual(tradeParams[exchange == .upbit ? "days_ago" : "daysAgo"] as? Int, 3)
      XCTAssertEqual(tradeParams["cursor"] as? String, "999")
    }
  }

  func testTickerDecimalAndFailures() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      let repo = repository { _ in "[{\"market\":\"KRW-BTC\",\"trade_price\":123.123456789123,\"timestamp\":\(self.base)}]" }
      XCTAssertEqual(try value(repo.markQuote(instrument(exchange))).price, Decimal(string: "123.123456789123"))
    }
    for body in ["[]", "null", "{}", "[{\"market\":\"KRW-BTC\",\"trade_price\":null,\"timestamp\":1}]",
      "[{\"market\":\"KRW-ETH\",\"trade_price\":100,\"timestamp\":1}]",
      "[{\"market\":\"KRW-BTC\",\"trade_price\":0,\"timestamp\":1}]"] {
      XCTAssertThrowsError(try value(repository { _ in body }.markQuote(instrument())))
    }
    for status in [429, 500] {
      XCTAssertThrowsError(try value(repository(status: status) { _ in "[]" }.markQuote(instrument()))) {
        XCTAssertEqual($0 as? FuturesMarketDataError, .httpStatus(status))
      }
    }
  }

  func testSparseMinutesUseAnchorAndCarryPreviousClose() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      let repo = repository { _ in "[\(self.candle(self.base + 60_000, close: 110)),\(self.candle(self.base - 60_000, close: 90))]" }
      let values = try value(repo.markCandles(instrument(exchange), start: base, endExclusive: base + 180_000)).values
      XCTAssertEqual(values.map(\.close), [90, 110, 110])
      XCTAssertEqual(values.map(\.low), [90, 80, 110])
      XCTAssertEqual(values.map(\.openTime), [base, base + 60_000, base + 120_000])
    }
  }

  func testEmptyMissingAnchorDuplicateAndInvalidCandleNeverBecomeSafeHistory() {
    for body in ["[]", "[\(candle(base))]", "[\(candle(base - 60_000)),\(candle(base - 60_000))]",
      "[\(candle(base - 60_000, close: 999))]", "[\(candle(base - 60_000).replacingOccurrences(of: "KRW-BTC", with: "KRW-ETH"))]"] {
      XCTAssertThrowsError(try value(repository { _ in body }.markCandles(instrument(), start: base, endExclusive: base + 60_000)))
    }
    XCTAssertThrowsError(try value(repository(serverTime: base + 59_000) { _ in "[\(self.candle(self.base - 60_000))]" }
      .markCandles(instrument(), start: base, endExclusive: base + 60_000)))
  }

  func testMinuteChunksCover499MinutesWithoutDroppingBoundaries() throws {
    let repo = repository { target in
      guard case .candles(_, let end, let count) = target.query else { return "[]" }
      XCTAssertEqual(count, 200)
      return "[" + (1...200).map { self.candle(end - Int64($0) * 60_000) }.joined(separator: ",") + "]"
    }
    let page = try value(repo.markCandles(instrument(), start: base, endExclusive: base + 499 * 60_000))
    XCTAssertEqual(page.values.count, 499)
    XCTAssertEqual(page.values.first?.openTime, base)
    XCTAssertEqual(page.values.last?.closeTime, base + 499 * 60_000 - 1)
    XCTAssertNil(page.nextStartTime)
  }

  func testSecondsAreUpbitOnlyAndRetentionIsNotAnEmptySuccess() throws {
    let repo = repository { _ in "[\(self.candle(self.base - 1000, seconds: true))]" }
    XCTAssertEqual(try value(repo.secondCandles(instrument(), start: base, endExclusive: base + 3000)).values.count, 3)
    XCTAssertThrowsError(try value(repo.secondCandles(instrument(.bithumb), start: base, endExclusive: base + 3000)))
    XCTAssertThrowsError(try value(repo.secondCandles(instrument(), start: base - 120 * 86_400_000, endExclusive: base - 120 * 86_400_000 + 1000)))
    XCTAssertThrowsError(try value(repo.secondCandles(instrument(), start: base + 1, endExclusive: base + 3000)))
  }

  func testDomesticAdapterFeedsLiquidationAndPersistsHistory() throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("accounts.json")
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
    let store = LocalFuturesAccountRepository(fileURL: fileURL)
    let order = domesticFuturesOrder(price: 100, date: Date(timeIntervalSince1970: Double(base) / 1000))
    try store.ensureAccount(order.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    try store.openTestPosition(order, expectedRevision: store.snapshot().revision)
    let repo = repository { target in
      switch target.query {
      case .ticker: return "[{\"market\":\"KRW-BTC\",\"trade_price\":100,\"timestamp\":\(self.base + 125_000)}]"
      case .candles: return "[\(self.candle(self.base)),\(self.candle(self.base - 60_000))]"
      case .trades: return "[]"
      }
    }
    let service = FuturesReconciliationService(store: { store }, provider: { _ in repo },
      now: { Date(timeIntervalSince1970: Double(self.base + 125_000) / 1000) })
    let finished = expectation(description: "domestic liquidation persisted")
    let subscription = service.status.subscribe(onNext: { status in
      if case .finished(let results) = status, !results.isEmpty {
        XCTAssertTrue(results[0].liquidated)
        XCTAssertNil(results[0].hold)
        finished.fulfill()
      }
    })
    defer { subscription.dispose(); service.suspend() }
    service.refresh()
    wait(for: [finished], timeout: 20)
    let snapshot = try store.snapshot()
    XCTAssertEqual(try snapshot.transactionHistory(for: order.account).count, 2)
    XCTAssertEqual(try snapshot.valuation(for: order.account, quotes: [:], now: order.executedAt).realizedPnL, -order.margin)
  }

  func testFullTradePageReturnsCursorWithoutClaimingCompleteCoverage() throws {
    let rows = (1...500).reversed().map { index in
      "{\"market\":\"KRW-BTC\",\"trade_price\":100,\"timestamp\":\(base + Int64(index)),\"sequential_id\":\(index)}"
    }.joined(separator: ",")
    let page = try value(repository { _ in "[\(rows)]" }.tradePage(instrument()))
    XCTAssertEqual(page.trades.count, 500)
    XCTAssertEqual(page.nextCursor, "1")
  }

  func testTradeCursorAndTimestampValidation() throws {
    let row = "{\"market\":\"KRW-BTC\",\"trade_price\":100,\"timestamp\":\(base),\"sequential_id\":123}"
    let repo = repository { _ in "[\(row)]" }
    let page = try value(repo.tradePage(instrument(), to: "123456", daysAgo: 1))
    XCTAssertEqual(page.trades.first?.id, "123")
    XCTAssertNil(page.nextCursor)
    XCTAssertThrowsError(try value(repo.tradePage(instrument(), cursor: "123")))
    XCTAssertThrowsError(try value(repo.tradePage(instrument(), daysAgo: 8)))
    XCTAssertThrowsError(try value(repo.tradePage(instrument(), to: "250000")))
    XCTAssertThrowsError(try value(repository { _ in "[\(row),\(row)]" }.tradePage(instrument())))
  }
  func testBoundaryTicksExcludePreEntryExtremesAndCoverEveryMillisecond() throws {
    let start = base + 34_123
    let row: (Int64, Int, Int) -> String = { time, price, id in
      "{\"market\":\"KRW-BTC\",\"trade_price\":\(price),\"timestamp\":\(time),\"sequential_id\":\(id)}"
    }
    let repo = repository { _ in
      "[\(row(self.base + 35_000, 95, 3)),\(row(self.base + 34_100, 100, 2)),\(row(self.base + 34_000, 1, 1))]"
    }
    let batch = try value(repo.boundaryHistory(instrument(), start: start, endExclusive: base + 36_000, initialEntry: true))
    XCTAssertTrue(batch.detailed)
    XCTAssertFalse(batch.entryCloseFallback)
    XCTAssertEqual(batch.candles.first?.openTime, start)
    XCTAssertEqual(batch.candles.last?.closeTime, base + 35_999)
    XCTAssertEqual(batch.candles.map(\.low).min(), 95)
    let position = try FuturesCalculator.open(domesticFuturesOrder(margin: 100, price: 100,
      date: Date(timeIntervalSince1970: Double(start) / 1000)))
    let result = try FuturesReplayCalculator.replay(batch, position: position, state: .initial(for: position),
      settledAt: Date(timeIntervalSince1970: Double(base + 36_000) / 1000))
    XCTAssertNil(result.state.liquidation)
  }

  func testExpiredEntryBoundaryUsesAuditableCloseOnlyAndErrorsNeverFallback() throws {
    let old = base - 120 * 86_400_000
    let repo = repository { target in
      guard case .candles(let seconds, _, _) = target.query else { return "[]" }
      XCTAssertFalse(seconds)
      return "[\(self.candle(old)),\(self.candle(old - 60_000))]"
    }
    let batch = try value(repo.boundaryHistory(instrument(), start: old + 34_123, endExclusive: old + 60_000, initialEntry: true))
    XCTAssertTrue(batch.entryCloseFallback)
    XCTAssertEqual(batch.candles[0].low, 100)
    XCTAssertThrowsError(try value(repo.boundaryHistory(instrument(), start: old + 34_123, endExclusive: old + 60_000, initialEntry: false)))
    let position = try FuturesCalculator.open(domesticFuturesOrder(margin: 100, price: 100,
      date: Date(timeIntervalSince1970: Double(old + 34_123) / 1000)))
    let result = try FuturesReplayCalculator.replay(batch, position: position, state: .initial(for: position),
      settledAt: Date(timeIntervalSince1970: Double(base) / 1000))
    XCTAssertEqual(result.state.entryCloseFallbacks, [.init(start: old + 34_123, endExclusive: old + 60_000)])
    for status in [429, 500] {
      XCTAssertThrowsError(try value(repository(status: status) { _ in "[]" }.boundaryHistory(instrument(),
        start: base + 34_123, endExclusive: base + 60_000, initialEntry: true))) {
        XCTAssertEqual($0 as? FuturesMarketDataError, .httpStatus(status))
      }
    }
  }

  func testBithumbRepeatedCursorIDsRetainAllPriceExtremes() throws {
    let time = base + 34_500
    let rows = [100, 80, 95].map {
      "{\"market\":\"KRW-BTC\",\"trade_price\":\($0),\"timestamp\":\(time),\"sequential_id\":123}"
    }.joined(separator: ",")
    let anchor = "{\"market\":\"KRW-BTC\",\"trade_price\":100,\"timestamp\":\(base + 33_999),\"sequential_id\":122}"
    let repo = repository { _ in "[\(rows),\(anchor)]" }
    let batch = try value(repo.boundaryHistory(instrument(.bithumb), start: base + 34_000,
      endExclusive: base + 35_000, initialEntry: true))
    XCTAssertEqual(batch.candles.map(\.low).min(), 80)
    XCTAssertThrowsError(try value(repo.tradePage(instrument(.upbit))))
  }

  func testBithumbTruncatedSameMillisecondNeverClaimsCompleteHistory() throws {
    let row = "{\"market\":\"KRW-BTC\",\"trade_price\":100,\"timestamp\":\(base + 34_500),\"sequential_id\":123}"
    let repo = repository { _ in "[" + Array(repeating: row, count: 500).joined(separator: ",") + "]" }
    XCTAssertThrowsError(try value(repo.boundaryHistory(instrument(.bithumb), start: base + 34_000,
      endExclusive: base + 35_000, initialEntry: true)))
  }

  func testDetailReplayRejectsGapsAndArbitraryFallbackAndCatchesDipRecovery() throws {
    let position = try FuturesCalculator.open(domesticFuturesOrder(margin: 100, price: 100,
      date: Date(timeIntervalSince1970: Double(base + 34_123) / 1000)))
    let start = try FuturesReconciliationState.milliseconds(position.order.executedAt)
    let initial = try FuturesReconciliationState.initial(for: position)
    let candle = FuturesMarkCandle(openTime: start, closeTime: start + 999, open: 100, high: 100, low: 80, close: 100)
    let batch = FuturesReplayBatch(instrument: position.order.instrument, start: start, endExclusive: start + 1000,
      candles: [candle], funding: [], detailed: true)
    let date = Date(timeIntervalSince1970: Double(start + 1000) / 1000)
    XCTAssertNotNil(try FuturesReplayCalculator.replay(batch, position: position, state: initial, settledAt: date).state.liquidation)
    var gap = batch
    gap = .init(instrument: batch.instrument, start: start, endExclusive: start + 1001,
      candles: [candle], funding: [], detailed: true)
    XCTAssertThrowsError(try FuturesReplayCalculator.replay(gap, position: position, state: initial, settledAt: date.addingTimeInterval(1)))
    var invalidFallback = batch
    invalidFallback.entryCloseFallback = true
    XCTAssertThrowsError(try FuturesReplayCalculator.replay(invalidFallback, position: position, state: initial, settledAt: date))
  }

}
