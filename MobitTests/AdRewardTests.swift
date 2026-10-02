import XCTest
@testable import Mobit

final class AdRewardTests: XCTestCase {
  private var directory: URL!
  private let futuresAccount = TradingAccountID(exchange: .binance, product: .perpetual, currency: .usdt)

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    clearDefaults()
    ExchangeSelectionStore.currentExchange = .upbit
    UserDataManager.resetInvestmentData()
  }

  override func tearDownWithError() throws {
    clearDefaults()
    ExchangeSelectionStore.currentExchange = .upbit
    if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
  }

  func testSpotRewardUsesOriginalAccountAndIsNotTradingProfit() throws {
    let claim = try AdRewardClaim(account: .spot(for: .upbit))
    ExchangeSelectionStore.currentExchange = .bithumb
    try UserDataManager.applyAdvertisementReward(claim)
    try UserDataManager.applyAdvertisementReward(claim)
    XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 10_000_000)
    XCTAssertEqual(UserDataManager.userInformation(for: .bithumb)?.userAvailableBalance, 0)
    XCTAssertEqual(UserDataManager.userPNLHistory?.count, 0)
    XCTAssertEqual(UserDataManager.userTransactionList?.count, 0)
  }

  func testConcurrentDuplicateRewardAndBalanceChangesDoNotLoseUpdates() throws {
    let claim = try AdRewardClaim(account: .spot(for: .upbit))
    DispatchQueue.concurrentPerform(iterations: 100) { index in
      do {
        if index.isMultiple(of: 2) { try UserDataManager.applyAdvertisementReward(claim) }
        else { try UserDataManager.updateUserInformation(for: .upbit) { $0.userAvailableBalance += 1 } }
      } catch { XCTFail("Concurrent mutation failed: \(error)") }
    }
    XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 10_000_050)
  }

  func testReceiptSurvivesResetAndConflictingIDIsRejected() throws {
    let claim = try AdRewardClaim(account: .spot(for: .upbit))
    try UserDataManager.applyAdvertisementReward(claim)
    XCTAssertTrue(UserDataManager.resetInvestmentData())
    try UserDataManager.applyAdvertisementReward(claim)
    XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 0)
    let conflict = try AdRewardClaim(id: claim.id, account: .spot(for: .bithumb), earnedAt: claim.earnedAt)
    XCTAssertThrowsError(try UserDataManager.applyAdvertisementReward(conflict))
    XCTAssertEqual(UserDataManager.userInformation(for: .bithumb)?.userAvailableBalance, 0)
  }

  func testCorruptReceiptDataPreventsRewardWithoutOverwritingCashState() throws {
    UserDataManager.resetInvestmentData(availableBalance: 123)
    let bytes = Data(#"{"schemaVersion":1,"informationByExchange":{"upbit":{"userAvailableBalance":123}},"adRewardClaims":null}"#.utf8)
    UserDefaults.standard.set(bytes, forKey: UserDataManager.Keys.userInformationByExchange)
    XCTAssertThrowsError(try UserDataManager.applyAdvertisementReward(AdRewardClaim(account: .spot(for: .upbit))))
    XCTAssertNil(UserDataManager.userInformation)
    XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userInformationByExchange), bytes)
    XCTAssertFalse(UserDataManager.resetInvestmentData())
  }

  func testLegacyCashDictionaryMigratesTogetherWithFirstReceipt() throws {
    let old = ["upbit": MobitUserInformation(userAvailableBalance: 123),
               "bithumb": MobitUserInformation(userAvailableBalance: 456)]
    UserDefaults.standard.set(try JSONEncoder().encode(old), forKey: UserDataManager.Keys.userInformationByExchange)
    let claim = try AdRewardClaim(account: .spot(for: .upbit))
    try UserDataManager.applyAdvertisementReward(claim)
    XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 10_000_123)
    XCTAssertEqual(UserDataManager.userInformation(for: .bithumb)?.userAvailableBalance, 456)
    let data = try XCTUnwrap(UserDefaults.standard.data(forKey: UserDataManager.Keys.userInformationByExchange))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertNotNil(object["informationByExchange"])
    XCTAssertEqual((object["adRewardClaims"] as? [[String: Any]])?.count, 1)
  }

  func testRetryAfterRestartUsesPersistedClaim() throws {
    let store = LocalAdRewardPendingStore(fileURL: directory.appendingPathComponent("pending.json"))
    let failed = AdRewardUseCase(store: store) { _ in throw AdRewardError.invalidStoredData }
    let claim = try AdRewardClaim(account: .spot(for: .upbit))
    XCTAssertThrowsError(try failed.receive(claim))
    XCTAssertEqual(try store.load(), [claim])
    XCTAssertThrowsError(try failed.resetSpotInvestment())
    let restarted = AdRewardUseCase(store: store)
    XCTAssertEqual(try restarted.retryPendingRewards(), [claim])
    XCTAssertTrue(try store.load().isEmpty)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 10_000_000)
  }

  func testInitialQueueWriteFailureKeepsInMemoryRightAndDoesNotCredit() throws {
    let store = PendingStoreDouble()
    store.failSave = true
    let useCase = AdRewardUseCase(store: store)
    let claim = try AdRewardClaim(account: .spot(for: .upbit))
    XCTAssertThrowsError(try useCase.receive(claim))
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 0)
    XCTAssertThrowsError(try useCase.resetSpotInvestment())
    store.failSave = false
    XCTAssertEqual(try useCase.retryPendingRewards(), [claim])
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 10_000_000)
  }

  func testCleanupFailureAfterCreditDoesNotCreditAgain() throws {
    let store = PendingStoreDouble()
    store.failEmptySave = true
    let useCase = AdRewardUseCase(store: store)
    let claim = try AdRewardClaim(account: .spot(for: .upbit))
    XCTAssertThrowsError(try useCase.receive(claim))
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 10_000_000)
    XCTAssertEqual(store.claims, [claim])
    store.failEmptySave = false
    try AdRewardUseCase(store: store).retryPendingRewards()
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 10_000_000)
    XCTAssertTrue(store.claims.isEmpty)
  }

  func testOneFailedAccountDoesNotBlockOtherPendingRewards() throws {
    let store = PendingStoreDouble()
    let upbit = try AdRewardClaim(account: .spot(for: .upbit))
    let bithumb = try AdRewardClaim(account: .spot(for: .bithumb))
    store.claims = [upbit, bithumb]
    let useCase = AdRewardUseCase(store: store) { claim in
      if claim.account.exchange == .upbit { throw AdRewardError.invalidStoredData }
      try UserDataManager.applyAdvertisementReward(claim)
    }
    XCTAssertThrowsError(try useCase.retryPendingRewards())
    XCTAssertEqual(store.claims, [upbit])
    XCTAssertEqual(UserDataManager.userInformation(for: .bithumb)?.userAvailableBalance, 10_000_000)
  }

  func testMalformedPendingFileIsNeverOverwritten() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("pending.json")
    let bytes = Data("broken".utf8)
    try bytes.write(to: url)
    let useCase = AdRewardUseCase(store: LocalAdRewardPendingStore(fileURL: url))
    XCTAssertThrowsError(try useCase.receive(AdRewardClaim(account: .spot(for: .upbit))))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 0)
  }

  func testDomesticRewardBeforeAnyAccountVisitCreatesOnlyCapturedAccountOnce() throws {
    let url = directory.appendingPathComponent("futures.json")
    let repository = LocalFuturesAccountRepository(fileURL: url)
    let pending = PendingStoreDouble()
    let useCase = AdRewardUseCase(store: pending, apply: repository.applyAdvertisementReward)
    for exchange in [Exchange.upbit, .bithumb] {
      let account = TradingAccountID(exchange: exchange, product: .perpetual, currency: .krw)
      let claim = try AdRewardClaim(account: account)
      XCTAssertFalse(try repository.snapshot().accounts.contains { $0.id == account })
      ExchangeSelectionStore.currentExchange = exchange == .upbit ? .bithumb : .upbit
      try useCase.receive(claim)
      try useCase.receive(claim)
      let saved = try repository.snapshot()
      XCTAssertEqual(saved.accounts.first { $0.id == account }?.availableBalance, 10_000_000)
      XCTAssertEqual(saved.rewardClaims.filter { $0.id == claim.id }, [claim])
      XCTAssertEqual(try saved.transactionHistory(for: account).count, 0)
      XCTAssertEqual(try saved.valuation(for: account, quotes: [:], now: Date()).realizedPnL, 0)
      XCTAssertTrue(pending.claims.isEmpty)
    }
    XCTAssertEqual(try LocalFuturesAccountRepository(fileURL: url).snapshot().accounts.count, 2)
    XCTAssertEqual(UserDataManager.userInformation(for: .upbit)?.userAvailableBalance, 0)
  }

  func testMissingAccountRewardWriteFailureRetainsPendingClaimAndRetriesAtomically() throws {
    let url = directory.appendingPathComponent("futures.json")
    let account = TradingAccountID(exchange: .upbit, product: .perpetual, currency: .krw)
    let claim = try AdRewardClaim(account: account)
    let pending = PendingStoreDouble()
    let failing = LocalFuturesAccountRepository(fileURL: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    let useCase = AdRewardUseCase(store: pending, apply: failing.applyAdvertisementReward)
    XCTAssertThrowsError(try useCase.receive(claim))
    XCTAssertEqual(pending.claims, [claim])
    XCTAssertTrue(try failing.snapshot().accounts.isEmpty)
    XCTAssertTrue(try failing.snapshot().rewardClaims.isEmpty)
    let good = LocalFuturesAccountRepository(fileURL: url)
    let retry = AdRewardUseCase(store: pending, apply: good.applyAdvertisementReward)
    XCTAssertEqual(try retry.retryPendingRewards(), [claim])
    XCTAssertTrue(try retry.retryPendingRewards().isEmpty)
    XCTAssertEqual(try good.snapshot().accounts.first?.availableBalance, 10_000_000)
    XCTAssertEqual(try good.snapshot().rewardClaims, [claim])
    XCTAssertEqual(try good.snapshot().revision, 1)
  }

  func testUSDTRewardAndReceiptCommitTogetherAndSurviveReopen() throws {
    let url = directory.appendingPathComponent("futures.json")
    let repository = LocalFuturesAccountRepository(fileURL: url)
    try repository.ensureAccount(futuresAccount)
    let claim = try AdRewardClaim(account: futuresAccount)
    try repository.applyAdvertisementReward(claim)
    try LocalFuturesAccountRepository(fileURL: url).applyAdvertisementReward(claim)
    let snapshot = try repository.snapshot()
    XCTAssertEqual(snapshot.accounts.first?.availableBalance, 1000)
    XCTAssertEqual(snapshot.rewardClaims, [claim])
    XCTAssertEqual(snapshot.revision, 2)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 0)
  }

  func testFailedUSDTWriteDoesNotSaveEitherCashOrReceipt() throws {
    let url = directory.appendingPathComponent("futures.json")
    let good = LocalFuturesAccountRepository(fileURL: url)
    let original = try good.ensureAccount(futuresAccount)
    let failing = LocalFuturesAccountRepository(fileURL: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    let claim = try AdRewardClaim(account: futuresAccount)
    XCTAssertThrowsError(try failing.applyAdvertisementReward(claim))
    XCTAssertEqual(try good.snapshot(), original)
    try good.applyAdvertisementReward(claim)
    XCTAssertEqual(try good.snapshot().accounts.first?.availableBalance, 1000)
  }

  func testSchemaOneMigratesAndSchemaTwoMissingReceiptsIsRejected() throws {
    let url = directory.appendingPathComponent("futures.json")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(#"{"schemaVersion":1,"revision":3,"accounts":[]}"#.utf8).write(to: url)
    let repository = LocalFuturesAccountRepository(fileURL: url)
    XCTAssertEqual(try repository.ensureAccount(futuresAccount).schemaVersion, 5)
    let corrupt = Data(#"{"schemaVersion":2,"revision":3,"accounts":[]}"#.utf8)
    try corrupt.write(to: url)
    XCTAssertThrowsError(try repository.ensureAccount(futuresAccount))
    XCTAssertEqual(try Data(contentsOf: url), corrupt)
  }

  @MainActor
  func testDismissWithoutRewardDoesNotCredit() async throws {
    let store = PendingStoreDouble()
    let session = try RewardedAdSession(account: .spot(for: .upbit))
    session.dismissed()
    XCTAssertNil(session.takeResultIfReady())
    XCTAssertTrue(store.claims.isEmpty)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 0)
  }

  @MainActor
  func testRewardAndDismissInEitherOrderNotifyAndCreditOnce() async throws {
    for dismissFirst in [false, true] {
      UserDataManager.resetInvestmentData()
      let session = try RewardedAdSession(account: .spot(for: .upbit))
      let useCase = AdRewardUseCase(store: PendingStoreDouble())
      if dismissFirst { session.dismissed() }
      session.earned(using: useCase)
      session.earned(using: useCase)
      if !dismissFirst {
        XCTAssertNil(session.takeResultIfReady())
        session.dismissed()
      }
      try XCTUnwrap(session.takeResultIfReady()).get()
      XCTAssertNil(session.takeResultIfReady())
      XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 10_000_000)
    }
  }

  @MainActor
  func testFailedRewardNeverNotifiesSuccessAndCanRetryWithoutNewAd() async throws {
    let store = PendingStoreDouble()
    store.failSave = true
    let useCase = AdRewardUseCase(store: store)
    let session = try RewardedAdSession(account: .spot(for: .upbit))
    session.earned(using: useCase)
    session.dismissed()
    XCTAssertThrowsError(try XCTUnwrap(session.takeResultIfReady()).get())
    store.failSave = false
    try useCase.retryPendingRewards()
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 10_000_000)
  }

  private func clearDefaults() {
    [UserDataManager.Keys.pendingInvestmentState,
     UserDataManager.Keys.userInformation, UserDataManager.Keys.userInformationByExchange,
     UserDataManager.Keys.userCryptoList, UserDataManager.Keys.userTransactionList,
     UserDataManager.Keys.userValidTransactionList, UserDataManager.Keys.userPNLHistory,
     UserDataManager.Keys.isFirstLaunch].forEach { UserDefaults.standard.removeObject(forKey: $0) }
  }
}

private final class PendingStoreDouble: AdRewardPendingStore {
  var claims: [AdRewardClaim] = []
  var failSave = false
  var failEmptySave = false
  func load() throws -> [AdRewardClaim] { claims }
  func save(_ claims: [AdRewardClaim]) throws {
    if failSave || (failEmptySave && claims.isEmpty) { throw CocoaError(.fileWriteOutOfSpace) }
    self.claims = claims
  }
}
