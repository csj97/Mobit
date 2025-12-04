//
//  Candle+MinuteResponseDTO.swift
//  Mobit
//
//  Created by 조성재 on 12/3/25.
//

import Foundation

struct MinuteResponseModelDTO: Codable {
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
  let unit: Int 	// default 1(분)
}

extension MinuteResponseModelDTO {
  func toDomain() -> MinuteResponseModel {
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
	  unit: unit
	)
  }
}

extension Array where Element == MinuteResponseModelDTO {
  func toDomainList() -> [MinuteResponseModel] {
	map { $0.toDomain() }
  }
}
