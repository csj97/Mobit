//
//  TradeOrderValidator.swift
//  Mobit
//
//  Created by 조성재 on 6/29/26.
//

import Foundation

enum TradeOrderValidator {
  static let minimumOrderAmount: Double = SettlementCurrency.krw.minimumOrderAmount

  enum ValidationError: Error, Equatable {
    case missingPrice
    case invalidQuantity
    case belowMinimumOrderAmount(minimum: Double, currency: SettlementCurrency)
    case insufficientBalance(currency: SettlementCurrency)
    case insufficientHolding
    case unsupportedMarket
    case invalidStoredData
    case missingCostBasis
    case missingSettlementRate

    var message: String {
      switch self {
      case .missingPrice:
        return "현재가를 불러온 뒤 다시 시도해 주세요."
      case .invalidQuantity:
        return "주문 수량을 입력해 주세요."
      case .belowMinimumOrderAmount(let minimum, let currency):
        switch currency {
        case .krw:
          return "\(minimum.formatSignificantDigits())원 이상 매수/매도 가능합니다."
        case .btc:
          return "\(minimum.formatSignificantDigits()) BTC 이상 매수/매도 가능합니다."
        }
      case .insufficientBalance(let currency):
        switch currency {
        case .krw:
          return "주문 가능 금액이 부족합니다."
        case .btc:
          // BTC 마켓은 원화가 아니라 보유 BTC로 결제하므로 확보 방법까지 안내한다.
          return "보유한 BTC가 부족합니다. 원화 마켓에서 BTC를 먼저 매수해 주세요."
        }
      case .insufficientHolding:
        return "보유 수량이 부족합니다."
      case .unsupportedMarket:
        return "지원하지 않는 마켓입니다."
      case .invalidStoredData:
        return "저장된 투자내역을 읽을 수 없어 주문할 수 없습니다."
      case .missingCostBasis:
        return "기존 보유분의 매수원가를 확인할 수 없어 주문할 수 없습니다."
      case .missingSettlementRate:
        return "BTC 시세를 불러온 뒤 다시 시도해 주세요."
      }
    }
  }

  static func validateBid(
    price: Double?,
    quantity: Double,
    availableBalance: Double?,
    currency: SettlementCurrency = .krw
  ) -> Result<Double, ValidationError> {
    guard let price, price.isFinite, price > 0 else { return .failure(.missingPrice) }
    guard quantity.isFinite, quantity > 0 else { return .failure(.invalidQuantity) }

    let executedAmount = PortfolioCalculator.executedAmount(
      price: price,
      quantity: quantity,
      currency: currency
    )
    guard executedAmount.isFinite else { return .failure(.invalidQuantity) }
    let minimumOrderAmount = currency.minimumOrderAmount

    guard executedAmount >= minimumOrderAmount else {
      return .failure(.belowMinimumOrderAmount(minimum: minimumOrderAmount, currency: currency))
    }

    guard let availableBalance, availableBalance >= executedAmount else {
      return .failure(.insufficientBalance(currency: currency))
    }

    return .success(executedAmount)
  }

  static func validateAsk(
    price: Double?,
    quantity: Double,
    holdingQuantity: Double,
    currency: SettlementCurrency = .krw
  ) -> Result<Double, ValidationError> {
    guard let price, price.isFinite, price > 0 else { return .failure(.missingPrice) }
    guard quantity.isFinite, quantity > 0 else { return .failure(.invalidQuantity) }
    guard quantity <= holdingQuantity else { return .failure(.insufficientHolding) }

    let executedAmount = PortfolioCalculator.executedAmount(
      price: price,
      quantity: quantity,
      currency: currency
    )
    guard executedAmount.isFinite else { return .failure(.invalidQuantity) }
    let minimumOrderAmount = currency.minimumOrderAmount

    guard executedAmount >= minimumOrderAmount else {
      return .failure(.belowMinimumOrderAmount(minimum: minimumOrderAmount, currency: currency))
    }

    return .success(executedAmount)
  }
}
