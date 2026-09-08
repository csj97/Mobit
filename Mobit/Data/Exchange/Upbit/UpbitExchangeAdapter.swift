//
//  UpbitExchangeAdapter.swift
//  Mobit
//
//  Created by 조성재 on 7/9/26.
//

import Foundation
import Moya

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
