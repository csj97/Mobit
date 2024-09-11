//
//  OrderBookResponseDTO.swift
//  Mobit
//
//  Created by 조성재 on 8/27/24.
//

import Foundation

struct OrderbookDTO: Codable {
  let type: String
  let code: String
  let timestamp: Int64
  let totalAskSize: Double
  let totalBidSize: Double
  let orderbookUnits: [OrderbookUnitDTO]
  let streamType: String
  let level: Int
  
  enum CodingKeys: String, CodingKey {
    case type
    case code
    case timestamp
    case totalAskSize = "total_ask_size"
    case totalBidSize = "total_bid_size"
    case orderbookUnits = "orderbook_units"
    case streamType = "stream_type"
    case level
  }
}

struct OrderbookUnitDTO: Codable {
  let askPrice: Double    // 매도 호가
  let bidPrice: Double    // 매수 호가
  let askSize: Double     // 매도 잔량
  let bidSize: Double     // 매수 잔량
  
  enum CodingKeys: String, CodingKey {
    case askPrice = "ask_price"
    case bidPrice = "bid_price"
    case askSize = "ask_size"
    case bidSize = "bid_size"
  }
}

extension OrderbookDTO {
  func toDomain() -> Orderbook {
    return .init(
      type: self.type,
      code: self.code,
      timestamp: self.timestamp,
      totalAskSize: self.totalAskSize,
      totalBidSize: self.totalBidSize,
      orderbookUnits: self.orderbookUnits.map { $0.toDomain() } , 
      streamType: self.streamType,
      level: self.level)
  }
}

extension OrderbookUnitDTO {
  func toDomain() -> OrderbookUnit {
    return .init(askPrice: self.askPrice, bidPrice: self.bidPrice, askSize: self.askSize, bidSize: self.bidSize)
  }
}
