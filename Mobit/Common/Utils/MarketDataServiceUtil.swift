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
  
  func addValidTransactionData(
	for marketName: String,
	orderType: OrderType,
	postValidTransactionList: [ValidTransactionInfo]?,
	newValidTransactionData: ValidTransactionInfo.Transaction
  ) {
	// 이미 해당 마켓의 거래 내역이 존재하는 경우
	if let index = postValidTransactionList?.firstIndex(where: { $0.marketName == marketName }) {
	  let target = UserDataManager.userValidTransactionList?[index]
	  guard var targetTransactionList = target?.transaction else { return }

	  switch orderType {
	  case .bid:
		// 매수인 경우 단순 추가
		targetTransactionList.append(newValidTransactionData)

	  case .ask:
		// 매도할 수량
		var remainingSellQuantity = newValidTransactionData.quantity
		// FIFO 방식으로 매도 수량만큼 기존 매수내역에서 차감
		var updatedTransactions: [ValidTransactionInfo.Transaction] = []
		
		// tx : transaction의 약어
		for var tx in targetTransactionList {
		  if remainingSellQuantity <= 0 {
			// 매도 수량 다 소진했으면 그대로 유지
			updatedTransactions.append(tx)
			continue
			
		  }
		  
		  if tx.orderType == .bid {
			if tx.quantity > remainingSellQuantity {
			  // 일부만 차감
			  tx.quantity -= remainingSellQuantity
			  updatedTransactions.append(tx)
			  remainingSellQuantity = 0
			} else {
			  // 전량 차감 (해당 매수 내역 제거됨)
			  remainingSellQuantity -= tx.quantity
			  // append 생략
			}
		  } else {
			// 기존 매도 내역은 그대로 유지
			updatedTransactions.append(tx)
		  }
		}

		targetTransactionList = updatedTransactions
	  }

	  // 업데이트된 거래 내역 반영
	  UserDataManager.userValidTransactionList?[index].transaction = targetTransactionList

	  // 보유량 0이면 제거
	  if UserDataManager.userValidTransactionList?[index].isFullySoldOut == true {
		UserDataManager.userValidTransactionList?.remove(at: index)
	  }
	} else {
	  // 아직 거래 내역이 없다면, 매수만 허용
	  guard orderType == .bid else { return }

	  let newValidTransaction = ValidTransactionInfo(
		marketName: marketName,
		transaction: [newValidTransactionData]
	  )
	  UserDataManager.userValidTransactionList?.append(newValidTransaction)
	}
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
	let evalPrice = (currentPrice * holdingQuantity)
	// 매수 금액
	let averagePrice = (averageBuyPrice * holdingQuantity)
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
