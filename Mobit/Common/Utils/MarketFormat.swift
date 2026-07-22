//
//  MarketFormat.swift
//  Mobit
//
//  Created by Codex on 6/29/26.
//

import Foundation

enum MarketFormat {
  static func displayMarket(
    fromAPIMarket market: String,
    exchange: Exchange = ExchangeSelectionStore.currentExchange
  ) -> String {
    ExchangeMarketCodeConverter.displayMarket(
      fromRawMarketCode: market,
      exchange: exchange
    )
  }

  static func apiMarket(
    fromDisplayMarket market: String,
    exchange: Exchange = ExchangeSelectionStore.currentExchange
  ) -> String {
    ExchangeMarketCodeConverter.rawMarketCode(
      fromDisplayMarket: market,
      exchange: exchange
    )
  }

  static func tradingViewSymbol(
    fromDisplayMarket market: String?,
    exchange: Exchange = ExchangeSelectionStore.currentExchange
  ) -> String {
    let fallbackTicker: String

    switch exchange {
    case .upbit:
      fallbackTicker = "BTCKRW"
    case .bithumb:
      fallbackTicker = "BTCKRW"
    case .binance:
      fallbackTicker = "BTCUSDT"
    case .okx:
      fallbackTicker = "BTCUSDT"
    }

    let normalizedSymbol = market.flatMap(self.tradingViewTicker(fromDisplayMarket:))
      ?? fallbackTicker

    return "\(self.tradingViewExchangeCode(for: exchange)):\(normalizedSymbol)"
  }

  static func apiMarketsForSubscription(
    tab: SelectedTab,
    totalList: [CryptoCellInfo],
    userCryptos: [CryptoTransactionDataModel]?,
    favorites: [FavoritePair],
    exchange: Exchange = ExchangeSelectionStore.currentExchange
  ) -> [String] {
    let displayMarkets: [String]

    switch tab {
    case .hold:
      let holdingMarkets = Set(
        (userCryptos ?? [])
          .filter { $0.staticData.exchange == exchange }
          .map { $0.staticData.marketName }
      )
      displayMarkets = totalList
        .filter { holdingMarkets.contains($0.market) }
        .map { $0.market }

    case .krw:
      displayMarkets = totalList
        .filter { $0.market.contains("/KRW") }
        .map { $0.market }

    case .btc:
      displayMarkets = totalList
        .filter { $0.market.contains("/BTC") }
        .map { $0.market }

    case .favorite:
      let favoriteMarkets = Set(
        favorites
          .filter { $0.exchange == exchange }
          .map(\.displayMarket)
      )
      displayMarkets = totalList
        .filter { favoriteMarkets.contains($0.market) }
        .map { $0.market }
    }

    return Array(
      Set(
        displayMarkets.map {
          self.apiMarket(fromDisplayMarket: $0, exchange: exchange)
        }
      )
    ).sorted()
  }

  private static func tradingViewExchangeCode(
    for exchange: Exchange
  ) -> String {
    switch exchange {
    case .upbit:
      return "UPBIT"
    case .bithumb:
      return "BITHUMB"
    case .binance:
      return "BINANCE"
    case .okx:
      return "OKX"
    }
  }

  private static func tradingViewTicker(
    fromDisplayMarket market: String
  ) -> String? {
    let components = market.split(separator: "/").map(String.init)
    guard components.count == 2 else {
      let normalized = market
        .replacingOccurrences(of: "/", with: "")
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: "_", with: "")
      return normalized.isEmpty ? nil : normalized
    }

    return "\(components[0])\(components[1])"
  }
}
