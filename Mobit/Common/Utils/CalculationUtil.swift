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
  
  func calcHoldingQuantity() -> Double {
	return prevHoldingQuantity + newHoldingQuantity
  }
  
  /// 평단가 계산 *** 매수 금액에 따라 평단가가 달라질 수 있음
  /// 평균 매수가 = (기존 보유 코인 × 기존 평균 매수가 + 새 매수 금액) ÷ (기존 보유 코인 + 새 매수 수량)
//  func calcAverBuyPrice() -> Double {
//	if prevAverageBuyPrice == 0 {
//	  return currentPrice
//	} else {
//	  return (prevAverageBuyPrice + currentPrice) / 2
//	}
//  }
  
  /// 평단가 계산: 매수 금액과 수량에 따라 평단가 계산
  func calcAverBuyPrice() -> Double {
	let totalCost = (prevAverageBuyPrice * prevHoldingQuantity) + (currentPrice * newHoldingQuantity)
	let totalAmount = prevHoldingQuantity + newHoldingQuantity
	
	guard totalAmount != 0 else { return 0 }  // 수량 0일 경우 방어
	
	return totalCost / totalAmount
  }
  
  /// 매수 예정) 총 매수금액 계산
  /// 현재 매수하려는 총 금액 * tradingFee
  func calcBuyAmount() -> Double {
	let newBuyAmount = floor(currentPrice * calcHoldingQuantity())
	let fee = calcTradingFee(tradingPrice: newBuyAmount)
	let amount = newBuyAmount
	
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
