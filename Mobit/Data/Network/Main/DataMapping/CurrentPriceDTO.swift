//
//  CurrentPriceDTO.swift
//  Mobit
//
//  Created by openobject on 2024/07/23.
//

import Foundation

typealias CurrentPriceListDTO = [CurrentPriceDTO]

struct CurrentPriceDTO: Codable {
  let market: String  // 종목
  let tradeDate: String // 최근 거래 일자 yyyyMMdd (UTC)
  let tradeTime: String // 최근 거래 시각 HHmmss (UTC)
  let tradeDateKst: String  // 최근 거래 일자 yyyyMMdd (KST)
  let tradeTimeKst: String  // 최근 거래 시각 HHmmss (KST)
  let tradeTimestamp: Int64 // 최근 거래 일시 Timestamp (UTC) ex) 1524047020000
  let openingPrice: Double  // 시가
  let highPrice: Double // 고가
  let lowPrice: Double  // 저가
  let tradePrice: Double  // 종가(현재가)
  let prevClosingPrice: Double  // 전일 종가 (UTC 0시 기준)
  let change: String  // EVEN보합, RISE상승, FALL하락 -> 전일 종가 대비값
  let changePrice: Double // 변화액 절대값  -> 전일 종가 대비값
  let changeRate: Double  // 변화율 절대값  -> 전일 종가 대비값
  let signedChangePrice: Double // 부호가 있는 변화액 -> 전일 종가 대비값
  let signedChangeRate: Double  // 부호가 있는 변화율 -> 전일 종가 대비값
  let tradeVolume: Double // 가장 최근 거래량
  let accTradePrice: Double // 누적 거래대금 (UTC 0시 기준)
  let accTradePrice24h: Double  // 24시간 누적 거래대금
  let accTradeVolume: Double  // 누적 거래량 (UTC 0시 기준)
  let accTradeVolume24h: Double // 24시간 누적 거래량
  let highest52WeekPrice: Double  // 52주 신고가
  let highest52WeekDate: String // 52주 신고가 달성일 yyyy-MM-dd
  let lowest52WeekPrice: Double // 52주 신저가
  let lowest52WeekDate: String  // 52주 신저가 달성일 yyyy-MM-dd
  let timestamp: Int64  // 타임스팸프
  
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

extension CurrentPriceDTO {
  func toDomain() -> CurrentPrice {
    return .init(market: market, tradeDate: tradeDate, tradeTime: tradeTime, tradeDateKst: tradeDateKst, tradeTimeKst: tradeTimeKst, tradeTimestamp: tradeTimestamp, openingPrice: openingPrice, highPrice: highPrice, lowPrice: lowPrice, tradePrice: tradePrice, prevClosingPrice: prevClosingPrice, change: change, changePrice: changePrice, changeRate: changeRate, signedChangePrice: signedChangePrice, signedChangeRate: signedChangeRate, tradeVolume: tradeVolume, accTradePrice: accTradePrice, accTradePrice24h: accTradePrice24h, accTradeVolume: accTradeVolume, accTradeVolume24h: accTradeVolume24h, highest52WeekPrice: highest52WeekPrice, highest52WeekDate: highest52WeekDate, lowest52WeekPrice: lowest52WeekPrice, lowest52WeekDate: lowest52WeekDate, timestamp: timestamp)
  }
}

extension CurrentPriceListDTO {
  // Crypto toDomain을 map을 사용해 배열로 return
  func toDomain() -> [CurrentPrice] {
    return self.map { $0.toDomain() }
  }
}

