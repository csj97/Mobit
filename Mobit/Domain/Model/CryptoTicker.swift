//
//  CryptoTickerList.swift
//  Mobit
//
//  Created by openobject on 2024/07/26.
//

import Foundation

typealias CryptoTickerList = [CryptoTicker]

struct CryptoTicker {
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
}
