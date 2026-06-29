//
//  MarketFormat.swift
//  Mobit
//
//  Created by Codex on 6/29/26.
//

import Foundation

enum MarketFormat {
  static func displayMarket(fromAPIMarket market: String) -> String {
    let components = market.split(separator: "-")
    guard components.count == 2 else { return market }
    return "\(components[1])/\(components[0])"
  }

  static func apiMarket(fromDisplayMarket market: String) -> String {
    let components = market.split(separator: "/")
    guard components.count == 2 else { return market }
    return "\(components[1])-\(components[0])"
  }

  static func apiMarketsForSubscription(
    tab: SelectedTab,
    totalList: [CryptoCellInfo],
    userCryptos: [CryptoTransactionDataModel]?,
    favorites: [String]
  ) -> [String] {
    let displayMarkets: [String]

    switch tab {
    case .hold:
      let holdingMarkets = Set((userCryptos ?? []).map { $0.staticData.marketName })
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
      let favoriteMarkets = Set(favorites)
      displayMarkets = totalList
        .filter { favoriteMarkets.contains($0.market) }
        .map { $0.market }
    }

    return Array(Set(displayMarkets.map(apiMarket(fromDisplayMarket:)))).sorted()
  }
}
