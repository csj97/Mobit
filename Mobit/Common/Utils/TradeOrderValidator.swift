//
//  TradeOrderValidator.swift
//  Mobit
//
//  Created by Codex on 6/29/26.
//

import Foundation

enum TradeOrderValidator {
  static let minimumOrderAmount: Double = 500

  enum ValidationError: Error, Equatable {
    case missingPrice
    case invalidQuantity
    case belowMinimumOrderAmount(minimum: Double)
    case insufficientBalance
    case insufficientHolding

    var message: String {
      switch self {
      case .missingPrice:
        return "현재가를 불러온 뒤 다시 시도해 주세요."
      case .invalidQuantity:
        return "주문 수량을 입력해 주세요."
      case .belowMinimumOrderAmount(let minimum):
        return "\(minimum.formatSignificantDigits())원 이상 매수/매도 가능합니다."
      case .insufficientBalance:
        return "주문 가능 금액이 부족합니다."
      case .insufficientHolding:
        return "보유 수량이 부족합니다."
      }
    }
  }

  static func validateBid(
    price: Double?,
    quantity: Double,
    availableBalance: Double?,
    minimumOrderAmount: Double = Self.minimumOrderAmount
  ) -> Result<Double, ValidationError> {
    guard let price, price > 0 else { return .failure(.missingPrice) }
    guard quantity > 0 else { return .failure(.invalidQuantity) }

    let executedAmount = PortfolioCalculator.executedAmount(
      price: price,
      quantity: quantity
    )

    guard executedAmount >= minimumOrderAmount else {
      return .failure(.belowMinimumOrderAmount(minimum: minimumOrderAmount))
    }

    guard let availableBalance, availableBalance >= executedAmount else {
      return .failure(.insufficientBalance)
    }

    return .success(executedAmount)
  }

  static func validateAsk(
    price: Double?,
    quantity: Double,
    holdingQuantity: Double,
    minimumOrderAmount: Double = Self.minimumOrderAmount
  ) -> Result<Double, ValidationError> {
    guard let price, price > 0 else { return .failure(.missingPrice) }
    guard quantity > 0 else { return .failure(.invalidQuantity) }
    guard quantity <= holdingQuantity else { return .failure(.insufficientHolding) }

    let executedAmount = PortfolioCalculator.executedAmount(
      price: price,
      quantity: quantity
    )

    guard executedAmount >= minimumOrderAmount else {
      return .failure(.belowMinimumOrderAmount(minimum: minimumOrderAmount))
    }

    return .success(executedAmount)
  }
}
