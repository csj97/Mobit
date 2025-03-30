//
//  BidCryptoInfo.swift
//  Mobit
//
//  Created by 조성재 on 2/19/25.
//

import Foundation

struct CryptoTransactionDataModel: Codable {
  var staticData: CryptoTransactionStaticData
  var dynamicData: CryptoTransactionDynamicData
  
  /// 거래 정보 (정적)
  struct CryptoTransactionStaticData: Codable {
	let marketName: String          // 코인 마켓 이름 (예: "BTC-USDT")
	var holdingQuantity: Double     // 보유 수량
	var averageBuyPrice: Double     // 매수 평균가
	var buyAmount: Double           // 매수 총액
	var transactionHistoryList: [TransactionInfo] // 거래 내역 리스트
	
	struct TransactionInfo: Codable {
	  let executedDate: String    // 체결 시간
	  let executedPrice: Double   // 체결 가격
	  let executedQuantity: Double // 체결 수량
	  let executedAmount: Double  // 체결 금액 (가격 * 수량)
	}
	
	// 보유 수량 업데이트
	mutating func updateHoldingQuantity(_ newQuantity: Double) {
	  self.holdingQuantity += newQuantity
	}
	
	// 매수 평균가 업데이트
	mutating func updateAverageBuyPrice(_ newPrice: Double) {
	  self.averageBuyPrice = (self.buyAmount + newPrice) / 2
	}
	
	mutating func updateBuyAmount(_ newAmount: Double) {
	  self.buyAmount += newAmount
	}
  }

  /// 거래 정보 (동적) - 실시간성 업데이트
  struct CryptoTransactionDynamicData: Codable {
	let marketName: String
	var profitRate: Double          // 수익률
	var evaluationProfitLoss: Double // 평가손익 (얼마 손해, 이익 중인지)
	var evaluationPrice: Double     // 평가금액	(지금 얼마인지)
  }
}
