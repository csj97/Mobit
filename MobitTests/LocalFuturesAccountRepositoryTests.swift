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
    let position = FuturesPosition(order: order, quantity: 10, entryTradeAmount: 10, entryFee: 0, ruleVersion: .simpleMarginV1)
    let snapshot = FuturesAccountSnapshot(revision: 2,
      accounts: [.init(id: order.account, availableBalance: 3)], positions: [position],
      ledger: [try FuturesCalculator.openingLedgerEntry(for: position)], historyCheckStates: [try .initial(for: position)])
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

  func testStoredAccountKeysRemainCompatibleAfterRenaming() throws {
    let data = Data(#"""
      {
        "schemaVersion": 5, "revision": 2,
        "accounts": [{
          "id": {"exchange": "upbit", "product": "perpetual", "currency": "KRW"},
          "availableBalance": 900000
        }],
        "rewardClaims": [], "closedPositions": [],
        "positions": [{
          "order": {
            "requestID": "00000000-0000-0000-0000-000000000001",
            "account": {"exchange": "upbit", "product": "perpetual", "currency": "KRW"},
            "instrument": {
              "exchange": "upbit", "product": "perpetual",
              "rawSymbol": "KRW-BTC", "settlementCurrency": "KRW"
            },
            "side": "long", "margin": 100000, "leverage": 10,
            "executionPrice": 100000000, "entryFeeRate": 0, "executedAt": 60,
            "contractRules": {
              "maximumLeverage": 100, "quantityStep": 0.00000001,
              "minimumQuantity": 0.00000001, "minimumNotional": 500
            }
          },
          "quantity": 0.01, "entryNotional": 1000000,
          "entryFee": 0, "ruleVersion": "simpleMarginV1"
        }],
        "ledger": [{
          "id": "00000000-0000-0000-0000-000000000001",
          "positionID": "00000000-0000-0000-0000-000000000001",
          "account": {"exchange": "upbit", "product": "perpetual", "currency": "KRW"},
          "occurredAt": 60, "kind": "open", "cashDelta": -100000,
          "collateralDelta": 100000, "feePaid": 0
        }],
        "reconciliations": [{
          "positionID": "00000000-0000-0000-0000-000000000001",
          "verifiedThrough": 978307260000, "netFunding": 0, "fundingReceipts": []
        }]
      }
      """#.utf8)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try data.write(to: fileURL)

    let snapshot = try LocalFuturesAccountRepository(fileURL: fileURL).snapshot()
    let position = try XCTUnwrap(snapshot.positions.first)
    XCTAssertEqual(position.entryTradeAmount, 1_000_000)
    XCTAssertEqual(position.order.contractRules.minimumOrderAmount, 500)
    XCTAssertEqual(snapshot.ledger.first?.reservedMarginChange, 100_000)
    XCTAssertEqual(snapshot.historyCheckStates.first?.verifiedThrough, 978_307_260_000)
    XCTAssertEqual(try Data(contentsOf: fileURL), data)

    let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    let encoded = try JSONEncoder().encode(snapshot)
    let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
    XCTAssertEqual(saved, original)
    try encoded.write(to: fileURL)
    XCTAssertEqual(try LocalFuturesAccountRepository(fileURL: fileURL).snapshot(), snapshot)
  }

  func testStoredLiquidationPriceKeyRemainsCompatibleAfterRenaming() throws {
    let data = Data(#"""
      {
        "intervalStart": 60000, "intervalEndExclusive": 120000,
        "witnessMarkPrice": 89.5, "settledAt": 120
      }
      """#.utf8)
    let record = try JSONDecoder().decode(FuturesLiquidationRecord.self, from: data)
    XCTAssertEqual(record.observedLiquidationPrice, Decimal(string: "89.5"))
    XCTAssertNil(record.observedAt)
    XCTAssertEqual(record.occurredMinute, 60_000)

    let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    let encoded = try JSONEncoder().encode(record)
    // 발생 분만 새로 저장하고 기존 청산 가격 키와 검증 구간은 보존한다.
    var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    XCTAssertEqual(saved.removeValue(forKey: "occurredMinute") as? Int, 60_000)
    XCTAssertEqual(saved as NSDictionary, original)
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

  func testSelectedFuturesResetRemovesOnlyItsPositionsHistoryAndCashAndPreservesReceipts() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      // 양 거래소 계좌를 매번 독립된 파일에 만든다.
      let store = LocalFuturesAccountRepository(fileURL: directory.appendingPathComponent("\(exchange.rawValue).json"))
      // 초기화 뒤 기존 보상 콜백이 잔고를 복구하지 못하게 보존할 지급 기록이다.
      let claim = try AdRewardClaim(account: .init(exchange: exchange, product: .perpetual, currency: .krw))
      try store.applyAdvertisementReward(claim)
      // 선택하지 않은 계좌의 잔고·포지션·원장·종료 이력을 함께 비교한다.
      let otherExchange: Exchange = exchange == .upbit ? .bithumb : .upbit
      try store.applyAdvertisementReward(AdRewardClaim(account: .init(exchange: otherExchange, product: .perpetual, currency: .krw)))
      for fundedExchange in [exchange, otherExchange] {
        for symbol in ["KRW-BTC", "KRW-ETH"] {
          // 한 계좌에 보유 중 포지션과 전량 종료 포지션을 모두 남긴다.
          let opening = domesticFuturesOrder(exchange: fundedExchange, symbol: symbol)
          // 직전 체결의 revision을 읽어 실제 주문 저장 경로를 사용한다.
          let opened = try store.openTestPosition(opening, expectedRevision: store.snapshot().revision)
          if symbol == "KRW-ETH" {
            // 진입 경계에서 종료해 별도 네트워크 검증 자료 없이 종료 이력을 구성한다.
            let closing = FuturesClosingOrder(
              requestID: UUID(),
              positionID: opening.requestID,
              executionPrice: opening.executionPrice,
              executedAt: opening.executedAt
            )
            // 현재 계좌·가격·revision으로 종료 주문을 검증한다.
            let check = FuturesOrderCheck(
              account: opening.account,
              instrument: opening.instrument,
              revision: opened.revision,
              mark: .init(instrument: opening.instrument, price: opening.executionPrice, timestamp: 60_000)
            )
            try store.closePosition(closing, orderCheck: check, now: closing.executedAt)
          }
        }
      }
      // 초기화 전 데이터와 검증 revision을 저장해 다른 계좌 보존·이전 쓰기 거절을 확인한다.
      let before = try store.snapshot()
      // 초기화할 계좌에 속했던 포지션 ID는 종료·검증 기록까지 모두 제거되어야 한다.
      let removedIDs = Set(before.positions.filter { $0.order.account == claim.account }.map(\.id))
      // 초기화 후 재실행 시 읽게 될 확정 스냅샷이다.
      let after = try store.resetInvestment(for: claim.account)
      XCTAssertEqual(after.revision, before.revision + 1)
      XCTAssertEqual(after.accounts.first { $0.id == claim.account }?.availableBalance, 0)
      XCTAssertEqual(after.accounts.filter { $0.id != claim.account }, before.accounts.filter { $0.id != claim.account })
      XCTAssertEqual(after.positions, before.positions.filter { $0.order.account != claim.account })
      XCTAssertEqual(after.ledger, before.ledger.filter { $0.account != claim.account })
      XCTAssertEqual(after.historyCheckStates, before.historyCheckStates.filter { !removedIDs.contains($0.positionID) })
      XCTAssertEqual(after.closedPositions, before.closedPositions.filter { !removedIDs.contains($0.order.positionID) })
      XCTAssertEqual(after.rewardClaims, before.rewardClaims)
      try store.applyAdvertisementReward(claim)
      XCTAssertEqual(try store.snapshot(), after)
      XCTAssertThrowsError(try store.update(expectedRevision: before.revision) { $0[0].availableBalance = 1 }) {
        XCTAssertEqual($0 as? LocalFuturesAccountRepository.StoreError, .revisionConflict)
      }
      XCTAssertEqual(try store.snapshot(), after)
    }
  }

  func testSelectedFuturesResetWriteFailurePreservesFileAndMissingAccountCreatesNothing() throws {
    // 새 계좌 초기화는 빈 파일이나 잔고를 생성하지 않는다.
    let selectedAccount = TradingAccountID(exchange: .upbit, product: .perpetual, currency: .krw)
    // 성공·실패 저장 경로가 같은 파일을 검사한다.
    let store = LocalFuturesAccountRepository(fileURL: fileURL)
    XCTAssertEqual(try store.resetInvestment(for: selectedAccount), .empty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    try store.applyAdvertisementReward(AdRewardClaim(account: selectedAccount))
    // 저장 실패 전 현금과 지급 기록을 포함한 원본이다.
    let before = try store.snapshot()
    // 저장 실패가 파일 일부를 교체하지 않았는지 확인한다.
    let bytes = try Data(contentsOf: fileURL)
    // 파일 교체 실패를 실제 commit 경로에서 주입한다.
    let failing = LocalFuturesAccountRepository(fileURL: fileURL) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    XCTAssertThrowsError(try failing.resetInvestment(for: selectedAccount))
    XCTAssertEqual(try Data(contentsOf: fileURL), bytes)
    XCTAssertEqual(try store.snapshot(), before)
    XCTAssertThrowsError(try store.resetInvestment(for: .spot(for: .upbit)))
    XCTAssertEqual(try Data(contentsOf: fileURL), bytes)
  }
}
