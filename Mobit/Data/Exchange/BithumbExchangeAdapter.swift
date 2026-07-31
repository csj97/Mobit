//
//  BithumbExchangeAdapter.swift
//  Mobit
//
//  Created by Codex on 7/9/26.
//

import Foundation
import Moya
import RxSwift
import Starscream

struct BithumbExchangeAdapter: ExchangeMarketDataProviding {
  let exchange: Exchange = .bithumb
  private let decoder = JSONDecoder()

  func makeCryptoListTarget() -> MultiTarget {
    MultiTarget(BithumbMainNetworkService.getCryptoList)
  }

  func makeCryptoTickerTarget(markets: [String]) -> MultiTarget {
    MultiTarget(BithumbMainNetworkService.getCryptoTicker(markets: markets))
  }

  func makeCryptoInformationTarget(
    market: String,
    currency: String
  ) -> MultiTarget {
    MultiTarget(
      BithumbMainNetworkService.getCryptoInformation(
        market: market,
        currency: currency
      )
    )
  }

  func makeFearAndGreedIndexTarget() -> MultiTarget {
    MultiTarget(BithumbMainNetworkService.getFearAndGreedIndex)
  }

  func makeCandleMinutesTarget(
    market: String,
    unit: Int32,
    to: String?,
    count: Int?
  ) -> MultiTarget {
    MultiTarget(
      BithumbTradeNetworkService.getCandleListMinutes(
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
  ) -> MultiTarget {
    MultiTarget(
      BithumbTradeNetworkService.getCandleListDays(
        market: market,
        to: to,
        count: count,
        convertingPriceUnit: convertingPriceUnit
      )
    )
  }

  func makeTickerWebSocketClient() -> WebSocketClientProtocol {
    BithumbWebSocketClient(socketType: .ticker)
  }

  func makeOrderBookWebSocketClient() -> WebSocketClientProtocol {
    BithumbWebSocketClient(socketType: .orderbook)
  }

  func decodeCryptoList(from data: Data) throws -> CryptoList {
    try decoder.decode(BithumbCryptoListDTO.self, from: data).toDomain()
  }

  func decodeCryptoTickerList(from data: Data) throws -> CryptoTickerList {
    try decoder.decode(BithumbTickerListDTO.self, from: data).toDomain()
  }

  func decodeCryptoInformation(
    from data: Data,
    symbol: String
  ) throws -> CryptoQuoteResponse {
    try decoder.decode(CryptoQuoteResponseDTO.self, from: data)
      .toDomain(symbol: symbol)
  }

  func decodeMinuteCandles(from data: Data) throws -> [MinuteResponseModel] {
    try decoder.decode([BithumbMinuteCandleDTO].self, from: data).toDomainList()
  }

  func decodeDayCandles(from data: Data) throws -> [DayResponseModel] {
    try decoder.decode([BithumbDayCandleDTO].self, from: data).toDomainList()
  }

  func decodeTickerWebSocketMessage(
    from data: Data
  ) throws -> CryptoSocketTicker? {
    if let status = try? decoder.decode(BithumbWebSocketStatusMessage.self, from: data),
       status.status != nil || status.error != nil {
      return nil
    }

    if let decoded = try? decoder.decode(CryptoSocketTickerDTO.self, from: data) {
      return decoded.toDomain()
    }

    let message = try decoder.decode(BithumbTickerSocketEnvelope.self, from: data)
    guard let content = message.content else { return nil }
    return content.toDomain()
  }

  func decodeOrderBookWebSocketMessage(
    from data: Data
  ) throws -> Orderbook? {
    if let status = try? decoder.decode(BithumbWebSocketStatusMessage.self, from: data),
       status.status != nil || status.error != nil {
      return nil
    }

    if let decoded = try? decoder.decode(OrderbookDTO.self, from: data) {
      return decoded.toDomain()
    }

    let message = try decoder.decode(BithumbOrderBookSocketEnvelope.self, from: data)
    guard let content = message.content else { return nil }
    return content.toDomain()
  }
}

private struct BithumbCryptoDTO: Decodable {
  let market: String
  let koreanName: String
  let englishName: String
  let marketWarning: String?

  enum CodingKeys: String, CodingKey {
    case market
    case koreanName = "korean_name"
    case englishName = "english_name"
    case marketWarning = "market_warning"
  }
}

private typealias BithumbCryptoListDTO = [BithumbCryptoDTO]

private extension BithumbCryptoDTO {
  func toDomain() -> Crypto {
    let isWarning = marketWarning == "CAUTION"
    return .init(
      market: market,
      koreanName: koreanName,
      englishName: englishName,
      marketEvent: .init(
        warning: isWarning,
        caution: .init(
          priceFluctuations: false,
          tradingVolumeSoaring: false,
          depositAmountSoaring: false,
          globalPriceDifferences: false,
          concentrationOfSmallAccounts: false
        )
      )
    )
  }
}

private extension Array where Element == BithumbCryptoDTO {
  func toDomain() -> CryptoList {
    map { $0.toDomain() }
  }
}

// MARK: - Bithumb REST DTO
// 현재 Bithumb v1 REST 응답은 Upbit 스키마와 사실상 동일하지만,
// 추후 스펙 분기에 대비해 Upbit DTO와 분리된 전용 타입으로 디코딩한다.
// 필드가 달라지면 이 파일의 DTO만 수정하면 되고 Upbit 경로에는 영향이 없다.

private typealias BithumbTickerListDTO = [BithumbTickerDTO]

private struct BithumbTickerDTO: Decodable {
  let market: String
  let tradeDate: String?
  let tradeTime: String?
  let tradeDateKst: String?
  let tradeTimeKst: String?
  let tradeTimestamp: Int64?
  let openingPrice: Double?
  let highPrice: Double?
  let lowPrice: Double?
  let tradePrice: Double?
  let prevClosingPrice: Double?
  let change: String?
  let changePrice: Double?
  let changeRate: Double?
  let signedChangePrice: Double?
  let signedChangeRate: Double?
  let tradeVolume: Double?
  let accTradePrice: Double?
  let accTradePrice24h: Double?
  let accTradeVolume: Double?
  let accTradeVolume24h: Double?
  let highest52WeekPrice: Double?
  let highest52WeekDate: String?
  let lowest52WeekPrice: Double?
  let lowest52WeekDate: String?
  let timestamp: Int64?

  enum CodingKeys: String, CodingKey {
    case market
    case tradeDate = "trade_date"
    case tradeTime = "trade_time"
    case tradeDateKst = "trade_date_kst"
    case tradeTimeKst = "trade_time_kst"
    case tradeTimestamp = "trade_timestamp"
    case openingPrice = "opening_price"
    case highPrice = "high_price"
    case lowPrice = "low_price"
    case tradePrice = "trade_price"
    case prevClosingPrice = "prev_closing_price"
    case change
    case changePrice = "change_price"
    case changeRate = "change_rate"
    case signedChangePrice = "signed_change_price"
    case signedChangeRate = "signed_change_rate"
    case tradeVolume = "trade_volume"
    case accTradePrice = "acc_trade_price"
    case accTradePrice24h = "acc_trade_price_24h"
    case accTradeVolume = "acc_trade_volume"
    case accTradeVolume24h = "acc_trade_volume_24h"
    case highest52WeekPrice = "highest_52_week_price"
    case highest52WeekDate = "highest_52_week_date"
    case lowest52WeekPrice = "lowest_52_week_price"
    case lowest52WeekDate = "lowest_52_week_date"
    case timestamp
  }
}

private extension BithumbTickerDTO {
  func toDomain() -> CryptoTicker {
    .init(
      market: market,
      tradeDate: tradeDate ?? "",
      tradeTime: tradeTime ?? "",
      tradeDateKst: tradeDateKst ?? "",
      tradeTimeKst: tradeTimeKst ?? "",
      tradeTimestamp: tradeTimestamp ?? 0,
      openingPrice: openingPrice ?? 0,
      highPrice: highPrice ?? 0,
      lowPrice: lowPrice ?? 0,
      tradePrice: tradePrice ?? 0,
      prevClosingPrice: prevClosingPrice ?? 0,
      change: change ?? "EVEN",
      changePrice: changePrice ?? 0,
      changeRate: changeRate ?? 0,
      signedChangePrice: signedChangePrice ?? 0,
      signedChangeRate: signedChangeRate ?? 0,
      tradeVolume: tradeVolume ?? 0,
      accTradePrice: accTradePrice ?? 0,
      accTradePrice24h: accTradePrice24h ?? 0,
      accTradeVolume: accTradeVolume ?? 0,
      accTradeVolume24h: accTradeVolume24h ?? 0,
      highest52WeekPrice: highest52WeekPrice ?? 0,
      highest52WeekDate: highest52WeekDate ?? "",
      lowest52WeekPrice: lowest52WeekPrice ?? 0,
      lowest52WeekDate: lowest52WeekDate ?? "",
      timestamp: timestamp ?? 0
    )
  }
}

private extension Array where Element == BithumbTickerDTO {
  func toDomain() -> [CryptoTicker] {
    map { $0.toDomain() }
  }
}

private struct BithumbMinuteCandleDTO: Decodable {
  // 식별키(market)와 차트 렌더링 필수값(시간, OHLC)만 필수로 두고,
  // 누락돼도 폴백 가능한 보조 필드는 옵셔널로 완화해 단일 필드 누락이 배치 전체 디코딩을 깨지 않게 한다.
  let market: String
  let candle_date_time_utc: String
  let candle_date_time_kst: String
  let opening_price: Double
  let high_price: Double
  let low_price: Double
  let trade_price: Double
  let timestamp: Int64?
  let candle_acc_trade_price: Double?
  let candle_acc_trade_volume: Double?
  let unit: Int?
}

private extension BithumbMinuteCandleDTO {
  func toDomain() -> MinuteResponseModel {
    .init(
      market: market,
      candle_date_time_utc: candle_date_time_utc,
      candle_date_time_kst: candle_date_time_kst,
      opening_price: opening_price,
      high_price: high_price,
      low_price: low_price,
      trade_price: trade_price,
      timestamp: timestamp ?? 0,
      candle_acc_trade_price: candle_acc_trade_price ?? 0,
      candle_acc_trade_volume: candle_acc_trade_volume ?? 0,
      unit: unit ?? 1
    )
  }
}

private extension Array where Element == BithumbMinuteCandleDTO {
  func toDomainList() -> [MinuteResponseModel] {
    map { $0.toDomain() }
  }
}

private struct BithumbDayCandleDTO: Decodable {
  // 식별키(market)와 차트 렌더링 필수값(시간, OHLC)만 필수로 두고,
  // 누락돼도 폴백 가능한 보조 필드는 옵셔널로 완화한다. converted_trade_price는
  // convertingPriceUnit 파라미터가 있을 때만 내려오므로 문서상으로도 선택 필드다.
  let market: String
  let candle_date_time_utc: String
  let candle_date_time_kst: String
  let opening_price: Double
  let high_price: Double
  let low_price: Double
  let trade_price: Double
  let timestamp: Int64?
  let candle_acc_trade_price: Double?
  let candle_acc_trade_volume: Double?
  let prev_closing_price: Double?
  let change_price: Double?
  let change_rate: Double?
  let converted_trade_price: Double?
}

private extension BithumbDayCandleDTO {
  func toDomain() -> DayResponseModel {
    .init(
      market: market,
      candle_date_time_utc: candle_date_time_utc,
      candle_date_time_kst: candle_date_time_kst,
      opening_price: opening_price,
      high_price: high_price,
      low_price: low_price,
      trade_price: trade_price,
      timestamp: timestamp ?? 0,
      candle_acc_trade_price: candle_acc_trade_price ?? 0,
      candle_acc_trade_volume: candle_acc_trade_volume ?? 0,
      prev_closing_price: prev_closing_price ?? 0,
      change_price: change_price,
      change_rate: change_rate,
      converted_trade_price: converted_trade_price
    )
  }
}

private extension Array where Element == BithumbDayCandleDTO {
  func toDomainList() -> [DayResponseModel] {
    map { $0.toDomain() }
  }
}

private struct BithumbWebSocketStatusMessage: Decodable {
  struct ErrorPayload: Decodable {
    let name: String?
    let message: String?
  }

  let status: String?
  let resmsg: String?
  let error: ErrorPayload?
}

private enum BithumbMainNetworkService {
  case getCryptoList
  case getCryptoTicker(markets: [String])
  case getCryptoInformation(market: String, currency: String = "KRW")
  case getFearAndGreedIndex
}

private struct BithumbTickerSocketEnvelope: Decodable {
  let type: String?
  let content: Content?
  let status: String?
  let resmsg: String?

  struct Content: Decodable {
    let symbol: String
    let tickType: String?
    let date: String?
    let time: String?
    let openPrice: String?
    let closePrice: String?
    let lowPrice: String?
    let highPrice: String?
    let value: String?
    let volume: String?
    let sellVolume: String?
    let buyVolume: String?
    let prevClosePrice: String?
    let chgRate: String?
    let chgAmt: String?
    let volumePower: String?

    enum CodingKeys: String, CodingKey {
      case symbol
      case tickType
      case date
      case time
      case openPrice
      case closePrice
      case lowPrice
      case highPrice
      case value
      case volume
      case sellVolume
      case buyVolume
      case prevClosePrice
      case chgRate
      case chgAmt
      case volumePower
    }
  }
}

private extension BithumbTickerSocketEnvelope.Content {
  func toDomain() -> CryptoSocketTicker {
    let openingPrice = openPrice.asDouble
    let tradePrice = closePrice.asDouble
    let prevClosingPrice = prevClosePrice.asDouble
    let changePrice = chgAmt.asDouble
    let signedChangeRate = (chgRate.asDouble ?? 0) / 100
    let signedChangePrice = inferredSignedChangePrice(
      changePrice: changePrice,
      tradePrice: tradePrice,
      prevClosingPrice: prevClosingPrice
    )

    return .init(
      type: "ticker",
      code: normalizedMarketCode,
      openingPrice: openingPrice ?? 0,
      highPrice: lowRiskDouble(highPrice),
      lowPrice: lowRiskDouble(lowPrice),
      tradePrice: tradePrice ?? 0,
      prevClosingPrice: prevClosingPrice ?? 0,
      change: inferredChange(
        tradePrice: tradePrice,
        prevClosingPrice: prevClosingPrice
      ),
      changePrice: abs(changePrice ?? 0),
      signedChangePrice: signedChangePrice,
      changeRate: abs(signedChangeRate),
      signedChangeRate: signedChangeRate,
      tradeVolume: 0,
      accTradeVolume: volume.asDouble ?? 0,
      accTradeVolume24H: volume.asDouble ?? 0,
      accTradePrice: value.asDouble ?? 0,
      accTradePrice24H: value.asDouble ?? 0,
      tradeDate: date ?? "",
      tradeTime: time ?? "",
      tradeTimestamp: 0,
      askBid: "",
      accAskVolume: sellVolume.asDouble ?? 0,
      accBidVolume: buyVolume.asDouble ?? 0,
      highest52WeekPrice: 0,
      highest52WeekDate: "",
      lowest52WeekPrice: 0,
      lowest52WeekDate: "",
      marketState: "",
      delistingDate: nil,
      marketWarning: nil,
      timestamp: Int64(Date().timeIntervalSince1970 * 1000),
      streamType: tickType ?? ""
    )
  }

  private var normalizedMarketCode: String {
    BithumbMarketCodeNormalizer.normalize(symbol)
  }

  private func lowRiskDouble(_ value: String?) -> Double {
    value.asDouble ?? 0
  }

  private func inferredChange(
    tradePrice: Double?,
    prevClosingPrice: Double?
  ) -> String {
    guard let tradePrice, let prevClosingPrice else { return "EVEN" }
    if tradePrice > prevClosingPrice { return "RISE" }
    if tradePrice < prevClosingPrice { return "FALL" }
    return "EVEN"
  }

  private func inferredSignedChangePrice(
    changePrice: Double?,
    tradePrice: Double?,
    prevClosingPrice: Double?
  ) -> Double {
    let absoluteChange = abs(changePrice ?? 0)

    guard let tradePrice, let prevClosingPrice else {
      return absoluteChange
    }

    if tradePrice > prevClosingPrice { return absoluteChange }
    if tradePrice < prevClosingPrice { return -absoluteChange }
    return 0
  }
}

private struct BithumbOrderBookSocketEnvelope: Decodable {
  let type: String?
  let content: Content?
  let status: String?
  let resmsg: String?

  struct Content: Decodable {
    let symbol: String
    let datetime: String?
    let asks: [[String]]
    let bids: [[String]]
  }
}

private extension BithumbOrderBookSocketEnvelope.Content {
  func toDomain() -> Orderbook {
    let askUnits = asks.compactMap(Self.makeAskUnit)
    let bidUnits = bids.compactMap(Self.makeBidUnit)
    let maxCount = max(askUnits.count, bidUnits.count)

    let units = (0..<maxCount).map { index in
      let askUnit = askUnits[safe: index]
      let bidUnit = bidUnits[safe: index]

      return Orderbook.OrderbookUnit(
        askPrice: askUnit?.price ?? 0,
        bidPrice: bidUnit?.price ?? 0,
        askSize: askUnit?.size ?? 0,
        bidSize: bidUnit?.size ?? 0
      )
    }

    return .init(
      type: "orderbook",
      code: normalizedMarketCode,
      timestamp: Int(datetime ?? "") ?? 0,
      totalAskSize: askUnits.reduce(0) { $0 + $1.size },
      totalBidSize: bidUnits.reduce(0) { $0 + $1.size },
      orderbookUnits: units,
      streamType: "SNAPSHOT",
      level: 0
    )
  }

  private var normalizedMarketCode: String {
    BithumbMarketCodeNormalizer.normalize(symbol)
  }

  private static func makeAskUnit(from values: [String]) -> (price: Double, size: Double)? {
    guard values.count >= 2,
          let price = values[0].asDouble,
          let size = values[1].asDouble else {
      return nil
    }
    return (price, size)
  }

  private static func makeBidUnit(from values: [String]) -> (price: Double, size: Double)? {
    guard values.count >= 2,
          let price = values[0].asDouble,
          let size = values[1].asDouble else {
      return nil
    }
    return (price, size)
  }
}

private extension Optional where Wrapped == String {
  var asDouble: Double? {
    guard let self else { return nil }
    return Double(self)
  }
}

private extension String {
  var asDouble: Double? {
    Double(self)
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    guard indices.contains(index) else { return nil }
    return self[index]
  }
}

private enum BithumbMarketCodeNormalizer {
  static func normalize(_ rawSymbol: String) -> String {
    let displayMarket = ExchangeMarketCodeConverter.displayMarket(
      fromRawMarketCode: rawSymbol,
      exchange: .bithumb
    )

    return ExchangeMarketCodeConverter.rawMarketCode(
      fromDisplayMarket: displayMarket,
      exchange: .bithumb
    )
  }
}

extension BithumbMainNetworkService: TargetType {
  var baseURL: URL {
    switch self {
    case .getCryptoList:
      return URL(string: "https://api.bithumb.com/v1/market/all")!
    case .getCryptoTicker:
      return URL(string: "https://api.bithumb.com/v1/ticker")!
    case .getCryptoInformation:
      return URL(string: "https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest")!
    case .getFearAndGreedIndex:
      return URL(string: "https://pro-api.coinmarketcap.com/v3/fear-and-greed/latest")!
    }
  }

  var path: String {
    ""
  }

  var method: Moya.Method {
    .get
  }

  var task: Moya.Task {
    switch self {
    case .getCryptoList:
      return .requestParameters(
        parameters: ["isDetails": true],
        encoding: URLEncoding.queryString
      )

    case .getCryptoTicker(let markets):
      return .requestParameters(
        parameters: ["markets": markets.joined(separator: ",")],
        encoding: URLEncoding.queryString
      )

    case .getCryptoInformation(let market, let currency):
      return .requestParameters(
        parameters: ["symbol": market, "convert": currency],
        encoding: URLEncoding.queryString
      )

    case .getFearAndGreedIndex:
      return .requestPlain
    }
  }

  var headers: [String: String]? {
    switch self {
    case .getCryptoInformation, .getFearAndGreedIndex:
      guard let apiKey = Environment.coinMarketCapApiKey else { return nil }
      return ["X-CMC_PRO_API_KEY": apiKey]
    default:
      return [
        "Accept": "application/json",
        "Content-type": "application/json"
      ]
    }
  }
}

private enum BithumbTradeNetworkService {
  case getCandleListMinutes(market: String, unit: Int32, to: String?, count: Int?)
  case getCandleListDays(market: String, to: String?, count: Int?, convertingPriceUnit: String?)
}

extension BithumbTradeNetworkService: TargetType {
  var baseURL: URL {
    URL(string: "https://api.bithumb.com/v1/candles")!
  }

  var path: String {
    switch self {
    case .getCandleListMinutes(_, let unit, _, _):
      return "/minutes/\(unit)"
    case .getCandleListDays:
      return "/days"
    }
  }

  var method: Moya.Method {
    .get
  }

  var task: Moya.Task {
    switch self {
    case .getCandleListMinutes(let market, _, let to, let count):
      var parameters: [String: Any] = ["market": market]
      if let to {
        parameters["to"] = Self.candleToParameter(from: to)
      }
      if let count {
        parameters["count"] = count
      }
      return .requestParameters(parameters: parameters, encoding: URLEncoding.queryString)

    case .getCandleListDays(let market, let to, let count, let convertingPriceUnit):
      var parameters: [String: Any] = ["market": market]
      if let to {
        parameters["to"] = Self.candleToParameter(from: to)
      }
      if let count {
        parameters["count"] = count
      }
      if let convertingPriceUnit {
        parameters["convertingPriceUnit"] = convertingPriceUnit
      }
      return .requestParameters(parameters: parameters, encoding: URLEncoding.queryString)
    }
  }

  var headers: [String: String]? {
    [
      "Accept": "application/json",
      "Content-type": "application/json"
    ]
  }

  // 빗썸 캔들 API는 타임존 suffix(Z/offset)와 소수초를 거부하고, tz 없는 시각을 KST로 해석한다.
  // 앱은 to를 UTC ISO8601로 넘기므로, 같은 순간의 KST 벽시계(yyyy-MM-dd'T'HH:mm:ss)로 변환해 전달한다.
  // (Z만 떼면 UTC 값이 KST로 오해돼 9시간 과거 캔들이 조회된다.)
  private static func candleToParameter(from to: String) -> String {
    let isoWithFraction = ISO8601DateFormatter()
    isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let isoPlain = ISO8601DateFormatter()
    isoPlain.formatOptions = [.withInternetDateTime]
    guard let date = isoWithFraction.date(from: to) ?? isoPlain.date(from: to) else {
      return to
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter.string(from: date)
  }
}

private final class BithumbWebSocketClient: WebSocketDelegate, WebSocketClientProtocol {
  private static let reconnectDelay: TimeInterval = 1

  private enum SubscriptionType: String {
    case ticker
    case orderbook
  }

  private let socket: WebSocket
  private let socketType: SocketType
  private let connectedSubject = PublishSubject<Void>()
  private let dataSubject = PublishSubject<Data>()

  private(set) var isConnected = false
  private var isConnecting = false
  private var isUserInitiatedDisconnect = false
  private var reconnectWorkItem: DispatchWorkItem?

  init(socketType: SocketType) {
    self.socketType = socketType

    var request = URLRequest(url: URL(string: "wss://ws-api.bithumb.com/websocket/v1")!)
    request.timeoutInterval = 5

    self.socket = WebSocket(request: request)
    self.socket.delegate = self
  }

  var onConnected: Observable<Void> {
    connectedSubject.asObservable()
  }

  var rawDataStream: Observable<Data> {
    dataSubject.asObservable()
  }

  func connect() {
    guard !isConnected, !isConnecting else { return }
    reconnectWorkItem?.cancel()
    reconnectWorkItem = nil
    isUserInitiatedDisconnect = false
    isConnecting = true
    socket.connect()
  }

  func disconnect(userInitiated: Bool = false) {
    isUserInitiatedDisconnect = userInitiated
    if userInitiated {
      reconnectWorkItem?.cancel()
      reconnectWorkItem = nil
    }
    guard isConnected || isConnecting else { return }

    Log.info("Disconnecting bithumb \(socketType.rawValue) socket...")
    isConnecting = false
    socket.disconnect()
  }

  func reconnectIfNeeded() {
    guard !isUserInitiatedDisconnect, !isConnected else { return }
    Log.info("Reconnecting bithumb \(socketType.rawValue) socket...")
    connect()
  }

  func sendSubscription(codes: [String]) {
    guard isConnected, !codes.isEmpty else { return }

    let payload = self.subscriptionPayload(codes: codes)
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
      return
    }

    socket.write(data: data) {
      Log.info("bithumb \(self.socketType.rawValue) subscription sent")
    }
  }

  func didReceive(
    event: Starscream.WebSocketEvent,
    client: any Starscream.WebSocketClient
  ) {
    switch event {
    case .connected:
      reconnectWorkItem?.cancel()
      reconnectWorkItem = nil
      isConnecting = false
      isConnected = true
      connectedSubject.onNext(())

    case .binary(let data):
      dataSubject.onNext(data)

    case .text(let text):
      guard let data = text.data(using: .utf8) else { return }
      dataSubject.onNext(data)

    case .disconnected:
      isConnecting = false
      isConnected = false
      scheduleReconnectIfNeeded()

    case .error:
      isConnecting = false
      isConnected = false
      scheduleReconnectIfNeeded()

    case .cancelled:
      isConnecting = false
      isConnected = false
      scheduleReconnectIfNeeded()

    case .reconnectSuggested(let shouldReconnect):
      guard shouldReconnect else { return }
      scheduleReconnectIfNeeded()

    case .peerClosed:
      isConnecting = false
      isConnected = false
      scheduleReconnectIfNeeded()

    case .ping, .pong, .viabilityChanged:
      break
    }
  }

  private func scheduleReconnectIfNeeded() {
    guard !isUserInitiatedDisconnect,
          !isConnected,
          !isConnecting,
          reconnectWorkItem == nil else { return }

    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.reconnectWorkItem = nil
      self.reconnectIfNeeded()
    }
    reconnectWorkItem = workItem
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.reconnectDelay,
      execute: workItem
    )
  }

  private func subscriptionPayload(codes: [String]) -> [[String: Any]] {
    switch socketType {
    case .ticker:
      return [
        ["ticket": UUID().uuidString],
        [
          "type": SubscriptionType.ticker.rawValue,
          "codes": codes
        ]
      ]

    case .orderbook:
      return [
        ["ticket": UUID().uuidString],
        [
          "type": SubscriptionType.orderbook.rawValue,
          "codes": codes
        ]
      ]
    }
  }
}
