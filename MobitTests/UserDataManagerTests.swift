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
  }

  private func makeTransaction(market: String) -> CryptoTransactionDataModel {
    CryptoTransactionDataModel(
      staticData: .init(
        marketName: market,
        cryptoName: market,
        holdingQuantity: 1,
        averageBuyPrice: 100,
        buyAmount: 100
      ),
      dynamicData: .init(
        marketName: market,
        profitRate: 0,
        evaluationProfitLoss: 0,
        evaluationPrice: 100
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
      UserDataManager.Keys.userInformationByExchange
    ].forEach {
      UserDefaults.standard.removeObject(forKey: $0)
    }
  }
}
