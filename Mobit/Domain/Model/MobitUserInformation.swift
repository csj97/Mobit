//
//  MobitUserInformation.swift
//  Mobit
//
//  Created by 조성재 on 1/26/25.
//

import Foundation

struct MobitUserInformation: Codable {
  var userAvailableBalance: Double = UserDataManager.userAvailableBalance
//  var userCryptoList: [UserCrypto]
  
//  struct UserCrypto: Codable {
//    var market: String
//    var bidPrice: Double    // 매수 평단가
//    var bidAmount: Double   // 매수 수량
//    var profitRate: Double // 수익률
//  }
}
