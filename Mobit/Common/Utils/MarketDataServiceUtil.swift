//
//  MarketDataServiceUtil.swift
//  Mobit
//
//  Created by 조성재 on 3/29/25.
//

import Foundation

/// 실시간 데이터 관리
class MarketDataServiceUtil {
  static let shared = MarketDataServiceUtil()
  var userCryptoList: [CryptoTransactionDataModel]? = UserDataManager.userCryptoList
  
  func fetchData(data: CryptoTransactionDataModel.CryptoTransactionStaticData, currentPrice: Double) {
	fetchAll(
	  for: data.marketName,
	  currentPrice: currentPrice,
	  holdingQuantity: data.holdingQuantity,
	  averageBuyPrice: data.averageBuyPrice,
	  buyAmount: data.buyAmount
	)
  }
  
  func fetchAll(
	for marketName: String,
	currentPrice: Double,
	holdingQuantity: Double,
	averageBuyPrice: Double,
	buyAmount: Double
  ) {
	// 매수금액 업데이트
	fetchStaticData(
	  for: marketName,
	  averageBuyAmount: averageBuyPrice,
	  holdingQuantity: holdingQuantity,
	  buyAmount: buyAmount
	)
	// 수익률
	let _ = fetchProfitRate(
	  for: marketName,
	  currentPrice: currentPrice,
	  averageBuyPrice: averageBuyPrice
	)
	// 평가손익
	let _ = fetchEvalProfitLoss(
	  for: marketName,
	  currentPrice: currentPrice,
	  holdingQuantity: holdingQuantity,
	  averageBuyPrice: averageBuyPrice
	)
	// 평가금액
	let _ = fetchEvalPrice(
	  for: marketName,
	  currentPrice: currentPrice,
	  holdingQuantity: holdingQuantity
	)
  }
  
  // 정적 데이터 업데이트 (평균매수가, 개수, 매수금액)
  func fetchStaticData(
	for marketName: String,
	averageBuyAmount: Double,
	holdingQuantity: Double,
	buyAmount: Double
  ) {
	if var userCryptoList = userCryptoList,
	   let index = userCryptoList.firstIndex(where: { $0.staticData.marketName == marketName }) {
	  
	  userCryptoList[index].staticData.averageBuyPrice = averageBuyAmount
	  userCryptoList[index].staticData.holdingQuantity = holdingQuantity
	  userCryptoList[index].staticData.buyAmount = buyAmount
	  
	  self.userCryptoList = userCryptoList
	  UserDataManager.userCryptoList = userCryptoList
	}
  }
  
  /// 수익률 계산
  /// 수익률 (%) = [(현재 가격 - 평균 매수가) ÷ 평균 매수가] × 100
  func fetchProfitRate(
	for marketName: String,
	currentPrice: Double,
	averageBuyPrice: Double
  ) -> Double {
	// 0으로 나누기 방지
	guard averageBuyPrice != 0 else { return 0 }
	
	let profitRate = (((currentPrice - averageBuyPrice) / averageBuyPrice) * 100).formatDigits(digits: 2)
	
	if var userCryptoList = userCryptoList,
	   let index = userCryptoList.firstIndex(where: { $0.staticData.marketName == marketName }) {
	  userCryptoList[index].dynamicData.profitRate = profitRate
	  self.userCryptoList = userCryptoList
	}
	
	return profitRate
  }
  
  /// 평가손익 계산
  /// 실현 수익 = (매도가 - 평균 매수가) × 매도 수량 - 수수료
  /// (현재가 - 평단가) * holdingQuantity
  func fetchEvalProfitLoss(
	for marketName: String,
	currentPrice: Double,
	holdingQuantity: Double,
	averageBuyPrice: Double,
	tradingFee: Double = 0.05
  ) -> Double {
	// 평가 금액
	let evalPrice = (currentPrice * holdingQuantity).formatDigits(digits: 8)
	// 매수 금액
	let averagePrice = (averageBuyPrice * holdingQuantity).formatDigits(digits: 8)
	
//	let newBuyAmount = floor(currentPrice * newHoldingQuantity).formatDigits(digits: 2)
//	let tradingFee = (tradingFee * (averageBuyPrice * cumulHoldingQuantity)).formatDigits(digits: 2)
//	let profitLoss = ((currentPrice - averageBuyPrice) * cumulHoldingQuantity)
	let profitLoss = evalPrice - averagePrice
	if var userCryptoList = userCryptoList,
	   let index = userCryptoList.firstIndex(where: { $0.staticData.marketName == marketName }) {
	  userCryptoList[index].dynamicData.evaluationProfitLoss = profitLoss
	  self.userCryptoList = userCryptoList
	}
	
	return profitLoss
  }
  
  /// 평가금액 계산
  /// 평가 금액 = 보유 코인 수량 × 현재 시장 가격
  func fetchEvalPrice(
	for marketName: String,
	currentPrice: Double,
	holdingQuantity: Double
  ) -> Double {
	// 보유 수량이 음수일 경우 방지
	guard holdingQuantity >= 0 else {
	  return 0
	}
	
	let evalPrice = (currentPrice * holdingQuantity).formatDigits(digits: 8)
	
	if var userCryptoList = userCryptoList,
	   let index = userCryptoList.firstIndex(where: { $0.staticData.marketName == marketName }) {
	  userCryptoList[index].dynamicData.evaluationPrice = evalPrice
	  self.userCryptoList = userCryptoList
	}
	
	return evalPrice
  }
}



// 실시간 데이터 계산 (수익률, 평가손익, 평가금액) - 정적 데이터가 필요함 (calculation에서 계산 해줘야함)
// 정적 데이터 계산 (마켓명, 보유수량, 매수평균가, 매수총액) - mutating func에서 업데이트 해줌
// 정적 데이터 <-> 실시간 데이터 사이에서 계산을 해줄 수 있는 util이 필요
