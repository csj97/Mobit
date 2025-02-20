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
  private let holdingQuantity: Double
  
  // 초기화
  init(
	currentPrice: Double,
	prevHoldingQuantity: Double = 0,
	prevAverageBuyPrice: Double = 0,
	prevBuyAmount: Double = 0,
	holdingQuantity: Double
  ) {
	self.currentPrice = currentPrice
	self.prevHoldingQuantity = prevHoldingQuantity
	self.prevAverageBuyPrice = prevAverageBuyPrice
	self.prevBuyAmount = prevBuyAmount
	self.holdingQuantity = holdingQuantity
  }
  
  func calcHoldingQuantity() -> Double {
	return prevHoldingQuantity + holdingQuantity
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
	let profitLoss = (currentPrice - averageBuyPrice) * holdingQuantity
	return profitLoss.formatDigits(digits: 2)
  }
  
  /// 평가금액 계산
  /// 현재가 * holdingQuantity
  func calcEvalPrice() -> Double {
	return (currentPrice * holdingQuantity).formatDigits(digits: 8)
  }
  
  /// 총 매수금액 계산
  /// prevBuyAmount + (현재 매수금액 * tradingFee)
  func calcBuyAmount() -> Double {
	let tradingFee: Double = 0.05
	let currentBuyAmount = floor(currentPrice * holdingQuantity)
	let tradingFeePrice = currentBuyAmount - (currentBuyAmount * tradingFee)
	
	return prevBuyAmount + (currentBuyAmount - tradingFeePrice)
  }
}
