import XCTest
@testable import Mobit

final class FuturesPositionRepositoryTests: XCTestCase {
  private var directory: URL!
  private var url: URL { directory.appendingPathComponent("accounts.json") }
  private var store: LocalFuturesAccountRepository { LocalFuturesAccountRepository(fileURL: url) }

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  override func tearDownWithError() throws {
    if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
  }

  private func funded() throws -> FuturesAccountSnapshot {
    try store.ensureAccount(futuresOrder().account)
    try store.applyAdvertisementReward(AdRewardClaim(account: futuresOrder().account))
    return try store.snapshot()
  }

  func testOpeningDebitsMarginAndPersistsImmutablePositionAndLedgerTogether() throws {
    let before = try funded()
    let order = futuresOrder(fee: Decimal(string: "0.001")!)
    let after = try store.openTestPosition(order, expectedRevision: before.revision)
    XCTAssertEqual(after.accounts[0].availableBalance, 900)
    XCTAssertEqual(after.positions[0].leverageAtExecution, 10)
    XCTAssertEqual(after.ledger[0].cashDelta, -100)
    XCTAssertEqual(after.ledger[0].collateralDelta, 99)
    XCTAssertEqual(after.ledger[0].feePaid, 1)
    XCTAssertEqual(try store.snapshot(), after)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let rewarded = try store.snapshot()
    XCTAssertEqual(rewarded.accounts[0].availableBalance, 1900)
    XCTAssertEqual(rewarded.positions, after.positions)
    XCTAssertEqual(rewarded.ledger, after.ledger)
  }

  func testIdempotentRetryConflictingIDAndDuplicateInstrument() throws {
    let before = try funded()
    let order = futuresOrder()
    let after = try store.openTestPosition(order, expectedRevision: before.revision)
    XCTAssertEqual(try store.openTestPosition(order, expectedRevision: before.revision), after)
    XCTAssertThrowsError(try store.openTestPosition(futuresOrder(id: order.requestID, side: .short), expectedRevision: after.revision))
    XCTAssertThrowsError(try store.openTestPosition(futuresOrder(), expectedRevision: after.revision))
    XCTAssertEqual(try store.snapshot(), after)
  }

  func testInsufficientFundsStaleRevisionAndInvalidOrderPreserveBytes() throws {
    let before = try funded()
    let bytes = try Data(contentsOf: url)
    XCTAssertThrowsError(try store.openTestPosition(futuresOrder(margin: 1001), expectedRevision: before.revision))
    XCTAssertThrowsError(try store.openTestPosition(futuresOrder(), expectedRevision: before.revision - 1))
    XCTAssertThrowsError(try store.openTestPosition(futuresOrder(leverage: 0), expectedRevision: before.revision))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
  }

  func testPreparedOpeningRejectsStaleFutureAndMismatchedQuotesWithoutWriting() throws {
    let before = try funded()
    let order = futuresOrder()
    let time = try FuturesReconciliationState.milliseconds(order.executedAt)
    let bytes = try Data(contentsOf: url)
    for quote in [
      FuturesMarkQuote(instrument: order.instrument, price: order.executionPrice, timestamp: time - 5001),
      FuturesMarkQuote(instrument: order.instrument, price: order.executionPrice, timestamp: time + 1),
      FuturesMarkQuote(instrument: order.instrument, price: order.executionPrice + 1, timestamp: time),
      FuturesMarkQuote(instrument: order.instrument, price: 0, timestamp: time)
    ] {
      let preflight = FuturesOrderPreflight(account: order.account, instrument: order.instrument,
        revision: before.revision, mark: quote)
      XCTAssertThrowsError(try store.openPosition(order, preflight: preflight, now: order.executedAt))
      XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    let valid = FuturesOrderPreflight(account: order.account, instrument: order.instrument,
      revision: before.revision, mark: .init(instrument: order.instrument, price: order.executionPrice, timestamp: time))
    XCTAssertNoThrow(try store.openPosition(order, preflight: valid, now: order.executedAt))
  }

  func testFailedWriteDoesNotDebitOrLoseRetry() throws {
    let before = try funded()
    let bytes = try Data(contentsOf: url)
    let order = futuresOrder()
    let failing = LocalFuturesAccountRepository(fileURL: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    XCTAssertThrowsError(try failing.openTestPosition(order, expectedRevision: before.revision))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    XCTAssertEqual(try store.snapshot(), before)
    XCTAssertEqual(try store.openTestPosition(order, expectedRevision: before.revision).accounts[0].availableBalance, 900)
  }

  func testConcurrentRepeatedOpeningCommitsOnce() throws {
    let before = try funded()
    let order = futuresOrder()
    DispatchQueue.concurrentPerform(iterations: 30) { _ in
      do { try store.openTestPosition(order, expectedRevision: before.revision) }
      catch { XCTFail("Concurrent opening failed: \(error)") }
    }
    let after = try store.snapshot()
    XCTAssertEqual(after.revision, before.revision + 1)
    XCTAssertEqual(after.accounts[0].availableBalance, 900)
    XCTAssertEqual(after.positions.count, 1)
    XCTAssertEqual(after.ledger.count, 1)
  }

  func testRewardAndOpeningRacePreservesBothAfterRevisionRetry() throws {
    let before = try funded()
    let order = futuresOrder()
    let claim = try AdRewardClaim(account: order.account)
    DispatchQueue.concurrentPerform(iterations: 2) { index in
      do {
        if index == 0 { try store.applyAdvertisementReward(claim) }
        else {
          do { try store.openTestPosition(order, expectedRevision: before.revision) }
          catch LocalFuturesAccountRepository.StoreError.revisionConflict {
            try store.openTestPosition(order, expectedRevision: store.snapshot().revision)
          }
        }
      } catch { XCTFail("Concurrent reward/open failed: \(error)") }
    }
    let after = try store.snapshot()
    XCTAssertEqual(after.accounts[0].availableBalance, 1900)
    XCTAssertEqual(after.positions.count, 1)
    XCTAssertEqual(after.rewardClaims.count, 2)
    XCTAssertEqual(after.revision, before.revision + 2)
  }

  func testLegacySnapshotsMigrateWithoutChangingCashOrRewards() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for schema in [1, 2] {
      let claims = schema == 1 ? [] : [try AdRewardClaim(account: futuresOrder().account)]
      let old = FuturesAccountSnapshot(schemaVersion: schema, revision: 5,
                                      accounts: [.init(id: futuresOrder().account, availableBalance: 1234)], rewardClaims: claims)
      var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
      object.removeValue(forKey: "positions")
      object.removeValue(forKey: "ledger")
      if schema == 1 { object.removeValue(forKey: "rewardClaims") }
      try JSONSerialization.data(withJSONObject: object).write(to: url)
      let migrated = try store.openTestPosition(futuresOrder(), expectedRevision: 5)
      XCTAssertEqual(migrated.schemaVersion, 5)
      XCTAssertEqual(migrated.accounts[0].availableBalance, 1134)
      XCTAssertEqual(migrated.rewardClaims, claims)
      XCTAssertEqual(migrated.revision, 6)
    }
  }

  func testCorruptPositionLedgerAndRequiredFieldsNeverOverwriteFile() throws {
    let before = try funded()
    let after = try store.openTestPosition(futuresOrder(), expectedRevision: before.revision)
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(after)) as? [String: Any])
    var mutations: [[String: Any]] = []
    for key in ["positions", "ledger", "rewardClaims"] {
      var missing = original
      missing.removeValue(forKey: key)
      mutations.append(missing)
      missing[key] = NSNull()
      mutations.append(missing)
    }
    var orphan = original
    orphan["accounts"] = []
    mutations.append(orphan)
    var duplicate = original
    let ledger = try XCTUnwrap(original["ledger"] as? [Any])
    duplicate["ledger"] = ledger + ledger
    mutations.append(duplicate)
    var noLeverage = original
    var positions = try XCTUnwrap(original["positions"] as? [[String: Any]])
    var order = try XCTUnwrap(positions[0]["order"] as? [String: Any])
    order.removeValue(forKey: "leverage")
    positions[0]["order"] = order
    noLeverage["positions"] = positions
    mutations.append(noLeverage)
    for mutation in mutations {
      let bytes = try JSONSerialization.data(withJSONObject: mutation)
      try bytes.write(to: url)
      XCTAssertThrowsError(try store.ensureAccount(futuresOrder().account))
      XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
  }

  func testRemovingAccountWithOpenPositionIsRejected() throws {
    let before = try funded()
    let after = try store.openTestPosition(futuresOrder(), expectedRevision: before.revision)
    XCTAssertThrowsError(try store.update(expectedRevision: after.revision) { $0.removeAll() })
    XCTAssertEqual(try store.snapshot(), after)
  }
}

// 테스트 데이터도 실제 주문과 동일한 검증·저장 경로를 통과시킨다.
extension LocalFuturesAccountRepository {
  @discardableResult
  func openTestPosition(_ order: FuturesOpeningOrder, expectedRevision: UInt64) throws -> FuturesAccountSnapshot {
    let timestamp = try FuturesReconciliationState.milliseconds(order.executedAt)
    let preflight = FuturesOrderPreflight(account: order.account, instrument: order.instrument,
      revision: expectedRevision, mark: .init(instrument: order.instrument, price: order.executionPrice, timestamp: timestamp))
    return try openPosition(order, preflight: preflight, now: order.executedAt)
  }
}

final class DomesticFuturesTradingTests: XCTestCase {
  private var directory: URL!
  private var url: URL { directory.appendingPathComponent("accounts.json") }
  private var store: LocalFuturesAccountRepository { .init(fileURL: url) }
  override func setUpWithError() throws { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
  override func tearDownWithError() throws {
    if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
  }
  private func open(_ side: FuturesSide = .long) throws -> FuturesPosition {
    let order = domesticFuturesOrder(side: side, margin: 100, price: 100)
    try store.ensureAccount(order.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    return try store.openTestPosition(order, expectedRevision: store.snapshot().revision).positions[0]
  }
  private func verify(_ position: FuturesPosition, end: Int64, price: Decimal = 100) throws -> FuturesReplayResult {
    let snapshot = try store.snapshot()
    let start = try XCTUnwrap(snapshot.reconciliations.first(where: { $0.positionID == position.id })).verifiedThrough
    return try store.reconcile(positionID: position.id, expectedRevision: snapshot.revision,
      batch: .init(instrument: position.order.instrument, start: start, endExclusive: end,
        candles: [.init(openTime: start, closeTime: end - 1, open: price, high: price, low: price, close: price)],
        funding: [], detailed: true), settledAt: Date(timeIntervalSince1970: Double(end) / 1000))
  }
  private func preflight(_ position: FuturesPosition, time: Int64, price: Decimal = 100,
                         proof: Bool = false) throws -> FuturesOrderPreflight {
    .init(account: position.order.account, instrument: position.order.instrument, revision: try store.snapshot().revision,
      mark: .init(instrument: position.order.instrument, price: price, timestamp: time),
      verifiedPositions: proof ? [position.id: time] : [:])
  }

  func testAdditionPreservesFillsAndUsesWeightedCostRatherThanAverageOfPrices() throws {
    let first = try open()
    _ = try verify(first, end: 120_000)
    let second = domesticFuturesOrder(margin: 200, price: 200, date: Date(timeIntervalSince1970: 120))
    let ready = try preflight(first, time: 120_000, price: 200)
    let snapshot = try store.openPosition(second, preflight: ready, now: second.executedAt)
    let position = try XCTUnwrap(snapshot.positions.first)
    XCTAssertEqual(position.id, first.id)
    XCTAssertEqual(position.order.executedAt, first.order.executedAt)
    XCTAssertEqual(position.lastExecutionAt, second.executedAt)
    XCTAssertEqual(position.executions.count, 2)
    XCTAssertEqual(position.quantity, 20)
    XCTAssertEqual(try position.margin, 300)
    XCTAssertEqual(try position.averageEntryPrice, 150)
    XCTAssertEqual(try FuturesCalculator.estimatedLiquidationPrice(position), 135)
    XCTAssertEqual(try FuturesCalculator.evaluate(position, markPrice: 200).tradingPnL, 1000)
    XCTAssertEqual(snapshot.accounts[0].availableBalance, 9_999_700)
    XCTAssertEqual(try snapshot.transactionHistory(for: first.order.account).map(\.quantity), [10, 10])
    XCTAssertEqual(try store.openPosition(second, preflight: ready, now: second.executedAt), snapshot)
    XCTAssertEqual(try store.snapshot(), snapshot)
  }

  func testDifferentDirectionLeverageAndUnverifiedAdditionPreserveFile() throws {
    let first = try open()
    let bytes = try Data(contentsOf: url)
    for order in [domesticFuturesOrder(side: .short, margin: 100, price: 100),
                  domesticFuturesOrder(leverage: 20, margin: 100, price: 100),
                  domesticFuturesOrder(margin: 100, price: 100, date: Date(timeIntervalSince1970: 61))] {
      XCTAssertThrowsError(try store.openPosition(order,
        preflight: preflight(first, time: FuturesReconciliationState.milliseconds(order.executedAt)), now: order.executedAt))
      XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
  }

  func testAdditionFailureAndAdRewardRaceDoNotSpendUnverifiedBalance() throws {
    let first = try open()
    _ = try verify(first, end: 120_000)
    let second = domesticFuturesOrder(margin: 100, price: 100, date: Date(timeIntervalSince1970: 120))
    let ready = try preflight(first, time: 120_000)
    let bytes = try Data(contentsOf: url)
    let failing = LocalFuturesAccountRepository(fileURL: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    XCTAssertThrowsError(try failing.openPosition(second, preflight: ready, now: second.executedAt))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    try store.applyAdvertisementReward(AdRewardClaim(account: first.order.account))
    XCTAssertThrowsError(try store.openPosition(second, preflight: ready, now: second.executedAt))
    XCTAssertEqual(try store.snapshot().positions[0].executions.count, 1)
  }

  func testSafeCurrentIntervalIsProofOnlyAndSurvivesAsCompletedMinuteCheckpoint() throws {
    let first = try open()
    let snapshot = try store.snapshot()
    let result = try verify(first, end: 65_123)
    XCTAssertEqual(result.state.verifiedThrough, 65_123)
    XCTAssertEqual(try store.snapshot(), snapshot)
    let ready = try preflight(first, time: 65_123, proof: true)
    XCTAssertNoThrow(try ready.validate(snapshot: snapshot, now: Date(timeIntervalSince1970: 66)))
    XCTAssertThrowsError(try preflight(first, time: 65_123).validate(snapshot: snapshot, now: Date(timeIntervalSince1970: 66)))
    XCTAssertThrowsError(try ready.validate(snapshot: snapshot, now: Date(timeIntervalSince1970: 71)))
  }

  func testLongAndShortManualCloseReturnMarginPlusPnLExactlyOnce() throws {
    for side in [FuturesSide.long, .short] {
      if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
      let position = try open(side)
      let price: Decimal = side == .long ? 105 : 95
      let result = try verify(position, end: 65_000, price: price)
      let ready = try preflight(position, time: result.state.verifiedThrough, price: price, proof: true)
      let close = FuturesClosingOrder(requestID: UUID(), positionID: position.id, executionPrice: price, executedAt: Date(timeIntervalSince1970: 65))
      let snapshot = try store.closePosition(close, preflight: ready, now: Date(timeIntervalSince1970: 66))
      XCTAssertEqual(snapshot.accounts[0].availableBalance, 10_000_050)
      XCTAssertFalse(snapshot.isActive(position))
      XCTAssertEqual(snapshot.closedPositions[0].realizedPnL, 50)
      XCTAssertEqual(try snapshot.transactionHistory(for: position.order.account).last?.kind, .closing)
      let value = try snapshot.valuation(for: position.order.account, quotes: [:], now: close.executedAt)
      XCTAssertEqual(value.realizedPnL, 50)
      XCTAssertEqual(value.totalEquity, 10_000_050)
      DispatchQueue.concurrentPerform(iterations: 12) { _ in
        do { XCTAssertEqual(try self.store.closePosition(close, preflight: ready, now: Date(timeIntervalSince1970: 80)), snapshot) }
        catch { XCTFail("Duplicate close failed: \(error)") }
      }
      XCTAssertEqual(try store.snapshot(), snapshot)
    }
  }

  func testClosingWriteFailurePreservesOpenPositionAndRetry() throws {
    let position = try open()
    _ = try verify(position, end: 65_000)
    let ready = try preflight(position, time: 65_000, proof: true)
    let order = FuturesClosingOrder(requestID: UUID(), positionID: position.id, executionPrice: 100, executedAt: Date(timeIntervalSince1970: 65))
    let bytes = try Data(contentsOf: url)
    let failing = LocalFuturesAccountRepository(fileURL: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    XCTAssertThrowsError(try failing.closePosition(order, preflight: ready, now: order.executedAt))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    XCTAssertEqual(try store.closePosition(order, preflight: ready, now: order.executedAt).accounts[0].availableBalance, 10_000_000)
  }

  func testCurrentIntervalLiquidationPersistsAndCannotBeManuallyClosed() throws {
    let position = try open()
    let ready = try preflight(position, time: 65_000, price: 100, proof: true)
    let result = try verify(position, end: 65_000, price: 80)
    XCTAssertNotNil(result.state.liquidation)
    XCTAssertEqual(try store.snapshot().reconciliations[0], result.state)
    let close = FuturesClosingOrder(requestID: UUID(), positionID: position.id, executionPrice: 100, executedAt: Date(timeIntervalSince1970: 65))
    XCTAssertThrowsError(try store.closePosition(close, preflight: ready, now: close.executedAt))
    XCTAssertEqual(try store.snapshot().accounts[0].availableBalance, 9_999_900)
  }

  func testValuationCapsLossAndRejectsStaleMissingAndWrongInstrumentQuotes() throws {
    let position = try open()
    let snapshot = try store.snapshot()
    let instrument = position.order.instrument
    let value = try snapshot.valuation(for: position.order.account,
      quotes: [instrument: .init(instrument: instrument, price: 1, timestamp: 65_000)], now: Date(timeIntervalSince1970: 65))
    let positionValue = try FuturesCalculator.evaluate(position, markPrice: 1)
    XCTAssertEqual(positionValue.displayedROEPercent, -100)
    XCTAssertEqual(try positionValue.displayedPnL, -100)
    XCTAssertEqual(positionValue.displayedEquity, 0)
    XCTAssertEqual(value.unrealizedPnL, -100)
    XCTAssertEqual(value.totalEquity, value.availableBalance + value.reservedMargin + value.unrealizedPnL)
    XCTAssertTrue(value.requiresReconciliation)
    for timestamp in [Int64(1), 66_000] {
      XCTAssertThrowsError(try snapshot.valuation(for: position.order.account,
        quotes: [instrument: .init(instrument: instrument, price: 100, timestamp: timestamp)], now: Date(timeIntervalSince1970: 65)))
    }
    XCTAssertThrowsError(try snapshot.valuation(for: position.order.account, quotes: [:], now: Date(timeIntervalSince1970: 65)))
  }

  func testLegacyUnverifiedMillisecondRoundingDoesNotMakeSavedAccountUnreadable() throws {
    let position = try open()
    let snapshot = try store.snapshot()
    var state = snapshot.reconciliations[0]
    state.verifiedThrough += 1
    let legacy = FuturesAccountSnapshot(schemaVersion: 4, revision: snapshot.revision, accounts: snapshot.accounts,
      rewardClaims: snapshot.rewardClaims, positions: snapshot.positions, ledger: snapshot.ledger, reconciliations: [state])
    try JSONEncoder().encode(legacy).write(to: url)
    let migrated = try store.snapshot()
    XCTAssertEqual(migrated.accounts, snapshot.accounts)
    XCTAssertEqual(migrated.reconciliations[0].verifiedThrough, try FuturesReconciliationState.milliseconds(position.order.executedAt))
  }

  func testEpochMillisecondsRoundTripDoesNotMoveEntryForward() throws {
    for time in [Int64(1_790_639_993_201), 1_780_272_034_123, 65_123] {
      XCTAssertEqual(try FuturesReconciliationState.milliseconds(Date(timeIntervalSince1970: Double(time) / 1000)), time)
    }
  }
}
