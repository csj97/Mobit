//
//  BithumbExchangeAdapter.swift
//  Mobit
//
//  Created by Codex on 7/9/26.
//

import Foundation
import Moya

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

    return try decoder.decode(BithumbTickerSocketDTO.self, from: data).toDomain()
  }

  func decodeOrderBookWebSocketMessage(
    from data: Data
  ) throws -> Orderbook? {
    if let status = try? decoder.decode(BithumbWebSocketStatusMessage.self, from: data),
       status.status != nil || status.error != nil {
      return nil
    }

    return try decoder.decode(BithumbOrderbookSocketDTO.self, from: data).toDomain()
  }
}

