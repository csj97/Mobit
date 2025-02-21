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
  /// (prevAverageBuyPrice + currentPrice) / 2
  func calcAverBuyPrice() -> Double {
	if prevAverageBuyPrice == 0 {
	  return currentPrice
	} else {
	  return (prevAverageBuyPrice + currentPrice) / 2
	}
  }
  
  /// 수익률 계산
  /// ((현재가 - 평단가) / 평단가) * 100
  func calcProfitRate() -> Double {
	let averageBuyPrice = calcAverBuyPrice()
	let profitRate = ((currentPrice - averageBuyPrice) / averageBuyPrice) * 100
	return profitRate.formatDigits(digits: 2)
  }
  
  /// 평가손익 계산
  /// (현재가 - 평단가) * holdingQuantity
  func calcEvalProfitLoss() -> Double {
	let averageBuyPrice = calcAverBuyPrice()
	let profitLoss = (currentPrice - averageBuyPrice) * newHoldingQuantity
	return profitLoss.formatDigits(digits: 2)
  }
  
  /// 평가금액 계산
  /// 현재가 * holdingQuantity
  func calcEvalPrice() -> Double {
	return (currentPrice * newHoldingQuantity).formatDigits(digits: 8)
  }
  
  /// 매수 예정) 총 매수금액 계산
  /// 현재 매수하려는 총 금액 * tradingFee
  func calcBuyAmount() -> Double {
	let tradingFee: Double = 0.05
	let newBuyAmount = floor(currentPrice * newHoldingQuantity)
	let totalAmount = newBuyAmount - (newBuyAmount * tradingFee)
	
	return totalAmount
  }
  
  /// 누적 총 매수금액 (이전 매수 금액 포함)
  /// prevBuyAmount + (현재 매수금액 * tradingFee)
  func cumulCalcBuyAmount() -> Double {
	let tradingFee: Double = 0.05
	let newBuyAmount = floor(currentPrice * newHoldingQuantity)
	let totalAmount = newBuyAmount - (newBuyAmount * tradingFee)
	
	return prevBuyAmount + totalAmount
  }
}
