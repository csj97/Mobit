//
//  BithumbTickerDTO.swift
//  Mobit
//
//  Created by Codex on 7/9/26.
//

import Foundation

// MARK: - Bithumb REST DTO
// 현재 Bithumb v1 REST 응답은 Upbit 스키마와 사실상 동일하지만,
// 추후 스펙 분기에 대비해 Upbit DTO와 분리된 전용 타입으로 디코딩한다.
// 필드가 달라지면 이 파일의 DTO만 수정하면 되고 Upbit 경로에는 영향이 없다.

typealias BithumbTickerListDTO = [BithumbTickerDTO]

struct BithumbTickerDTO: Decodable {
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
  let change: String?
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
  let timestamp: Int64?

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

extension BithumbTickerDTO {
  func toDomain() -> CryptoTicker {
    .init(
      market: market,
      tradeDate: tradeDate ?? "",
      tradeTime: tradeTime ?? "",
      tradeDateKst: tradeDateKst ?? "",
      tradeTimeKst: tradeTimeKst ?? "",
      tradeTimestamp: tradeTimestamp ?? 0,
      openingPrice: openingPrice,
      highPrice: highPrice,
      lowPrice: lowPrice,
      tradePrice: tradePrice,
      prevClosingPrice: prevClosingPrice,
      change: change ?? "EVEN",
      changePrice: changePrice,
      changeRate: changeRate,
      signedChangePrice: signedChangePrice,
      signedChangeRate: signedChangeRate,
      tradeVolume: tradeVolume,
      accTradePrice: accTradePrice,
      accTradePrice24h: accTradePrice24h,
      accTradeVolume: accTradeVolume,
      accTradeVolume24h: accTradeVolume24h,
      highest52WeekPrice: highest52WeekPrice,
      highest52WeekDate: highest52WeekDate ?? "",
      lowest52WeekPrice: lowest52WeekPrice,
      lowest52WeekDate: lowest52WeekDate ?? "",
      timestamp: timestamp ?? 0
    )
  }
}

extension Array where Element == BithumbTickerDTO {
  func toDomain() -> [CryptoTicker] {
    map { $0.toDomain() }
  }
}

