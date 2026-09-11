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
  }

  override func tearDown() {
    clearUserDefaults()
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
