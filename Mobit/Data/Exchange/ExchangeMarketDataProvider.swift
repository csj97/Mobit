//
//  ExchangeMarketDataProvider.swift
//  Mobit
//
//  Created by Codex on 7/8/26.
//

import Foundation
import Moya

protocol ExchangeMarketDataProviding {
  var exchange: Exchange { get }

  func makeCryptoListTarget() -> MultiTarget
  func makeCryptoTickerTarget(markets: [String]) -> MultiTarget
  func makeCryptoInformationTarget(market: String, currency: String) -> MultiTarget
  func makeFearAndGreedIndexTarget() -> MultiTarget
  func makeCandleMinutesTarget(
    market: String,
    unit: Int32,
    to: String?,
    count: Int?
  ) -> MultiTarget
  func makeCandleDaysTarget(
    market: String,
    to: String?,
    count: Int?,
    convertingPriceUnit: String?
  ) -> MultiTarget

  func makeTickerWebSocketClient() -> WebSocketClientProtocol
  func makeOrderBookWebSocketClient() -> WebSocketClientProtocol

  func decodeCryptoList(from data: Data) throws -> CryptoList
  func decodeCryptoTickerList(from data: Data) throws -> CryptoTickerList
  func decodeCryptoInformation(
    from data: Data,
    symbol: String
  ) throws -> CryptoQuoteResponse
  func decodeMinuteCandles(from data: Data) throws -> [MinuteResponseModel]
  func decodeDayCandles(from data: Data) throws -> [DayResponseModel]
  func decodeTickerWebSocketMessage(
    from data: Data
  ) throws -> CryptoSocketTicker?
  func decodeOrderBookWebSocketMessage(
    from data: Data
  ) throws -> Orderbook?
}

struct ExchangeAdapterRegistry {
  static var `default`: ExchangeMarketDataProviding {
    self.provider(for: ExchangeSelectionStore.currentExchange)
  }

  static func provider(for exchange: Exchange) -> ExchangeMarketDataProviding {
    switch exchange {
    case .upbit:
      return UpbitExchangeAdapter()
    case .bithumb:
      return BithumbExchangeAdapter()
    case .binance, .okx:
      return UpbitExchangeAdapter()
    }
  }
}

struct UpbitExchangeAdapter: ExchangeMarketDataProviding {
  let exchange: Exchange = .upbit
  private let decoder = JSONDecoder()

  func makeCryptoListTarget() -> MultiTarget {
    MultiTarget(MainNetworkService.getCryptoList)
  }

  func makeCryptoTickerTarget(markets: [String]) -> MultiTarget {
    MultiTarget(MainNetworkService.getCryptoTicker(markets: markets))
  }

  func makeCryptoInformationTarget(
    market: String,
    currency: String
  ) -> MultiTarget {
    MultiTarget(
      MainNetworkService.getCryptoInformation(
        market: market,
        currency: currency
      )
    )
  }

  func makeFearAndGreedIndexTarget() -> MultiTarget {
    MultiTarget(MainNetworkService.getFearAndGreedIndex)
  }

  func makeCandleMinutesTarget(
    market: String,
    unit: Int32,
    to: String?,
    count: Int?
  ) -> MultiTarget {
    MultiTarget(
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
  ) -> MultiTarget {
    MultiTarget(
      TradeNetworkService.getCandleListDays(
        market: market,
        to: to,
        count: count,
        convertingPriceUnit: convertingPriceUnit
      )
    )
  }

  func makeTickerWebSocketClient() -> WebSocketClientProtocol {
    UpbitWebSocketClient(socketType: .ticker)
  }

  func makeOrderBookWebSocketClient() -> WebSocketClientProtocol {
    UpbitWebSocketClient(socketType: .orderbook)
  }

  func decodeCryptoList(from data: Data) throws -> CryptoList {
    try decoder.decode(CryptoListDTO.self, from: data).toDomain()
  }

  func decodeCryptoTickerList(from data: Data) throws -> CryptoTickerList {
    try decoder.decode(CryptoTickerListDTO.self, from: data).toDomain()
  }

  func decodeCryptoInformation(
    from data: Data,
    symbol: String
  ) throws -> CryptoQuoteResponse {
    try decoder.decode(CryptoQuoteResponseDTO.self, from: data)
      .toDomain(symbol: symbol)
  }

  func decodeMinuteCandles(from data: Data) throws -> [MinuteResponseModel] {
    try decoder.decode([MinuteResponseModelDTO].self, from: data).toDomainList()
  }

  func decodeDayCandles(from data: Data) throws -> [DayResponseModel] {
    try decoder.decode([DayResponseModelDTO].self, from: data).toDomainList()
  }

  func decodeTickerWebSocketMessage(
    from data: Data
  ) throws -> CryptoSocketTicker? {
    try decoder.decode(CryptoSocketTickerDTO.self, from: data).toDomain()
  }

  func decodeOrderBookWebSocketMessage(
    from data: Data
  ) throws -> Orderbook? {
    try decoder.decode(OrderbookDTO.self, from: data).toDomain()
  }
}
