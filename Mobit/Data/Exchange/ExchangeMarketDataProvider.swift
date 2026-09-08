//
//  ExchangeMarketDataProvider.swift
//  Mobit
//
//  Created by 조성재 on 7/8/26.
//

import Foundation
import Moya

protocol ExchangeMarketDataProviding {
  var exchange: Exchange { get }

  /// Moya의 MultiTarget을 사용함으로써 거래소별 타겟을 별도 관리하지 않아도 된다.
  /// MultiTarget이 중앙 Repository를 거래소별 TargetType에서 분리해주는 역할
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
