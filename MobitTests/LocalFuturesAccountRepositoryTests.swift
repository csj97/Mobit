import XCTest
@testable import Mobit

final class LocalFuturesAccountRepositoryTests: XCTestCase {
  private var directory: URL!
  private var fileURL: URL { directory.appendingPathComponent("accounts.json") }
  private let account = TradingAccountID(exchange: .binance, product: .perpetual, currency: .usdt)

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  override func tearDownWithError() throws {
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }

  func testAccountAndInstrumentIdentitySeparateExchangeAndProduct() throws {
    let spot = TradingAccountID.spot(for: .upbit)
    XCTAssertNotEqual(spot, TradingAccountID(exchange: .upbit, product: .perpetual, currency: .krw))
    XCTAssertNotEqual(spot, .spot(for: .bithumb))
    let first = TradingInstrumentID(exchange: .binance, product: .spot, rawSymbol: "BTCUSDT", settlementCurrency: .usdt)
    let second = TradingInstrumentID(exchange: .binance, product: .perpetual, rawSymbol: "BTCUSDT", settlementCurrency: .usdt)
    XCTAssertNotEqual(first, second)
    XCTAssertEqual(try JSONDecoder().decode(TradingAccountID.self, from: JSONEncoder().encode(account)), account)
    XCTAssertEqual(account.availability, .preparing)
    XCTAssertEqual(spot.availability, .available)
    XCTAssertEqual(TradingAccountID(exchange: .upbit, product: .perpetual, currency: .usdt).availability, .unsupported)
  }

  func testFundingPoliciesDoNotCreateUSDTInitialFundsOrBTCRewards() {
    XCTAssertEqual(TradingFundingPolicy.initialGrant(for: .spot(for: .upbit)), 1_000_000)
    XCTAssertEqual(TradingFundingPolicy.initialGrant(for: .spot(for: .bithumb)), 0)
    XCTAssertEqual(TradingFundingPolicy.initialGrant(for: account), 0)
    XCTAssertEqual(TradingFundingPolicy.advertisementReward(for: account), 1_000)
    XCTAssertEqual(TradingFundingPolicy.advertisementReward(for: .spot(for: .upbit)), 10_000_000)
    XCTAssertNil(TradingFundingPolicy.advertisementReward(for: .init(exchange: .upbit, product: .spot, currency: .btc)))
  }

  func testNewAccountIsZeroAndReopeningDoesNotResetBalance() throws {
    let store = LocalFuturesAccountRepository(fileURL: fileURL)
    let created = try store.ensureAccount(account)
    XCTAssertEqual(created.accounts.first?.availableBalance, 0)
    let changed = try store.update(expectedRevision: created.revision) { $0[0].availableBalance = 1000 }
    let reopened = LocalFuturesAccountRepository(fileURL: fileURL)
    XCTAssertEqual(try reopened.ensureAccount(account), changed)
    let second = TradingAccountID(exchange: .okx, product: .perpetual, currency: .usdt)
    let both = try reopened.ensureAccount(second)
    XCTAssertEqual(both.accounts.map(\.availableBalance), [1000, 0])
    XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
  }

  func testDomesticAccountsRewardsAndLegacyUSDTCoexistAfterReopening() throws {
    let store = LocalFuturesAccountRepository(fileURL: fileURL)
    try store.ensureAccount(account)
    try store.applyAdvertisementReward(AdRewardClaim(account: account))
    for exchange in [Exchange.upbit, .bithumb] {
      let domestic = TradingAccountID(exchange: exchange, product: .perpetual, currency: .krw)
      let snapshot = try store.ensureAccount(domestic)
      XCTAssertEqual(snapshot.accounts.first(where: { $0.id == domestic })?.availableBalance, 0)
      XCTAssertEqual(domestic.availability, .available)
      let claim = try AdRewardClaim(account: domestic)
      try store.applyAdvertisementReward(claim)
      try store.applyAdvertisementReward(claim)
      XCTAssertEqual(try store.snapshot().accounts.first(where: { $0.id == domestic })?.availableBalance, 10_000_000)
      let btc = TradingAccountID(exchange: exchange, product: .perpetual, currency: .btc)
      XCTAssertThrowsError(try store.ensureAccount(btc))
      XCTAssertNil(TradingFundingPolicy.advertisementReward(for: btc))
    }
    let reopened = try LocalFuturesAccountRepository(fileURL: fileURL).snapshot()
    XCTAssertEqual(reopened.accounts.count, 3)
    XCTAssertEqual(reopened.accounts.first(where: { $0.id == account })?.availableBalance, 1000)
    XCTAssertEqual(reopened.rewardClaims.count, 3)
  }

  func testLegacyDomesticBTCFileRemainsReadableButNewBTCOrdersAreRejected() throws {
    let order = domesticFuturesOrder(currency: .btc, symbol: "BTC-ETH", margin: 1, price: 1)
    let position = FuturesPosition(order: order, quantity: 10, entryNotional: 10, entryFee: 0, ruleVersion: .simpleMarginV1)
    let snapshot = FuturesAccountSnapshot(revision: 2,
      accounts: [.init(id: order.account, availableBalance: 3)], positions: [position],
      ledger: [try FuturesCalculator.openingLedgerEntry(for: position)], reconciliations: [try .initial(for: position)])
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let bytes = try JSONEncoder().encode(snapshot)
    try bytes.write(to: fileURL)
    let store = LocalFuturesAccountRepository(fileURL: fileURL)
    XCTAssertEqual(try store.snapshot(), snapshot)
    XCTAssertThrowsError(try FuturesCalculator.open(order))
    XCTAssertEqual(try Data(contentsOf: fileURL), bytes)
  }

  func testTwoInstancesRejectStaleRevisionInsteadOfOverwriting() throws {
    let first = LocalFuturesAccountRepository(fileURL: fileURL)
    let second = LocalFuturesAccountRepository(fileURL: fileURL)
    let original = try first.ensureAccount(account)
    let updated = try second.update(expectedRevision: original.revision) { $0[0].availableBalance = 1000 }
    XCTAssertThrowsError(try first.update(expectedRevision: original.revision) { $0[0].availableBalance = 50 }) {
      XCTAssertEqual($0 as? LocalFuturesAccountRepository.StoreError, .revisionConflict)
    }
    XCTAssertEqual(try first.snapshot(), updated)
  }

  func testFailedWriteKeepsPreviousFileAndRevision() throws {
    let original = try LocalFuturesAccountRepository(fileURL: fileURL).ensureAccount(account)
    let bytes = try Data(contentsOf: fileURL)
    let failing = LocalFuturesAccountRepository(fileURL: fileURL) { _, _ in
      throw CocoaError(.fileWriteOutOfSpace)
    }
    XCTAssertThrowsError(try failing.update(expectedRevision: original.revision) { $0[0].availableBalance = 1000 })
    XCTAssertEqual(try Data(contentsOf: fileURL), bytes)
    XCTAssertEqual(try failing.snapshot(), original)
  }

  func testInvalidNumbersDuplicateAccountsAndSpotNeverReplaceFile() throws {
    let store = LocalFuturesAccountRepository(fileURL: fileURL)
    let original = try store.ensureAccount(account)
    let bytes = try Data(contentsOf: fileURL)
    for balance in [Decimal.nan, Decimal(-1)] {
      XCTAssertThrowsError(try store.update(expectedRevision: original.revision) { $0[0].availableBalance = balance })
    }
    XCTAssertThrowsError(try store.update(expectedRevision: original.revision) { $0.append($0[0]) })
    XCTAssertThrowsError(try store.ensureAccount(.spot(for: .upbit)))
    XCTAssertEqual(try Data(contentsOf: fileURL), bytes)
  }

  func testCorruptAndFutureSchemaFilesArePreserved() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = LocalFuturesAccountRepository(fileURL: fileURL)
    for bytes in [Data("null".utf8), Data("broken".utf8), Data(#"{"schemaVersion":5,"revision":0,"accounts":[]}"#.utf8)] {
      try bytes.write(to: fileURL)
      XCTAssertThrowsError(try store.ensureAccount(account))
      XCTAssertEqual(try Data(contentsOf: fileURL), bytes)
    }
  }

  func testExactDecimalRoundTripAndThrowingMutationRollback() throws {
    let store = LocalFuturesAccountRepository(fileURL: fileURL)
    let original = try store.ensureAccount(account)
    let balance = try XCTUnwrap(Decimal(string: "123456789.123456789123456789"))
    let updated = try store.update(expectedRevision: original.revision) { $0[0].availableBalance = balance }
    XCTAssertEqual(try LocalFuturesAccountRepository(fileURL: fileURL).snapshot(), updated)
    XCTAssertThrowsError(try store.update(expectedRevision: updated.revision) {
      $0[0].availableBalance = 0
      throw LocalFuturesAccountRepository.StoreError.invalidStoredData
    })
    XCTAssertEqual(try store.snapshot(), updated)
  }

  func testConcurrentCreationHasOneAccountAndOneCommit() throws {
    DispatchQueue.concurrentPerform(iterations: 40) { _ in
      do {
        try LocalFuturesAccountRepository(fileURL: fileURL).ensureAccount(account)
      } catch {
        XCTFail("Concurrent creation failed: \(error)")
      }
    }
    let snapshot = try LocalFuturesAccountRepository(fileURL: fileURL).snapshot()
    XCTAssertEqual(snapshot.accounts.count, 1)
    XCTAssertEqual(snapshot.revision, 1)
  }
}
