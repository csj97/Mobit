//
//  UserDataManagerTests.swift
//  MobitTests
//
//  Created by Codex on 6/29/26.
//

import XCTest
@testable import Mobit

final class UserDataManagerTests: XCTestCase {
  override func setUp() {
    super.setUp()
    clearUserDefaults()
    ExchangeSelectionStore.currentExchange = .upbit
  }

  override func tearDown() {
    clearUserDefaults()
    ExchangeSelectionStore.currentExchange = .upbit
    super.tearDown()
  }

  func testSeedInitialUserInformationOnlyRunsOnFirstLaunch() {
    let didSeed = UserDataManager.seedInitialUserInformationIfNeeded(
      initialBalance: 1_000_000
    )
    let didSeedAgain = UserDataManager.seedInitialUserInformationIfNeeded(
      initialBalance: 2_000_000
    )

    XCTAssertTrue(didSeed)
    XCTAssertFalse(didSeedAgain)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 1_000_000)
  }

  func testSpotHoldingIsNotRemovedAtMinusOneHundredPercentOnEitherExchange() throws {
    UserDataManager.resetInvestmentData(availableBalance: 500)
    UserDataManager.userCryptoList = [
      makeTransaction(market: "BTC/KRW", exchange: .upbit),
      makeTransaction(market: "BTC/KRW", exchange: .bithumb)
    ]
    // 손익률 갱신으로 거래 이력이 생기거나 수량·현금이 바뀌면 안 된다.
    let before = try XCTUnwrap(UserDataManager.userCryptoList)
    for holding in before {
      MarketDataServiceUtil.shared.updateHoldingData(data: holding.staticData, currentPrice: 0)
    }
    // 평가금액 0원이어도 보유 자산과 매수 원가는 그대로 남는다.
    let after = try XCTUnwrap(UserDataManager.userCryptoList)
    XCTAssertEqual(after.map { $0.staticData.exchangePairID }, before.map { $0.staticData.exchangePairID })
    XCTAssertEqual(after.map { $0.staticData.holdingQuantity }, before.map { $0.staticData.holdingQuantity })
    XCTAssertEqual(after.map { $0.staticData.averageBuyPrice }, before.map { $0.staticData.averageBuyPrice })
    XCTAssertEqual(after.map { $0.staticData.buyAmount }, before.map { $0.staticData.buyAmount })
    XCTAssertEqual(after.map { $0.staticData.costBasisKRW }, before.map { $0.staticData.costBasisKRW })
    XCTAssertEqual(after.map { $0.dynamicData.profitRate }, [-100, -100])
    XCTAssertEqual(after.map { $0.dynamicData.evaluationPrice }, [0, 0])
    XCTAssertEqual(after.map { $0.dynamicData.evaluationProfitLoss }, [-100, -100])
    XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 500)
    XCTAssertEqual(UserDataManager.userInformation(for: .bithumb)?.userAvailableBalance, 0)
    XCTAssertEqual(UserDataManager.userTransactionList, [])
    XCTAssertEqual(UserDataManager.userPNLHistory?.count, 0)
  }

  func testInitialGrantAlwaysBelongsToUpbitEvenWhenBithumbSelected() {
    ExchangeSelectionStore.currentExchange = .bithumb
    XCTAssertTrue(UserDataManager.seedInitialUserInformationIfNeeded())
    XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 1_000_000)
    XCTAssertEqual(UserDataManager.userInformation(for: .bithumb)?.userAvailableBalance, 0)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 0)
  }

  func testExistingBalanceIsPreservedWhenFirstLaunchFlagIsMissing() {
    UserDataManager.updateUserInformation(MobitUserInformation(userAvailableBalance: 123), for: .bithumb)
    XCTAssertFalse(UserDataManager.seedInitialUserInformationIfNeeded())
    XCTAssertFalse(UserDataManager.isFirstLaunch)
    XCTAssertEqual(UserDataManager.userInformation(for: .bithumb)?.userAvailableBalance, 123)
    XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 0)
  }

  func testCorruptBalanceDoesNotFallBackToLegacyOrAllowMutation() throws {
    let defaults = UserDefaults.standard
    defaults.set(try JSONEncoder().encode(MobitUserInformation(userAvailableBalance: 500)), forKey: UserDataManager.Keys.userInformation)
    let corrupt = Data("broken".utf8)
    defaults.set(corrupt, forKey: UserDataManager.Keys.userInformationByExchange)
    XCTAssertNil(UserDataManager.userInformation)
    XCTAssertFalse(UserDataManager.seedInitialUserInformationIfNeeded())
    XCTAssertThrowsError(try UserDataManager.performAtomicInvestmentUpdate {
      UserDataManager.updateUserInformation(MobitUserInformation(userAvailableBalance: 1000), for: .upbit)
    })
    XCTAssertEqual(defaults.data(forKey: UserDataManager.Keys.userInformationByExchange), corrupt)
    XCTAssertTrue(UserDataManager.isFirstLaunch)
  }

  func testInvalidInitialBalanceDoesNotConsumeGrant() {
    for value in [Double.nan, Double.infinity, -1, 0] {
      XCTAssertFalse(UserDataManager.seedInitialUserInformationIfNeeded(initialBalance: value))
      XCTAssertTrue(UserDataManager.isFirstLaunch)
    }
    XCTAssertTrue(UserDataManager.seedInitialUserInformationIfNeeded())
  }

  func testConcurrentInitialGrantOnlySeedsOnce() {
    DispatchQueue.concurrentPerform(iterations: 30) { _ in
      UserDataManager.seedInitialUserInformationIfNeeded()
    }
    XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 1_000_000)
    XCTAssertFalse(UserDataManager.seedInitialUserInformationIfNeeded())
  }

  func testAtomicBalanceMutationKeepsConcurrentIncrementsAcrossExchanges() {
    UserDataManager.resetInvestmentData()
    DispatchQueue.concurrentPerform(iterations: 100) { index in
      do {
        try UserDataManager.updateUserInformation(for: index.isMultiple(of: 2) ? .upbit : .bithumb) {
          $0.userAvailableBalance += 1
        }
      } catch {
        XCTFail("Concurrent balance mutation failed: \(error)")
      }
    }
    XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 50)
    XCTAssertEqual(UserDataManager.userInformation(for: .bithumb)?.userAvailableBalance, 50)
  }

  func testInvalidBalanceMutationRollsBackWithoutLosingOriginal() {
    UserDataManager.resetInvestmentData(availableBalance: 100)
    for value in [Double.nan, Double.infinity, -1] {
      XCTAssertThrowsError(try UserDataManager.updateUserInformation(for: .upbit) { $0.userAvailableBalance = value })
      XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 100)
    }
  }

  func testWrongStoredValueTypePreventsSeedingAndAtomicUpdate() {
    UserDefaults.standard.set("wrong type", forKey: UserDataManager.Keys.userTransactionList)
    XCTAssertFalse(UserDataManager.seedInitialUserInformationIfNeeded())
    XCTAssertThrowsError(try UserDataManager.performAtomicInvestmentUpdate {})
    XCTAssertEqual(UserDefaults.standard.string(forKey: UserDataManager.Keys.userTransactionList), "wrong type")
  }

  func testInvalidPendingSnapshotBlocksReadsAndPreservesPreviousBytes() throws {
    UserDataManager.resetInvestmentData(availableBalance: 500)
    let balanceBytes = UserDefaults.standard.data(forKey: UserDataManager.Keys.userInformationByExchange)
    let pending = TestPendingInvestmentState(
      cryptoList: [], transactionList: [], validTransactionList: [], pnlHistory: [],
      informationByExchange: ["upbit": MobitUserInformation(userAvailableBalance: -1)]
    )
    let pendingBytes = try JSONEncoder().encode(pending)
    UserDefaults.standard.set(pendingBytes, forKey: UserDataManager.Keys.pendingInvestmentState)
    XCTAssertNil(UserDataManager.userInformation)
    XCTAssertNil(UserDataManager.userCryptoList)
    XCTAssertNil(UserDataManager.userTransactionList)
    XCTAssertThrowsError(try UserDataManager.performAtomicInvestmentUpdate {})
    XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userInformationByExchange), balanceBytes)
    XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.pendingInvestmentState), pendingBytes)
  }

  func testResetDoesNotRestoreInitialGrantEligibility() {
    XCTAssertTrue(UserDataManager.seedInitialUserInformationIfNeeded())
    UserDataManager.resetInvestmentData()
    XCTAssertFalse(UserDataManager.seedInitialUserInformationIfNeeded())
    XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 0)
  }

  func testMarketCellTintDefaultsToOffAndKeepsSavedPreference() {
    XCTAssertFalse(UserDataManager.marketCellTintEnabled)

    UserDataManager.marketCellTintEnabled = true

    XCTAssertTrue(UserDataManager.marketCellTintEnabled)
  }

  func testResetInvestmentDataClearsInvestmentState() {
    UserDataManager.userInformation = MobitUserInformation(userAvailableBalance: 100)
    UserDataManager.userCryptoList = [makeTransaction(market: "BTC/KRW")]
    UserDataManager.userTransactionList = [
      TransactionInfo(
        marketName: "BTC/KRW",
        orderType: .bid,
        executedDate: "01.01 09:00",
        executedPrice: 100,
        executedQuantity: 1,
        executedAmount: 100
      )
    ]
    UserDataManager.userValidTransactionList = [
      ValidTransactionInfo(
        marketName: "BTC/KRW",
        transaction: [.init(orderType: .bid, quantity: 1, buyPrice: 100)]
      )
    ]

    UserDataManager.resetInvestmentData()

    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 0)
    XCTAssertEqual(UserDataManager.userCryptoList, [])
    XCTAssertEqual(UserDataManager.userTransactionList, [])
    XCTAssertEqual(UserDataManager.userValidTransactionList, [])
    XCTAssertEqual(UserDataManager.userPNLHistory?.count, 0)
  }

  func testAtomicInvestmentUpdateRollsBackEveryListAndBalanceOnFailure() {
    UserDataManager.resetInvestmentData(availableBalance: 10_000)

    XCTAssertThrowsError(try UserDataManager.performAtomicInvestmentUpdate {
      UserDataManager.userCryptoList = [makeTransaction(market: "BTC/KRW")]
      UserDataManager.userTransactionList = [
        TransactionInfo(
          marketName: "BTC/KRW",
          orderType: .bid,
          executedDate: "01.01 09:00",
          executedPrice: 100,
          executedQuantity: 1,
          executedAmount: 100
        )
      ]
      UserDataManager.updateUserInformation(
        MobitUserInformation(userAvailableBalance: 9_900),
        for: .upbit
      )
      throw UserDataManager.InvestmentStateError.invalidStoredData
    })

    XCTAssertEqual(UserDataManager.userCryptoList, [])
    XCTAssertEqual(UserDataManager.userTransactionList, [])
    XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 10_000)
  }

  func testSelectedSpotResetPreservesOtherExchangeAndConsumedRewards() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      XCTAssertTrue(UserDataManager.resetInvestmentData())
      // 초기화 이후 다시 전달되는 광고 보상이 잔고를 복구하면 안 된다.
      let claim = try AdRewardClaim(account: .spot(for: exchange))
      try UserDataManager.applyAdvertisementReward(claim)
      // 선택 대상과 다른 현물 계좌의 모든 저장 데이터를 비교한다.
      let otherExchange: Exchange = exchange == .upbit ? .bithumb : .upbit
      try UserDataManager.applyAdvertisementReward(AdRewardClaim(account: .spot(for: otherExchange)))
      for fundedExchange in [exchange, otherExchange] {
        _ = try TradeOrderService.executeBid(
          marketName: "ETH/KRW",
          cryptoName: "이더리움",
          currentPrice: 100_000,
          quantity: 1,
          exchange: fundedExchange
        ).get()
        _ = try TradeOrderService.executeAsk(
          marketName: "ETH/KRW",
          currentPrice: 110_000,
          quantity: 0.5,
          exchange: fundedExchange
        ).get()
      }
      // 초기화는 화면에서 현재 선택한 거래소를 변경하지 않아야 한다.
      ExchangeSelectionStore.currentExchange = otherExchange
      // 선택하지 않은 계좌의 잔고와 거래·보유·실현손익 원본이다.
      let otherBalance = try UserDataManager.getAvailableBalance(for: otherExchange)
      // 반대 거래소의 보유 자산을 비교한다.
      let otherHoldings = UserDataManager.userCryptoList?.filter { $0.staticData.exchange == otherExchange }
      // 반대 거래소의 체결 이력을 비교한다.
      let otherTransactions = UserDataManager.userTransactionList?.filter { $0.exchange == otherExchange }
      // 반대 거래소의 유효 매수 이력을 비교한다.
      let otherValidTransactions = UserDataManager.userValidTransactionList?.filter { $0.exchange == otherExchange }
      // JSON 객체 키 순서 차이를 제외하고 실현손익 값을 비교한다.
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      // Equatable이 없는 실현손익은 인코딩된 값으로 비교한다.
      let otherPNL = try encoder.encode(UserDataManager.userPNLHistory?.filter { $0.exchange == otherExchange })

      try UserDataManager.resetInvestmentData(for: exchange)
      try UserDataManager.applyAdvertisementReward(claim)

      XCTAssertEqual(try UserDataManager.getAvailableBalance(for: exchange), 0)
      XCTAssertEqual(UserDataManager.userCryptoList?.filter { $0.staticData.exchange == exchange }, [])
      XCTAssertEqual(UserDataManager.userTransactionList?.filter { $0.exchange == exchange }, [])
      XCTAssertEqual(UserDataManager.userValidTransactionList?.filter { $0.exchange == exchange }, [])
      XCTAssertEqual(UserDataManager.userPNLHistory?.filter { $0.exchange == exchange }.count, 0)
      XCTAssertEqual(try UserDataManager.getAvailableBalance(for: otherExchange), otherBalance)
      // 읽을 때 재생성되는 화면용 UUID를 제외하고 저장되는 모든 값을 비교한다.
      XCTAssertEqual(try encoder.encode(UserDataManager.userCryptoList), try encoder.encode(otherHoldings))
      XCTAssertEqual(UserDataManager.userTransactionList, otherTransactions)
      XCTAssertEqual(UserDataManager.userValidTransactionList, otherValidTransactions)
      XCTAssertEqual(try encoder.encode(UserDataManager.userPNLHistory), otherPNL)
      XCTAssertEqual(ExchangeSelectionStore.currentExchange, otherExchange)
      XCTAssertFalse(UserDataManager.seedInitialUserInformationIfNeeded())
    }
  }

  func testSelectedSpotResetPreservesCorruptStorageInsteadOfClearingOtherAccounts() throws {
    XCTAssertTrue(UserDataManager.resetInvestmentData(availableBalance: 123))
    // 다른 계좌를 보존할 수 없는 저장 오류는 초기화를 중단해야 한다.
    let broken = Data("broken-transaction-list".utf8)
    UserDefaults.standard.set(broken, forKey: UserDataManager.Keys.userTransactionList)
    XCTAssertThrowsError(try UserDataManager.resetInvestmentData(for: .upbit))
    XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userTransactionList), broken)
    XCTAssertEqual(try UserDataManager.getAvailableBalance(for: .upbit), 123)
  }

  func testLegacyBTCSettlementRestoresCurrentDisplayedValueAndKeepsNormalHoldings() throws {
    UserDataManager.resetInvestmentData(availableBalance: 10_000)
    UserDataManager.updateUserInformation(
      MobitUserInformation(userAvailableBalance: 5_000),
      for: .bithumb
    )
    let legacyUpbit = makeTransaction(
      market: "ETH/BTC",
      exchange: .upbit,
      quantity: 2_500_000_000,
      buyAmount: 87_500,
      evaluationPrice: 100_000
    )
    let legacyBithumb = makeTransaction(
      market: "SOL/BTC",
      exchange: .bithumb,
      quantity: 1_000_000_000,
      buyAmount: 15_000,
      evaluationPrice: 20_000
    )
    let legacyKRW = makeTransaction(market: "BTC/KRW", buyAmount: 100)
    let normalBTC = makeTransaction(
      market: "XRP/BTC",
      quantity: 100,
      buyAmount: 0.00002,
      costBasisKRW: 2_000
    )
    UserDataManager.userCryptoList = [legacyUpbit, legacyBithumb, legacyKRW, normalBTC]
    UserDataManager.userTransactionList = [legacyUpbit, legacyBithumb].map {
      TransactionInfo(
        exchange: $0.staticData.exchange,
        marketName: $0.staticData.marketName,
        orderType: .bid,
        executedDate: "01.01 09:00",
        executedPrice: $0.staticData.averageBuyPrice,
        executedQuantity: $0.staticData.holdingQuantity,
        executedAmount: $0.staticData.buyAmount
      )
    }
    UserDataManager.userValidTransactionList = [legacyUpbit, legacyBithumb, legacyKRW, normalBTC].map {
      ValidTransactionInfo(
        exchange: $0.staticData.exchange,
        marketName: $0.staticData.marketName,
        transaction: [.init(orderType: .bid, quantity: $0.staticData.holdingQuantity, buyPrice: 1)]
      )
    }

    let result = try UserDataManager.settleLegacyBTCMarketHoldings()

    XCTAssertEqual(result.restoredKRWByExchange[.upbit], 100_000)
    XCTAssertEqual(result.restoredKRWByExchange[.bithumb], 20_000)
    XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 110_000)
    XCTAssertEqual(UserDataManager.userInformation(for: .bithumb)?.userAvailableBalance, 25_000)
    XCTAssertEqual(
      Set(UserDataManager.userCryptoList?.map { $0.staticData.exchangePairID } ?? []),
      Set([legacyKRW.staticData.exchangePairID, normalBTC.staticData.exchangePairID])
    )
    XCTAssertEqual(
      Set(UserDataManager.userValidTransactionList?.map(\.exchangePairID) ?? []),
      Set([legacyKRW.staticData.exchangePairID, normalBTC.staticData.exchangePairID])
    )
    let transactionList = UserDataManager.userTransactionList ?? []
    let settlementRecords = transactionList.filter { $0.recordType == .legacyBTCSettlement }
    XCTAssertEqual(settlementRecords.count, 2)
    XCTAssertEqual(settlementRecords.first { $0.exchange == .upbit }?.executedAmount, 100_000)
    XCTAssertEqual(settlementRecords.first { $0.exchange == .bithumb }?.executedAmount, 20_000)
    XCTAssertEqual(transactionList.filter { $0.recordType == .userOrder }.count, 2)
  }

  func testLegacyBTCSettlementRepairsNullTransactionAndPNLLists() throws {
    UserDataManager.resetInvestmentData(availableBalance: 10_000)
    let legacy = makeTransaction(
      market: "ETH/BTC",
      quantity: 2_500_000_000,
      buyAmount: 87_500,
      evaluationPrice: 100_000
    )
    UserDataManager.userCryptoList = [legacy]
    UserDataManager.userValidTransactionList = [
      ValidTransactionInfo(
        marketName: legacy.staticData.marketName,
        transaction: [
          .init(
            orderType: .bid,
            quantity: legacy.staticData.holdingQuantity,
            buyPrice: legacy.staticData.averageBuyPrice
          )
        ]
      )
    ]
    let storedNull = Data("null".utf8)
    UserDefaults.standard.set(
      storedNull,
      forKey: UserDataManager.Keys.userTransactionList
    )
    UserDefaults.standard.set(
      storedNull,
      forKey: UserDataManager.Keys.userPNLHistory
    )

    let result = try UserDataManager.settleLegacyBTCMarketHoldings()

    XCTAssertEqual(result.restoredKRWByExchange[.upbit], 100_000)
    XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 110_000)
    XCTAssertEqual(UserDataManager.userCryptoList, [])
    XCTAssertEqual(UserDataManager.userPNLHistory?.count, 0)
    XCTAssertEqual(UserDataManager.userTransactionList?.count, 1)
    XCTAssertEqual(UserDataManager.userTransactionList?.first?.recordType, .legacyBTCSettlement)
  }

  func testNilInvestmentListDoesNotPersistJSONNull() {
    UserDataManager.userTransactionList = nil
    UserDataManager.userValidTransactionList = nil
    UserDataManager.userPNLHistory = nil

    XCTAssertNil(UserDefaults.standard.data(forKey: UserDataManager.Keys.userTransactionList))
    XCTAssertNil(UserDefaults.standard.data(forKey: UserDataManager.Keys.userValidTransactionList))
    XCTAssertNil(UserDefaults.standard.data(forKey: UserDataManager.Keys.userPNLHistory))
    XCTAssertEqual(UserDataManager.userTransactionList, [])
    XCTAssertEqual(UserDataManager.userValidTransactionList, [])
    XCTAssertEqual(UserDataManager.userPNLHistory?.count, 0)
  }

  func testLegacyBTCSettlementRollsBackWhenDisplayedEvaluationIsInvalid() {
    UserDataManager.resetInvestmentData(availableBalance: 10_000)
    let legacy = makeTransaction(
      market: "ETH/BTC",
      quantity: 2_500_000_000,
      buyAmount: 87_500,
      evaluationPrice: -1
    )
    UserDataManager.userCryptoList = [legacy]

    XCTAssertThrowsError(
      try UserDataManager.settleLegacyBTCMarketHoldings()
    )
    XCTAssertEqual(UserDataManager.userCryptoList?.count, 1)
    XCTAssertEqual(
      UserDataManager.userCryptoList?.first?.staticData.exchangePairID,
      legacy.staticData.exchangePairID
    )
    XCTAssertEqual(
      UserDataManager.userCryptoList?.first?.staticData.holdingQuantity,
      legacy.staticData.holdingQuantity
    )
    XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 10_000)
  }

  func testPendingInvestmentSnapshotRecoversEveryStoredComponent() throws {
    let holding = makeTransaction(market: "BTC/KRW")
    let transaction = TransactionInfo(
      marketName: "BTC/KRW",
      orderType: .bid,
      executedDate: "01.01 09:00",
      executedPrice: 100,
      executedQuantity: 1,
      executedAmount: 100
    )
    let pending = TestPendingInvestmentState(
      cryptoList: [holding],
      transactionList: [transaction],
      validTransactionList: [
        ValidTransactionInfo(
          marketName: "BTC/KRW",
          transaction: [.init(orderType: .bid, quantity: 1, buyPrice: 100)]
        )
      ],
      pnlHistory: [],
      informationByExchange: [
        Exchange.upbit.rawValue: MobitUserInformation(userAvailableBalance: 9_900)
      ]
    )
    UserDefaults.standard.set(
      try JSONEncoder().encode(pending),
      forKey: UserDataManager.Keys.pendingInvestmentState
    )

    XCTAssertEqual(UserDataManager.userCryptoList?.first?.staticData.marketName, holding.staticData.marketName)
    XCTAssertEqual(UserDataManager.userCryptoList?.first?.staticData.holdingQuantity, 1)
    XCTAssertEqual(UserDataManager.userTransactionList, [transaction])
    XCTAssertEqual(UserDataManager.userValidTransactionList?.count, 1)
    XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 9_900)
    XCTAssertNil(UserDefaults.standard.data(forKey: UserDataManager.Keys.pendingInvestmentState))
  }

  func testLegacyCryptoMigrationPreservesValues() {
    let legacy = LegacyModel(
      staticData: LegacyStatic(
        marketName: "BTC/KRW",
        cryptoName: "비트코인",
        holdingQuantity: 2,
        averageBuyPrice: 100,
        buyAmount: 200
      ),
      dynamicData: LegacyDynamic(
        marketName: "BTC/KRW",
        profitRate: 10,
        evaluationProfitLoss: 20,
        evaluationPrice: 220
      )
    )

    let migrated = UserDataMigration.migrateUserCryptoList(from: [legacy])

    XCTAssertEqual(migrated.count, 1)
    XCTAssertEqual(migrated[0].staticData.marketName, "BTC/KRW")
    XCTAssertEqual(migrated[0].staticData.exchange, Exchange.upbit)
    XCTAssertEqual(migrated[0].staticData.cryptoName, "비트코인")
    XCTAssertEqual(migrated[0].staticData.holdingQuantity, 2)
    XCTAssertEqual(migrated[0].staticData.averageBuyPrice, 100)
    XCTAssertEqual(migrated[0].staticData.buyAmount, 200)
    XCTAssertEqual(migrated[0].dynamicData.exchange, Exchange.upbit)
    XCTAssertEqual(migrated[0].dynamicData.profitRate, 10)
    XCTAssertEqual(migrated[0].dynamicData.evaluationProfitLoss, 20)
    XCTAssertEqual(migrated[0].dynamicData.evaluationPrice, 220)
    XCTAssertNil(migrated[0].dynamicData.settlementPriceSnapshot)
  }

  func testLegacyFavoriteMigrationPreservesCountAndMapsToUpbitPairID() {
    let legacyFavorites = ["BTC/KRW", "ETH/KRW"]

    let migrated = UserDataMigration.migrateFavoritePairs(from: legacyFavorites)

    XCTAssertEqual(migrated.count, 2)
    XCTAssertEqual(migrated[0].pairID.rawValue, "upbit:KRW-BTC")
    XCTAssertEqual(migrated[1].pairID.rawValue, "upbit:KRW-ETH")
    XCTAssertEqual(migrated.map { $0.displayMarket }, legacyFavorites)
  }

  func testUserFavoritePairsMigratesLegacyStringArrayOnRead() {
    UserDefaults.standard.set(
      ["BTC/KRW", "ETH/KRW"],
      forKey: UserDataManager.Keys.userFavoriteList
    )

    let favorites = UserDataManager.userFavoritePairs

    XCTAssertEqual(favorites.count, 2)
    XCTAssertEqual(favorites[0].exchange, .upbit)
    XCTAssertEqual(favorites[0].pairID.rawValue, "upbit:KRW-BTC")
    XCTAssertEqual(UserDataManager.userFavoriteList, ["BTC/KRW", "ETH/KRW"])
  }

  func testTransactionDataDefaultsToUpbitWhenExchangeIsMissing() throws {
    let json = """
    {
      "staticData": {
        "marketName": "BTC/KRW",
        "cryptoName": "비트코인",
        "holdingQuantity": 1.5,
        "averageBuyPrice": 100.0,
        "buyAmount": 150.0
      },
      "dynamicData": {
        "marketName": "BTC/KRW",
        "profitRate": 10.0,
        "evaluationProfitLoss": 15.0,
        "evaluationPrice": 165.0
      }
    }
    """

    let decoded = try JSONDecoder().decode(
      CryptoTransactionDataModel.self,
      from: Data(json.utf8)
    )

    XCTAssertEqual(decoded.staticData.exchange, .upbit)
    XCTAssertEqual(decoded.dynamicData.exchange, .upbit)
    XCTAssertEqual(decoded.staticData.exchangePairID.rawValue, "upbit:KRW-BTC")
    XCTAssertEqual(decoded.dynamicData.evaluationProfitLoss, 15)
    XCTAssertEqual(decoded.dynamicData.evaluationPrice, 165)
    XCTAssertNil(decoded.dynamicData.settlementPriceSnapshot)
  }

  func testSettlementPriceSnapshotSurvivesEncodingAndStoredRead() throws {
    XCTAssertTrue(UserDataManager.resetInvestmentData())
    // 업비트에 저장할 정산 기준 보유분이다.
    var upbitHolding = makeTransaction(market: "BTC/KRW", exchange: .upbit, quantity: 1.5, buyAmount: 150, evaluationPrice: 165)
    // 같은 종목의 빗썸 정산 기준 보유분이다.
    var bithumbHolding = makeTransaction(market: "BTC/KRW", exchange: .bithumb, quantity: 1.5, buyAmount: 150, evaluationPrice: 180)
    upbitHolding.dynamicData.evaluationProfitLoss = 15
    bithumbHolding.dynamicData.evaluationProfitLoss = 30
    upbitHolding.updateSettlementPriceSnapshot(currentPrice: 110)
    bithumbHolding.updateSettlementPriceSnapshot(currentPrice: 120)

    // 두 보유분을 저장 형식으로 변환한다.
    let encoded = try JSONEncoder().encode([upbitHolding, bithumbHolding])
    // 인코딩된 데이터에서 보유분을 복원한다.
    let decoded = try JSONDecoder().decode([CryptoTransactionDataModel].self, from: encoded)
    // 업비트에 복원된 정산 기준이다.
    let upbitSnapshot = try XCTUnwrap(decoded[0].dynamicData.settlementPriceSnapshot)
    // 빗썸에 복원된 정산 기준이다.
    let bithumbSnapshot = try XCTUnwrap(decoded[1].dynamicData.settlementPriceSnapshot)
    XCTAssertEqual(upbitSnapshot.price, 110)
    XCTAssertEqual(upbitSnapshot.quantity, 1.5)
    XCTAssertEqual(upbitSnapshot.averageBuyPrice, 100)
    XCTAssertEqual(upbitSnapshot.evaluationProfitLoss, 15)
    XCTAssertEqual(upbitSnapshot.evaluationPrice, 165)
    XCTAssertEqual(bithumbSnapshot.price, 120)
    XCTAssertEqual(bithumbSnapshot.quantity, 1.5)
    XCTAssertEqual(bithumbSnapshot.averageBuyPrice, 100)
    XCTAssertEqual(bithumbSnapshot.evaluationProfitLoss, 30)
    XCTAssertEqual(bithumbSnapshot.evaluationPrice, 180)

    // 저장소의 원자 갱신과 재조회도 거래소별 기준값을 유지해야 한다.
    try UserDataManager.performAtomicInvestmentUpdate {
      UserDataManager.userCryptoList = [upbitHolding, bithumbHolding]
    }
    // 저장소에서 다시 읽은 두 거래소의 보유분이다.
    let restored = try XCTUnwrap(UserDataManager.userCryptoList)
    XCTAssertEqual(restored.count, 2)
    XCTAssertEqual(restored[0].staticData.exchange, .upbit)
    XCTAssertEqual(restored[0].dynamicData.settlementPriceSnapshot, upbitSnapshot)
    XCTAssertEqual(restored[1].staticData.exchange, .bithumb)
    XCTAssertEqual(restored[1].dynamicData.settlementPriceSnapshot, bithumbSnapshot)
  }

  func testCorruptSettlementSnapshotPreservesAccountAndBlocksSettlement() throws {
    XCTAssertTrue(UserDataManager.resetInvestmentData())
    // 업비트에 저장할 원본 보유분이다.
    let upbitHolding = makeTransaction(
      market: "ETH/KRW",
      exchange: .upbit,
      quantity: 1.5,
      buyAmount: 150,
      costBasisKRW: 150,
      evaluationPrice: 165
    )
    // 빗썸에 저장할 원본 보유분이다.
    let bithumbHolding = makeTransaction(
      market: "ETH/KRW",
      exchange: .bithumb,
      quantity: 1.5,
      buyAmount: 150,
      costBasisKRW: 150,
      evaluationPrice: 165
    )
    // 저장된 보유 배열에서 새 기준값만 손상시킨다.
    let encoded = try JSONEncoder().encode([upbitHolding, bithumbHolding])
    // 손상 전 JSON의 구조를 검사한다.
    let encodedObject = try JSONSerialization.jsonObject(with: encoded)
    // 각 손상 사례가 공유하는 원본 보유 배열이다.
    let initialList = try XCTUnwrap(encodedObject as? [[String: Any]])

    for (index, exchange) in [Exchange.upbit, .bithumb].enumerated() {
      for invalidSnapshot: Any in ["invalid", ["price": 110], NSNull()] {
        // 현재 손상 사례에 사용할 독립 보유 배열이다.
        var list = initialList
        // 새 기준값만 교체할 평가 데이터다.
        var dynamicData = try XCTUnwrap(list[index]["dynamicData"] as? [String: Any])
        dynamicData["settlementPriceSnapshot"] = invalidSnapshot
        list[index]["dynamicData"] = dynamicData
        // 기존 JSON 바이트가 조회 또는 정산 시 변경되지 않아야 한다.
        let corruptedData = try JSONSerialization.data(withJSONObject: list)
        UserDefaults.standard.set(corruptedData, forKey: UserDataManager.Keys.userCryptoList)

        // 구형 마이그레이션으로 손상 기준값을 버리지 않고 해당 계좌를 복원한다.
        let restoredList = try XCTUnwrap(UserDataManager.userCryptoList)
        XCTAssertEqual(restoredList.count, 2)
        // 이번 사례에서 기준값이 손상된 보유분이다.
        let restored = restoredList[index]
        XCTAssertEqual(restored.staticData.exchange, exchange)
        XCTAssertEqual(restored.staticData.costBasisKRW, 150)
        XCTAssertEqual(restored.staticData.holdingQuantity, 1.5)
        XCTAssertEqual(restored.dynamicData.exchange, exchange)
        XCTAssertEqual(restored.dynamicData.settlementPriceSnapshot, .invalid)
        XCTAssertEqual(restoredList[1 - index].staticData.exchange, index == 0 ? .bithumb : .upbit)
        XCTAssertEqual(restoredList[1 - index].staticData.costBasisKRW, 150)
        XCTAssertNil(restoredList[1 - index].dynamicData.settlementPriceSnapshot)
        XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList), corruptedData)

        // 잘못된 정산 기준으로 자산이나 내역을 변경할 수 없다.
        let balanceBefore = UserDataManager.userInformation(for: exchange)?.userAvailableBalance
        // 정산 전 거래내역이다.
        let transactionsBefore = UserDataManager.userTransactionList
        // 정산 전 실현손익 저장 데이터다.
        let pnlBefore = UserDefaults.standard.data(forKey: UserDataManager.Keys.userPNLHistory)
        switch TradeOrderService.executeDelistingSettlement(marketName: "ETH/KRW", exchange: exchange) {
        case .success:
          XCTFail("손상된 정산 기준으로 정산하면 안 됩니다.")
        case .failure(let error):
          XCTAssertEqual(error, .settlementUnverified)
        }
        XCTAssertEqual(UserDataManager.userInformation(for: exchange)?.userAvailableBalance, balanceBefore)
        XCTAssertEqual(UserDataManager.userTransactionList, transactionsBefore)
        XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userPNLHistory), pnlBefore)
        XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList), corruptedData)
      }
    }
  }

  func testIndependentHoldingUpdatesPersistInvalidSnapshotAndBlockSettlement() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      for update in 0..<4 {
        XCTAssertTrue(UserDataManager.resetInvestmentData())
        // 같은 시점의 보유 정보와 정산 기준이다.
        var holding = makeTransaction(
          market: "ETH/KRW",
          exchange: exchange,
          quantity: 1.5,
          buyAmount: 150,
          costBasisKRW: 150,
          evaluationPrice: 165
        )
        holding.dynamicData.evaluationProfitLoss = 15
        holding.updateSettlementPriceSnapshot(currentPrice: 110)
        XCTAssertNotNil(holding.dynamicData.settlementPriceSnapshot)
        UserDataManager.userCryptoList = [holding]

        switch update {
        case 0:
          // 유효하지 않은 시세로 기준을 갱신하면 구형 fallback으로 돌아가면 안 된다.
          holding.updateSettlementPriceSnapshot(currentPrice: .nan)
          UserDataManager.userCryptoList = [holding]
        case 1:
          MarketDataServiceUtil.shared.updateStaticHoldingData(
            for: "ETH/KRW",
            exchange: exchange,
            cryptoName: "이더리움",
            averageBuyAmount: 100,
            holdingQuantity: 2,
            buyAmount: 200
          )
        case 2:
          MarketDataServiceUtil.shared.updateEvaluationProfitLoss(
            for: "ETH/KRW",
            exchange: exchange,
            currentPrice: 120,
            holdingQuantity: 1.5,
            averageBuyPrice: 100
          )
        default:
          MarketDataServiceUtil.shared.updateEvaluationPrice(
            for: "ETH/KRW",
            exchange: exchange,
            currentPrice: 120,
            holdingQuantity: 1.5
          )
        }

        // 저장소를 다시 읽었을 때도 무효 상태가 유지되어야 한다.
        let restored = try XCTUnwrap(UserDataManager.userCryptoList?.first)
        XCTAssertEqual(restored.staticData.exchange, exchange)
        XCTAssertEqual(restored.dynamicData.settlementPriceSnapshot, .invalid)
        // 정산을 시도해도 보유·현금·원장이 그대로여야 한다.
        let bytesBefore = UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList)
        // 정산 전 선택 거래소의 잔고다.
        let balanceBefore = UserDataManager.userInformation(for: exchange)?.userAvailableBalance
        // 정산 전 거래내역이다.
        let transactionBefore = UserDataManager.userTransactionList
        // 정산 전 실현손익 저장 데이터다.
        let pnlBefore = UserDefaults.standard.data(forKey: UserDataManager.Keys.userPNLHistory)
        switch TradeOrderService.executeDelistingSettlement(marketName: "ETH/KRW", exchange: exchange) {
        case .success:
          XCTFail("검증되지 않은 기준으로 정산하면 안 됩니다.")
        case .failure(let error):
          XCTAssertEqual(error, .settlementUnverified)
        }
        XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList), bytesBefore)
        XCTAssertEqual(UserDataManager.userInformation(for: exchange)?.userAvailableBalance, balanceBefore)
        XCTAssertEqual(UserDataManager.userTransactionList, transactionBefore)
        XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userPNLHistory), pnlBefore)
      }
    }
  }

  func testPNLHistoryDefaultsToUpbitWhenExchangeIsMissing() throws {
    let json = """
    {
      "marketName": "BTC/KRW",
      "entryPrice": 100.0,
      "exitPrice": 120.0,
      "transactionDate": "07.09 12:00",
      "orderQuantity": 1.0,
      "pnl": 20.0
    }
    """

    let decoded = try JSONDecoder().decode(
      UserPNLHistoryModel.self,
      from: Data(json.utf8)
    )

    XCTAssertEqual(decoded.exchange, .upbit)
    XCTAssertEqual(decoded.exchangePairID.rawValue, "upbit:KRW-BTC")
    XCTAssertNil(decoded.transactionTimestamp)
    XCTAssertEqual(decoded.transactionDate, "07.09 12:00")
  }

  func testTransactionRecordTypeDefaultsToUserOrderWhenMissing() throws {
    let transaction = TransactionInfo(
      marketName: "ETH/BTC",
      orderType: .bid,
      executedDate: "07.09 12:00",
      executedPrice: 0.00003,
      executedQuantity: 100,
      executedAmount: 0.003
    )
    let encoded = try JSONEncoder().encode(transaction)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object.removeValue(forKey: "recordType")
    let legacyData = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(
      TransactionInfo.self,
      from: legacyData
    )

    XCTAssertEqual(decoded.exchange, .upbit)
    XCTAssertEqual(decoded.recordType, .userOrder)
  }

  private func makeTransaction(
    market: String,
    exchange: Exchange = .upbit,
    quantity: Double = 1,
    buyAmount: Double = 100,
    costBasisKRW: Decimal? = nil,
    evaluationPrice: Double = 100
  ) -> CryptoTransactionDataModel {
    CryptoTransactionDataModel(
      staticData: .init(
		exchange: exchange,
        marketName: market,
        cryptoName: market,
        holdingQuantity: quantity,
        averageBuyPrice: 100,
        buyAmount: buyAmount,
        costBasisKRW: costBasisKRW
      ),
      dynamicData: .init(
		exchange: exchange,
        marketName: market,
        profitRate: 0,
        evaluationProfitLoss: 0,
        evaluationPrice: evaluationPrice
      )
    )
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
      UserDataManager.Keys.userInformationByExchange,
      UserDataManager.Keys.pendingInvestmentState,
      UserDataManager.Keys.marketCellTintEnabled
    ].forEach {
      UserDefaults.standard.removeObject(forKey: $0)
    }
  }
}

private struct TestPendingInvestmentState: Encodable {
  let cryptoList: [CryptoTransactionDataModel]
  let transactionList: [TransactionInfo]
  let validTransactionList: [ValidTransactionInfo]
  let pnlHistory: [UserPNLHistoryModel]
  let informationByExchange: [String: MobitUserInformation]
}

final class ValidTransactionDecimalTests: XCTestCase {
  func testDecimalQuantitySumClosesFractionalPosition() throws {
    // 이진 부동소수 합산으로는 양수 잔량이 남을 수 있는 전체 매도 이력이다.
    let history = ValidTransactionInfo(
      marketName: "BTC/KRW",
      transaction: [
        .init(orderType: .bid, quantity: 0.1, buyPrice: 10),
        .init(orderType: .bid, quantity: 0.2, buyPrice: 10),
        .init(orderType: .ask, quantity: 0.3, buyPrice: 10)
      ]
    )
    XCTAssertEqual(history.totalHoldingQuantity, 0)
    XCTAssertTrue(history.isFullySoldOut)

    // 기존 거래이력의 직렬화 키와 Double 데이터 형식은 그대로 사용한다.
    let data = try JSONEncoder().encode(history)
    // 저장 후 복원된 이력에서도 전량 매도가 유지돼야 한다.
    let decoded = try JSONDecoder().decode(ValidTransactionInfo.self, from: data)
    XCTAssertEqual(decoded, history)
    XCTAssertTrue(decoded.isFullySoldOut)
  }

  func testWeightedBuyAverageUsesDecimalArithmetic() throws {
    // 이진 곱셈과 수량 합산으로 평단이 달라질 수 있는 매수 이력이다.
    let history = ValidTransactionInfo(
      marketName: "BTC/KRW",
      transaction: [
        .init(orderType: .bid, quantity: 0.1, buyPrice: 10.1),
        .init(orderType: .bid, quantity: 0.2, buyPrice: 10.2),
        .init(orderType: .ask, quantity: 0.1, buyPrice: 12)
      ]
    )
    XCTAssertEqual(history.totalHoldingQuantity, 0.2)
    XCTAssertEqual(try XCTUnwrap(history.averageBuyPrice), 10.166666666666666)
  }

  func testNonFiniteValuesKeepExistingFallbackBehavior() throws {
    // 기존 이력에 비유한 수량이 있으면 이전 Double 계산 결과를 유지한다.
    let history = ValidTransactionInfo(
      marketName: "BTC/KRW",
      transaction: [.init(orderType: .bid, quantity: .infinity, buyPrice: 1)]
    )
    XCTAssertEqual(history.totalHoldingQuantity, .infinity)
    XCTAssertTrue(try XCTUnwrap(history.averageBuyPrice).isNaN)
    XCTAssertFalse(history.isFullySoldOut)
  }

  func testWeightedBuyAverageFallsBackWhenProductExceedsDecimalExponentRange() throws {
    // Decimal 곱셈의 지수가 범위를 벗어나도 기존 Double 결과를 유지한다.
    let history = ValidTransactionInfo(
      marketName: "BTC/KRW",
      transaction: [.init(orderType: .bid, quantity: 1e-100, buyPrice: 1e-100)]
    )
    XCTAssertEqual(try XCTUnwrap(history.averageBuyPrice), 1e-100 * 1e-100 / 1e-100)
  }
}
