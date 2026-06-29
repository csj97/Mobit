//
//  TradeOrderValidatorTests.swift
//  MobitTests
//
//  Created by Codex on 6/29/26.
//

import XCTest
@testable import Mobit

final class TradeOrderValidatorTests: XCTestCase {
  func testBidValidationSucceedsWithEnoughBalance() {
    let result = TradeOrderValidator.validateBid(
      price: 1_000,
      quantity: 1.2,
      availableBalance: 2_000
    )

    XCTAssertEqual(try? result.get(), 1_200)
  }

  func testBidValidationRejectsInvalidQuantity() {
    let result = TradeOrderValidator.validateBid(
      price: 1_000,
      quantity: 0,
      availableBalance: 2_000
    )

    XCTAssertEqual(result.failure, .invalidQuantity)
  }

  func testBidValidationRejectsBelowMinimumAmount() {
    let result = TradeOrderValidator.validateBid(
      price: 100,
      quantity: 1,
      availableBalance: 2_000
    )

    XCTAssertEqual(result.failure, .belowMinimumOrderAmount(minimum: 500))
  }

  func testBidValidationRejectsInsufficientBalance() {
    let result = TradeOrderValidator.validateBid(
      price: 1_000,
      quantity: 2,
      availableBalance: 1_999
    )

    XCTAssertEqual(result.failure, .insufficientBalance)
  }

  func testAskValidationSucceedsWithEnoughHolding() {
    let result = TradeOrderValidator.validateAsk(
      price: 1_000,
      quantity: 1.5,
      holdingQuantity: 2
    )

    XCTAssertEqual(try? result.get(), 1_500)
  }

  func testAskValidationRejectsInsufficientHolding() {
    let result = TradeOrderValidator.validateAsk(
      price: 1_000,
      quantity: 3,
      holdingQuantity: 2
    )

    XCTAssertEqual(result.failure, .insufficientHolding)
  }
}

private extension Result where Failure == TradeOrderValidator.ValidationError {
  var failure: Failure? {
    if case .failure(let error) = self {
      return error
    }
    return nil
  }
}
