import XCTest
import Moya
import RxSwift
@testable import Mobit

final class BinanceFuturesMarketRepositoryTests: XCTestCase {
  private let instrument = TradingInstrumentID(exchange: .binance, product: .perpetual, rawSymbol: "BTCUSDT", settlementCurrency: .usdt)
  private let candle = #"[60000,"100","110","90","105","0",119999,"0",60,"0","0","0"]"#

  private func repository(_ body: String, status: Int = 200, serverTime: Int64 = 180000) -> BinanceFuturesMarketRepository {
    let provider = MoyaProvider<BinanceFuturesNetworkService>(endpointClosure: { target in
      let data: Data
      if case .serverTime = target { data = Data("{\"serverTime\":\(serverTime)}".utf8) }
      else { data = Data(body.utf8) }
      return Endpoint(url: target.baseURL.appendingPathComponent(target.path).absoluteString,
                      sampleResponseClosure: { .networkResponse(status, data) }, method: target.method, task: target.task, httpHeaderFields: target.headers)
    }, stubClosure: MoyaProvider.immediatelyStub)
    return BinanceFuturesMarketRepository(provider: provider)
  }

  private func value<T>(_ single: Single<T>) throws -> T {
    let completed = expectation(description: "request")
    var result: Result<T, Error>?
    let disposable = single.subscribe(onSuccess: { result = .success($0); completed.fulfill() },
                                      onFailure: { result = .failure($0); completed.fulfill() })
    defer { disposable.dispose() }
    wait(for: [completed], timeout: 2)
    return try XCTUnwrap(result).get()
  }

  func testMarkPreservesDecimalAndSymbol() throws {
    let quote = try value(repository(#"{"symbol":"BTCUSDT","markPrice":"12345.123456789123456789","time":123456}"#).markQuote(instrument))
    XCTAssertEqual(quote.price, Decimal(string: "12345.123456789123456789"))
    XCTAssertEqual(quote.instrument, instrument)
    XCTAssertEqual(quote.timestamp, 123456)
  }

  func testMalformedMissingZeroAndWrongSymbolAreRejected() {
    for body in ["null", "{}", #"{"symbol":"ETHUSDT","markPrice":"100","time":1}"#,
                 #"{"symbol":"BTCUSDT","markPrice":"0","time":1}"#,
                 #"{"symbol":"BTCUSDT","markPrice":"100oops","time":1}"#,
                 #"{"symbol":"BTCUSDT","markPrice":null,"time":1}"#] {
      XCTAssertThrowsError(try value(repository(body).markQuote(instrument)))
    }
  }

  func testHTTPFailuresAreNotConvertedToEmptySuccess() {
    for status in [418, 429, 500] {
      XCTAssertThrowsError(try value(repository("[]", status: status).funding(instrument, start: 1, endExclusive: 100))) {
        XCTAssertEqual($0 as? FuturesMarketDataError, .httpStatus(status))
      }
    }
  }

  func testUnsupportedExchangeNeverFallsBackToSpot() {
    let other = TradingInstrumentID(exchange: .upbit, product: .spot, rawSymbol: "KRW-BTC", settlementCurrency: .krw)
    XCTAssertThrowsError(try value(repository("{}").markQuote(other))) {
      XCTAssertEqual($0 as? FuturesMarketDataError, .unsupportedInstrument)
    }
  }

  func testClosedCandleAndMissingDuplicateInvalidOHLC() throws {
    let page = try value(repository("[\(candle)]").markCandles(instrument, start: 60000, endExclusive: 120000))
    XCTAssertEqual(page.values.count, 1)
    XCTAssertEqual(page.values[0].low, 90)
    XCTAssertNil(page.nextStartTime)
    for body in ["[]", "[\(candle),\(candle)]", "[\(candle.replacingOccurrences(of: "\"90\"", with: "\"109\""))]"] {
      XCTAssertThrowsError(try value(repository(body).markCandles(instrument, start: 60000, endExclusive: 120000)))
    }
  }

  func testPartialAndUnfinishedCandlesAreRejected() {
    XCTAssertThrowsError(try value(repository("[]").markCandles(instrument, start: 60001, endExclusive: 120000)))
    XCTAssertThrowsError(try value(repository("[\(candle)]", serverTime: 119999).markCandles(instrument, start: 60000, endExclusive: 120000)))
    XCTAssertThrowsError(try value(repository("[]").markCandles(instrument, start: 60000, endExclusive: Int64.max)))
  }

  func testPaginationKeepsContiguousCoverageAndSortsReverseResponse() throws {
    let rows = (1...499).reversed().map { index in
      "[\(index * 60000),\"100\",\"110\",\"90\",\"105\",\"0\",\(index * 60000 + 59999),\"0\",60,\"0\",\"0\",\"0\"]"
    }.joined(separator: ",")
    let page = try value(repository("[\(rows)]", serverTime: 40_000_000).markCandles(instrument, start: 60000, endExclusive: 30_060_000))
    XCTAssertEqual(page.nextStartTime, 30_000_000)
    XCTAssertEqual(page.values.first?.openTime, 60000)
  }

  func testFundingSignedRateAndBoundaryValidation() throws {
    let row = #"{"symbol":"BTCUSDT","fundingTime":100,"fundingRate":"-0.001","markPrice":"100","rateType":"Regular"}"#
    let page = try value(repository("[\(row)]").funding(instrument, start: 100, endExclusive: 101))
    XCTAssertEqual(page.values.first?.rate, Decimal(string: "-0.001"))
    XCTAssertNil(page.nextStartTime)
    XCTAssertThrowsError(try value(repository("[\(row)]").funding(instrument, start: 1, endExclusive: 100)))
    XCTAssertThrowsError(try value(repository("[\(row),\(row)]").funding(instrument, start: 1, endExclusive: 101)))
    XCTAssertThrowsError(try value(repository("[\(row.replacingOccurrences(of: "Regular", with: "Special"))]").funding(instrument, start: 1, endExclusive: 101)))
    XCTAssertEqual(try value(repository("[]").funding(instrument, start: 1, endExclusive: 101)).values.count, 0)
  }

  func testContractUsesFiltersInsteadOfDisplayPrecision() throws {
    let body = #"{"symbols":[{"symbol":"BTCUSDT","status":"TRADING","contractType":"PERPETUAL","quoteAsset":"USDT","marginAsset":"USDT","quantityPrecision":8,"filters":[{"filterType":"MARKET_LOT_SIZE","minQty":"0.001","maxQty":"100","stepSize":"0.001"},{"filterType":"MIN_NOTIONAL","notional":"5"},{"filterType":"PRICE_FILTER","tickSize":"0.1"}]}]}"#
    let contract = try value(repository(body).contract(instrument))
    XCTAssertEqual(contract.quantityStep, Decimal(string: "0.001"))
    XCTAssertEqual(contract.maximumQuantity, 100)
    XCTAssertThrowsError(try value(repository(body.replacingOccurrences(of: "MARKET_LOT_SIZE", with: "LOT_SIZE")).contract(instrument)))
    XCTAssertThrowsError(try value(repository(body.replacingOccurrences(of: "TRADING", with: "SETTLING")).contract(instrument)))
  }

  func testNetworkTargetsUseExclusiveEndWithoutAuthentication() {
    let target = BinanceFuturesNetworkService.candles("BTCUSDT", 60000, 120000)
    XCTAssertEqual(target.path, "/fapi/v1/markPriceKlines")
    guard case .requestParameters(let parameters, _) = target.task else { return XCTFail("Missing parameters") }
    XCTAssertEqual(parameters["endTime"] as? Int64, 119999)
    XCTAssertEqual(parameters["interval"] as? String, "1m")
    XCTAssertNil(target.headers?["X-MBX-APIKEY"])
  }
}
