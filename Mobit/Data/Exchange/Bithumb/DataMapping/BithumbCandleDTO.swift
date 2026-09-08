//
//  BithumbCandleDTO.swift
//  Mobit
//
//  Created by 조성재 on 7/9/26.
//

import Foundation

struct BithumbMinuteCandleDTO: Decodable {
  // 식별키(market)와 차트 렌더링 필수값(시간, OHLC)만 필수로 두고,
  // 누락돼도 폴백 가능한 보조 필드는 옵셔널로 완화해 단일 필드 누락이 배치 전체 디코딩을 깨지 않게 한다.
  let market: String
  let candle_date_time_utc: String
  let candle_date_time_kst: String
  let opening_price: Double
  let high_price: Double
  let low_price: Double
  let trade_price: Double
  let timestamp: Int64?
  let candle_acc_trade_price: Double?
  let candle_acc_trade_volume: Double?
  let unit: Int?
}

extension BithumbMinuteCandleDTO {
  func toDomain() -> MinuteResponseModel {
    .init(
      market: market,
      candle_date_time_utc: candle_date_time_utc,
      candle_date_time_kst: candle_date_time_kst,
      opening_price: opening_price,
      high_price: high_price,
      low_price: low_price,
      trade_price: trade_price,
      timestamp: timestamp ?? 0,
      candle_acc_trade_price: candle_acc_trade_price ?? 0,
      candle_acc_trade_volume: candle_acc_trade_volume ?? 0,
      unit: unit ?? 1
    )
  }
}

extension Array where Element == BithumbMinuteCandleDTO {
  func toDomainList() -> [MinuteResponseModel] {
    map { $0.toDomain() }
  }
}

struct BithumbDayCandleDTO: Decodable {
  // 식별키(market)와 차트 렌더링 필수값(시간, OHLC)만 필수로 두고,
  // 누락돼도 폴백 가능한 보조 필드는 옵셔널로 완화한다.
  let market: String
  let candle_date_time_utc: String
  let candle_date_time_kst: String
  let opening_price: Double
  let high_price: Double
  let low_price: Double
  let trade_price: Double
  let timestamp: Int64?
  let candle_acc_trade_price: Double?
  let candle_acc_trade_volume: Double?
  let prev_closing_price: Double?
  let change_price: Double?
  let change_rate: Double?
  let converted_trade_price: Double?
}

extension BithumbDayCandleDTO {
  func toDomain() -> DayResponseModel {
    .init(
      market: market,
      candle_date_time_utc: candle_date_time_utc,
      candle_date_time_kst: candle_date_time_kst,
      opening_price: opening_price,
      high_price: high_price,
      low_price: low_price,
      trade_price: trade_price,
      timestamp: timestamp ?? 0,
      candle_acc_trade_price: candle_acc_trade_price ?? 0,
      candle_acc_trade_volume: candle_acc_trade_volume ?? 0,
      prev_closing_price: prev_closing_price ?? 0,
      change_price: change_price,
      change_rate: change_rate,
      converted_trade_price: converted_trade_price
    )
  }
}

extension Array where Element == BithumbDayCandleDTO {
  func toDomainList() -> [DayResponseModel] {
    map { $0.toDomain() }
  }
}

