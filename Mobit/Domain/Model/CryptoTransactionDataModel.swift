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

/// 유효한 거래내역 (현재 보유하고 있는 건에 대한 매수 내역, 총보유수량이 0이 되면 해당 코인 내역 통으로 날림)
struct ValidTransactionInfo: Codable, Equatable {
  let marketName: String
  var transaction: [Transaction]
  
  // 매수 & 매도 +- 계산해서 토탈 0이 되면 통으로 삭제
  struct Transaction: Codable, Equatable {
	let orderType: OrderType
	let quantity: Double
	let buyPrice: Double
  }
}

extension ValidTransactionInfo {
  
  var totalHoldingQuantity: Double {
	transaction.reduce(0.0) { result, t in
	  switch t.orderType {
	  case .bid:
		return result + t.quantity
	  case .ask:
		return result - t.quantity
	  }
	}
  }
  
  var averageBuyPrice: Double? {
	let buyTransactions = transaction.filter { $0.orderType == .bid }
	
	let totalBuyAmount = buyTransactions.reduce(0.0) { $0 + ($1.buyPrice * $1.quantity) }
	let totalBuyQuantity = buyTransactions.reduce(0.0) { $0 + $1.quantity }
	
	return totalBuyQuantity > 0 ? totalBuyAmount / totalBuyQuantity : nil
  }
  
  var isFullySoldOut: Bool {
	totalHoldingQuantity == 0
  }
}
