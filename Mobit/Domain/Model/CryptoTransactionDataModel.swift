//
//  BidCryptoInfo.swift
//  Mobit
//
//  Created by 조성재 on 2/19/25.
//

import Foundation

struct CryptoTransactionDataModel: Codable, Equatable {
  var staticData: CryptoTransactionStaticData
  var dynamicData: CryptoTransactionDynamicData
  
  /// 거래 정보 (정적)
  struct CryptoTransactionStaticData: Codable, Equatable {
	let marketName: String          // 코인 마켓 이름 (예: "BTC-USDT")
	var holdingQuantity: Double     // 보유 수량
	var averageBuyPrice: Double     // 매수 평균가
	var buyAmount: Double           // 매수 총액
  }

  /// 거래 정보 (동적) - 실시간성 업데이트
  struct CryptoTransactionDynamicData: Codable, Equatable {
	let marketName: String
	var profitRate: Double          // 수익률
	var evaluationProfitLoss: Double // 평가손익 (얼마 손해, 이익 중인지)
	var evaluationPrice: Double     // 평가금액	(지금 얼마인지)
  }
}

struct TransactionInfo: Codable, Equatable {
  let marketName: String          // 코인 마켓 이름 (예: "BTC-USDT")
  let orderType: OrderType		// 주문 타입 (매도, 매수)
  let executedDate: String    // 체결 시간
  let executedPrice: Double   // 체결 가격
  let executedQuantity: Double // 체결 수량
  let executedAmount: Double  // 체결 금액 (가격 * 수량)
}
