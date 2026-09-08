//
//  SocketServiceTests.swift
//  MobitTests
//
//  Created by Codex on 6/29/26.
//

import XCTest
import Moya
import RxSwift
@testable import Mobit

final class SocketServiceTests: XCTestCase {
  private let disposeBag = DisposeBag()

  func testTickerServiceBuildsClientFromExchangeProviderWhenClientIsMissing() {
    let tickerClient = MockWebSocketClient()
    let provider = MockExchangeMarketDataProvider(
      tickerClient: tickerClient,
      orderBookClient: MockWebSocketClient()
    )
    let service = TickerSocketService(exchangeProvider: provider)

    service.connect()
    service.subscribe(markets: ["KRW-BTC"])

    XCTAssertEqual(provider.makeTickerWebSocketClientCallCount, 1)
    XCTAssertEqual(provider.makeOrderBookWebSocketClientCallCount, 0)
    XCTAssertEqual(tickerClient.connectCallCount, 1)
    XCTAssertEqual(tickerClient.sentSubscriptions, [["KRW-BTC"]])
  }

  func testOrderBookServiceBuildsClientFromExchangeProviderWhenClientIsMissing() {
    let orderBookClient = MockWebSocketClient()
    let provider = MockExchangeMarketDataProvider(
      tickerClient: MockWebSocketClient(),
      orderBookClient: orderBookClient
    )
    let service = OrderBookSocketService(exchangeProvider: provider)

    service.connect()
    service.subscribe(market: "KRW-BTC")

    XCTAssertEqual(provider.makeTickerWebSocketClientCallCount, 0)
    XCTAssertEqual(provider.makeOrderBookWebSocketClientCallCount, 1)
    XCTAssertEqual(orderBookClient.connectCallCount, 1)
    XCTAssertEqual(orderBookClient.sentSubscriptions, [["KRW-BTC"]])
  }

  func testTickerSubscribeSkipsDuplicateMarketSubscriptions() {
    let client = MockWebSocketClient()
    let service = TickerSocketService(client: client)

    client.connect()
    service.subscribe(markets: ["KRW-BTC", "KRW-ETH", "KRW-BTC"])
    service.subscribe(markets: ["KRW-ETH", "KRW-BTC"])

    XCTAssertEqual(client.sentSubscriptions, [["KRW-BTC", "KRW-ETH"]])
  }

  func testTickerResubscribesAfterNonUserInitiatedReconnect() {
    let client = MockWebSocketClient()
    let service = TickerSocketService(client: client)

    client.connect()
    service.subscribe(markets: ["KRW-BTC"])
    service.disconnect(userInitiated: false)
    client.connect()

    XCTAssertEqual(client.sentSubscriptions, [["KRW-BTC"], ["KRW-BTC"]])
  }

  func testTickerUserInitiatedDisconnectClearsPendingSubscription() {
    let client = MockWebSocketClient()
    let service = TickerSocketService(client: client)

    client.connect()
    service.subscribe(markets: ["KRW-BTC"])
    service.disconnect(userInitiated: true)
    client.connect()

    XCTAssertEqual(client.sentSubscriptions, [["KRW-BTC"]])
  }

  func testOrderBookSubscribeSkipsDuplicateMarketSubscriptions() {
    let client = MockWebSocketClient()
    let service = OrderBookSocketService(client: client)

    client.connect()
    service.subscribe(market: "KRW-BTC")
    service.subscribe(market: "KRW-BTC")

    XCTAssertEqual(client.sentSubscriptions, [["KRW-BTC"]])
  }

  func testOrderBookResubscribesAfterNonUserInitiatedReconnect() {
    let client = MockWebSocketClient()
    let service = OrderBookSocketService(client: client)

    client.connect()
    service.subscribe(market: "KRW-BTC")
    service.disconnect(userInitiated: false)
    client.connect()

    XCTAssertEqual(client.sentSubscriptions, [["KRW-BTC"], ["KRW-BTC"]])
  }

  func testTickerStreamUsesExchangeProviderDecoder() {
    let client = MockWebSocketClient()
    let expectedTicker = CryptoSocketTicker(
      type: "ticker",
      code: "KRW-BTC",
      openingPrice: 1,
      highPrice: 2,
      lowPrice: 0.5,
      tradePrice: 1.5,
      prevClosingPrice: 1.2,
      change: "RISE",
      changePrice: 0.3,
      signedChangePrice: 0.3,
      changeRate: 0.25,
      signedChangeRate: 0.25,
      tradeVolume: 0,
      accTradeVolume: 10,
      accTradeVolume24H: 10,
      accTradePrice: 15,
      accTradePrice24H: 15,
      tradeDate: "20260709",
      tradeTime: "120000",
      tradeTimestamp: 0,
      askBid: "",
      accAskVolume: 0,
      accBidVolume: 0,
      highest52WeekPrice: 0,
      highest52WeekDate: "",
      lowest52WeekPrice: 0,
      lowest52WeekDate: "",
      marketState: "",
      delistingDate: nil,
      marketWarning: nil,
      timestamp: 1,
      streamType: "SNAPSHOT"
    )
    let provider = MockExchangeMarketDataProvider(
      tickerClient: client,
      orderBookClient: MockWebSocketClient(),
      decodedTicker: expectedTicker
    )
    let service = TickerSocketService(client: client, exchangeProvider: provider)

    let expectation = expectation(description: "ticker decoded")
    var receivedTicker: CryptoSocketTicker?

    service.stream
      .subscribe(onNext: { ticker in
        receivedTicker = ticker
        expectation.fulfill()
      })
      .disposed(by: disposeBag)

    client.emitRawData(Data("ignored".utf8))

    wait(for: [expectation], timeout: 1)

    XCTAssertEqual(receivedTicker?.code, "KRW-BTC")
    XCTAssertEqual(provider.decodeTickerWebSocketMessageCallCount, 1)
  }

  func testOrderBookStreamUsesExchangeProviderDecoder() {
    let client = MockWebSocketClient()
    let expectedOrderBook = Orderbook(
      type: "orderbook",
      code: "KRW-BTC",
      timestamp: 1,
      totalAskSize: 3,
      totalBidSize: 4,
      orderbookUnits: [
        .init(askPrice: 101, bidPrice: 100, askSize: 1, bidSize: 2)
      ],
      streamType: "SNAPSHOT",
      level: 0
    )
    let provider = MockExchangeMarketDataProvider(
      tickerClient: MockWebSocketClient(),
      orderBookClient: client,
      decodedOrderBook: expectedOrderBook
    )
    let service = OrderBookSocketService(
      client: client,
      exchangeProvider: provider
    )

    let expectation = expectation(description: "orderbook decoded")
    var receivedOrderBook: Orderbook?

    service.stream
      .subscribe(onNext: { orderBook in
        receivedOrderBook = orderBook
        expectation.fulfill()
      })
      .disposed(by: disposeBag)

    client.emitRawData(Data("ignored".utf8))

    wait(for: [expectation], timeout: 1)

    XCTAssertEqual(receivedOrderBook?.code, "KRW-BTC")
    XCTAssertEqual(provider.decodeOrderBookWebSocketMessageCallCount, 1)
  }

  func testBithumbTickerSocketDecoderIgnoresStatusMessage() throws {
    let adapter = BithumbExchangeAdapter()
    let data = Data(#"{"status":"0000","resmsg":"Connected Successfully"}"#.utf8)

    let decoded = try adapter.decodeTickerWebSocketMessage(from: data)

    XCTAssertNil(decoded)
  }

  func testBithumbTickerSocketDecoderMapsContentToDomain() throws {
    let adapter = BithumbExchangeAdapter()
    let data = Data(
      #"""
      {
        "type":"ticker",
        "code":"KRW-BTC",
        "opening_price":100,
        "high_price":130,
        "low_price":90,
        "trade_price":120,
        "prev_closing_price":110,
        "change":"RISE",
        "change_price":10,
        "signed_change_price":10,
        "change_rate":0.0909,
        "signed_change_rate":0.0909,
        "trade_volume":1.25,
        "acc_trade_volume":10,
        "acc_trade_volume_24h":10,
        "acc_trade_price":1000,
        "acc_trade_price_24h":1000,
        "trade_date":"20260709",
        "trade_time":"120000",
        "trade_timestamp":1720500000000,
        "ask_bid":"BID",
        "acc_ask_volume":4,
        "acc_bid_volume":6,
        "highest_52_week_price":200,
        "highest_52_week_date":"2026-01-01",
        "lowest_52_week_price":50,
        "lowest_52_week_date":"2026-02-01",
        "market_state":"ACTIVE",
        "is_trading_suspended":false,
        "delisting_date":null,
        "market_warning":"NONE",
        "timestamp":1720500000100,
        "stream_type":"SNAPSHOT"
      }
      """#.utf8
    )

    let decoded = try adapter.decodeTickerWebSocketMessage(from: data)

    XCTAssertEqual(decoded?.code, "KRW-BTC")
    XCTAssertEqual(decoded?.tradePrice, 120)
    XCTAssertEqual(decoded?.change, "RISE")
    XCTAssertEqual(decoded?.signedChangePrice, 10)
    XCTAssertEqual(decoded?.signedChangeRate ?? 0, 0.0909, accuracy: 0.0001)
  }

  func testBithumbTickerSocketDecoderIgnoresStatusUpMessage() throws {
    let adapter = BithumbExchangeAdapter()
    let data = Data(#"{"status":"UP"}"#.utf8)

    let decoded = try adapter.decodeTickerWebSocketMessage(from: data)

    XCTAssertNil(decoded)
  }

  func testBithumbCryptoListDecoderMapsMarketWarningField() throws {
    let adapter = BithumbExchangeAdapter()
    let data = Data(
      #"""
      [
        {
          "market": "KRW-BTC",
          "korean_name": "비트코인",
          "english_name": "Bitcoin",
          "market_warning": "NONE"
        },
        {
          "market": "BTC-ETH",
          "korean_name": "이더리움",
          "english_name": "Ethereum",
          "market_warning": "CAUTION"
        }
      ]
      """#.utf8
    )

    let decoded = try adapter.decodeCryptoList(from: data)

    XCTAssertEqual(decoded.count, 2)
    XCTAssertEqual(decoded[0].market, "KRW-BTC")
    XCTAssertFalse(decoded[0].marketEvent.warning)
    XCTAssertEqual(decoded[1].market, "BTC-ETH")
    XCTAssertTrue(decoded[1].marketEvent.warning)
  }

  func testBithumbTickerRestDecoderMapsDocumentedFields() throws {
    let adapter = BithumbExchangeAdapter()
    let data = Data(
      #"""
      [
        {
          "market": "KRW-BTC",
          "trade_date": "20260709",
          "trade_time": "120000",
          "trade_date_kst": "20260709",
          "trade_time_kst": "210000",
          "trade_timestamp": 1720500000000,
          "opening_price": 100.0,
          "high_price": 130.0,
          "low_price": 90.0,
          "trade_price": 120.0,
          "prev_closing_price": 110.0,
          "change": "RISE",
          "change_price": 10.0,
          "change_rate": 0.0909,
          "signed_change_price": 10.0,
          "signed_change_rate": 0.0909,
          "trade_volume": 1.2,
          "acc_trade_price": 1000.0,
          "acc_trade_price_24h": 1500.0,
          "acc_trade_volume": 10.0,
          "acc_trade_volume_24h": 15.0,
          "highest_52_week_price": 200.0,
          "highest_52_week_date": "2026-01-01",
          "lowest_52_week_price": 50.0,
          "lowest_52_week_date": "2026-02-01",
          "timestamp": 1720500000100
        }
      ]
      """#.utf8
    )

    let decoded = try adapter.decodeCryptoTickerList(from: data)

    XCTAssertEqual(decoded.count, 1)
    XCTAssertEqual(decoded[0].market, "KRW-BTC")
    XCTAssertEqual(decoded[0].tradePrice, 120)
    XCTAssertEqual(decoded[0].signedChangeRate, 0.0909)
    XCTAssertEqual(decoded[0].highest52WeekPrice, 200)
  }

  func testBithumbMinuteCandleDecoderMapsDocumentedFields() throws {
    let adapter = BithumbExchangeAdapter()
    let data = Data(
      #"""
      [
        {
          "market": "KRW-BTC",
          "candle_date_time_utc": "2026-07-09T12:00:00",
          "candle_date_time_kst": "2026-07-09T21:00:00",
          "opening_price": 100.0,
          "high_price": 130.0,
          "low_price": 90.0,
          "trade_price": 120.0,
          "timestamp": 1720500000000,
          "candle_acc_trade_price": 10000.0,
          "candle_acc_trade_volume": 123.45,
          "unit": 60
        }
      ]
      """#.utf8
    )

    let decoded = try adapter.decodeMinuteCandles(from: data)

    XCTAssertEqual(decoded.count, 1)
    XCTAssertEqual(decoded[0].market, "KRW-BTC")
    XCTAssertEqual(decoded[0].trade_price, 120)
    XCTAssertEqual(decoded[0].unit, 60)
  }

  func testBithumbOrderBookSocketDecoderMapsSnapshotToDomain() throws {
    let adapter = BithumbExchangeAdapter()
    let data = Data(
      #"""
      {
        "type":"orderbooksnapshot",
        "content":{
          "symbol":"BTC_KRW",
          "datetime":"1720500000000",
          "asks":[["101","1.5"],["102","2.5"]],
          "bids":[["100","3.5"],["99","4.5"]]
        }
      }
      """#.utf8
    )

    let decoded = try adapter.decodeOrderBookWebSocketMessage(from: data)

    XCTAssertEqual(decoded?.code, "KRW-BTC")
    XCTAssertEqual(decoded?.orderbookUnits.count, 2)
    XCTAssertEqual(decoded?.orderbookUnits.first?.askPrice, 101)
    XCTAssertEqual(decoded?.orderbookUnits.first?.bidPrice, 100)
    XCTAssertEqual(decoded?.totalAskSize, 4.0)
    XCTAssertEqual(decoded?.totalBidSize, 8.0)
  }

  func testBithumbTickerSocketLegacyEnvelopeNormalizesSymbol() throws {
    let adapter = BithumbExchangeAdapter()
    let data = Data(
      #"""
      {
        "type":"ticker",
        "content":{
          "symbol":"BTC_KRW",
          "tickType":"24H",
          "date":"20260709",
          "time":"120000",
          "openPrice":"100",
          "closePrice":"120",
          "lowPrice":"90",
          "highPrice":"130",
          "value":"1000",
          "volume":"10",
          "sellVolume":"4",
          "buyVolume":"6",
          "prevClosePrice":"110",
          "chgRate":"9.09",
          "chgAmt":"10",
          "volumePower":"150"
        }
      }
      """#.utf8
    )

    let decoded = try adapter.decodeTickerWebSocketMessage(from: data)

    XCTAssertEqual(decoded?.code, "KRW-BTC")
    XCTAssertEqual(decoded?.tradePrice, 120)
    XCTAssertEqual(decoded?.signedChangeRate ?? 0, 0.0909, accuracy: 0.0001)
  }
}

private final class MockExchangeMarketDataProvider: ExchangeMarketDataProviding {
  let exchange: Exchange = .upbit

  private let tickerClient: MockWebSocketClient
  private let orderBookClient: MockWebSocketClient
  private let decodedTicker: CryptoSocketTicker?
  private let decodedOrderBook: Orderbook?

  private(set) var makeTickerWebSocketClientCallCount = 0
  private(set) var makeOrderBookWebSocketClientCallCount = 0
  private(set) var decodeTickerWebSocketMessageCallCount = 0
  private(set) var decodeOrderBookWebSocketMessageCallCount = 0

  init(
    tickerClient: MockWebSocketClient,
    orderBookClient: MockWebSocketClient,
    decodedTicker: CryptoSocketTicker? = nil,
    decodedOrderBook: Orderbook? = nil
  ) {
    self.tickerClient = tickerClient
    self.orderBookClient = orderBookClient
    self.decodedTicker = decodedTicker
    self.decodedOrderBook = decodedOrderBook
  }

  func makeCryptoListTarget() -> Moya.MultiTarget {
    Moya.MultiTarget(MainNetworkService.getCryptoList)
  }

  func makeCryptoTickerTarget(markets: [String]) -> Moya.MultiTarget {
    Moya.MultiTarget(MainNetworkService.getCryptoTicker(markets: markets))
  }

  func makeCryptoInformationTarget(
    market: String,
    currency: String
  ) -> Moya.MultiTarget {
    Moya.MultiTarget(
      MainNetworkService.getCryptoInformation(
        market: market,
        currency: currency
      )
    )
  }

  func makeFearAndGreedIndexTarget() -> Moya.MultiTarget {
    Moya.MultiTarget(MainNetworkService.getFearAndGreedIndex)
  }

  func makeCandleMinutesTarget(
    market: String,
    unit: Int32,
    to: String?,
    count: Int?
  ) -> Moya.MultiTarget {
    Moya.MultiTarget(
      TradeNetworkService.getCandleListMinutes(
        market: market,
        unit: unit,
        to: to,
        count: count
      )
    )
  }

  func makeCandleDaysTarget(
    market: String,
    to: String?,
    count: Int?,
    convertingPriceUnit: String?
  ) -> Moya.MultiTarget {
    Moya.MultiTarget(
      TradeNetworkService.getCandleListDays(
        market: market,
        to: to,
        count: count,
        convertingPriceUnit: convertingPriceUnit
      )
    )
  }

  func makeTickerWebSocketClient() -> WebSocketClientProtocol {
    makeTickerWebSocketClientCallCount += 1
    return tickerClient
  }

  func makeOrderBookWebSocketClient() -> WebSocketClientProtocol {
    makeOrderBookWebSocketClientCallCount += 1
    return orderBookClient
  }

  func decodeCryptoList(from data: Data) throws -> CryptoList {
    []
  }

  func decodeCryptoTickerList(from data: Data) throws -> CryptoTickerList {
    []
  }

  func decodeCryptoInformation(
    from data: Data,
    symbol: String
  ) throws -> CryptoQuoteResponse {
    throw ErrorType.decodingFailed
  }

  func decodeMinuteCandles(from data: Data) throws -> [MinuteResponseModel] {
    []
  }

  func decodeDayCandles(from data: Data) throws -> [DayResponseModel] {
    []
  }

  func decodeTickerWebSocketMessage(
    from data: Data
  ) throws -> CryptoSocketTicker? {
    decodeTickerWebSocketMessageCallCount += 1
    return decodedTicker
  }

  func decodeOrderBookWebSocketMessage(
    from data: Data
  ) throws -> Orderbook? {
    decodeOrderBookWebSocketMessageCallCount += 1
    return decodedOrderBook
  }
}

private final class MockWebSocketClient: WebSocketClientProtocol {
  private let connectedSubject = PublishSubject<Void>()
  private let dataSubject = PublishSubject<Data>()

  private(set) var isConnected = false
  private(set) var connectCallCount = 0
  private(set) var disconnectCallCount = 0
  private(set) var sentSubscriptions: [[String]] = []
  private var isUserInitiatedDisconnect = false

  var onConnected: Observable<Void> {
    connectedSubject.asObservable()
  }

  var rawDataStream: Observable<Data> {
    dataSubject.asObservable()
  }

  func connect() {
    guard !isConnected else { return }
    connectCallCount += 1
    isUserInitiatedDisconnect = false
    isConnected = true
    connectedSubject.onNext(())
  }

  func disconnect(userInitiated: Bool) {
    disconnectCallCount += 1
    isUserInitiatedDisconnect = userInitiated
    isConnected = false
  }

  func reconnectIfNeeded() {
    guard !isUserInitiatedDisconnect, !isConnected else { return }
    connect()
  }

  func sendSubscription(codes: [String]) {
    guard isConnected else { return }
    sentSubscriptions.append(codes)
  }

  func emitRawData(_ data: Data) {
    dataSubject.onNext(data)
  }
}

// 임시 진단: 빗썸 로드 후 업비트 로드가 실패하는지 실제 네트워크로 재현
final class ExchangeSwitchLoadDiagTests: XCTestCase {
  private let bag = DisposeBag()

  private func load(exchange: Exchange) -> (list: Int, listErr: String?, tickerErr: String?) {
    ExchangeSelectionStore.currentExchange = exchange
    let repo = MainRepository()
    var listCount = -1
    var listErr: String?
    var tickerErr: String?
    var markets: [String] = []

    let listExp = expectation(description: "list-\(exchange.rawValue)")
    repo.loadCryptoList().subscribe(
      onNext: { markets = $0.map { $0.market }; listCount = $0.count },
      onError: { listErr = "\($0)"; listExp.fulfill() },
      onCompleted: { listExp.fulfill() }
    ).disposed(by: bag)
    wait(for: [listExp], timeout: 30)

    guard listErr == nil, !markets.isEmpty else { return (listCount, listErr, tickerErr) }

    let tickerExp = expectation(description: "ticker-\(exchange.rawValue)")
    repo.loadCryptoTicker(markets: markets).subscribe(
      onNext: { _ in },
      onError: { tickerErr = "\($0)"; tickerExp.fulfill() },
      onCompleted: { tickerExp.fulfill() }
    ).disposed(by: bag)
    wait(for: [tickerExp], timeout: 40)

    return (listCount, listErr, tickerErr)
  }

  func testUpbitLoadAfterBithumb() throws {
    let b = load(exchange: .bithumb)
    print("🧪DIAG BITHUMB list=\(b.list) listErr=\(String(describing: b.listErr)) tickerErr=\(String(describing: b.tickerErr))")
    let u = load(exchange: .upbit)
    print("🧪DIAG UPBIT list=\(u.list) listErr=\(String(describing: u.listErr)) tickerErr=\(String(describing: u.tickerErr))")
    XCTAssertNil(u.listErr, "UPBIT listErr=\(String(describing: u.listErr)) | tickerErr=\(String(describing: u.tickerErr))")
    XCTAssertNil(u.tickerErr, "UPBIT tickerErr=\(String(describing: u.tickerErr))")
  }
}
