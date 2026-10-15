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
      case .missingPrice: return FuturesText.text("spot_order_missing_price")
      case .invalidQuantity: return FuturesText.text("spot_order_invalid_quantity")
      case .belowMinimumOrderAmount(let minimum, let currency):
        return String(
          format: FuturesText.text("spot_order_minimum"),
          minimum.formatSignificantDigits(),
          currency == .krw ? FuturesText.text("currency_krw_unit") : currency.rawValue
        )
      case .insufficientBalance(let currency):
        return FuturesText.text(currency == .btc ? "spot_order_insufficient_btc" : "spot_order_insufficient_balance")
      case .insufficientHolding: return FuturesText.text("spot_order_insufficient_holding")
      case .unsupportedMarket: return FuturesText.text("spot_order_unsupported_market")
      case .invalidStoredData: return FuturesText.text("spot_order_storage_error")
      case .missingCostBasis: return FuturesText.text("spot_order_missing_cost")
      case .missingSettlementRate: return FuturesText.text("spot_order_missing_rate")
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
