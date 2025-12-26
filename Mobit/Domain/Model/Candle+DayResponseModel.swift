//
//  Candle+DayResponseModel.swift
//  Mobit
//
//  Created by 조성재 on 12/19/25.
//

import Foundation

struct DayResponseModel: CandleModel {
  var id: Int64 { timestamp }
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
  let prev_closing_price: Double		// 전일 종가 (UTC 0시 기준)
  let change_price: Double?				// 전일 종가 대비 가격 변화
  let change_rate: Double?				// 전일 종가 대비 가격 변화율
  let converted_trade_price: Double?	// 종가 환산 가격
}
