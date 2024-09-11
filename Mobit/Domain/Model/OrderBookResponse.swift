//
//  OrderBookResponse.swift
//  Mobit
//
//  Created by 조성재 on 8/25/24.
//

import Foundation

struct Orderbook: Hashable {
  var identifier: UUID = UUID()
  let type: String
  let code: String
  let timestamp: Int64
  let totalAskSize: Double
  let totalBidSize: Double
  let orderbookUnits: [OrderbookUnit]
  let streamType: String
  let level: Int
}

struct OrderbookUnit: Hashable {
  let askPrice: Double    // 매도 호가
  let bidPrice: Double    // 매수 호가
  let askSize: Double     // 매도 잔량
  let bidSize: Double     // 매수 잔량
}
