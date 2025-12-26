//
//  Candle+DayResponseDTO.swift
//  Mobit
//
//  Created by 조성재 on 12/19/25.
//

import Foundation

struct DayResponseModelDTO: Codable {
  let market: String
  let candle_date_time_utc: String
  let candle_date_time_kst: String
  let opening_price: Double
  let high_price: Double
  let low_price: Double
  let trade_price: Double
  let timestamp: Int64
  let candle_acc_trade_price: Double
  let candle_acc_trade_volume: Double
  let prev_closing_price: Double
  let change_price: Double?
  let change_rate: Double?
  let converted_trade_price: Double?
}

extension DayResponseModelDTO {
  func toDomain() -> DayResponseModel {
	return .init(
	  market: market,
	  candle_date_time_utc: candle_date_time_utc,
	  candle_date_time_kst: candle_date_time_kst,
	  opening_price: opening_price,
	  high_price: high_price,
	  low_price: low_price,
	  trade_price: trade_price,
	  timestamp: timestamp,
	  candle_acc_trade_price: candle_acc_trade_price,
	  candle_acc_trade_volume: candle_acc_trade_volume,
	  prev_closing_price: prev_closing_price,
	  change_price: change_price,
	  change_rate: change_rate,
	  converted_trade_price: converted_trade_price
	)
  }
}

extension Array where Element == DayResponseModelDTO {
  func toDomainList() -> [DayResponseModel] {
	map { $0.toDomain() }
  }
}
