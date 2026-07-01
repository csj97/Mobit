//
//  TradeOrderServiceTests.swift
//  MobitTests
//
//  Created by Codex on 6/30/26.
//

import XCTest
@testable import Mobit

final class TradeOrderServiceTests: XCTestCase {
  override func setUp() {
    super.setUp()
    clearUserDefaults()
    UserDataManager.resetInvestmentData(availableBalance: 10_000)
  }

  override func tearDown() {
    clearUserDefaults()
    super.tearDown()
  }

  func testExecuteBidCreatesFirstHolding() throws {
    let result = TradeOrderService.executeBid(
      marketName: "BTC/KRW",
      cryptoName: "비트코인",
      currentPrice: 1_000,
      quantity: 2
    )

    let execution = try result.get()
    let crypto = try XCTUnwrap(UserDataManager.userCryptoList?.first)

    XCTAssertEqual(execution.executedAmount, 2_000)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 8_000)
    XCTAssertEqual(crypto.staticData.holdingQuantity, 2)
    XCTAssertEqual(crypto.staticData.averageBuyPrice, 1_000)
    XCTAssertEqual(crypto.staticData.buyAmount, 2_000)
    XCTAssertEqual(UserDataManager.userTransactionList?.count, 1)
    XCTAssertEqual(UserDataManager.userValidTransactionList?.count, 1)
  }

  func testExecuteBidRejectsBelowMinimumAmountWithoutMutatingState() {
    let result = TradeOrderService.executeBid(
      marketName: "BTC/KRW",
      cryptoName: "비트코인",
      currentPrice: 100,
      quantity: 1
    )

    XCTAssertEqual(result.failure, .belowMinimumOrderAmount(minimum: 500))
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 10_000)
    XCTAssertEqual(UserDataManager.userCryptoList?.count, 0)
    XCTAssertEqual(UserDataManager.userTransactionList?.count, 0)
    XCTAssertEqual(UserDataManager.userValidTransactionList?.count, 0)
  }

  func testExecuteBidRejectsInsufficientBalanceWithoutMutatingState() {
    let result = TradeOrderService.executeBid(
      marketName: "BTC/KRW",
      cryptoName: "비트코인",
      currentPrice: 9_000,
      quantity: 2
    )

    XCTAssertEqual(result.failure, .insufficientBalance)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 10_000)
    XCTAssertEqual(UserDataManager.userCryptoList?.count, 0)
    XCTAssertEqual(UserDataManager.userTransactionList?.count, 0)
    XCTAssertEqual(UserDataManager.userValidTransactionList?.count, 0)
  }

  func testExecuteBidUpdatesAveragePriceForExistingHolding() throws {
    _ = TradeOrderService.executeBid(
      marketName: "BTC/KRW",
      cryptoName: "비트코인",
      currentPrice: 1_000,
      quantity: 2
    )

    let result = TradeOrderService.executeBid(
      marketName: "BTC/KRW",
      cryptoName: "비트코인",
      currentPrice: 2_000,
      quantity: 1
    )

    _ = try result.get()
    let crypto = try XCTUnwrap(UserDataManager.userCryptoList?.first)

    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 6_000)
    XCTAssertEqual(crypto.staticData.holdingQuantity, 3)
    XCTAssertEqual(crypto.staticData.averageBuyPrice, 1_333.3333333333333)
    XCTAssertEqual(crypto.staticData.buyAmount, 4_000)
    XCTAssertEqual(UserDataManager.userTransactionList?.count, 2)
  }

  func testExecuteAskPartiallySellsHoldingAndRecordsPNL() throws {
    _ = TradeOrderService.executeBid(
      marketName: "BTC/KRW",
      cryptoName: "비트코인",
      currentPrice: 1_000,
      quantity: 3
    )

    let result = TradeOrderService.executeAsk(
      marketName: "BTC/KRW",
      currentPrice: 1_500,
      quantity: 1
    )

    let execution = try result.get()
    let crypto = try XCTUnwrap(UserDataManager.userCryptoList?.first)
    let pnl = try XCTUnwrap(UserDataManager.userPNLHistory?.first)

    XCTAssertEqual(execution.executedAmount, 1_500)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 8_500)
    XCTAssertEqual(crypto.staticData.holdingQuantity, 2)
    XCTAssertEqual(crypto.staticData.buyAmount, 2_000)
    XCTAssertEqual(pnl.pnl, 500)
    XCTAssertEqual(UserDataManager.userTransactionList?.count, 2)
  }

  func testExecuteAskRejectsMissingHoldingWithoutMutatingState() {
    let result = TradeOrderService.executeAsk(
      marketName: "BTC/KRW",
      currentPrice: 1_500,
      quantity: 1
    )

    XCTAssertEqual(result.failure, .insufficientHolding)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 10_000)
    XCTAssertEqual(UserDataManager.userCryptoList?.count, 0)
    XCTAssertEqual(UserDataManager.userTransactionList?.count, 0)
    XCTAssertEqual(UserDataManager.userPNLHistory?.count, 0)
  }

  func testExecuteAskRejectsQuantityAboveHoldingWithoutMutatingSellState() {
    _ = TradeOrderService.executeBid(
      marketName: "BTC/KRW",
      cryptoName: "비트코인",
      currentPrice: 1_000,
      quantity: 2
    )

    let result = TradeOrderService.executeAsk(
      marketName: "BTC/KRW",
      currentPrice: 1_500,
      quantity: 3
    )

    let crypto = UserDataManager.userCryptoList?.first
    XCTAssertEqual(result.failure, .insufficientHolding)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 8_000)
    XCTAssertEqual(crypto?.staticData.holdingQuantity, 2)
    XCTAssertEqual(UserDataManager.userTransactionList?.count, 1)
    XCTAssertEqual(UserDataManager.userPNLHistory?.count, 0)
  }

  func testExecuteAskConsumesValidTransactionsFIFO() throws {
    _ = TradeOrderService.executeBid(
      marketName: "BTC/KRW",
      cryptoName: "비트코인",
      currentPrice: 1_000,
      quantity: 1
    )
    _ = TradeOrderService.executeBid(
      marketName: "BTC/KRW",
      cryptoName: "비트코인",
      currentPrice: 2_000,
      quantity: 2
    )

    _ = TradeOrderService.executeAsk(
      marketName: "BTC/KRW",
      currentPrice: 3_000,
      quantity: 1.5
    )

    let crypto = try XCTUnwrap(UserDataManager.userCryptoList?.first)
    let validTransaction = try XCTUnwrap(UserDataManager.userValidTransactionList?.first)

    XCTAssertEqual(crypto.staticData.holdingQuantity, 1.5)
    XCTAssertEqual(validTransaction.transaction.count, 1)
    XCTAssertEqual(validTransaction.transaction[0].quantity, 1.5)
    XCTAssertEqual(validTransaction.transaction[0].buyPrice, 2_000)
  }

  func testExecuteAskFullySellsHolding() throws {
    _ = TradeOrderService.executeBid(
      marketName: "BTC/KRW",
      cryptoName: "비트코인",
      currentPrice: 1_000,
      quantity: 2
    )

    let result = TradeOrderService.executeAsk(
      marketName: "BTC/KRW",
      currentPrice: 1_500,
      quantity: 2
    )

    _ = try result.get()

    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 11_000)
    XCTAssertEqual(UserDataManager.userCryptoList?.count, 0)
    XCTAssertEqual(UserDataManager.userValidTransactionList?.count, 0)
    XCTAssertEqual(UserDataManager.userPNLHistory?.count, 1)
  }

  private func clearUserDefaults() {
    [
      UserDataManager.Keys.isFirstLaunch,
      UserDataManager.Keys.userFavoriteList,
      UserDataManager.Keys.userTransactionList,
      UserDataManager.Keys.userValidTransactionList,
      UserDataManager.Keys.userCryptoList,
      UserDataManager.Keys.userPNLHistory,
      UserDataManager.Keys.userInformation
    ].forEach {
      UserDefaults.standard.removeObject(forKey: $0)
    }
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
