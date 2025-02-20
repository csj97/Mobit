//
//  BidCryptoInfo.swift
//  Mobit
//
//  Created by 조성재 on 2/19/25.
//

import Foundation

struct CryptoTransaction: Codable {
  var marketName: String		// 코인마켓명
  var holdingQuantity: Double      // 보유수량
  var profitRate: Double          // 수익률
  var evaluationProfitLoss: Double // 평가손익 (얼마 손해, 이익 중인지)
  var evaluationPrice: Double     // 평가금액	(지금 얼마인지)
  var averageBuyPrice: Double      // 매수평균가 (평단가)
  var buyAmount: Double            // 매수금액 (매수한 나의 총 금액)
}
