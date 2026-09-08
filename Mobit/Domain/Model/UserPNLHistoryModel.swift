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
  let transactionTimestamp: Int64?
  let orderQuantity: Double
  let pnl: Double
  private let legacyTransactionDate: String?

  enum CodingKeys: String, CodingKey {
    case exchange, marketName, entryPrice, exitPrice, transactionTimestamp, transactionDate, orderQuantity, pnl
  }

  var transactionDate: String {
    if let transactionTimestamp {
      return TradeTimestampFormatter.displayString(from: transactionTimestamp)
    }
    return legacyTransactionDate ?? ""
  }

  init(
    exchange: Exchange = .upbit,
    marketName: String,
    entryPrice: Double,
    exitPrice: Double,
    transactionTimestamp: Int64,
    orderQuantity: Double,
    pnl: Double
  ) {
    self.exchange = exchange
    self.marketName = marketName
    self.entryPrice = entryPrice
    self.exitPrice = exitPrice
    self.transactionTimestamp = transactionTimestamp
    self.orderQuantity = orderQuantity
    self.pnl = pnl
    self.legacyTransactionDate = nil
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
    self.transactionTimestamp = nil
    self.orderQuantity = orderQuantity
    self.pnl = pnl
    self.legacyTransactionDate = transactionDate
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.exchange = try container.decodeIfPresent(Exchange.self, forKey: .exchange) ?? .upbit
    self.marketName = try container.decode(String.self, forKey: .marketName)
    self.entryPrice = try container.decode(Double.self, forKey: .entryPrice)
    self.exitPrice = try container.decode(Double.self, forKey: .exitPrice)
    self.transactionTimestamp = try container.decodeIfPresent(Int64.self, forKey: .transactionTimestamp)
    self.legacyTransactionDate = try container.decodeIfPresent(String.self, forKey: .transactionDate)
    self.orderQuantity = try container.decode(Double.self, forKey: .orderQuantity)
    self.pnl = try container.decode(Double.self, forKey: .pnl)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(exchange, forKey: .exchange)
    try container.encode(marketName, forKey: .marketName)
    try container.encode(entryPrice, forKey: .entryPrice)
    try container.encode(exitPrice, forKey: .exitPrice)
    try container.encodeIfPresent(transactionTimestamp, forKey: .transactionTimestamp)
    try container.encodeIfPresent(legacyTransactionDate, forKey: .transactionDate)
    try container.encode(orderQuantity, forKey: .orderQuantity)
    try container.encode(pnl, forKey: .pnl)
  }
}
