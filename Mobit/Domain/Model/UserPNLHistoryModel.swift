//
//  File.swift
//  Mobit
//
//  Created by 조성재 on 7/29/25.
//

import Foundation

/// 실현손익 내역
struct UserPNLHistoryModel: Codable {
  let marketName: String
  let entryPrice: Double
  let exitPrice: Double
  let transactionDate: String
  let orderQuantity: Double
  let pnl: Double
}
