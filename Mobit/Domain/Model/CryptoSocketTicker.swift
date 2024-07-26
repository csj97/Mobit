//
//  CryptoTicker.swift
//  Mobit
//
//  Created by openobject on 2024/07/23.
//

import Foundation

typealias CryptoSocketTickerList = [CryptoSocketTicker]

struct CryptoSocketTicker: Hashable {
  let identifier: UUID = UUID()
  let type: String  // ticker : 현재가
  let code: String  // market
  let openingPrice: Double
  let highPrice: Double
  let lowPrice: Double
  let tradePrice: Double
  let prevClosingPrice: Double
  let change: String // RISE : 상승, EVEN : 보합, FALL : 하락
  let changePrice: Double
  let signedChangePrice: Double
  let changeRate: Double
  let signedChangeRate: Double
  let tradeVolume: Double
  let accTradeVolume: Double
  let accTradeVolume24H: Double
  let accTradePrice: Double
  let accTradePrice24H: Double
  let tradeDate: String // yyyyMMdd
  let tradeTime: String // HHmmss
  let tradeTimestamp: Int64
  let askBid: String
  let accAskVolume: Double
  let accBidVolume: Double
  let highest52WeekPrice: Double
  let highest52WeekDate: String
  let lowest52WeekPrice: Double
  let lowest52WeekDate: String
  let tradeStatus: String?
  let marketState: String
  let marketStateForIOS: String?
  let isTradingSuspended: Bool
  let delistingDate: Date?
  let marketWarning: String
  let timestamp: Int64
  let streamType: String
}

