import XCTest
import UIKit
import RxSwift
import GoogleMobileAds
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
    let failed = AdRewardUseCase(store: store, apply: { _ in throw AdRewardError.invalidStoredData })
    let claim = try AdRewardClaim(account: .spot(for: .upbit))
    XCTAssertThrowsError(try failed.receive(claim))
    XCTAssertEqual(try store.fetchClaims(), [claim])
    XCTAssertThrowsError(try failed.resetSpotInvestment())
    let restarted = AdRewardUseCase(store: store)
    XCTAssertEqual(try restarted.retryPendingRewards(), [claim])
    XCTAssertTrue(try store.fetchClaims().isEmpty)
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
    let useCase = AdRewardUseCase(
      store: store,
      apply: { claim in
        if claim.account.exchange == .upbit { throw AdRewardError.invalidStoredData }
        try UserDataManager.applyAdvertisementReward(claim)
      }
    )
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
    XCTAssertEqual(try repository.ensureAccount(futuresAccount).schemaVersion, 6)
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

  @MainActor
  func testManagerCreditsOnlyChosenAccountAndRefreshesMoreWithoutChangingSelection() throws {
    // 현재 선택은 충전 전후에 동일해야 하며 다른 테스트의 선택도 복원한다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    defer { ExchangeSelectionStore.currentProduct = previousProduct }
    ExchangeSelectionStore.currentProduct = .spot
    // SDK만 대체하고 실제 계좌 저장·보상·More UI를 독립된 임시 선물 저장소로 연결한다.
    let fixture = try RewardedManagerFixture(directory: directory)
    defer { fixture.close() }
    fixture.waitUntil { fixture.balanceText(for: MoreAccountsUseCase.accounts[0]).contains("0") }
    for (index, account) in MoreAccountsUseCase.accounts.enumerated() {
      // 지급 전 다른 계좌의 표시값이 바뀌지 않는지 비교한다.
      let before = MoreAccountsUseCase.accounts.map { fixture.balanceText(for: $0) }
      // 더보기의 실제 충전 버튼과 확인창을 거쳐 manager로 전달한다.
      let button = try XCTUnwrap(fixture.find("more.charge.\(account.exchange.rawValue).\(account.product.rawValue)") as? UIButton)
      button.sendActions(for: .touchUpInside)
      fixture.waitUntil { fixture.controller.presentedViewController is MobitAlertViewController && fixture.controller.presentedViewController?.isBeingPresented == false }
      // 확인창에서 승인한 계좌를 SDK 완료까지 보존한다.
      let confirmation = try XCTUnwrap(fixture.controller.presentedViewController as? MobitAlertViewController)
      confirmation.confirmButton.sendActions(for: .touchUpInside)
      fixture.waitUntil { fixture.loader.requests.count == index + 1 && fixture.indicatorCount == 1 }
      // 같은 광고의 SDK 보상·종료 중복 콜백을 재현한다.
      let ad = RewardedAdDouble()
      fixture.loader.requests[index].resume(returning: ad)
      fixture.waitUntil { ad.presentations == 1 }
      ad.show()
      fixture.waitUntil { fixture.indicatorCount == 0 }
      fixture.clock.advanceTo(fixture.clock.clock.addingTimeInterval(30))
      XCTAssertNil(fixture.controller.presentedViewController)
      ad.earn()
      ad.earn()
      fixture.waitUntil { fixture.balanceText(for: account).contains("10,000,000") }
      for (row, oldText) in zip(MoreAccountsUseCase.accounts, before) where row != account {
        XCTAssertEqual(fixture.balanceText(for: row), oldText)
      }
      XCTAssertEqual(ExchangeSelectionStore.currentExchange, .upbit)
      XCTAssertEqual(ExchangeSelectionStore.currentProduct, .spot)
      ad.dismiss()
      ad.dismiss()
      fixture.waitUntil { fixture.controller.presentedViewController is MobitAlertViewController }
      XCTAssertEqual((fixture.controller.presentedViewController as? MobitAlertViewController)?.content, FuturesText.text("ad_reward_complete"))
      XCTAssertEqual(fixture.indicatorCount, 0)
      fixture.dismissMessage()
    }
    XCTAssertEqual(try UserDataManager.getAvailableBalance(for: .upbit), 10_000_000)
    XCTAssertEqual(try UserDataManager.getAvailableBalance(for: .bithumb), 10_000_000)
    XCTAssertEqual(try fixture.repository.snapshot().accounts.map(\.availableBalance), [10_000_000, 10_000_000])
    XCTAssertTrue(fixture.store.claims.isEmpty)
  }

  @MainActor
  func testManagerCoalescesContinuousTapsAndDismissWithoutRewardUnlocks() throws {
    // 연속 요청도 SDK 로드와 인디케이터는 하나만 만든다.
    let fixture = try RewardedManagerFixture(directory: directory)
    defer { fixture.close() }
    for _ in 0..<10 { fixture.manager.showAd(from: fixture.controller, account: .spot(for: .upbit)) }
    fixture.waitUntil { fixture.loader.requests.count == 1 && fixture.indicatorCount == 1 }
    XCTAssertEqual(fixture.loader.requests.count, 1)
    // 보상 조건을 달성하지 않고 광고를 닫는 경우다.
    let ad = RewardedAdDouble()
    fixture.loader.requests[0].resume(returning: ad)
    fixture.waitUntil { ad.presentations == 1 }
    ad.show()
    ad.dismiss()
    fixture.waitUntil { fixture.indicatorCount == 0 }
    XCTAssertEqual(try UserDataManager.getAvailableBalance(for: .upbit), 0)
    XCTAssertTrue(fixture.store.claims.isEmpty)
    XCTAssertNil(fixture.controller.presentedViewController)
    fixture.manager.showAd(from: fixture.controller, account: .spot(for: .bithumb))
    fixture.waitUntil { fixture.loader.requests.count == 2 && fixture.indicatorCount == 1 }
    fixture.loader.requests[1].resume(throwing: CocoaError(.fileReadNoSuchFile))
    fixture.waitUntil { fixture.indicatorCount == 0 && fixture.controller.presentedViewController != nil }
    fixture.dismissMessage()
  }

  @MainActor
  func testManagerLoadAndPresentationFailuresUnlockAndCanRetryWithoutDoubleReward() throws {
    for loadFailed in [true, false] {
      UserDataManager.resetInvestmentData()
      // 각 실패 시나리오는 자체 임시 저장소를 사용한다.
      let fixture = try RewardedManagerFixture(directory: directory.appendingPathComponent(UUID().uuidString))
      defer { fixture.close() }
      fixture.manager.showAd(from: fixture.controller, account: .spot(for: .bithumb))
      fixture.waitUntil { fixture.loader.requests.count == 1 && fixture.indicatorCount == 1 }
      // 실패한 표시 요청의 늦은 보상 콜백도 재현한다.
      let failedAd = RewardedAdDouble()
      if loadFailed { fixture.loader.requests[0].resume(throwing: CocoaError(.fileReadNoSuchFile)) }
      else {
        fixture.loader.requests[0].resume(returning: failedAd)
        fixture.waitUntil { failedAd.presentations == 1 }
        failedAd.fail()
        failedAd.earn()
      }
      fixture.waitUntil { fixture.indicatorCount == 0 && fixture.controller.presentedViewController is MobitAlertViewController }
      XCTAssertEqual(try UserDataManager.getAvailableBalance(for: .bithumb), 0)
      XCTAssertTrue(fixture.store.claims.isEmpty)
      fixture.dismissMessage()
      fixture.manager.showAd(from: fixture.controller, account: .spot(for: .bithumb))
      fixture.waitUntil { fixture.loader.requests.count == 2 && fixture.indicatorCount == 1 }
      // 실패 뒤 버튼과 manager가 잠기지 않고 정상 재시도한다.
      let retryAd = RewardedAdDouble()
      fixture.loader.requests[1].resume(returning: retryAd)
      fixture.waitUntil { retryAd.presentations == 1 }
      failedAd.fail()
      failedAd.dismiss()
      retryAd.show()
      retryAd.earn()
      retryAd.earn()
      retryAd.dismiss()
      fixture.waitUntil { (try? UserDataManager.getAvailableBalance(for: .bithumb)) == 10_000_000 && fixture.indicatorCount == 0 }
      fixture.waitUntil { fixture.controller.presentedViewController is MobitAlertViewController }
      fixture.dismissMessage()
      XCTAssertEqual(try UserDataManager.getAvailableBalance(for: .upbit), 0)
    }
  }

  @MainActor
  func testManagerPreparationTimeoutRejectsLateAdAndDoesNotHideNextIndicator() throws {
    // 실제 20초를 기다리지 않고 동일한 timer를 가상 시간으로 진행한다.
    let fixture = try RewardedManagerFixture(directory: directory)
    defer { fixture.close() }
    fixture.manager.showAd(from: fixture.controller, account: .spot(for: .upbit))
    fixture.waitUntil { fixture.loader.requests.count == 1 && fixture.indicatorCount == 1 }
    fixture.clock.advanceTo(fixture.clock.clock.addingTimeInterval(19))
    XCTAssertEqual(fixture.indicatorCount, 1)
    fixture.clock.advanceTo(fixture.clock.clock.addingTimeInterval(1))
    fixture.waitUntil { fixture.indicatorCount == 0 && fixture.controller.presentedViewController != nil }
    fixture.dismissMessage()
    fixture.manager.showAd(from: fixture.controller, account: .spot(for: .bithumb))
    fixture.waitUntil { fixture.loader.requests.count == 2 && fixture.indicatorCount == 1 }
    // 시간 초과한 광고 응답이 새 인디케이터를 종료하면 안 된다.
    let lateAd = RewardedAdDouble()
    fixture.loader.requests[0].resume(returning: lateAd)
    fixture.waitUntil { fixture.loader.completed == 1 }
    XCTAssertEqual(lateAd.presentations, 0)
    XCTAssertEqual(fixture.indicatorCount, 1)
    // 로드는 끝났지만 표시 시작 콜백이 없는 경우도 상한으로 종료한다.
    let stalledAd = RewardedAdDouble()
    fixture.loader.requests[1].resume(returning: stalledAd)
    fixture.waitUntil { stalledAd.presentations == 1 }
    fixture.clock.advanceTo(fixture.clock.clock.addingTimeInterval(20))
    fixture.waitUntil { fixture.indicatorCount == 0 && fixture.controller.presentedViewController != nil }
    stalledAd.show()
    stalledAd.earn()
    stalledAd.dismiss()
    XCTAssertEqual(try UserDataManager.getAvailableBalance(for: .bithumb), 0)
    fixture.dismissMessage()
  }

  @MainActor
  func testManagerBackgroundCancelsPreparationButPreservesShowingAdReward() throws {
    // 백그라운드로 간 준비 요청은 자동으로 광고를 표시하지 않는다.
    let fixture = try RewardedManagerFixture(directory: directory)
    defer { fixture.close() }
    fixture.manager.showAd(from: fixture.controller, account: .spot(for: .upbit))
    fixture.waitUntil { fixture.loader.requests.count == 1 && fixture.indicatorCount == 1 }
    NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    fixture.waitUntil { fixture.indicatorCount == 0 }
    XCTAssertNil(fixture.controller.presentedViewController)
    fixture.manager.showAd(from: fixture.controller, account: .spot(for: .bithumb))
    fixture.waitUntil { fixture.loader.requests.count == 2 && fixture.indicatorCount == 1 }
    fixture.loader.requests[0].resume(throwing: CocoaError(.fileReadNoSuchFile))
    fixture.waitUntil { fixture.loader.completed == 1 }
    XCTAssertEqual(fixture.indicatorCount, 1)
    XCTAssertNil(fixture.controller.presentedViewController)
    // 이미 재생 중인 광고는 백그라운드나 준비 상한 때문에 보상을 잃지 않는다.
    let ad = RewardedAdDouble()
    fixture.loader.requests[1].resume(returning: ad)
    fixture.waitUntil { ad.presentations == 1 }
    ad.show()
    NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    fixture.clock.advanceTo(fixture.clock.clock.addingTimeInterval(60))
    ad.earn()
    ad.dismiss()
    fixture.waitUntil { (try? UserDataManager.getAvailableBalance(for: .bithumb)) == 10_000_000 && fixture.indicatorCount == 0 }
    fixture.waitUntil { fixture.controller.presentedViewController != nil }
    fixture.dismissMessage()
    XCTAssertEqual(try UserDataManager.getAvailableBalance(for: .upbit), 0)
  }

  @MainActor
  func testManagerLateRewardAfterDismissIsCreditedOnceAndStorageFailureCanRecover() throws {
    // 닫힘 뒤 전달되는 보상과 지급 실패 후 복구도 원래 계좌에만 반영한다.
    let fixture = try RewardedManagerFixture(directory: directory)
    defer { fixture.close() }
    fixture.manager.showAd(from: fixture.controller, account: .spot(for: .bithumb))
    fixture.waitUntil { fixture.loader.requests.count == 1 }
    // 종료 뒤 보상이 전달되는 SDK 순서를 재현한다.
    let ad = RewardedAdDouble()
    fixture.loader.requests[0].resume(returning: ad)
    fixture.waitUntil { ad.presentations == 1 }
    ad.show()
    ad.dismiss()
    fixture.store.failSave = true
    ad.earn()
    ad.earn()
    fixture.waitUntil { fixture.controller.presentedViewController is MobitAlertViewController }
    XCTAssertEqual((fixture.controller.presentedViewController as? MobitAlertViewController)?.content, FuturesText.text("ad_reward_pending"))
    XCTAssertEqual(try UserDataManager.getAvailableBalance(for: .bithumb), 0)
    XCTAssertEqual(fixture.indicatorCount, 0)
    fixture.dismissMessage()
    fixture.store.failSave = false
    fixture.manager.showAd(from: fixture.controller, account: .spot(for: .upbit))
    fixture.waitUntil { (try? UserDataManager.getAvailableBalance(for: .bithumb)) == 10_000_000 }
    XCTAssertEqual(fixture.loader.requests.count, 1)
    XCTAssertEqual(try UserDataManager.getAvailableBalance(for: .upbit), 0)
    fixture.waitUntil { fixture.controller.presentedViewController is MobitAlertViewController }
    XCTAssertEqual((fixture.controller.presentedViewController as? MobitAlertViewController)?.content, FuturesText.text("ad_reward_recovered"))
    XCTAssertTrue(fixture.store.claims.isEmpty)
    fixture.dismissMessage()
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
  // 파일 대신 메모리에 보관한 테스트용 보상 요청을 반환한다.
  func fetchClaims() throws -> [AdRewardClaim] { claims }
  func save(_ claims: [AdRewardClaim]) throws {
    if failSave || (failEmptySave && claims.isEmpty) { throw CocoaError(.fileWriteOutOfSpace) }
    self.claims = claims
  }
}

// 실제 SDK 프로토콜의 delegate와 보상 콜백만 제어한다.
private final class RewardedAdDouble: NSObject, RewardedAdPresenting {
  // SDK와 같이 delegate를 약한 참조로 연결한다.
  weak var fullScreenContentDelegate: FullScreenContentDelegate?
  // SDK 표시 요청의 중복 여부를 확인한다.
  private(set) var presentations = 0
  // 종료·실패 뒤 늦게 오는 보상도 재현한다.
  private var rewardCallBack: (() -> Void)?

  @MainActor func present(from viewController: UIViewController?, userDidEarnRewardHandler: @escaping () -> Void) {
    presentations += 1
    rewardCallBack = userDidEarnRewardHandler
  }
  @MainActor func show() { fullScreenContentDelegate?.adWillPresentFullScreenContent?(self) }
  @MainActor func earn() { rewardCallBack?() }
  @MainActor func dismiss() { fullScreenContentDelegate?.adDidDismissFullScreenContent?(self) }
  @MainActor func fail() { fullScreenContentDelegate?.ad?(self, didFailToPresentFullScreenContentWithError: CocoaError(.fileReadNoSuchFile)) }
}

@MainActor
private final class RewardedAdLoaderDouble {
  // 로드 요청마다 서로 다른 SDK 응답 시점을 재현한다.
  var requests: [CheckedContinuation<RewardedAdPresenting, Error>] = []
  // 늦은 로드 응답의 처리가 끝났는지 확인한다.
  private(set) var completed = 0
  func load() async throws -> RewardedAdPresenting {
    defer { completed += 1 }
    return try await withCheckedThrowingContinuation { requests.append($0) }
  }
}

@MainActor
private final class RewardedManagerFixture {
  // 테스트의 지급 대기 큐다.
  let store = PendingStoreDouble()
  // 네트워크 대신 SDK 응답만 제어한다.
  let loader = RewardedAdLoaderDouble()
  // 실제 timer를 가상 시간으로 검증한다.
  let clock = HistoricalScheduler()
  // 기존 계좌 파일과 완전히 분리한 테스트 저장소다.
  let repository: LocalFuturesAccountRepository
  // 실제 광고 준비·표시·종료 관리 대상이다.
  let manager: RewardedAdManager
  // 실제 More XIB와 잔고 갱신을 연결한다.
  let controller: MoreViewController
  // 실제 공통 인디케이터를 표시하는 테스트 창이다.
  let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))

  init(directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // 계좌 준비와 보상 지급 모두 이 임시 파일만 사용한다.
    let repository = LocalFuturesAccountRepository(fileURL: directory.appendingPathComponent("manager-futures.json"))
    self.repository = repository
    // 보상 큐·현물 원자적 저장·선물 저장을 실제 사용 사례로 검사한다.
    let useCase = AdRewardUseCase(
      store: store,
      prepareFuturesAccount: { _ = try repository.ensureAccount($0) },
      apply: { claim in
        if claim.account.product == .spot { try UserDataManager.applyAdvertisementReward(claim) }
        else { try repository.applyAdvertisementReward(claim) }
      }
    )
    // SDK 비동기 로드만 대체한 실제 manager다.
    let manager = RewardedAdManager(useCase: useCase, loadAd: { [loader] in try await loader.load() }, scheduler: clock)
    self.manager = manager
    controller = MoreViewController(
      accountsUseCase: MoreAccountsUseCase(futuresSnapshot: repository.snapshot, scheduler: MainScheduler.instance),
      presentRewardedAd: { manager.showAd(from: $0, account: $1) }
    )
    window.rootViewController = controller
    window.makeKeyAndVisible()
  }
  var indicatorCount: Int { window.subviews.filter { $0.tag == 999_999 }.count }
  func close() { controller.hideLoadingIndicator(); window.isHidden = true; window.rootViewController = nil }
  func balanceText(for account: TradingAccountID) -> String {
    (find("more.balance.\(account.exchange.rawValue).\(account.product.rawValue)") as? UILabel)?.text ?? "—"
  }
  func find(_ identifier: String) -> UIView? {
    // 테스트에서 실제 계좌 행을 찾는 데만 사용하는 탐색이다.
    func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { descendants($0) } }
    return descendants(controller.view).first { $0.accessibilityIdentifier == identifier }
  }
  func waitUntil(_ predicate: @escaping () -> Bool) {
    // SDK Task·UI 갱신·애니메이션의 실제 완료 조건을 기다린다.
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed)
  }
  func dismissMessage() {
    waitUntil { self.controller.presentedViewController?.isBeingPresented == false }
    (controller.presentedViewController as? MobitAlertViewController)?.confirmButton.sendActions(for: .touchUpInside)
    waitUntil { self.controller.presentedViewController == nil }
  }
}
