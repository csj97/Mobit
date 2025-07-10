//
//  CryptoTickerDTO.swift
//  Mobit
//
//  Created by openobject on 2024/07/26.
//

import Foundation

typealias CryptoTickerListDTO = [CryptoTickerDTO]

struct CryptoTickerDTO: Hashable, Codable {
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
  let change: String
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
  let timestamp: Int64
  
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

extension CryptoTickerDTO {
  func toDomain() -> CryptoTicker {
	return .init(
	  market: self.market,
	  tradeDate: self.tradeDate ?? "",
	  tradeTime: self.tradeTime ?? "",
	  tradeDateKst: self.tradeDateKst ?? "",
	  tradeTimeKst: self.tradeTimeKst ?? "",
	  tradeTimestamp: self.tradeTimestamp ?? 0,
	  openingPrice: self.openingPrice ?? 0,
	  highPrice: self.highPrice ?? 0,
	  lowPrice: self.lowPrice ?? 0,
	  tradePrice: self.tradePrice ?? 0,
	  prevClosingPrice: self.prevClosingPrice ?? 0,
	  change: self.change,
	  changePrice: self.changePrice ?? 0,
	  changeRate: self.changeRate ?? 0,
	  signedChangePrice: self.signedChangePrice ?? 0,
	  signedChangeRate: self.signedChangeRate ?? 0,
	  tradeVolume: self.tradeVolume ?? 0,
	  accTradePrice: self.accTradePrice ?? 0,
	  accTradePrice24h: self.accTradePrice24h ?? 0,
	  accTradeVolume: self.accTradeVolume ?? 0,
	  accTradeVolume24h: self.accTradeVolume24h ?? 0,
	  highest52WeekPrice: self.highest52WeekPrice ?? 0,
	  highest52WeekDate: self.highest52WeekDate ?? "",
	  lowest52WeekPrice: self.lowest52WeekPrice ?? 0,
	  lowest52WeekDate: self.lowest52WeekDate ?? "",
	  timestamp: self.timestamp
	)
  }
}

extension CryptoTickerListDTO {
  func toDomain() -> [CryptoTicker] {
    return self.map { $0.toDomain() }
  }
}
