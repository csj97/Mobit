//
//  CryptoCellInfo.swift
//  Mobit
//
//  Created by openobject on 2024/07/25.
//

import Foundation

// Main TableViewCell에 사용되는 정보
struct CryptoCellInfo: Hashable {
  var identifier: UUID = UUID()
  var cryptoName: String  // 종목명
  var market: String    // 종목 구분 코드 BTC-KRW
  var marketEvent: MarketEvent?
  var prevPrice: Double?
  var tradePrice: Double?
  var changePrice: Double?
  var signedChangeRate: Double?  // 부호있는 전일대비 변화율
  var change: String?    // 변화 (상승, 하락, 보합)
  var accTradePrice24h: Double?  //  24시간 누적 거래대금
  var accTradeVolume24h: Double?  //  24시간 누적 거래볼륨
  var highest52WeekPrice: Double? // 52주 최고가
  var lowest52WeekPrice: Double? // 52주 최저가

  // 보유(hold) 탭에서만 채워지는 보유 정보 (다른 탭에서는 nil)
  var holdingQuantity: Double?    // 보유 수량
  var averageBuyPrice: Double?    // 평균 매수가
  var evaluationPrice: Double?    // 평가금액 (현재가 × 보유량)
  var profitRate: Double?         // 수익률 (%)
  var evaluationProfitLoss: Double? // 평가손익
}
