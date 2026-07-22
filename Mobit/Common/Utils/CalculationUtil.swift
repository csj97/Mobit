//
//  CalculationUtil.swift
//  Mobit
//
//  Created by 조성재 on 2/20/25.
//

import Foundation

class CalculationUtil {
  
  // 초기화 시 전달받을 값들
  private let currentPrice: Double
  private let prevAverageBuyPrice: Double
  private let prevBuyAmount: Double
  private let prevHoldingQuantity: Double
  private let newHoldingQuantity: Double
  
  // 초기화
  init(
	currentPrice: Double,
	prevHoldingQuantity: Double = 0,
	prevAverageBuyPrice: Double = 0,
	prevBuyAmount: Double = 0,
	newHoldingQuantity: Double
  ) {
	self.currentPrice = currentPrice
	self.prevHoldingQuantity = prevHoldingQuantity
	self.prevAverageBuyPrice = prevAverageBuyPrice
	self.prevBuyAmount = prevBuyAmount
	self.newHoldingQuantity = newHoldingQuantity
  }
  
  /// 누적 수량
  func cumulCalcHoldingQuantity() -> Double {
	return PortfolioCalculator.cumulativeHoldingQuantity(
	  previousQuantity: prevHoldingQuantity,
	  newQuantity: newHoldingQuantity
	)
  }
  
  /// new 수량
  func calcHoldingQuantity() -> Double {
	return newHoldingQuantity
  }
  
  /// 평단가 계산: 매수 금액과 수량에 따라 평단가 계산
  func calcAverBuyPrice(
    for marketName: String,
    exchange: Exchange = ExchangeSelectionStore.currentExchange
  ) -> Double {
	let userValidTransactionList = UserDataManager.userValidTransactionList
    let targetPairID = ExchangeMarketCodeConverter.pairID(
      fromDisplayMarket: marketName,
      exchange: exchange
    )
	let validTransactionData = userValidTransactionList?.first {
      $0.exchangePairID == targetPairID
    }
	
	let averageBuyPrice = validTransactionData?.averageBuyPrice
	
	return averageBuyPrice ?? 0
  }
  
  /// 매수금액
  func calcBuyAmount() -> Double {
	return PortfolioCalculator.executedAmount(
	  price: currentPrice,
	  quantity: newHoldingQuantity
	)
  }
  
  /// 누적 총 매수금액 (이전 매수 금액 포함)
  /// prevBuyAmount + (현재 매수금액 * tradingFee)
  func cumulCalcBuyAmount() -> Double {
	return PortfolioCalculator.cumulativeBuyAmount(
	  previousBuyAmount: prevBuyAmount,
	  price: currentPrice,
	  quantity: newHoldingQuantity
	)
  }
  
  /// 수수료 계산
  /// 수수료 = 총 거래 금액 × 수수료율
  func calcTradingFee(tradingPrice: Double) -> Double {
	let tradingFee = 0.05
	return tradingPrice * tradingFee
  }
  
  /// 실현손익 계산
  /// 실현손익 = (매도가 - 매수가)  * 수량
  func calcPnl(entryPrice: Double, exitPrice: Double, quantity: Double) -> Double {
	return PortfolioCalculator.realizedProfitLoss(
	  entryPrice: entryPrice,
	  exitPrice: exitPrice,
	  quantity: quantity
	)
  }
}
