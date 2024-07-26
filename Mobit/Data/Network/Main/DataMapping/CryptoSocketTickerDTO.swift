//
//  CryptoTickerDTO.swift
//  Mobit
//
//  Created by openobject on 2024/07/23.
//

import Foundation

typealias CryptoSocketTickerListDTO = [CryptoSocketTickerDTO]

struct CryptoSocketTickerDTO: Codable {
  let type: String // ticker : 현재가
  let code: String
  let openingPrice: Double
  let highPrice: Double
  let lowPrice: Double
  let tradePrice: Double
  let prevClosingPrice: Double
  let change: String // RISE : 상승, EVEN : 보합, FALL : 하락
  let changePrice: Double
  let signedChangePrice: Double
  let changeRate: Double
  let signedChangeRate: Double
  let tradeVolume: Double
  let accTradeVolume: Double
  let accTradeVolume24H: Double
  let accTradePrice: Double
  let accTradePrice24H: Double
  let tradeDate: String // yyyyMMdd
  let tradeTime: String // HHmmss
  let tradeTimestamp: Int64
  let askBid: String
  let accAskVolume: Double
  let accBidVolume: Double
  let highest52WeekPrice: Double
  let highest52WeekDate: String
  let lowest52WeekPrice: Double
  let lowest52WeekDate: String
  let tradeStatus: String?
  let marketState: String
  let marketStateForIOS: String?
  let isTradingSuspended: Bool
  let delistingDate: Date?
  let marketWarning: String
  let timestamp: Int64
  let streamType: String
  
  enum CodingKeys: String, CodingKey {
    case type, code, change, timestamp
    case openingPrice = "opening_price"
    case highPrice = "high_price"
    case lowPrice = "low_price"
    case tradePrice = "trade_price"
    case prevClosingPrice = "prev_closing_price"
    case accTradePrice = "acc_trade_price"
    case changePrice = "change_price"
    case signedChangePrice = "signed_change_price"
    case changeRate = "change_rate"
    case signedChangeRate = "signed_change_rate"
    case askBid = "ask_bid"
    case tradeVolume = "trade_volume"
    case accTradeVolume = "acc_trade_volume"
    case tradeDate = "trade_date"
    case tradeTime = "trade_time"
    case tradeTimestamp = "trade_timestamp"
    case accAskVolume = "acc_ask_volume"
    case accBidVolume = "acc_bid_volume"
    case highest52WeekPrice = "highest_52_week_price"
    case highest52WeekDate = "highest_52_week_date"
    case lowest52WeekPrice = "lowest_52_week_price"
    case lowest52WeekDate = "lowest_52_week_date"
    case tradeStatus = "trade_status"
    case marketState = "market_state"
    case marketStateForIOS = "market_state_for_ios"
    case isTradingSuspended = "is_trading_suspended"
    case delistingDate = "delisting_date"
    case marketWarning = "market_warning"
    case accTradePrice24H = "acc_trade_price_24h"
    case accTradeVolume24H = "acc_trade_volume_24h"
    case streamType = "stream_type"
  }
}

extension CryptoSocketTickerDTO {
  func toDomain() -> CryptoSocketTicker {
    return .init(type: type,
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
                 highest52WeekDate: highest52WeekDate,
                 lowest52WeekPrice: lowest52WeekPrice,
                 lowest52WeekDate: lowest52WeekDate,
                 tradeStatus: tradeStatus,
                 marketState: marketState,
                 marketStateForIOS: marketStateForIOS,
                 isTradingSuspended: isTradingSuspended,
                 delistingDate: delistingDate,
                 marketWarning: marketWarning,
                 timestamp: timestamp,
                 streamType: streamType)
  }
}

extension CryptoSocketTickerListDTO{
  // Crypto toDomain을 map을 사용해 배열로 return
  func toDomain() -> [CryptoSocketTicker] {
    return self.map { $0.toDomain() }
  }
}
