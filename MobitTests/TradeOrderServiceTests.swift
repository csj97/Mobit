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
    ExchangeSelectionStore.currentExchange = .upbit
    UserDataManager.resetInvestmentData(availableBalance: 10_000)
  }

  override func tearDown() {
    clearUserDefaults()
    ExchangeSelectionStore.currentExchange = .upbit
    super.tearDown()
  }

  func testExecuteBidCreatesFirstHolding() throws {
    let executedAt = makeDate(year: 2026, month: 7, day: 31, hour: 13, minute: 49)
    let result = TradeOrderService.executeBid(
      marketName: "BTC/KRW",
      cryptoName: "비트코인",
      currentPrice: 1_000,
      quantity: 2,
      executedAt: executedAt
    )

    let execution = try result.get()
    let crypto = try XCTUnwrap(UserDataManager.userCryptoList?.first)
    let transaction = try XCTUnwrap(UserDataManager.userTransactionList?.first)

    XCTAssertEqual(execution.executedAmount, 2_000)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 8_000)
    XCTAssertEqual(crypto.staticData.holdingQuantity, 2)
    XCTAssertEqual(crypto.staticData.averageBuyPrice, 1_000)
    XCTAssertEqual(crypto.staticData.buyAmount, 2_000)
    XCTAssertEqual(UserDataManager.userTransactionList?.count, 1)
    XCTAssertEqual(UserDataManager.userValidTransactionList?.count, 1)
    XCTAssertEqual(transaction.executedTimestamp, TradeTimestampFormatter.timestamp(from: executedAt))
    XCTAssertEqual(transaction.executedDate, "2026.07.31 13:49")
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

    let executedAt = makeDate(year: 2026, month: 8, day: 1, hour: 9, minute: 5)
    let result = TradeOrderService.executeAsk(
      marketName: "BTC/KRW",
      currentPrice: 1_500,
      quantity: 1,
      executedAt: executedAt
    )

    let execution = try result.get()
    let crypto = try XCTUnwrap(UserDataManager.userCryptoList?.first)
    let pnl = try XCTUnwrap(UserDataManager.userPNLHistory?.first)
    let sellTransaction = try XCTUnwrap(UserDataManager.userTransactionList?.last)

    XCTAssertEqual(execution.executedAmount, 1_500)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 8_500)
    XCTAssertEqual(crypto.staticData.holdingQuantity, 2)
    XCTAssertEqual(crypto.staticData.buyAmount, 2_000)
    XCTAssertEqual(pnl.pnl, 500)
    XCTAssertEqual(UserDataManager.userTransactionList?.count, 2)
    XCTAssertEqual(sellTransaction.executedTimestamp, TradeTimestampFormatter.timestamp(from: executedAt))
    XCTAssertEqual(sellTransaction.executedDate, "2026.08.01 09:05")
    XCTAssertEqual(pnl.transactionTimestamp, TradeTimestampFormatter.timestamp(from: executedAt))
    XCTAssertEqual(pnl.transactionDate, "2026.08.01 09:05")
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

  func testExecuteAskTreatsTruncatedQuantityAsFullSell() throws {
    // 최대 수량 버튼은 소수점 8자리로 절삭된 값을 넘기므로, 미세 잔량이 남지 않아야 한다.
    let holdingQuantity = 0.123456789
    _ = TradeOrderService.executeBid(
      marketName: "BTC/KRW",
      cryptoName: "비트코인",
      currentPrice: 10_000,
      quantity: holdingQuantity
    )

    let result = TradeOrderService.executeAsk(
      marketName: "BTC/KRW",
      currentPrice: 10_000,
      quantity: holdingQuantity.formatDigits(digits: 8)
    )

    let execution = try result.get()

    XCTAssertEqual(execution.executedAmount, floor(10_000 * holdingQuantity))
    XCTAssertEqual(UserDataManager.userCryptoList?.count, 0)
    XCTAssertEqual(UserDataManager.userValidTransactionList?.count, 0)
    XCTAssertEqual(UserDataManager.userPNLHistory?.first?.orderQuantity, holdingQuantity)
  }

  func testExecuteAskAppliesProceedsToOrderExchangeNotSelectedExchange() throws {
    ExchangeSelectionStore.currentExchange = .bithumb
    UserDataManager.resetInvestmentData(availableBalance: 10_000)

    _ = TradeOrderService.executeBid(
      marketName: "BTC/KRW",
      cryptoName: "비트코인",
      currentPrice: 1_000,
      quantity: 2,
      exchange: .bithumb
    )

    // 매도 체결 처리 도중 거래소가 전환된 상황
    ExchangeSelectionStore.currentExchange = .upbit
    let result = TradeOrderService.executeAsk(
      marketName: "BTC/KRW",
      currentPrice: 1_500,
      quantity: 2,
      exchange: .bithumb
    )

    _ = try result.get()

    XCTAssertEqual(UserDataManager.userInformation(for: .bithumb)?.userAvailableBalance, 11_000)
    XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 0)
  }

  func testExchangeAuditKeepsHoldingsHistoryAndBalancesSeparate() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      UserDataManager.updateUserInformation(MobitUserInformation(userAvailableBalance: 10_000), for: exchange)
      _ = try TradeOrderService.executeBid(
        marketName: "ETH/KRW", cryptoName: "이더리움", currentPrice: 1_000,
        quantity: 2, exchange: exchange
      ).get()
      _ = try TradeOrderService.executeAsk(
        marketName: "ETH/KRW", currentPrice: 1_500, quantity: 1, exchange: exchange
      ).get()
    }
    for exchange in [Exchange.upbit, .bithumb] {
      let holding = try XCTUnwrap(UserDataManager.userCryptoList?.first { $0.staticData.exchange == exchange })
      XCTAssertEqual(holding.staticData.holdingQuantity, 1)
      XCTAssertEqual(holding.staticData.buyAmount, 1_000)
      XCTAssertEqual(holding.dynamicData.evaluationPrice, 1_500)
      XCTAssertEqual(UserDataManager.userInformation(for: exchange)?.userAvailableBalance, 9_500)
      XCTAssertEqual(UserDataManager.userTransactionList?.filter { $0.exchange == exchange }.count, 2)
      XCTAssertEqual(UserDataManager.userPNLHistory?.first { $0.exchange == exchange }?.pnl, 500)
    }
  }

  func testExchangeAuditCostBasisRemainsConsistentAfterPartialSaleAndRebuy() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      UserDataManager.resetInvestmentData(availableBalance: 10_000)
      for price in [1_000.0, 2_000.0] {
        _ = try TradeOrderService.executeBid(
          marketName: "ETH/KRW", cryptoName: "이더리움", currentPrice: price,
          quantity: 1, exchange: exchange
        ).get()
      }
      _ = try TradeOrderService.executeAsk(
        marketName: "ETH/KRW", currentPrice: 2_000, quantity: 1, exchange: exchange
      ).get()
      _ = try TradeOrderService.executeBid(
        marketName: "ETH/KRW", cryptoName: "이더리움", currentPrice: 2_000,
        quantity: 1, exchange: exchange
      ).get()
      let holding = try XCTUnwrap(UserDataManager.userCryptoList?.first)
      XCTExpectFailure("\(exchange.rawValue): FIFO 잔여 매수내역과 유지된 평균단가가 재매수 시 혼합됨") {
        XCTAssertEqual(
          holding.staticData.buyAmount,
          holding.staticData.averageBuyPrice * holding.staticData.holdingQuantity,
          accuracy: 0.000001
        )
      }
    }
  }

  func testExchangeAuditRejectsOrderWhenStoredHoldingsCannotBeDecoded() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      UserDataManager.resetInvestmentData(availableBalance: 10_000)
      let corruptedData = Data("invalid-json".utf8)
      UserDefaults.standard.set(corruptedData, forKey: UserDataManager.Keys.userCryptoList)
      let result = TradeOrderService.executeBid(
        marketName: "ETH/KRW", cryptoName: "이더리움", currentPrice: 1_000,
        quantity: 1, exchange: exchange
      )
      XCTExpectFailure("\(exchange.rawValue): 보유 데이터 디코딩 실패에도 잔고 차감과 성공 반환이 진행됨") {
        if case .success = result { XCTFail("손상된 보유 데이터에서 주문이 성공함") }
        XCTAssertEqual(UserDataManager.userInformation(for: exchange)?.userAvailableBalance, 10_000)
        XCTAssertEqual(UserDataManager.userTransactionList?.count, 0)
      }
      XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList), corruptedData)
    }
  }

  private func clearUserDefaults() {
    [
      UserDataManager.Keys.isFirstLaunch,
      UserDataManager.Keys.userFavoriteList,
      UserDataManager.Keys.userTransactionList,
      UserDataManager.Keys.userValidTransactionList,
      UserDataManager.Keys.userCryptoList,
      UserDataManager.Keys.userPNLHistory,
      UserDataManager.Keys.userInformation,
      UserDataManager.Keys.userInformationByExchange
    ].forEach {
      UserDefaults.standard.removeObject(forKey: $0)
    }
  }

  private func makeDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int
  ) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(identifier: "Asia/Seoul")
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return components.date!
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
