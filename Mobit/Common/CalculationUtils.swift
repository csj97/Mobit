//
//  CalculationUtils.swift
//  Mobit
//
//  Created by 조성재 on 2/20/25.
//

import Foundation

class CalculationUtils {
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
  
  func calcHoldingQuantity() -> Double {
	return prevHoldingQuantity + newHoldingQuantity
  }
  
  /// 평단가 계산
  /// 평균 매수가 = (기존 보유 코인 × 기존 평균 매수가 + 새 매수 금액) ÷ (기존 보유 코인 + 새 매수 수량)
  func calcAverBuyPrice() -> Double {
	if prevAverageBuyPrice == 0 {
	  return currentPrice
	} else {
//	  let averageBuyPrice = (prevHoldingQuantity * prevAverageBuyPrice + currentPrice) / (prevHoldingQuantity + newHoldingQuantity)
//	  return averageBuyPrice
	  return (prevAverageBuyPrice + currentPrice) / 2
	}
  }
  
  /// 수익률 계산
  /// 수익률 (%) = [(현재 가격 - 평균 매수가) ÷ 평균 매수가] × 100
  func calcProfitRate() -> Double {
	let averageBuyPrice = calcAverBuyPrice()
	let profitRate = ((currentPrice - averageBuyPrice) / averageBuyPrice) * 100
	return profitRate.formatDigits(digits: 2)
  }
  
  /// 평가손익 계산
  /// 실현 수익 = (매도가 - 평균 매수가) × 매도 수량 - 수수료
  /// (현재가 - 평단가) * holdingQuantity
  func calcEvalProfitLoss() -> Double {
	let newBuyAmount = floor(currentPrice * newHoldingQuantity)
	let averageBuyPrice = calcAverBuyPrice()
	let profitLoss = ((currentPrice - averageBuyPrice) * newHoldingQuantity) - calcTradingFee(tradingPrice: newBuyAmount)
	return profitLoss.formatDigits(digits: 2)
  }
  
  /// 평가금액 계산
  /// 평가 금액 = 보유 코인 수량 × 현재 시장 가격
  func calcEvalPrice() -> Double {
	let cumulHoldingQuantity = calcHoldingQuantity()
	return (currentPrice * cumulHoldingQuantity).formatDigits(digits: 8)
  }
  
  /// 매수 예정) 총 매수금액 계산
  /// 현재 매수하려는 총 금액 * tradingFee
  func calcBuyAmount() -> Double {
	let newBuyAmount = floor(currentPrice * newHoldingQuantity)
	let fee = calcTradingFee(tradingPrice: newBuyAmount)
	let amount = newBuyAmount - fee
	
	return amount
  }
  
  /// 누적 총 매수금액 (이전 매수 금액 포함)
  /// prevBuyAmount + (현재 매수금액 * tradingFee)
  func cumulCalcBuyAmount() -> Double {
	let cumulAmount = prevBuyAmount + calcBuyAmount()
	
	return cumulAmount
  }
  
  /// 수수료 계산
  /// 수수료 = 총 거래 금액 × 수수료율
  func calcTradingFee(tradingPrice: Double) -> Double {
	let tradingFee = 0.05
	return tradingPrice * tradingFee
  }
}
