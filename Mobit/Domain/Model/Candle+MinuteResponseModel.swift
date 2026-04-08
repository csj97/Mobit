//
//  Candle+MinuteResponseModel.swift
//  Mobit
//
//  Created by 조성재 on 12/3/25.
//

import Foundation

struct MinuteResponseModel: Equatable {
  let identifier: UUID = UUID()
  let market: String		// KRW-BTC
  let candle_date_time_utc: String	// 캔들 구간의 시작 시간 (UTC)
  let candle_date_time_kst: String	// 캔들 구간의 시작 시간 (KST)
  let opening_price: Double		// 시가 (캔들의 첫 거래 가격)
  let high_price: Double		// 고가 (캔들의 최고 거래 가격)
  let low_price: Double			// 저가 (캔들의 최저 거래 가격)
  let trade_price: Double		// 종가
  let timestamp: Int64			// 마지막 틱이 저장된 시각의 타임스탬프(ms)
  let candle_acc_trade_price: Double	// 누적 거래 금액
  let candle_acc_trade_volume: Double	// 누적 수량
  let unit: Int 	// default 1(분)		// 캔들 집계 시간 단위 (분)
}
