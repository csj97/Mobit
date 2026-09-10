//
//  BithumbSocketDTO.swift
//  Mobit
//
//  Created by 조성재 on 7/9/26.
//

import Foundation

private func normalizedBithumbMarket(_ symbol: String) -> String {
  let components = symbol.split(separator: "_").map(String.init)
  guard components.count == 2 else { return symbol.replacingOccurrences(of: "_", with: "-") }
  return "\(components[1])-\(components[0])"
}

struct BithumbWebSocketStatusMessage: Decodable {
  struct ErrorPayload: Decodable {
    let name: String?
    let message: String?
  }

  let status: String?
  let resmsg: String?
  let error: ErrorPayload?
}


struct BithumbTickerSocketDTO: Decodable {
  let type: String
  let code: String
  let openingPrice: Double
  let highPrice: Double
  let lowPrice: Double
  let tradePrice: Double
  let prevClosingPrice: Double
  let change: String
  let changePrice: Double
  let signedChangePrice: Double
  let changeRate: Double
  let signedChangeRate: Double
  let tradeVolume: Double
  let accTradeVolume: Double
  let accTradeVolume24H: Double
  let accTradePrice: Double
  let accTradePrice24H: Double
  let tradeDate: String
  let tradeTime: String
  let tradeTimestamp: Int64
  let askBid: String
  let accAskVolume: Double
  let accBidVolume: Double
  let highest52WeekPrice: Double
  let highest52WeekDate: String?
  let lowest52WeekPrice: Double
  let lowest52WeekDate: String?
  let marketState: String
  let delistingDate: String?
  let marketWarning: String?
  let timestamp: Int64
  let streamType: String

  enum CodingKeys: String, CodingKey {
    case type
    case code
    case openingPrice = "opening_price"
    case highPrice = "high_price"
    case lowPrice = "low_price"
    case tradePrice = "trade_price"
    case prevClosingPrice = "prev_closing_price"
    case change
    case changePrice = "change_price"
    case signedChangePrice = "signed_change_price"
    case changeRate = "change_rate"
    case signedChangeRate = "signed_change_rate"
    case tradeVolume = "trade_volume"
    case accTradeVolume = "acc_trade_volume"
    case accTradeVolume24H = "acc_trade_volume_24h"
    case accTradePrice = "acc_trade_price"
    case accTradePrice24H = "acc_trade_price_24h"
    case tradeDate = "trade_date"
    case tradeTime = "trade_time"
    case tradeTimestamp = "trade_timestamp"
    case askBid = "ask_bid"
    case accAskVolume = "acc_ask_volume"
    case accBidVolume = "acc_bid_volume"
    case highest52WeekPrice = "highest_52_week_price"
    case highest52WeekDate = "highest_52_week_date"
    case lowest52WeekPrice = "lowest_52_week_price"
    case lowest52WeekDate = "lowest_52_week_date"
    case marketState = "market_state"
    case delistingDate = "delisting_date"
    case marketWarning = "market_warning"
    case timestamp
    case streamType = "stream_type"
  }
}

extension BithumbTickerSocketDTO {
  func toDomain() -> CryptoSocketTicker {
    .init(
      type: type,
      code: code,
      openingPrice: openingPrice,
      highPrice: highPrice,
      lowPrice: lowPrice,
      tradePrice: tradePrice,
      prevClosingPrice: prevClosingPrice,
      change: change,
      changePrice: changePrice,
      signedChangePrice: signedChangePrice,
      changeRate: changeRate,
      signedChangeRate: signedChangeRate,
      tradeVolume: tradeVolume,
      accTradeVolume: accTradeVolume,
      accTradeVolume24H: accTradeVolume24H,
      accTradePrice: accTradePrice,
      accTradePrice24H: accTradePrice24H,
      tradeDate: tradeDate,
      tradeTime: tradeTime,
      tradeTimestamp: tradeTimestamp,
      askBid: askBid,
      accAskVolume: accAskVolume,
      accBidVolume: accBidVolume,
      highest52WeekPrice: highest52WeekPrice,
      highest52WeekDate: highest52WeekDate ?? "",
      lowest52WeekPrice: lowest52WeekPrice,
      lowest52WeekDate: lowest52WeekDate ?? "",
      marketState: marketState,
      delistingDate: self.toDelistingDate(from: delistingDate),
      marketWarning: marketWarning,
      timestamp: timestamp,
      streamType: streamType
    )
  }

  private func toDelistingDate(
    from value: String?
  ) -> CryptoSocketTicker.DelistingDate? {
    guard let value, !value.isEmpty else { return nil }
    let components = value.split(separator: "-").compactMap { Int($0) }
    guard components.count == 3 else { return nil }
    return .init(
      year: components[0],
      month: components[1],
      day: components[2]
    )
  }
}

struct BithumbOrderbookSocketDTO: Decodable {
  let type: String
  let code: String
  let totalAskSize: Double
  let totalBidSize: Double
  let orderbookUnits: [OrderbookUnitDTO]
  let level: Double
  let timestamp: Int
  let streamType: String?

  enum CodingKeys: String, CodingKey {
    case type
    case code
    case totalAskSize = "total_ask_size"
    case totalBidSize = "total_bid_size"
    case orderbookUnits = "orderbook_units"
    case level
    case timestamp
    case streamType = "stream_type"
  }

  struct OrderbookUnitDTO: Decodable {
    let askPrice: Double
    let bidPrice: Double
    let askSize: Double
    let bidSize: Double

    enum CodingKeys: String, CodingKey {
      case askPrice = "ask_price"
      case bidPrice = "bid_price"
      case askSize = "ask_size"
      case bidSize = "bid_size"
    }
  }
}

extension BithumbOrderbookSocketDTO {
  func toDomain() -> Orderbook {
    .init(
      type: type,
      code: code,
      timestamp: timestamp,
      totalAskSize: totalAskSize,
      totalBidSize: totalBidSize,
      orderbookUnits: orderbookUnits.map { $0.toDomain() },
      streamType: streamType,
      level: Int(level)
    )
  }
}

extension BithumbOrderbookSocketDTO.OrderbookUnitDTO {
  func toDomain() -> Orderbook.OrderbookUnit {
    .init(
      askPrice: askPrice,
      bidPrice: bidPrice,
      askSize: askSize,
      bidSize: bidSize
    )
  }
}

struct BithumbLegacyTickerSocketEnvelope: Decodable {
  let type: String
  let content: Content

  struct Content: Decodable {
    let symbol: String
    let date: String?
    let time: String?
    let openPrice: String
    let closePrice: String
    let lowPrice: String
    let highPrice: String
    let value: String?
    let volume: String?
    let sellVolume: String?
    let buyVolume: String?
    let prevClosePrice: String
    let chgRate: String
    let chgAmt: String
  }

  func toDomain() -> CryptoSocketTicker {
    let changeAmount = Double(content.chgAmt) ?? 0
    let signedRate = (Double(content.chgRate) ?? 0) / 100
    let change = changeAmount > 0 ? "RISE" : (changeAmount < 0 ? "FALL" : "EVEN")
    return .init(
      type: type,
      code: normalizedBithumbMarket(content.symbol),
      openingPrice: Double(content.openPrice) ?? 0,
      highPrice: Double(content.highPrice) ?? 0,
      lowPrice: Double(content.lowPrice) ?? 0,
      tradePrice: Double(content.closePrice) ?? 0,
      prevClosingPrice: Double(content.prevClosePrice) ?? 0,
      change: change,
      changePrice: abs(changeAmount),
      signedChangePrice: changeAmount,
      changeRate: abs(signedRate),
      signedChangeRate: signedRate,
      tradeVolume: 0,
      accTradeVolume: Double(content.volume ?? "") ?? 0,
      accTradeVolume24H: Double(content.volume ?? "") ?? 0,
      accTradePrice: Double(content.value ?? "") ?? 0,
      accTradePrice24H: Double(content.value ?? "") ?? 0,
      tradeDate: content.date ?? "",
      tradeTime: content.time ?? "",
      tradeTimestamp: 0,
      askBid: "",
      accAskVolume: Double(content.sellVolume ?? "") ?? 0,
      accBidVolume: Double(content.buyVolume ?? "") ?? 0,
      highest52WeekPrice: 0,
      highest52WeekDate: "",
      lowest52WeekPrice: 0,
      lowest52WeekDate: "",
      marketState: "ACTIVE",
      delistingDate: nil,
      marketWarning: nil,
      timestamp: 0,
      streamType: "REALTIME"
    )
  }
}

struct BithumbLegacyOrderbookSocketEnvelope: Decodable {
  let type: String
  let content: Content

  struct Content: Decodable {
    let symbol: String
    let datetime: String
    let asks: [[String]]
    let bids: [[String]]
  }

  func toDomain() -> Orderbook {
    let count = min(content.asks.count, content.bids.count)
    let units = (0..<count).compactMap { index -> Orderbook.OrderbookUnit? in
      let ask = content.asks[index]
      let bid = content.bids[index]
      guard ask.count >= 2, bid.count >= 2,
            let askPrice = Double(ask[0]), let askSize = Double(ask[1]),
            let bidPrice = Double(bid[0]), let bidSize = Double(bid[1]) else { return nil }
      return .init(
        askPrice: askPrice,
        bidPrice: bidPrice,
        askSize: askSize,
        bidSize: bidSize
      )
    }
    return .init(
      type: type,
      code: normalizedBithumbMarket(content.symbol),
      timestamp: Int(content.datetime) ?? 0,
      totalAskSize: units.reduce(0) { $0 + $1.askSize },
      totalBidSize: units.reduce(0) { $0 + $1.bidSize },
      orderbookUnits: units,
      streamType: "SNAPSHOT",
      level: 0
    )
  }
}
