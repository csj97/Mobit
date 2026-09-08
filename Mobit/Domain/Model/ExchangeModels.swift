//
//  ExchangeModels.swift
//  Mobit
//
//  Created by 조성재 on 7/8/26.
//

import Foundation

enum Exchange: String, Codable, CaseIterable {
  case upbit
  case bithumb
  case binance
  case okx
}

struct ExchangePairID: RawRepresentable, Hashable, Codable, ExpressibleByStringLiteral {
  let rawValue: String

  init(rawValue: String) {
	self.rawValue = rawValue
  }

  init(stringLiteral value: StringLiteralType) {
	self.rawValue = value
  }

  init(exchange: Exchange, rawMarketCode: String) {
	self.rawValue = "\(exchange.rawValue):\(rawMarketCode)"
  }

  var exchange: Exchange? {
	guard let separatorIndex = self.rawValue.firstIndex(of: ":") else { return nil }
	let exchangeString = String(self.rawValue[..<separatorIndex])
	return Exchange(rawValue: exchangeString)
  }

  var rawMarketCode: String? {
	guard let separatorIndex = self.rawValue.firstIndex(of: ":") else { return nil }
	let marketStartIndex = self.rawValue.index(after: separatorIndex)
	return String(self.rawValue[marketStartIndex...])
  }
}

struct ExchangeMarketWarning: Hashable, Codable {
  let warning: Bool
  let priceFluctuations: Bool
  let tradingVolumeSoaring: Bool
  let depositAmountSoaring: Bool
  let globalPriceDifferences: Bool
  let concentrationOfSmallAccounts: Bool
}

struct ExchangeMarketPair: Hashable, Codable {
  let id: ExchangePairID
  let exchange: Exchange
  let rawMarketCode: String
  let baseAsset: String
  let quoteAsset: String
  let displayMarket: String
  let koreanName: String?
  let englishName: String?
  let marketWarning: ExchangeMarketWarning?
}

struct FavoritePair: Hashable, Codable {
  let pairID: ExchangePairID
  let exchange: Exchange
  let rawMarketCode: String
  let displayMarket: String

  init(pairID: ExchangePairID, exchange: Exchange, rawMarketCode: String, displayMarket: String) {
    self.pairID = pairID
    self.exchange = exchange
    self.rawMarketCode = rawMarketCode
    self.displayMarket = displayMarket
  }

  init(displayMarket: String, exchange: Exchange) {
    let rawMarketCode = ExchangeMarketCodeConverter.rawMarketCode(
      fromDisplayMarket: displayMarket,
      exchange: exchange
    )
    self.init(
      pairID: ExchangePairID(exchange: exchange, rawMarketCode: rawMarketCode),
      exchange: exchange,
      rawMarketCode: rawMarketCode,
      displayMarket: displayMarket
    )
  }
}

struct ExchangeTickerSnapshot: Hashable, Codable {
  let pairID: ExchangePairID
  let tradePrice: Double
  let prevClosingPrice: Double
  let change: String
  let changePrice: Double
  let signedChangeRate: Double
  let accTradePrice24h: Double
  let accTradeVolume24h: Double
  let highest52WeekPrice: Double?
  let lowest52WeekPrice: Double?
  let tradeTimestamp: Int64?
}

struct ExchangeRealtimeTicker: Hashable, Codable {
  let pairID: ExchangePairID
  let tradePrice: Double
  let prevClosingPrice: Double
  let change: String
  let changePrice: Double
  let signedChangeRate: Double
  let accTradePrice24h: Double
  let accTradeVolume24h: Double
  let highest52WeekPrice: Double?
  let lowest52WeekPrice: Double?
  let tradeTimestamp: Int64?
  let streamType: String?
}

struct ExchangeOrderBook: Hashable, Codable {
  let pairID: ExchangePairID
  let totalAskSize: Double
  let totalBidSize: Double
  let levels: [Level]
  let timestamp: Int64?
  let streamType: String?

  struct Level: Hashable, Codable {
	let askPrice: Double
	let bidPrice: Double
	let askSize: Double
	let bidSize: Double
  }
}

struct ExchangeCandle: Hashable, Codable {
  let pairID: ExchangePairID
  let interval: Interval
  let timestamp: Date
  let openingPrice: Double
  let highPrice: Double
  let lowPrice: Double
  let tradePrice: Double
  let accTradePrice: Double
  let accTradeVolume: Double

  enum Interval: Hashable, Codable {
	case minute(Int)
	case day
	case week
	case month
	case year
  }
}
