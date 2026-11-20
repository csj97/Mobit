//
//  TradeOrderServiceTests.swift
//  MobitTests
//
//  Created by Codex on 6/30/26.
//

import XCTest
import UIKit
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

    XCTAssertEqual(result.failure, .belowMinimumOrderAmount(minimum: 500, currency: .krw))
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

    XCTAssertEqual(result.failure, .insufficientBalance(currency: .krw))
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

  func testKRWSettlementPreservesDecimalBalanceAcrossBuyAndSell() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      XCTAssertTrue(UserDataManager.resetInvestmentData(availableBalance: 1_000.29))

      _ = try TradeOrderService.executeBid(
        marketName: "BTC/KRW",
        cryptoName: nil,
        currentPrice: 500,
        quantity: 1,
        exchange: exchange
      ).get()
      XCTAssertEqual(UserDataManager.userInformation(for: exchange)?.userAvailableBalance, 500.29)

      _ = try TradeOrderService.executeAsk(
        marketName: "BTC/KRW",
        currentPrice: 500,
        quantity: 1,
        exchange: exchange
      ).get()
      XCTAssertEqual(UserDataManager.userInformation(for: exchange)?.userAvailableBalance, 1_000.29)
    }
  }

  func testPartialSalePreservesDecimalQuantityAndCost() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      XCTAssertTrue(UserDataManager.resetInvestmentData(availableBalance: 10_000))

      _ = try TradeOrderService.executeBid(
        marketName: "BTC/KRW",
        cryptoName: nil,
        currentPrice: 10_000,
        quantity: 0.3,
        exchange: exchange
      ).get()
      _ = try TradeOrderService.executeAsk(
        marketName: "BTC/KRW",
        currentPrice: 10_000,
        quantity: 0.1,
        exchange: exchange
      ).get()

      // 부분 매도 이후 수량과 기존 원가가 모두 같은 보유분을 나타내야 한다.
      let holding = try XCTUnwrap(UserDataManager.userCryptoList?.first)
      XCTAssertEqual(holding.staticData.holdingQuantity, 0.2)
      XCTAssertEqual(holding.staticData.buyAmount, 2_000)
      XCTAssertEqual(holding.staticData.costBasisKRW, 2_000)
      XCTAssertEqual(UserDataManager.userInformation(for: exchange)?.userAvailableBalance, 8_000)
      XCTAssertEqual(UserDataManager.userPNLHistory?.last?.realizedProfitLossKRW, 0)
    }
  }

  func testPartialSaleFallsBackWhenDecimalProductExceedsExponentRange() throws {
    _ = try TradeOrderService.executeBid(
      marketName: "BTC/KRW",
      cryptoName: nil,
      currentPrice: 10_000,
      quantity: 0.3
    ).get()
    // 구형 저장값의 극단적인 매수금액이 십진수 곱셈에서 거대 값으로 바뀌지 않아야 한다.
    var holdings = try XCTUnwrap(UserDataManager.userCryptoList)
    holdings[0].staticData.buyAmount = 1e-128
    UserDataManager.userCryptoList = holdings

    _ = try TradeOrderService.executeAsk(
      marketName: "BTC/KRW",
      currentPrice: 10_000,
      quantity: 0.1
    ).get()

    let remainingAmount = try XCTUnwrap(UserDataManager.userCryptoList?.first?.staticData.buyAmount)
    XCTAssertEqual(remainingAmount, 1e-128 * 0.2 / 0.3)
  }

  func testConcurrentBidRequestsCannotSpendTheSameBalanceTwice() {
    UserDataManager.resetInvestmentData(availableBalance: 500)
    let queue = DispatchQueue(label: "TradeOrderServiceTests.concurrent", attributes: .concurrent)
    let group = DispatchGroup()
    let resultLock = NSLock()
    var results: [Result<TradeOrderService.Execution, TradeOrderValidator.ValidationError>] = []

    for _ in 0..<2 {
      group.enter()
      queue.async {
        let result = TradeOrderService.executeBid(
          marketName: "BTC/KRW",
          cryptoName: "비트코인",
          currentPrice: 500,
          quantity: 1
        )
        resultLock.lock()
        results.append(result)
        resultLock.unlock()
        group.leave()
      }
    }

    XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
    XCTAssertEqual(results.filter {
      if case .success = $0 { return true }
      return false
    }.count, 1)
    XCTAssertEqual(results.compactMap(\.failure), [.insufficientBalance(currency: .krw)])
    XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 0)
    XCTAssertEqual(UserDataManager.userCryptoList?.first?.staticData.holdingQuantity, 1)
    XCTAssertEqual(UserDataManager.userTransactionList?.count, 1)
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

  func testLegacyDelistingCreditsSavedEvaluationToBalance() throws {
    _ = try TradeOrderService.executeBid(
      marketName: "GEOD/KRW",
      cryptoName: "지오드넷",
      currentPrice: 500,
      quantity: 10
    ).get()

    var holdings = try XCTUnwrap(UserDataManager.userCryptoList)
    holdings[0].dynamicData.evaluationProfitLoss = -4_660
    holdings[0].dynamicData.evaluationPrice = 340
    holdings[0].dynamicData.settlementPriceSnapshot = nil
    UserDataManager.userCryptoList = holdings

    let result = TradeOrderService.executeDelistingSettlement(
      marketName: "GEOD/KRW",
      executedAt: makeDate(year: 2026, month: 9, day: 17, hour: 11, minute: 30)
    )

    let execution = try result.get()
    let transaction = try XCTUnwrap(UserDataManager.userTransactionList?.last)
    let pnl = try XCTUnwrap(UserDataManager.userPNLHistory?.last)
    XCTAssertEqual(execution.executedAmount, 340)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 5_340)
    XCTAssertTrue(UserDataManager.userCryptoList?.isEmpty == true)
    XCTAssertEqual(transaction.executedPrice, 34)
    XCTAssertEqual(transaction.recordType, .delistingSettlement)
    XCTAssertEqual(pnl.realizedProfitLossKRW, -4_660)
  }

  func testDelistingQuoteMatchesKRWSettlementIncludingZeroValue() throws {
    for storedProfitLoss in [-4_660.0, -5_000.0] {
      XCTAssertTrue(UserDataManager.resetInvestmentData(availableBalance: 10_000))
      _ = try TradeOrderService.executeBid(
        marketName: "ZZQATEST/KRW",
        cryptoName: "시험코인",
        currentPrice: 500,
        quantity: 10
      ).get()
      // 구형 평가금액과 손익이 다르면 정산을 보류한다.
      var holdings = try XCTUnwrap(UserDataManager.userCryptoList)
      holdings[0].dynamicData.evaluationProfitLoss = storedProfitLoss
      holdings[0].dynamicData.evaluationPrice = 9_999
      holdings[0].dynamicData.settlementPriceSnapshot = nil
      UserDataManager.userCryptoList = holdings

      XCTAssertEqual(TradeOrderService.delistingSettlementQuote(for: holdings[0]).failure, .settlementUnverified)
      let balanceBefore = try XCTUnwrap(UserDataManager.userInformation?.userAvailableBalance)
      let holdingsBefore = UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList)
      XCTAssertEqual(
        TradeOrderService.executeDelistingSettlement(marketName: "ZZQATEST/KRW").failure,
        .settlementUnverified
      )
      XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList), holdingsBefore)
      XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, balanceBefore)

      // 저장 평가금액과 손익이 일치하면 확인한 금액으로 정산한다.
      holdings[0].dynamicData.evaluationPrice = storedProfitLoss == -5_000 ? 0 : 340
      UserDataManager.userCryptoList = holdings
      let quote = try TradeOrderService.delistingSettlementQuote(for: holdings[0]).get()
      XCTAssertEqual(quote.marketName, "ZZQATEST/KRW")
      XCTAssertEqual(quote.quantity, 10)
      XCTAssertEqual(quote.currency, .krw)
      XCTAssertEqual(quote.executedAmount, storedProfitLoss == -5_000 ? 0 : 340)

      let execution = try TradeOrderService.executeDelistingSettlement(
        marketName: "ZZQATEST/KRW",
        expectedQuote: quote
      ).get()
      XCTAssertEqual(execution.settlementCurrency, quote.currency)
      XCTAssertEqual(execution.executedAmount, quote.executedAmount)
      XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, balanceBefore + quote.executedAmount)
      XCTAssertTrue(UserDataManager.userCryptoList?.isEmpty == true)
    }
  }

  func testDelistingQuoteMatchesBTCSettlementForBothExchanges() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      XCTAssertTrue(UserDataManager.resetInvestmentData(availableBalance: 10_000_000))
      try seedBTCHolding(quantity: 0.1, btcKRWPrice: 100_000_000, exchange: exchange)
      _ = try TradeOrderService.executeBid(
        marketName: "ZZQATEST/BTC",
        cryptoName: "시험코인",
        currentPrice: 0.05,
        quantity: 1,
        exchange: exchange,
        btcKRWPrice: 100_000_000
      ).get()
      // BTC 마켓의 저장 손익은 BTC 결제 단위다.
      var holdings = try XCTUnwrap(UserDataManager.userCryptoList)
      let index = try XCTUnwrap(holdings.firstIndex { $0.staticData.marketName == "ZZQATEST/BTC" })
      holdings[index].dynamicData.evaluationProfitLoss = 0.01
      holdings[index].dynamicData.evaluationPrice = 0.06
      holdings[index].dynamicData.settlementPriceSnapshot = nil
      UserDataManager.userCryptoList = holdings

      let quote = try TradeOrderService.delistingSettlementQuote(for: holdings[index]).get()
      XCTAssertEqual(quote.currency, .btc)
      XCTAssertEqual(quote.quantity, 1)
      XCTAssertEqual(quote.executedAmount, 0.06, accuracy: 1e-12)
      let balanceBefore = try XCTUnwrap(UserDataManager.userInformation(for: exchange)?.userAvailableBalance)
      let btcBefore = try XCTUnwrap(holdings.first { $0.staticData.marketName == "BTC/KRW" })
      // 원화 환산 시세가 없어 정산하지 못해도 미리 본 자산은 그대로 보존된다.
      let holdingsBefore = UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList)
      let missingRate = TradeOrderService.executeDelistingSettlement(
        marketName: "ZZQATEST/BTC",
        exchange: exchange,
        expectedQuote: quote
      )
      XCTAssertEqual(missingRate.failure, .missingSettlementRate)
      XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList), holdingsBefore)
      let execution = try TradeOrderService.executeDelistingSettlement(
        marketName: "ZZQATEST/BTC",
        exchange: exchange,
        btcKRWPrice: 100_000_000,
        expectedQuote: quote
      ).get()
      let btcAfter = try XCTUnwrap(UserDataManager.userCryptoList?.first { $0.staticData.marketName == "BTC/KRW" })
      XCTAssertEqual(execution.settlementCurrency, .btc)
      XCTAssertEqual(execution.executedAmount, quote.executedAmount, accuracy: 1e-12)
      XCTAssertEqual(btcAfter.staticData.holdingQuantity, btcBefore.staticData.holdingQuantity + quote.executedAmount, accuracy: 1e-12)
      XCTAssertEqual(UserDataManager.userInformation(for: exchange)?.userAvailableBalance, balanceBefore)
    }
  }

  func testDelistingSettlementAcceptsOnlyPreviousZeroPriceAtDecimalBoundary() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      XCTAssertTrue(UserDataManager.resetInvestmentData(availableBalance: 10_000))
      // 이전 Double 계산으로 저장된 0원 가치의 보유 종목이다.
      var holding = makeDelistingHolding(
        exchange: exchange,
        marketName: "ZZQATEST/KRW",
        averageBuyPrice: 100,
        profitLoss: -(100.0 * 64.4),
        costBasisKRW: 6_440
      )
      holding.staticData.holdingQuantity = 64.4
      holding.staticData.buyAmount = 6_440
      holding.dynamicData.evaluationPrice = 0
      UserDataManager.userCryptoList = [holding]

      // 저장 손익이 소수 곱셈 오차를 포함해도 기존 정산 가격은 0이다.
      XCTAssertLessThan(holding.dynamicData.evaluationProfitLoss, -6_440)
      let quote = try TradeOrderService.delistingSettlementQuote(for: holding).get()
      XCTAssertEqual(quote.settlementPrice, 0)
      XCTAssertEqual(quote.executedAmount, 0)

      // 실제 손실이나 양수 가치는 0원 오차 예외로 바꾸지 않는다.
      var negativeHolding = holding
      negativeHolding.dynamicData.evaluationProfitLoss = holding.dynamicData.evaluationProfitLoss.nextDown
      XCTAssertEqual(TradeOrderService.delistingSettlementQuote(for: negativeHolding).failure, .settlementUnverified)
      var positiveHolding = holding
      positiveHolding.dynamicData.evaluationProfitLoss = -6_439.999999999999
      XCTAssertEqual(try TradeOrderService.delistingSettlementQuote(for: positiveHolding).get().executedAmount, 0)

      // 0원 반환도 보유 제거와 실현손익을 한 번 기록한다.
      let execution = try TradeOrderService.executeDelistingSettlement(
        marketName: holding.staticData.marketName,
        exchange: exchange,
        expectedQuote: quote
      ).get()
      XCTAssertEqual(execution.executedAmount, 0)
      XCTAssertEqual(UserDataManager.userInformation(for: exchange)?.userAvailableBalance, 10_000)
      XCTAssertTrue(UserDataManager.userCryptoList?.isEmpty == true)
      XCTAssertEqual(UserDataManager.userTransactionList?.count, 1)
      XCTAssertEqual(UserDataManager.userTransactionList?.last?.executedAmount, 0)
      XCTAssertEqual(UserDataManager.userPNLHistory?.count, 1)
      XCTAssertEqual(UserDataManager.userPNLHistory?.last?.realizedProfitLossKRW, -6_440)
      XCTAssertEqual(
        TradeOrderService.executeDelistingSettlement(marketName: holding.staticData.marketName, exchange: exchange).failure,
        .insufficientHolding
      )
    }
  }

  func testLegacyDelistingUsesConsistentSavedValuationAtKRWBoundary() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      XCTAssertTrue(UserDataManager.resetInvestmentData(availableBalance: 10_000))
      // 구형 Double 저장 손익을 다시 더하면 정수보다 미세하게 작아지는 사례다.
      var holding = makeDelistingHolding(
        exchange: exchange,
        marketName: "ZZQATEST/KRW",
        averageBuyPrice: 15_560.0 / 940.2,
        profitLoss: 4_657_234,
        costBasisKRW: 15_560
      )
      holding.staticData.holdingQuantity = 940.2
      holding.staticData.buyAmount = 15_560
      holding.dynamicData.evaluationPrice = 4_672_794
      UserDataManager.userCryptoList = [holding]

      let quote = try TradeOrderService.delistingSettlementQuote(for: holding).get()
      XCTAssertEqual(quote.executedAmount, 4_672_794)
      let execution = try TradeOrderService.executeDelistingSettlement(
        marketName: holding.staticData.marketName,
        exchange: exchange,
        expectedQuote: quote
      ).get()
      XCTAssertEqual(execution.executedAmount, quote.executedAmount)
      XCTAssertEqual(UserDataManager.userTransactionList?.last?.executedAmount, quote.executedAmount)
      XCTAssertEqual(UserDataManager.userInformation(for: exchange)?.userAvailableBalance, 4_682_794)
      XCTAssertEqual(UserDataManager.userPNLHistory?.last?.realizedProfitLossKRW, 4_657_234)
    }
  }

  func testSnapshotPriceMustMatchSavedEvaluationAndProfit() throws {
    // 저장된 마지막 시세가 같은 평가 상태에서 계산한 값임을 확인한다.
    var holding = makeDelistingHolding(
      exchange: .upbit,
      marketName: "ZZQATEST/KRW",
      averageBuyPrice: 15_560.0 / 940.2,
      profitLoss: 0,
      costBasisKRW: 15_560
    )
    holding.staticData.holdingQuantity = 940.2
    holding.staticData.buyAmount = 15_560
    holding.dynamicData.evaluationProfitLoss = PortfolioCalculator.evaluationProfitLoss(
      currentPrice: 4_970,
      holdingQuantity: holding.staticData.holdingQuantity,
      averageBuyPrice: holding.staticData.averageBuyPrice
    )
    holding.dynamicData.evaluationPrice = PortfolioCalculator.evaluationPrice(
      currentPrice: 4_970,
      holdingQuantity: holding.staticData.holdingQuantity
    )
    holding.updateSettlementPriceSnapshot(currentPrice: 4_970)
    let snapshot = try XCTUnwrap(holding.dynamicData.settlementPriceSnapshot)
    XCTAssertEqual(try TradeOrderService.delistingSettlementQuote(for: holding).get().executedAmount, 4_672_794)

    // 다른 fingerprint는 그대로이고 시세만 오염되면 정산을 허용하지 않는다.
    holding.dynamicData.settlementPriceSnapshot = .init(
      price: 4_900,
      quantity: snapshot.quantity,
      averageBuyPrice: snapshot.averageBuyPrice,
      evaluationProfitLoss: snapshot.evaluationProfitLoss,
      evaluationPrice: snapshot.evaluationPrice
    )
    XCTAssertEqual(TradeOrderService.delistingSettlementQuote(for: holding).failure, .settlementUnverified)
  }

  func testConfirmedSnapshotChangesRejectWithoutMutatingAssets() throws {
    // 확인창 이후 저장 시세만 바뀌어도 사용자가 본 기준을 다시 확인해야 한다.
    _ = try TradeOrderService.executeBid(
      marketName: "ZZQATEST/KRW",
      cryptoName: "시험코인",
      currentPrice: 500,
      quantity: 10
    ).get()
    var holdings = try XCTUnwrap(UserDataManager.userCryptoList)
    let quote = try TradeOrderService.delistingSettlementQuote(for: holdings[0]).get()
    let previousSnapshot = try XCTUnwrap(holdings[0].dynamicData.settlementPriceSnapshot)
    holdings[0].dynamicData.settlementPriceSnapshot = .init(
      price: 501,
      quantity: previousSnapshot.quantity,
      averageBuyPrice: previousSnapshot.averageBuyPrice,
      evaluationProfitLoss: previousSnapshot.evaluationProfitLoss,
      evaluationPrice: previousSnapshot.evaluationPrice
    )
    UserDataManager.userCryptoList = holdings
    let holdingsBefore = UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList)
    let transactionsBefore = UserDefaults.standard.data(forKey: UserDataManager.Keys.userTransactionList)
    let pnlBefore = UserDefaults.standard.data(forKey: UserDataManager.Keys.userPNLHistory)
    let balanceBefore = UserDataManager.userInformation?.userAvailableBalance

    XCTAssertEqual(
      TradeOrderService.executeDelistingSettlement(
        marketName: "ZZQATEST/KRW",
        expectedQuote: quote
      ).failure,
      .settlementChanged
    )
    XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList), holdingsBefore)
    XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userTransactionList), transactionsBefore)
    XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userPNLHistory), pnlBefore)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, balanceBefore)
  }

  func testLegacyBTCValuationUsesStoredAmountAtSatoshiBoundary() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      // 구형 저장 손익을 더한 값은 1 사토시보다 작지만 평가액은 1 사토시다.
      var holding = makeDelistingHolding(
        exchange: exchange,
        marketName: "ZZQATEST/BTC",
        averageBuyPrice: 1,
        profitLoss: -0.9999999900000001,
        costBasisKRW: 100_000_000
      )
      holding.staticData.holdingQuantity = 1
      holding.dynamicData.evaluationPrice = 0.00000001
      let quote = try TradeOrderService.delistingSettlementQuote(for: holding).get()
      XCTAssertEqual(quote.executedAmount, 0.00000001)
    }
  }

  func testLegacySettlementUsesSavedAmountWhenPayoutsDifferByOneUnit() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      for (market, average, evaluation, expectedAmount) in [
        ("ZZQATEST/KRW", 4_970.0, 4_969.99999999, 4_969.0),
        ("ZZQATEST/KRW", 4_970.0, 4_971.0, 4_971.0),
        ("ZZQATEST/BTC", 0.29, 0.28999999, 0.28999999),
        ("ZZQATEST/BTC", 0.29, 0.29000001, 0.29000001)
      ] {
        // 역산값보다 한 단위 위·아래인 구형 평가금액을 각각 정산한다.
        var holding = makeDelistingHolding(
          exchange: exchange,
          marketName: market,
          averageBuyPrice: average,
          profitLoss: 0,
          costBasisKRW: 1
        )
        holding.staticData.holdingQuantity = 1
        holding.dynamicData.evaluationPrice = evaluation
        XCTAssertEqual(try TradeOrderService.delistingSettlementQuote(for: holding).get().executedAmount, expectedAmount)
      }
    }
  }

  func testDelistingPaysAccordingToWhetherTheLastPriceWasSaved() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      for savesLastPrice in [false, true] {
        ExchangeSelectionStore.currentExchange = exchange
        XCTAssertTrue(UserDataManager.resetInvestmentData(availableBalance: 10_000))
        // 구형 Double 평가액이 실제 시세 곱보다 1원 높게 절삭되는 보유분이다.
        let quantity = 10.299999999999999
        // 마지막 시세와 구형 평가액이 서로 다른 지급액을 만드는 경계다.
        let lastPrice = 100.0
        // 구형 저장 경로로 손익을 재현할 때 사용하는 평단이다.
        let average = 80.0
        // 시세 저장 여부만 바꿔 미리보기와 실제 지급 금액을 비교한다.
        var holding = makeDelistingHolding(
          exchange: exchange,
          marketName: "ZZQATEST/KRW",
          averageBuyPrice: average,
          profitLoss: lastPrice * quantity - average * quantity,
          costBasisKRW: 824
        )
        holding.staticData.holdingQuantity = quantity
        holding.staticData.buyAmount = 824
        holding.dynamicData.evaluationPrice = (lastPrice * quantity).formatDigits(digits: 8)
        XCTAssertEqual(holding.dynamicData.evaluationPrice, 1_030)
        if savesLastPrice { holding.updateSettlementPriceSnapshot(currentPrice: lastPrice) }
        UserDataManager.userCryptoList = [holding]

        // 시세가 없는 기록은 저장 평가금액, 있는 기록은 시세 곱에서 원 단위를 절삭한다.
        let expected = savesLastPrice ? 1_029.0 : 1_030.0
        // 실제 지급 직전에 확인창에서 확정한 금액과 다시 대조한다.
        let quote = try TradeOrderService.delistingSettlementQuote(for: holding).get()
        XCTAssertEqual(quote.executedAmount, expected)
        // 정산을 실행해 미리보기와 잔고·거래내역의 금액을 대조한다.
        let execution = try TradeOrderService.executeDelistingSettlement(
          marketName: holding.staticData.marketName,
          exchange: exchange,
          expectedQuote: quote
        ).get()
        XCTAssertEqual(execution.executedAmount, expected)
        XCTAssertEqual(UserDataManager.userInformation(for: exchange)?.userAvailableBalance, 10_000 + expected)
        XCTAssertEqual(UserDataManager.userTransactionList?.last?.executedAmount, expected)
        XCTAssertEqual(UserDataManager.userPNLHistory?.last?.realizedProfitLossKRW, PortfolioCalculator.decimal(expected) - 824)
        XCTAssertTrue(UserDataManager.userCryptoList?.isEmpty == true)
      }
    }
  }

  func testLegacyBTCValuationAwayFromUpperBoundaryRemainsUsable() throws {
    // 8자리 평가 절삭 구간 안에 있으면서 다음 사토시 경계와 충분히 떨어진 사례다.
    var holding = makeDelistingHolding(
      exchange: .upbit,
      marketName: "ZZQATEST/BTC",
      averageBuyPrice: 1,
      profitLoss: -0.999999985,
      costBasisKRW: 100_000_000
    )
    holding.staticData.holdingQuantity = 1
    holding.dynamicData.evaluationPrice = 0.00000001
    XCTAssertEqual(try TradeOrderService.delistingSettlementQuote(for: holding).get().executedAmount, 0.00000001)
  }

  func testSnapshotRetainsOriginalPriceWhenOldDoubleValuationRoundedDown() throws {
    // 최초 보유 생성 경로의 Double 내림으로 0.29 BTC가 한 사토시 작게 저장된 사례다.
    var holding = makeDelistingHolding(
      exchange: .upbit,
      marketName: "ZZQATEST/BTC",
      averageBuyPrice: 0.1,
      profitLoss: 0.29 - 0.1,
      costBasisKRW: 10_000_000
    )
    holding.staticData.holdingQuantity = 1
    holding.dynamicData.evaluationPrice = (0.29 as Double).formatDigits(digits: 8)
    holding.updateSettlementPriceSnapshot(currentPrice: 0.29)
    XCTAssertEqual(holding.dynamicData.evaluationPrice, 0.28999999)
    XCTAssertEqual(try TradeOrderService.delistingSettlementQuote(for: holding).get().executedAmount, 0.29)
  }

  func testSnapshotAndLegacyAllowBoundedDecimalAdditionPrecisionLoss() throws {
    // 실제 값은 정상이나 Decimal 38자리 합산에 정밀도 손실이 보고되는 보유분이다.
    let lastPrice = 93_332.0
    let averagePrice = 0.060365300000000004
    let quantity = 0.000000026391200000000002
    var holding = makeDelistingHolding(
      exchange: .upbit,
      marketName: "ZZQATEST/BTC",
      averageBuyPrice: averagePrice,
      profitLoss: PortfolioCalculator.evaluationProfitLoss(
        currentPrice: lastPrice,
        holdingQuantity: quantity,
        averageBuyPrice: averagePrice
      ),
      costBasisKRW: 1
    )
    holding.staticData.holdingQuantity = quantity
    holding.dynamicData.evaluationPrice = PortfolioCalculator.evaluationPrice(
      currentPrice: lastPrice,
      holdingQuantity: quantity
    )
    holding.updateSettlementPriceSnapshot(currentPrice: lastPrice)
    XCTAssertEqual(try TradeOrderService.delistingSettlementQuote(for: holding).get().executedAmount, 0.00246314)
    // 시세가 없는 같은 보유분은 저장 평가금액으로 정산한다.
    holding.dynamicData.settlementPriceSnapshot = nil
    XCTAssertEqual(try TradeOrderService.delistingSettlementQuote(for: holding).get().executedAmount, 0.00246314)
  }

  func testLegacySettlementRejectsConflictingAndImpreciseValues() {
    // 저장 평가금액이 손익과 다르거나 반올림 불확실도가 큰 구형 보유분이다.
    var holding = makeDelistingHolding(
      exchange: .upbit,
      marketName: "ZZQATEST/KRW",
      averageBuyPrice: 100,
      profitLoss: 0,
      costBasisKRW: 9_650
    )
    holding.dynamicData.evaluationPrice = 9_652
    XCTAssertEqual(TradeOrderService.delistingSettlementQuote(for: holding).failure, .settlementUnverified)
    holding.staticData.averageBuyPrice = 1e20
    holding.dynamicData.evaluationProfitLoss = 0
    holding.dynamicData.evaluationPrice = 9.65e21
    XCTAssertEqual(TradeOrderService.delistingSettlementQuote(for: holding).failure, .settlementUnverified)
  }

  func testDelistingSettlementRejectsWhenOnlyOnePreviousZeroCheckMatches() {
    for (averagePrice, quantity, profitLoss) in [
      (894.61, 587.95, -525_985.9495000001),
      (628.64, 800.07, -502_956.00480000005)
    ] {
      // 이전 합계와 단가가 각각 하나씩만 0이 되는 손익이다.
      var holding = makeDelistingHolding(
        exchange: .upbit,
        marketName: "ZZQATEST/KRW",
        averageBuyPrice: averagePrice,
        profitLoss: profitLoss,
        costBasisKRW: 1
      )
      holding.staticData.holdingQuantity = quantity
      XCTAssertEqual(TradeOrderService.delistingSettlementQuote(for: holding).failure, .settlementUnverified)
    }
  }

  func testDelistingSettlementPreservesKRWAmountAtDecimalBoundary() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      for (profitLoss, expectedAmount) in [(-67_974.600001, 2_315.0), (-67_974.6, 2_316.0), (-67_974.599999, 2_316.0)] {
        ExchangeSelectionStore.currentExchange = exchange
        XCTAssertTrue(UserDataManager.resetInvestmentData(availableBalance: 10_000))
        // 소수 경계에서 정산 전 반환액과 저장된 손익을 재현한다.
        let holding = makeDelistingHolding(
          exchange: exchange,
          marketName: "ZZQATEST/KRW",
          averageBuyPrice: 728.4,
          profitLoss: profitLoss,
          costBasisKRW: PortfolioCalculator.decimal(70_290.6)
        )
        UserDataManager.userCryptoList = [holding]

        // 확인창에 안내한 반환액은 확정한 정산에 그대로 사용된다.
        let quote = try TradeOrderService.delistingSettlementQuote(for: holding).get()
        XCTAssertEqual(quote.executedAmount, expectedAmount)
        // 확인한 반환액으로 전량 정산한 결과다.
        let execution = try TradeOrderService.executeDelistingSettlement(
          marketName: "ZZQATEST/KRW",
          exchange: exchange,
          expectedQuote: quote
        ).get()
        // 저장된 체결 금액을 확인한다.
        let transaction = try XCTUnwrap(UserDataManager.userTransactionList?.last)
        // 반환액을 반영한 원화 손익을 확인한다.
        let pnl = try XCTUnwrap(UserDataManager.userPNLHistory?.last)
        XCTAssertEqual(execution.executedAmount, expectedAmount)
        XCTAssertEqual(transaction.executedAmount, expectedAmount)
        XCTAssertEqual(UserDataManager.userInformation(for: exchange)?.userAvailableBalance, 10_000 + expectedAmount)
        XCTAssertEqual(pnl.realizedProfitLossKRW, PortfolioCalculator.decimal(expectedAmount) - PortfolioCalculator.decimal(70_290.6))
        XCTAssertEqual(pnl.pnl, expectedAmount - 70_290.6, accuracy: 1e-9)
        XCTAssertTrue(UserDataManager.userCryptoList?.isEmpty == true)
      }
    }
  }

  func testDelistingSettlementPreservesBTCAmountAtDecimalBoundary() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      XCTAssertTrue(UserDataManager.resetInvestmentData(availableBalance: 10_000_000))
      try seedBTCHolding(quantity: 0.1, btcKRWPrice: 100_000_000, exchange: exchange)
      // BTC 결제 금액의 여덟 번째 자리에서 절삭이 필요한 보유분이다.
      let holding = makeDelistingHolding(
        exchange: exchange,
        marketName: "ZZQATEST/BTC",
        averageBuyPrice: 0.000007284,
        profitLoss: -0.000679746,
        costBasisKRW: PortfolioCalculator.decimal(70_290.6)
      )
      UserDataManager.userCryptoList?.append(holding)

      // BTC 단위로 확인창에 표시할 반환액이다.
      let quote = try TradeOrderService.delistingSettlementQuote(for: holding).get()
      XCTAssertEqual(quote.executedAmount, 0.00002316, accuracy: 1e-16)
      // 확인한 BTC 반환액으로 전량 정산한 결과다.
      let execution = try TradeOrderService.executeDelistingSettlement(
        marketName: "ZZQATEST/BTC",
        exchange: exchange,
        btcKRWPrice: 100_000_000,
        expectedQuote: quote
      ).get()
      // 정산 금액이 저장된 체결 내역이다.
      let transaction = try XCTUnwrap(UserDataManager.userTransactionList?.last)
      // BTC 반환액의 원화 환산 손익이다.
      let pnl = try XCTUnwrap(UserDataManager.userPNLHistory?.last)
      // 반환 BTC가 더해진 결제 자산이다.
      let btc = try XCTUnwrap(UserDataManager.userCryptoList?.first { $0.staticData.marketName == "BTC/KRW" })
      XCTAssertEqual(execution.executedAmount, quote.executedAmount, accuracy: 1e-16)
      XCTAssertEqual(transaction.executedAmount, quote.executedAmount, accuracy: 1e-16)
      XCTAssertEqual(btc.staticData.holdingQuantity, 0.10002316, accuracy: 1e-16)
      XCTAssertEqual(pnl.realizedProfitLossKRW, PortfolioCalculator.decimal(-67_974.6))
      XCTAssertEqual(pnl.pnl, -0.000679746, accuracy: 1e-16)
    }
  }

  func testZeroBTCSettlementDoesNotCreateOrChangeBTCHolding() throws {
    // 읽을 때 생성되는 임시 UUID를 제외하고 모든 영구 저장 필드를 비교한다.
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    for exchange in [Exchange.upbit, .bithumb] {
      for hasBTCHolding in [false, true] {
        for storedProfitLoss in [-1.0, -0.999999995] {
          ExchangeSelectionStore.currentExchange = exchange
          XCTAssertTrue(UserDataManager.resetInvestmentData(availableBalance: 10_000_000))
          if hasBTCHolding {
            try seedBTCHolding(quantity: 0.1, btcKRWPrice: 100_000_000, exchange: exchange)
          }
          // 정확히 0 또는 BTC 절삭 후 0이 되는 종료 종목이다.
          var holding = makeDelistingHolding(
            exchange: exchange,
            marketName: "ZZQATEST/BTC",
            averageBuyPrice: 1,
            profitLoss: storedProfitLoss,
            costBasisKRW: 100_000_000
          )
          holding.staticData.holdingQuantity = 1
          holding.staticData.buyAmount = 1
          holding.dynamicData.evaluationPrice = 0
          UserDataManager.userCryptoList?.append(holding)
          // 다른 거래소 보유 자산은 현재 거래소의 정산과 독립적이다.
          let otherExchange: Exchange = exchange == .upbit ? .bithumb : .upbit
          let otherHolding = makeDelistingHolding(
            exchange: otherExchange,
            marketName: "BTC/KRW",
            averageBuyPrice: 100,
            profitLoss: 0,
            costBasisKRW: 9_650
          )
          UserDataManager.userCryptoList?.append(otherHolding)
          // 0 BTC 입금 전 결제 자산과 해당 거래 이력이다.
          let btcPair = ExchangeMarketCodeConverter.pairID(fromDisplayMarket: "BTC/KRW", exchange: exchange)
          let otherPair = ExchangeMarketCodeConverter.pairID(fromDisplayMarket: "BTC/KRW", exchange: otherExchange)
          let btcBefore = UserDataManager.userCryptoList?.first { $0.staticData.exchangePairID == btcPair }
          let btcTransactionsBefore = UserDataManager.userValidTransactionList?
            .first { $0.exchangePairID == btcPair }?.transaction
          let balanceBefore = UserDataManager.userInformation(for: exchange)?.userAvailableBalance
          let otherBalanceBefore = UserDataManager.userInformation(for: otherExchange)?.userAvailableBalance
          let transactionCount = UserDataManager.userTransactionList?.count ?? 0
          let pnlCount = UserDataManager.userPNLHistory?.count ?? 0
          // 표시 금액이 0 BTC인 정산을 확인한다.
          let quote = try TradeOrderService.delistingSettlementQuote(for: holding).get()
          XCTAssertEqual(quote.executedAmount, 0)
          let execution = try TradeOrderService.executeDelistingSettlement(
            marketName: holding.staticData.marketName,
            exchange: exchange,
            btcKRWPrice: 100_000_000,
            expectedQuote: quote
          ).get()

          XCTAssertEqual(execution.executedAmount, 0)
          XCTAssertEqual(execution.availableBalance, btcBefore?.staticData.holdingQuantity ?? 0)
          XCTAssertEqual(
            try encoder.encode(UserDataManager.userCryptoList?.first { $0.staticData.exchangePairID == btcPair }),
            try encoder.encode(btcBefore)
          )
          XCTAssertEqual(
            UserDataManager.userValidTransactionList?.first { $0.exchangePairID == btcPair }?.transaction,
            btcTransactionsBefore
          )
          XCTAssertFalse(UserDataManager.userCryptoList?.contains { $0.staticData.exchangePairID == holding.staticData.exchangePairID } ?? true)
          XCTAssertEqual(UserDataManager.userInformation(for: exchange)?.userAvailableBalance, balanceBefore)
          XCTAssertEqual(
            try encoder.encode(UserDataManager.userCryptoList?.first { $0.staticData.exchangePairID == otherPair }),
            try encoder.encode(otherHolding)
          )
          XCTAssertEqual(UserDataManager.userInformation(for: otherExchange)?.userAvailableBalance, otherBalanceBefore)
          XCTAssertEqual(UserDataManager.userTransactionList?.count, transactionCount + 1)
          XCTAssertEqual(UserDataManager.userTransactionList?.last?.executedAmount, 0)
          XCTAssertEqual(UserDataManager.userTransactionList?.last?.recordType, .delistingSettlement)
          XCTAssertEqual(UserDataManager.userPNLHistory?.count, pnlCount + 1)
          XCTAssertEqual(UserDataManager.userPNLHistory?.last?.realizedProfitLossKRW, -100_000_000)
        }
      }
    }
  }

  func testDelistingSettlementCreditsMinimumPositiveBTC() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      XCTAssertTrue(UserDataManager.resetInvestmentData(availableBalance: 10_000))
      // 절삭 후 1 사토시가 반환되는 종료 종목이다.
      var holding = makeDelistingHolding(
        exchange: exchange,
        marketName: "ZZQATEST/BTC",
        averageBuyPrice: 1,
        profitLoss: -0.99999999,
        costBasisKRW: 100_000_000
      )
      holding.staticData.holdingQuantity = 1
      holding.staticData.buyAmount = 1
      holding.dynamicData.evaluationPrice = 0.00000001
      UserDataManager.userCryptoList = [holding]

      // 양수 반환은 기존 BTC 입금과 거래 기록을 유지한다.
      let execution = try TradeOrderService.executeDelistingSettlement(
        marketName: holding.staticData.marketName,
        exchange: exchange,
        btcKRWPrice: 100_000_000
      ).get()
      XCTAssertEqual(execution.executedAmount, 0.00000001)
      XCTAssertEqual(execution.availableBalance, 0.00000001)
      XCTAssertEqual(UserDataManager.userCryptoList?.first?.staticData.holdingQuantity, 0.00000001)
      XCTAssertEqual(UserDataManager.userValidTransactionList?.first?.transaction.last?.quantity, 0.00000001)
      XCTAssertEqual(UserDataManager.userTransactionList?.last?.executedAmount, 0.00000001)
    }
  }

  func testDelistingSettlementKeepsFullQuantityBeyondEightDecimals() throws {
    // 표시 정밀도를 넘는 보유 수량도 전량 정산에 사용한다.
    var holding = makeDelistingHolding(
      exchange: .upbit,
      marketName: "ZZQATEST/KRW",
      averageBuyPrice: 728.4,
      profitLoss: -67_974.6000065556,
      costBasisKRW: PortfolioCalculator.decimal(70_290.6)
    )
    holding.staticData.holdingQuantity = 96.500000009
    holding.dynamicData.evaluationPrice = 2_316
    UserDataManager.userCryptoList = [holding]

    // 확인창과 체결 수량이 원래 보유 수량을 유지하는지 확인한다.
    let quote = try TradeOrderService.delistingSettlementQuote(for: holding).get()
    XCTAssertEqual(quote.quantity, 96.500000009)
    XCTAssertEqual(quote.executedAmount, 2_316)
    // 저장된 원본 수량으로 처리한 정산 결과다.
    let execution = try TradeOrderService.executeDelistingSettlement(
      marketName: "ZZQATEST/KRW",
      expectedQuote: quote
    ).get()
    XCTAssertEqual(execution.executedAmount, 2_316)
    XCTAssertEqual(UserDataManager.userTransactionList?.last?.executedQuantity, holding.staticData.holdingQuantity)
    XCTAssertTrue(UserDataManager.userCryptoList?.isEmpty == true)
  }

  private func makeDelistingHolding(
    exchange: Exchange,
    marketName: String,
    averageBuyPrice: Double,
    profitLoss: Double,
    costBasisKRW: Decimal
  ) -> CryptoTransactionDataModel {
    // 구형 손익과 같은 수량·평단으로 계산한 저장 평가금액이다.
    var evaluation = PortfolioCalculator.decimal(averageBuyPrice) * PortfolioCalculator.decimal(96.5)
      + PortfolioCalculator.decimal(profitLoss)
    // 실제 저장 평가금액은 소수 8자리까지만 남긴다.
    var storedEvaluation = Decimal.zero
    NSDecimalRound(&storedEvaluation, &evaluation, 8, .down)
    return CryptoTransactionDataModel(
      staticData: .init(
        exchange: exchange,
        marketName: marketName,
        cryptoName: "시험코인",
        holdingQuantity: 96.5,
        averageBuyPrice: averageBuyPrice,
        buyAmount: averageBuyPrice * 96.5,
        costBasisKRW: costBasisKRW
      ),
      dynamicData: .init(
        exchange: exchange,
        marketName: marketName,
        profitRate: 0,
        evaluationProfitLoss: profitLoss,
        evaluationPrice: max(0, PortfolioCalculator.double(storedEvaluation))
      )
    )
  }

  func testDelistingQuoteRejectsChangedHoldingOrSettlementBasis() throws {
    for changedField in 0..<4 {
      XCTAssertTrue(UserDataManager.resetInvestmentData(availableBalance: 10_000))
      _ = try TradeOrderService.executeBid(
        marketName: "ZZQATEST/KRW",
        cryptoName: "시험코인",
        currentPrice: 500,
        quantity: 10
      ).get()
      var holdings = try XCTUnwrap(UserDataManager.userCryptoList)
      let quote = try TradeOrderService.delistingSettlementQuote(for: holdings[0]).get()
      switch changedField {
      case 0:
        holdings[0].staticData.holdingQuantity = 9
      case 1:
        holdings[0].dynamicData.evaluationProfitLoss = -500
      case 2:
        holdings[0].staticData.averageBuyPrice = 501
      default:
        holdings[0].staticData.costBasisKRW = 4_999
      }
      UserDataManager.userCryptoList = holdings
      let holdingsBefore = UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList)
      let transactionsBefore = UserDefaults.standard.data(forKey: UserDataManager.Keys.userTransactionList)
      let pnlBefore = UserDefaults.standard.data(forKey: UserDataManager.Keys.userPNLHistory)
      let balanceBefore = UserDataManager.userInformation?.userAvailableBalance

      let result = TradeOrderService.executeDelistingSettlement(
        marketName: "ZZQATEST/KRW",
        expectedQuote: quote
      )
      XCTAssertEqual(result.failure, .settlementChanged)
      XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList), holdingsBefore)
      XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userTransactionList), transactionsBefore)
      XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userPNLHistory), pnlBefore)
      XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, balanceBefore)
    }
  }

  func testDelistingQuoteRejectsInvalidStoredValues() throws {
    _ = try TradeOrderService.executeBid(
      marketName: "ZZQATEST/KRW",
      cryptoName: "시험코인",
      currentPrice: 500,
      quantity: 10
    ).get()
    let holding = try XCTUnwrap(UserDataManager.userCryptoList?.first)
    // 숫자가 잘못된 보유분은 확인창에 임의의 반환 금액을 표시하지 않는다.
    var invalidQuantity = holding
    invalidQuantity.staticData.holdingQuantity = 0
    XCTAssertEqual(TradeOrderService.delistingSettlementQuote(for: invalidQuantity).failure, .missingPrice)
    var invalidPrice = holding
    invalidPrice.staticData.averageBuyPrice = .nan
    XCTAssertEqual(TradeOrderService.delistingSettlementQuote(for: invalidPrice).failure, .missingPrice)
    var negativeSettlement = holding
    negativeSettlement.dynamicData.evaluationProfitLoss = -6_000
    XCTAssertEqual(TradeOrderService.delistingSettlementQuote(for: negativeSettlement).failure, .settlementUnverified)
  }

  @MainActor
  func testDelistingOverlayConfirmationSettlesHoldingOnlyOnce() throws {
    // 실제 시세 업데이트와 무관한 보유 자산을 정산의 원본으로 준비한다.
    _ = try TradeOrderService.executeBid(
      marketName: "ZZQATEST/KRW",
      cryptoName: "시험코인",
      currentPrice: 500,
      quantity: 10
    ).get()
    // 시세 갱신이 멈추기 전에 저장된 값이다.
    var holdings = try XCTUnwrap(UserDataManager.userCryptoList)
    holdings[0].dynamicData.evaluationProfitLoss = -4_660
    holdings[0].dynamicData.evaluationPrice = 340
    holdings[0].dynamicData.settlementPriceSnapshot = nil
    UserDataManager.userCryptoList = holdings

    // 외부 네트워크 없이 지원 종료된 보유 종목을 실제 화면에 전달한다.
    let reactor = InvestReactor(mainUseCase: DelistingMarketFixtureUseCase())
    reactor.isStubEnabled = true
    // 거래지원 목록에 없는 보유 종목의 화면 상태다.
    var state = reactor.initialState
    state.cryptos = holdings
    state.supportedMarketPairIDs = [ExchangePairID(exchange: .upbit, rawMarketCode: "KRW-BTC")]
    reactor.stub.state.value = state
    // 실제 셀 버튼과 확인창의 연결을 확인한다.
    let controller = InvestmentViewController(reactor: reactor)
    // 알림과 테이블 터치 계층을 표시할 화면이다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }

    // 보유 내역 스냅샷이 실제 셀을 만들 때까지 기다린다.
    let cellReady = expectation(for: NSPredicate { _, _ in
      controller.transactionTableview.visibleCells.contains { $0 is InvestmentTableViewCell }
    }, evaluatedWith: nil)
    wait(for: [cellReady], timeout: 5)
    // 버튼 이벤트가 실제로 전달될 종료 종목 셀이다.
    let cell = try XCTUnwrap(controller.transactionTableview.visibleCells.first as? InvestmentTableViewCell)
    XCTAssertFalse(cell.unsupportedOverlayView.isHidden)
    cell.unsupportedSettlementButton.sendActions(for: .touchUpInside)

    // 확인 전에는 보유 자산과 잔고가 바뀌지 않아야 한다.
    let alert = try XCTUnwrap(controller.presentedViewController as? MobitAlertViewController)
    XCTAssertEqual(alert.alertType, .canCancel)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 5_000)
    XCTAssertEqual(UserDataManager.userCryptoList?.count, 1)
    alert.loadViewIfNeeded()
    // 실제 확인창의 대상과 반환액은 정산에 사용할 저장값과 같아야 한다.
    func label(in view: UIView, identifier: String) -> UILabel? {
      if view.accessibilityIdentifier == identifier { return view as? UILabel }
      return view.subviews.lazy.compactMap { label(in: $0, identifier: identifier) }.first
    }
    XCTAssertEqual(label(in: alert.view, identifier: "delisting.market")?.text, "시험코인 (ZZQATEST)")
    // 수량과 마켓 단위는 별도 라벨이지만 접근성에서는 함께 읽는다.
    let quantityLabel = try XCTUnwrap(label(in: alert.view, identifier: "delisting.quantity"))
    let quantityUnitLabel = try XCTUnwrap(label(in: alert.view, identifier: "delisting.quantity.unit"))
    let amountLabel = try XCTUnwrap(label(in: alert.view, identifier: "delisting.amount"))
    XCTAssertEqual(quantityLabel.text, "10")
    XCTAssertEqual(quantityUnitLabel.text, "ZZQATEST")
    XCTAssertEqual(quantityLabel.accessibilityLabel, "10 ZZQATEST")
    XCTAssertFalse(quantityUnitLabel.isAccessibilityElement)
    XCTAssertEqual(quantityLabel.font.pointSize, amountLabel.font.pointSize)
    XCTAssertLessThan(quantityUnitLabel.font.pointSize, quantityLabel.font.pointSize)
    XCTAssertEqual(label(in: alert.view, identifier: "delisting.amount")?.text, "340 \(FuturesText.text("currency_krw_unit"))")
    // 금액 숫자와 통화에 적용된 개별 글꼴 속성을 확인한다.
    let attributedAmount = try XCTUnwrap(amountLabel.attributedText)
    // 반환 금액의 첫 숫자에 적용된 글꼴이다.
    let amountNumberFont = try XCTUnwrap(attributedAmount.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
    // 수량에 요구된 크기의 세미볼드 시스템 글꼴이다.
    let expectedNumberFont = UIFont.systemFont(ofSize: quantityLabel.font.pointSize, weight: .semibold)
    // 기존 수량의 캡션 크기를 사용자 글자 크기 설정에 맞춰 확인한다.
    let originalNumberFont = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: alert.traitCollection)
    XCTAssertEqual(amountNumberFont, quantityLabel.font)
    XCTAssertEqual(quantityLabel.font.fontName, expectedNumberFont.fontName)
    XCTAssertEqual(quantityLabel.font.pointSize, originalNumberFont.pointSize, accuracy: 0.01)
    // 사용자가 전량 매도되는 동작을 분명히 구분할 수 있어야 한다.
    let message = try XCTUnwrap(alert.contentLabel.attributedText)
    let emphasis = FuturesText.text("spot_delisting_emphasis")
    let emphasisRange = (message.string as NSString).range(of: emphasis)
    XCTAssertNotEqual(emphasisRange.location, NSNotFound)
    if emphasisRange.location != NSNotFound {
      let font = try XCTUnwrap(message.attribute(.font, at: emphasisRange.location, effectiveRange: nil) as? UIFont)
      XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold))
      // 테마가 바뀌어도 전량 매도 문구가 앱의 포인트 색상으로 강조되어야 한다.
      let color = try XCTUnwrap(message.attribute(.foregroundColor, at: emphasisRange.location, effectiveRange: nil) as? UIColor)
      for style in [UIUserInterfaceStyle.light, .dark] {
        // 동일한 강조 색상이 밝은 화면과 어두운 화면에 맞게 해석되는지 확인한다.
        let traits = UITraitCollection(userInterfaceStyle: style)
        XCTAssertEqual(color.resolvedColor(with: traits), UIColor.mobitColors(.accentPrimary).resolvedColor(with: traits))
      }
    }
    alert.confirmButton.sendActions(for: .touchUpInside)
    alert.confirmButton.sendActions(for: .touchUpInside)

    // 정산은 확인창이 닫힌 뒤 완료되므로 실제 저장 결과를 기다린다.
    let settled = expectation(for: NSPredicate { _, _ in
      UserDataManager.userTransactionList?.last?.recordType == .delistingSettlement
    }, evaluatedWith: nil)
    wait(for: [settled], timeout: 5)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 5_340)
    XCTAssertTrue(UserDataManager.userCryptoList?.isEmpty == true)
    XCTAssertEqual(UserDataManager.userTransactionList?.count, 2)
    XCTAssertEqual(UserDataManager.userPNLHistory?.count, 1)
    XCTAssertEqual(UserDataManager.userPNLHistory?.last?.realizedProfitLossKRW, -4_660)
  }

  @MainActor
  func testDelistingConfirmationKeepsAssetsWhenMarketCheckFailsOrSupportReturns() throws {
    // 조회 실패나 재상장에도 정산하지 않아야 하는 보유 자산이다.
    _ = try TradeOrderService.executeBid(
      marketName: "ZZQATEST/KRW",
      cryptoName: "시험코인",
      currentPrice: 500,
      quantity: 10
    ).get()
    // 확인 전의 잔고와 원장 원본이다.
    let balanceBefore = UserDataManager.userInformation?.userAvailableBalance
    let holdingsBefore = UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList)
    let transactionsBefore = UserDefaults.standard.data(forKey: UserDataManager.Keys.userTransactionList)
    let pnlBefore = UserDefaults.standard.data(forKey: UserDataManager.Keys.userPNLHistory)

    for isSupported in [false, true] {
      // 빈 응답과 해당 종목의 거래지원 재개를 각각 주입한다.
      let useCase = DelistingMarketFixtureUseCase()
      useCase.marketResponse = .just(isSupported ? [DelistingMarketFixtureUseCase.crypto("KRW-ZZQATEST")] : [])
      let reactor = InvestReactor(mainUseCase: useCase)
      reactor.isStubEnabled = true
      var state = reactor.initialState
      state.cryptos = try XCTUnwrap(UserDataManager.userCryptoList)
      state.supportedMarketPairIDs = [ExchangePairID(exchange: .upbit, rawMarketCode: "KRW-BTC")]
      reactor.stub.state.value = state
      let controller = InvestmentViewController(reactor: reactor)
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
      window.rootViewController = controller
      window.makeKeyAndVisible()
      defer { window.isHidden = true; window.rootViewController = nil }

      let cellReady = expectation(for: NSPredicate { _, _ in
        controller.transactionTableview.visibleCells.contains { $0 is InvestmentTableViewCell }
      }, evaluatedWith: nil)
      wait(for: [cellReady], timeout: 5)
      let cell = try XCTUnwrap(controller.transactionTableview.visibleCells.first as? InvestmentTableViewCell)
      cell.unsupportedSettlementButton.sendActions(for: .touchUpInside)
      let confirmation = try XCTUnwrap(controller.presentedViewController as? MobitAlertViewController)
      confirmation.loadViewIfNeeded()
      confirmation.confirmButton.sendActions(for: .touchUpInside)

      // 거래지원 확인 결과가 표시될 때까지 정산 원본은 그대로여야 한다.
      let expectedMessage = FuturesText.text(isSupported ? "spot_delisting_support_changed" : "spot_delisting_market_unavailable")
      let errorShown = expectation(for: NSPredicate { _, _ in
        (controller.presentedViewController as? MobitAlertViewController)?.content == expectedMessage
      }, evaluatedWith: nil)
      wait(for: [errorShown], timeout: 5)
      XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, balanceBefore)
      XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList), holdingsBefore)
      XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userTransactionList), transactionsBefore)
      XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userPNLHistory), pnlBefore)
    }
  }

  func testZeroValueDelistingSettlementStillRemovesHolding() throws {
    _ = try TradeOrderService.executeBid(
      marketName: "GEOD/KRW",
      cryptoName: "지오드넷",
      currentPrice: 500,
      quantity: 1
    ).get()

    var holdings = try XCTUnwrap(UserDataManager.userCryptoList)
    holdings[0].dynamicData.evaluationProfitLoss = -500
    holdings[0].dynamicData.evaluationPrice = 0
    holdings[0].dynamicData.settlementPriceSnapshot = nil
    UserDataManager.userCryptoList = holdings

    let result = TradeOrderService.executeDelistingSettlement(marketName: "GEOD/KRW")

    XCTAssertNoThrow(try result.get())
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 9_500)
    XCTAssertTrue(UserDataManager.userCryptoList?.isEmpty == true)
    XCTAssertEqual(UserDataManager.userPNLHistory?.last?.realizedProfitLossKRW, -500)
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
      XCTAssertEqual(holding.staticData.buyAmount, 3_500)
      XCTAssertEqual(holding.staticData.averageBuyPrice, 1_750)
      XCTAssertEqual(holding.staticData.costBasisKRW, 3_500)
      XCTAssertEqual(holding.staticData.buyAmount,
                     holding.staticData.averageBuyPrice * holding.staticData.holdingQuantity,
                     accuracy: 0.000001)
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
      if case .failure(.invalidStoredData) = result {} else { XCTFail("손상된 데이터에서 주문이 거절되지 않음") }
      XCTAssertEqual(UserDataManager.userInformation(for: exchange)?.userAvailableBalance, 10_000)
      XCTAssertEqual(UserDataManager.userTransactionList?.count, 0)
      XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList), corruptedData)
    }
  }

  func testBTCFixedCostAndRealizedKRWSurvivePersistenceForBothExchanges() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      UserDataManager.resetInvestmentData(availableBalance: 10_000_000)
      _ = try TradeOrderService.executeBid(marketName: "BTC/KRW", cryptoName: nil,
        currentPrice: 100_000_000, quantity: 0.1, exchange: exchange).get()
      _ = try TradeOrderService.executeBid(marketName: "ETH/BTC", cryptoName: nil,
        currentPrice: 0.05, quantity: 1, exchange: exchange, btcKRWPrice: 100_000_000).get()
      let eth = try XCTUnwrap(UserDataManager.userCryptoList?.first { $0.staticData.marketName == "ETH/BTC" })
      let decoded = try JSONDecoder().decode(CryptoTransactionDataModel.self, from: JSONEncoder().encode(eth))
      XCTAssertEqual(decoded.staticData.costBasisKRW, 5_000_000)
      XCTAssertEqual(PortfolioCalculator.valuation(of: decoded, btcKRWPrice: 120_000_000).profitLossKRW, 1_000_000)
      let buy = try XCTUnwrap(UserDataManager.userTransactionList?.last)
      XCTAssertEqual(buy.settlementRateKRW, 100_000_000)
      XCTAssertEqual(buy.executedAmountKRW, 5_000_000)
      _ = try TradeOrderService.executeAsk(marketName: "ETH/BTC", currentPrice: 0.06,
        quantity: 1, exchange: exchange, btcKRWPrice: 120_000_000).get()
      let btc = try XCTUnwrap(UserDataManager.userCryptoList?.first)
      XCTAssertEqual(btc.staticData.holdingQuantity, 0.11, accuracy: 1e-12)
      XCTAssertEqual(btc.staticData.costBasisKRW, 12_200_000)
      XCTAssertEqual(UserDataManager.userPNLHistory?.last?.realizedProfitLossKRW, 2_200_000)
      XCTAssertEqual(UserDataManager.userInformation(for: exchange)?.userAvailableBalance, 0)
    }
  }

  func testBTCExchangeGainAndSatoshiRemainderArePreserved() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      UserDataManager.resetInvestmentData(availableBalance: 8_000_000)
      _ = try TradeOrderService.executeBid(marketName: "BTC/KRW", cryptoName: nil,
        currentPrice: 80_000_000, quantity: 0.1, exchange: exchange).get()
      _ = try TradeOrderService.executeBid(marketName: "ETH/BTC", cryptoName: nil,
        currentPrice: 0.05, quantity: 1, exchange: exchange, btcKRWPrice: 100_000_000).get()
      XCTAssertEqual(UserDataManager.userTransactionList?.last?.settlementProfitLossKRW, 1_000_000)
      _ = try TradeOrderService.executeBid(marketName: "ETH/BTC", cryptoName: nil,
        currentPrice: 0.04999999, quantity: 1, exchange: exchange, btcKRWPrice: 100_000_000).get()
      let btc = try XCTUnwrap(UserDataManager.userCryptoList?.first { $0.staticData.marketName == "BTC/KRW" })
      XCTAssertEqual(btc.staticData.holdingQuantity, 0.00000001, accuracy: 1e-16)
      let validBTC = try XCTUnwrap(UserDataManager.userValidTransactionList?.first { $0.marketName == "BTC/KRW" })
      XCTAssertEqual(validBTC.totalHoldingQuantity, 0.00000001, accuracy: 1e-16)
      XCTAssertEqual(PortfolioCalculator.double(try XCTUnwrap(btc.staticData.costBasisKRW)), 0.8, accuracy: 1e-9)
    }
  }

  func testBTCPartialSaleAndRebuyUseRemainingHistoricalCost() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      UserDataManager.resetInvestmentData(availableBalance: 20_000_000)
      _ = try TradeOrderService.executeBid(marketName: "BTC/KRW", cryptoName: nil,
        currentPrice: 100_000_000, quantity: 0.2, exchange: exchange).get()
      _ = try TradeOrderService.executeBid(marketName: "ETH/BTC", cryptoName: nil,
        currentPrice: 0.05, quantity: 2, exchange: exchange, btcKRWPrice: 100_000_000).get()
      _ = try TradeOrderService.executeAsk(marketName: "ETH/BTC", currentPrice: 0.06,
        quantity: 1, exchange: exchange, btcKRWPrice: 120_000_000).get()
      _ = try TradeOrderService.executeBid(marketName: "ETH/BTC", cryptoName: nil,
        currentPrice: 0.04, quantity: 1, exchange: exchange, btcKRWPrice: 120_000_000).get()
      let eth = try XCTUnwrap(UserDataManager.userCryptoList?.first { $0.staticData.marketName == "ETH/BTC" })
      XCTAssertEqual(eth.staticData.holdingQuantity, 2)
      XCTAssertEqual(eth.staticData.costBasisKRW, 9_800_000)
      XCTAssertEqual(eth.staticData.averageBuyPrice, 0.045, accuracy: 1e-12)
    }
  }

  func testBTCInvalidRatesAndUnknownCostDoNotMutateHoldings() throws {
    try seedBTCHolding(quantity: 0.00005, btcKRWPrice: 100_000_000)
    let before = UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList)
    for rate in [Double.nan, .infinity, 0, -1] {
      let result = TradeOrderService.executeBid(marketName: "ETH/BTC", cryptoName: nil,
        currentPrice: 0.05, quantity: 1, btcKRWPrice: rate)
      if case .failure(.missingSettlementRate) = result {} else { XCTFail("Invalid rate accepted") }
      XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList), before)
    }
    UserDataManager.userCryptoList?.append(CryptoTransactionDataModel(
      staticData: .init(marketName: "ETH/BTC", cryptoName: nil, holdingQuantity: 1,
                        averageBuyPrice: 0.05, buyAmount: 0.05),
      dynamicData: .init(marketName: "ETH/BTC", profitRate: 0, evaluationProfitLoss: 0, evaluationPrice: 0.05)
    ))
    let legacy = UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList)
    let result = TradeOrderService.executeAsk(marketName: "ETH/BTC", currentPrice: 0.05,
      quantity: 1, btcKRWPrice: 100_000_000)
    if case .failure(.missingCostBasis) = result {} else { XCTFail("Unknown cost accepted") }
    XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList), legacy)
  }

  // MARK: - BTC 마켓

  func testSpotOrderPriceKeepsWholeSatoshisThroughBidAskAndHistory() throws {
    for invalid in [nil, 0, -1, 0.000000009, Double.nan, .infinity] as [Double?] {
      XCTAssertNil(PortfolioCalculator.spotOrderPrice(invalid))
    }
    XCTAssertEqual(PortfolioCalculator.spotOrderPrice(0.000000039), 0.00000003)
    XCTAssertEqual(PortfolioCalculator.spotOrderPrice(12.345678919), 12.34567891)
    // 3사토시는 Double 곱셈으로 내리면 2사토시가 되던 주문 단가다.
    let price = try XCTUnwrap(PortfolioCalculator.spotOrderPrice(0.00000003))
    XCTAssertEqual(price, 0.00000003)
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      XCTAssertTrue(UserDataManager.resetInvestmentData(availableBalance: 20_000_000))
      try seedBTCHolding(quantity: 0.1, btcKRWPrice: 100_000_000, exchange: exchange)
      // 수량 입력 시의 예상 금액과 실제 BTC 차감액을 비교한다.
      let preview = PortfolioCalculator.executedAmount(price: price, quantity: 10_000, currency: .btc)
      XCTAssertEqual(preview, 0.0003)
      // 해당 단가로 보유분과 마지막 정산 기준을 함께 저장한다.
      let bid = try TradeOrderService.executeBid(
        marketName: "ABC/BTC",
        cryptoName: nil,
        currentPrice: price,
        quantity: 10_000,
        exchange: exchange,
        btcKRWPrice: 100_000_000
      ).get()
      XCTAssertEqual(bid.executedAmount, preview)
      XCTAssertEqual(bid.availableBalance, 0.0997, accuracy: 1e-15)
      XCTAssertEqual(UserDataManager.userTransactionList?.last?.executedPrice, price)
      // 나중에 거래지원이 종료되어도 동일한 단가와 반환 금액을 사용해야 한다.
      let holding = try XCTUnwrap(UserDataManager.userCryptoList?.first { $0.staticData.marketName == "ABC/BTC" })
      XCTAssertEqual(holding.dynamicData.settlementPriceSnapshot?.price, price)
      XCTAssertEqual(try TradeOrderService.delistingSettlementQuote(for: holding).get().executedAmount, preview)
      // 전량 매도했을 때 같은 BTC 금액이 되돌아오는지 확인한다.
      let ask = try TradeOrderService.executeAsk(
        marketName: "ABC/BTC",
        currentPrice: price,
        quantity: 10_000,
        exchange: exchange,
        btcKRWPrice: 100_000_000
      ).get()
      XCTAssertEqual(ask.executedAmount, preview)
      XCTAssertEqual(ask.availableBalance, 0.1, accuracy: 1e-15)
      XCTAssertEqual(UserDataManager.userTransactionList?.last?.executedPrice, price)
    }
  }

  /// 원화 마켓에서 BTC를 확보한 뒤 BTC 마켓 주문에 쓸 수 있는 상태를 만든다.
  @discardableResult
  private func seedBTCHolding(
    quantity: Double,
    btcKRWPrice: Double,
    exchange: Exchange = .upbit
  ) throws -> Double {
    let result = TradeOrderService.executeBid(
      marketName: "BTC/KRW",
      cryptoName: "비트코인",
      currentPrice: btcKRWPrice,
      quantity: quantity,
      exchange: exchange
    )
    _ = try result.get()
    return quantity
  }

  func testBTCMarketBidSpendsBTCHoldingAndKeepsKRWBalance() throws {
    UserDataManager.resetInvestmentData(availableBalance: 10_000_000)
    try seedBTCHolding(quantity: 0.1, btcKRWPrice: 100_000_000)

    let krwBalanceAfterSeed = UserDataManager.userInformation?.userAvailableBalance

    let result = TradeOrderService.executeBid(
      marketName: "ETH/BTC",
      cryptoName: "이더리움",
      currentPrice: 0.0315,
      quantity: 1,
      btcKRWPrice: 100_000_000
    )

    let execution = try result.get()
    XCTAssertEqual(execution.settlementCurrency, .btc)
    XCTAssertEqual(execution.executedAmount, 0.0315, accuracy: 1e-9)
    // BTC 마켓 결제는 원화 잔고를 건드리지 않는다.
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, krwBalanceAfterSeed)

    let btcPairID = ExchangeMarketCodeConverter.pairID(fromDisplayMarket: "BTC/KRW", exchange: .upbit)
    let btcHolding = try XCTUnwrap(
      UserDataManager.userCryptoList?.first(where: { $0.staticData.exchangePairID == btcPairID })
    )
    XCTAssertEqual(btcHolding.staticData.holdingQuantity, 0.0685, accuracy: 1e-9)
    // BTC를 결제에 써도 원화 평단은 유지된다.
    XCTAssertEqual(btcHolding.staticData.averageBuyPrice, 100_000_000, accuracy: 1e-6)

    let ethPairID = ExchangeMarketCodeConverter.pairID(fromDisplayMarket: "ETH/BTC", exchange: .upbit)
    let ethHolding = try XCTUnwrap(
      UserDataManager.userCryptoList?.first(where: { $0.staticData.exchangePairID == ethPairID })
    )
    XCTAssertEqual(ethHolding.staticData.holdingQuantity, 1)
    // BTC 마켓 보유분의 평단과 매수금액은 BTC 단위로 기록한다.
    XCTAssertEqual(ethHolding.staticData.averageBuyPrice, 0.0315, accuracy: 1e-9)
    XCTAssertEqual(ethHolding.staticData.buyAmount, 0.0315, accuracy: 1e-9)
  }

  func testBTCMarketBidRejectsWhenBTCHoldingIsInsufficient() {
    UserDataManager.resetInvestmentData(availableBalance: 10_000_000)

    let result = TradeOrderService.executeBid(
      marketName: "ETH/BTC",
      cryptoName: "이더리움",
      currentPrice: 0.0315,
      quantity: 1,
      btcKRWPrice: 100_000_000
    )

    // 원화가 충분해도 BTC가 없으면 BTC 마켓 주문은 거절되어야 한다.
    XCTAssertEqual(result.failure, .insufficientBalance(currency: .btc))
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 10_000_000)
    XCTAssertEqual(UserDataManager.userCryptoList?.count, 0)
  }

  func testBTCMarketBidRejectsWithoutSettlementRate() throws {
    UserDataManager.resetInvestmentData(availableBalance: 10_000_000)
    try seedBTCHolding(quantity: 0.1, btcKRWPrice: 100_000_000)

    let result = TradeOrderService.executeBid(
      marketName: "ETH/BTC",
      cryptoName: "이더리움",
      currentPrice: 0.0315,
      quantity: 1
    )

    XCTAssertEqual(result.failure, .missingSettlementRate)
    XCTAssertEqual(UserDataManager.userTransactionList?.count, 1)
  }

  func testBTCMarketBidBelowMinimumUsesBTCThreshold() throws {
    UserDataManager.resetInvestmentData(availableBalance: 10_000_000)
    try seedBTCHolding(quantity: 0.1, btcKRWPrice: 100_000_000)

    let result = TradeOrderService.executeBid(
      marketName: "ETH/BTC",
      cryptoName: "이더리움",
      currentPrice: 0.0000001,
      quantity: 1,
      btcKRWPrice: 100_000_000
    )

    XCTAssertEqual(
      result.failure,
      .belowMinimumOrderAmount(minimum: SettlementCurrency.btc.minimumOrderAmount, currency: .btc)
    )
  }

  func testBTCMarketAskCreditsBTCWithWeightedAverageCost() throws {
    UserDataManager.resetInvestmentData(availableBalance: 10_000_000)
    try seedBTCHolding(quantity: 0.1, btcKRWPrice: 100_000_000)

    _ = try TradeOrderService.executeBid(
      marketName: "ETH/BTC",
      cryptoName: "이더리움",
      currentPrice: 0.0315,
      quantity: 1,
      btcKRWPrice: 100_000_000
    ).get()

    let krwBalanceBeforeAsk = UserDataManager.userInformation?.userAvailableBalance

    // BTC/KRW 시세가 오른 시점에 매도하면 받은 BTC의 원화 원가도 그 시세로 반영되어야 한다.
    let result = TradeOrderService.executeAsk(
      marketName: "ETH/BTC",
      currentPrice: 0.035,
      quantity: 1,
      btcKRWPrice: 120_000_000
    )

    let execution = try result.get()
    XCTAssertEqual(execution.settlementCurrency, .btc)
    XCTAssertEqual(execution.executedAmount, 0.035, accuracy: 1e-9)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, krwBalanceBeforeAsk)

    let btcPairID = ExchangeMarketCodeConverter.pairID(fromDisplayMarket: "BTC/KRW", exchange: .upbit)
    let btcHolding = try XCTUnwrap(
      UserDataManager.userCryptoList?.first(where: { $0.staticData.exchangePairID == btcPairID })
    )
    XCTAssertEqual(btcHolding.staticData.holdingQuantity, 0.1035, accuracy: 1e-9)

    let expectedAveragePrice = ((0.0685 * 100_000_000) + (0.035 * 120_000_000)) / 0.1035
    XCTAssertEqual(btcHolding.staticData.averageBuyPrice, expectedAveragePrice, accuracy: 1e-2)

    // ETH 실현손익은 BTC 단위로 남는다.
    let pnl = try XCTUnwrap(UserDataManager.userPNLHistory?.last)
    XCTAssertEqual(pnl.pnl, 0.0035, accuracy: 1e-9)

    let ethPairID = ExchangeMarketCodeConverter.pairID(fromDisplayMarket: "ETH/BTC", exchange: .upbit)
    XCTAssertNil(
      UserDataManager.userCryptoList?.first(where: { $0.staticData.exchangePairID == ethPairID })
    )
  }

  func testBTCSettlementPreservesDecimalQuantityAndCostOnRebuy() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      XCTAssertTrue(UserDataManager.resetInvestmentData(availableBalance: 50_000_000))
      try seedBTCHolding(quantity: 0.2, btcKRWPrice: 100_000_000, exchange: exchange)

      _ = try TradeOrderService.executeBid(
        marketName: "ETH/BTC",
        cryptoName: nil,
        currentPrice: 0.1,
        quantity: 1,
        exchange: exchange,
        btcKRWPrice: 100_000_000
      ).get()
      // BTC 결제 후 남은 수량과 원가는 동일한 비율이어야 한다.
      var holding = try XCTUnwrap(UserDataManager.userCryptoList?.first { $0.staticData.marketName == "BTC/KRW" })
      XCTAssertEqual(holding.staticData.holdingQuantity, 0.1)
      XCTAssertEqual(holding.staticData.buyAmount, 10_000_000)
      XCTAssertEqual(holding.staticData.costBasisKRW, 10_000_000)

      _ = try TradeOrderService.executeAsk(
        marketName: "ETH/BTC",
        currentPrice: 0.2,
        quantity: 1,
        exchange: exchange,
        btcKRWPrice: 100_000_000
      ).get()
      holding = try XCTUnwrap(UserDataManager.userCryptoList?.first { $0.staticData.marketName == "BTC/KRW" })
      XCTAssertEqual(holding.staticData.holdingQuantity, 0.3)
      XCTAssertEqual(holding.staticData.averageBuyPrice, 100_000_000)
      XCTAssertEqual(holding.staticData.buyAmount, 30_000_000)
      XCTAssertEqual(holding.staticData.costBasisKRW, 30_000_000)
      XCTAssertEqual(UserDataManager.userInformation(for: exchange)?.userAvailableBalance, 30_000_000)
    }
  }

  func testKRWMarketOrderStillSettlesInKRW() throws {
    UserDataManager.resetInvestmentData(availableBalance: 10_000)

    let execution = try TradeOrderService.executeBid(
      marketName: "ETH/KRW",
      cryptoName: "이더리움",
      currentPrice: 1_000,
      quantity: 2
    ).get()

    XCTAssertEqual(execution.settlementCurrency, .krw)
    XCTAssertEqual(execution.executedAmount, 2_000)
    XCTAssertEqual(execution.availableBalance, 8_000)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 8_000)
  }

  private func clearUserDefaults() {
    [
      UserDataManager.Keys.pendingInvestmentState,
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
