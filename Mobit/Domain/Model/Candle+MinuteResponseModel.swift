//
//  Candle+MinuteResponseModel.swift
//  Mobit
//
//  Created by 조성재 on 12/3/25.
//

import Foundation

struct MinuteResponseModel {
  let identifier: UUID = UUID()
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
