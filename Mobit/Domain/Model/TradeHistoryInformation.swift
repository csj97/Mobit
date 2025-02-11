//
//  TradeHistoryInformation.swift
//  Mobit
//
//  Created by 조성재 on 2/11/25.
//

import Foundation

struct TradeHistoryInformation: Codable {
  let tradeDate: String
  let marketName: String
  let tradeCryptoPrice: Double
  let tradeAmount: Double
  let tradeTotalPrice: Double
}
