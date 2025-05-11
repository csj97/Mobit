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

  func fetchData(
	data: CryptoTransactionDataModel.CryptoTransactionStaticData,
	currentPrice: Double
  ) {
	fetchAll(
	  for: data.marketName,
	  currentPrice: currentPrice,
	  holdingQuantity: data.holdingQuantity,
	  averageBuyPrice: data.averageBuyPrice,
	  buyAmount: data.buyAmount
	)
  }
  
  /// 기존 매매내역이 없을 때, 추가
  func addCryptoFirstData(
	for marketName: String,
	staticData: CryptoTransactionDataModel.CryptoTransactionStaticData,
	currentPrice: Double
  ) {
	let profitRate = fetchProfitRate(
	  for: marketName,
	  currentPrice: currentPrice,
	  averageBuyPrice: staticData.averageBuyPrice
	)
	
	let evalProfitLoss = fetchEvalProfitLoss(
	  for: marketName,
	  currentPrice: currentPrice,
	  holdingQuantity: staticData.holdingQuantity,
	  averageBuyPrice: staticData.averageBuyPrice
	)
	
	let evalPrice = fetchEvalPrice(
	  for: marketName,
	  currentPrice: currentPrice,
	  holdingQuantity: staticData.holdingQuantity
	)
	
	let dynamicData = CryptoTransactionDataModel.CryptoTransactionDynamicData(
	  marketName: marketName,
	  profitRate: profitRate,
	  evaluationProfitLoss: evalProfitLoss,
	  evaluationPrice: evalPrice
	)
	
	let newCrypto = CryptoTransactionDataModel(
	  staticData: staticData,
	  dynamicData: dynamicData
	)
	
	UserDataManager.userCryptoList?.append(newCrypto)
  }
  
  /// Static & Dynamic Data Fetch
  func fetchAll(
	for marketName: String,
	currentPrice: Double,
	holdingQuantity: Double,
	averageBuyPrice: Double,
	buyAmount: Double
  ) {
	// 정적 데이터 업데이트
	fetchStaticData(
	  for: marketName,
	  averageBuyAmount: averageBuyPrice,
	  holdingQuantity: holdingQuantity,
	  buyAmount: buyAmount
	)
	// 수익률
	fetchProfitRate(
	  for: marketName,
	  currentPrice: currentPrice,
	  averageBuyPrice: averageBuyPrice
	)
	// 평가손익
	fetchEvalProfitLoss(
	  for: marketName,
	  currentPrice: currentPrice,
	  holdingQuantity: holdingQuantity,
	  averageBuyPrice: averageBuyPrice
	)
	// 평가금액
	fetchEvalPrice(
	  for: marketName,
	  currentPrice: currentPrice,
	  holdingQuantity: holdingQuantity
	)
  }
  
  /// 정적 데이터 업데이트 (평균매수가, 개수, 매수금액)
  func fetchStaticData(
	for marketName: String,
	averageBuyAmount: Double,
	holdingQuantity: Double,
	buyAmount: Double
  ) {
	if var userCryptoList = UserDataManager.userCryptoList,
	   let index = userCryptoList.firstIndex(where: { $0.staticData.marketName == marketName }) {
	  
	  userCryptoList[index].staticData.averageBuyPrice = averageBuyAmount
	  userCryptoList[index].staticData.holdingQuantity = holdingQuantity
	  userCryptoList[index].staticData.buyAmount = buyAmount
	  
	  UserDataManager.userCryptoList = userCryptoList
	}
  }
  
  /// 거래내역 추가
  func addTransactionData(
	postTransactionList: [TransactionInfo]?,
	data: TransactionInfo
  ) {
	var newTransactionList = postTransactionList
	newTransactionList?.append(data)
	
	UserDataManager.userTransactionList = newTransactionList
  }
  
  /// 매수&매도 시, 사용자 잔고 업데이트
  func fetchUserAvailableBalance(
	orderType: OrderType,
	balance: Double,
	newBuyAmount: Double
  ) {
	var newBalance = balance
	
	if orderType == .bid {
	  // 매수
	  newBalance -= newBuyAmount
	} else {
	  // 매도 (수익 현황에 따라 -값이 들어올 수도 있음)
	  newBalance += newBuyAmount
	}
	
	UserDataManager.userInformation = MobitUserInformation(
	  userAvailableBalance: newBalance
	)
  }
  
  /// 수익률 계산
  @discardableResult
  func fetchProfitRate(
	for marketName: String,
	currentPrice: Double,
	averageBuyPrice: Double
  ) -> Double {
	// 0으로 나누기 방지
	guard averageBuyPrice != 0 else { return 0 }
	
	let profitRate = (((currentPrice - averageBuyPrice) / averageBuyPrice) * 100).formatDigits(digits: 2)
	
	if var userCryptoList = UserDataManager.userCryptoList,
	   let index = userCryptoList.firstIndex(where: { $0.staticData.marketName == marketName }) {
	  
	  // 수익률 (%) = [(현재 가격 - 평균 매수가) ÷ 평균 매수가] × 100
	  userCryptoList[index].dynamicData.profitRate = profitRate
	  UserDataManager.userCryptoList = userCryptoList
	}
	
	return profitRate
  }
  
  /// 평가손익 계산
  @discardableResult
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
	// 평가 손익
	let profitLoss = evalPrice - averagePrice
	
	if var userCryptoList = UserDataManager.userCryptoList,
	   let index = userCryptoList.firstIndex(where: { $0.staticData.marketName == marketName }) {
	  
	  userCryptoList[index].dynamicData.evaluationProfitLoss = profitLoss
	  UserDataManager.userCryptoList = userCryptoList
	}
	
	return profitLoss
  }
  
  /// 평가금액 계산
  @discardableResult
  func fetchEvalPrice(
	for marketName: String,
	currentPrice: Double,
	holdingQuantity: Double
  ) -> Double {
	// 보유 수량이 음수일 경우 방지
	guard holdingQuantity >= 0 else { return 0 }
	
	let evalPrice = (currentPrice * holdingQuantity).formatDigits(digits: 8)
	
	if var userCryptoList = UserDataManager.userCryptoList,
	   let index = userCryptoList.firstIndex(where: { $0.staticData.marketName == marketName }) {
	  
	  userCryptoList[index].dynamicData.evaluationPrice = evalPrice
	  UserDataManager.userCryptoList = userCryptoList
	}
	
	return evalPrice
  }
}
