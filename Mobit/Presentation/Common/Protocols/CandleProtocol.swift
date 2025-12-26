//
//  CandleProtocol.swift
//  Mobit
//
//  Created by 조성재 on 12/22/25.
//

import Foundation

// 차트를 그리기 위해 필요한 최소 정보
protocol CandleModel: Identifiable, Equatable {
  var market: String { get }
  var candle_date_time_utc: String { get }
  var candle_date_time_kst: String { get }

  var opening_price: Double { get }
  var high_price: Double { get }
  var low_price: Double { get }
  var trade_price: Double { get }

  var timestamp: Int64 { get }
  var candle_acc_trade_price: Double { get }
  var candle_acc_trade_volume: Double { get }
}
