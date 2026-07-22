//
//  File.swift
//  Mobit
//
//  Created by 조성재 on 7/29/25.
//

import Foundation

/// 실현손익 내역
struct UserPNLHistoryModel: Codable {
  var exchange: Exchange = .upbit
  let marketName: String
  let entryPrice: Double
  let exitPrice: Double
  let transactionDate: String
  let orderQuantity: Double
  let pnl: Double

  enum CodingKeys: String, CodingKey {
    case exchange, marketName, entryPrice, exitPrice, transactionDate, orderQuantity, pnl
  }

  init(
    exchange: Exchange = .upbit,
    marketName: String,
    entryPrice: Double,
    exitPrice: Double,
    transactionDate: String,
    orderQuantity: Double,
    pnl: Double
  ) {
    self.exchange = exchange
    self.marketName = marketName
    self.entryPrice = entryPrice
    self.exitPrice = exitPrice
    self.transactionDate = transactionDate
    self.orderQuantity = orderQuantity
    self.pnl = pnl
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.exchange = try container.decodeIfPresent(Exchange.self, forKey: .exchange) ?? .upbit
    self.marketName = try container.decode(String.self, forKey: .marketName)
    self.entryPrice = try container.decode(Double.self, forKey: .entryPrice)
    self.exitPrice = try container.decode(Double.self, forKey: .exitPrice)
    self.transactionDate = try container.decode(String.self, forKey: .transactionDate)
    self.orderQuantity = try container.decode(Double.self, forKey: .orderQuantity)
    self.pnl = try container.decode(Double.self, forKey: .pnl)
  }
}
