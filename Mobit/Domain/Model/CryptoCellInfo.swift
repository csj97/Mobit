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
  var tradePrice: Double?
  var changePrice: Double?
  var signedChangeRate: Double?  // 부호있는 전일대비 변화율
  var change: String?    // 변화 (상승, 하락, 보합)
  var accTradeVolume: Double?  //  24시간 누적 거래량
}
