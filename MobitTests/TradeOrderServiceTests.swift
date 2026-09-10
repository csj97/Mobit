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
