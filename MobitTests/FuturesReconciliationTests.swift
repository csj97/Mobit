import XCTest
import RxSwift
@testable import Mobit

final class FuturesReconciliationTests: XCTestCase {
  private var directory: URL!
  private var url: URL { directory.appendingPathComponent("accounts.json") }
  private var store: LocalFuturesAccountRepository { LocalFuturesAccountRepository(fileURL: url) }
  private var position: FuturesPosition { get throws { try FuturesCalculator.open(futuresOrder(date: Date(timeIntervalSince1970: 60))) } }
  private let settledAt = Date(timeIntervalSince1970: 300)

  override func setUpWithError() throws { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
  override func tearDownWithError() throws {
    if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
  }

  private func candle(_ start: Int64 = 60000, low: Decimal = 95, high: Decimal = 105) -> FuturesMarkCandle {
    .init(openTime: start, closeTime: start + 59999, open: 100, high: high, low: low, close: 100)
  }
  private func batch(_ position: FuturesPosition, start: Int64 = 60000, end: Int64 = 120000,
                     candles: [FuturesMarkCandle]? = nil, funding: [FuturesFundingEvent] = []) -> FuturesReplayBatch {
    .init(instrument: position.order.instrument, start: start, endExclusive: end, candles: candles ?? [candle()], funding: funding)
  }
  private func opened() throws -> FuturesAccountSnapshot {
    let position = try position
    try store.ensureAccount(position.order.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: position.order.account))
    return try store.openTestPosition(position.order, expectedRevision: store.snapshot().revision)
  }

  func testDipAndRecoveryStillLiquidatesWithoutDebitingFreeBalance() throws {
    let snapshot = try opened()
    let position = snapshot.positions[0]
    let outcome = try store.reconcile(positionID: position.id, expectedRevision: snapshot.revision,
                                      batch: batch(position, candles: [candle(low: 80)]), settledAt: settledAt)
    XCTAssertEqual(outcome.state.liquidation?.intervalStart, 60000)
    XCTAssertEqual(outcome.state.liquidation?.intervalEndExclusive, 120000)
    XCTAssertEqual(try store.snapshot().accounts[0].availableBalance, 900)
    XCTAssertEqual(try store.snapshot().reconciliations[0], outcome.state)
    XCTAssertThrowsError(try store.reconcile(positionID: position.id, expectedRevision: snapshot.revision,
                                            batch: batch(position), settledAt: settledAt))
  }

  func testDomesticCheckpointSurvivesReopenAndResumesWithoutChangingEntry() throws {
    let order = domesticFuturesOrder()
    try store.ensureAccount(order.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let funded = try store.snapshot()
    let preflight = FuturesOrderPreflight(account: order.account, instrument: order.instrument,
      revision: funded.revision, mark: .init(instrument: order.instrument, price: order.executionPrice, timestamp: 60_000))
    let opened = try store.openPosition(order, preflight: preflight, now: order.executedAt)
    let position = opened.positions[0]
    let safe = FuturesMarkCandle(openTime: 60_000, closeTime: 119_999,
      open: 100_000_000, high: 105_000_000, low: 95_000_000, close: 102_000_000)
    let firstBatch = batch(position, candles: [safe])
    _ = try store.reconcile(positionID: position.id, expectedRevision: opened.revision, batch: firstBatch, settledAt: settledAt)
    let reopened = LocalFuturesAccountRepository(fileURL: url)
    let saved = try reopened.snapshot()
    XCTAssertEqual(saved.reconciliations[0].verifiedThrough, 120_000)
    XCTAssertEqual(saved.positions[0].order.executedAt, order.executedAt)
    XCTAssertEqual(saved.positions[0].leverageAtExecution, 10)
    XCTAssertThrowsError(try reopened.reconcile(positionID: position.id, expectedRevision: saved.revision,
      batch: firstBatch, settledAt: settledAt))
    let dip = FuturesMarkCandle(openTime: 120_000, closeTime: 179_999,
      open: 102_000_000, high: 110_000_000, low: 89_000_000, close: 110_000_000)
    let resumed = batch(position, start: saved.reconciliations[0].verifiedThrough, end: 180_000, candles: [dip])
    let result = try reopened.reconcile(positionID: position.id, expectedRevision: saved.revision,
      batch: resumed, settledAt: settledAt)
    XCTAssertEqual(result.state.liquidation?.intervalStart, 120_000)
    XCTAssertEqual(result.state.verifiedThrough, 180_000)
    XCTAssertEqual(try reopened.snapshot().accounts[0].availableBalance, 9_900_000)
    XCTAssertEqual(try reopened.snapshot().positions[0], position)
  }

  func testDomesticLiquidationHistoryPnLAndAssetsPersistTogether() throws {
    for side in [FuturesSide.long, .short] {
      let order = domesticFuturesOrder(exchange: side == .long ? .upbit : .bithumb, side: side)
      try store.ensureAccount(order.account)
      try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
      let opened = try store.openTestPosition(order, expectedRevision: store.snapshot().revision)
      let before = try opened.valuation(for: order.account, quotes: [order.instrument: .init(instrument: order.instrument, price: 100_000_000, timestamp: 60_000)], now: order.executedAt)
      XCTAssertEqual(before.totalEquity, 10_000_000)
      XCTAssertEqual(before.availableBalance, 9_900_000)
      XCTAssertEqual(before.reservedMargin, 100_000)
      XCTAssertThrowsError(try opened.valuation(for: order.account, quotes: [:], now: order.executedAt))
      let adverse = FuturesMarkCandle(openTime: 60_000, closeTime: 119_999,
        open: 100_000_000, high: 120_000_000, low: 80_000_000, close: 100_000_000)
      let replay = batch(try XCTUnwrap(opened.positions.last), candles: [adverse])
      let bytes = try Data(contentsOf: url)
      let failing = LocalFuturesAccountRepository(fileURL: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
      XCTAssertThrowsError(try failing.reconcile(positionID: order.requestID, expectedRevision: opened.revision,
        batch: replay, settledAt: settledAt))
      XCTAssertEqual(try Data(contentsOf: url), bytes)
      XCTAssertEqual(try store.snapshot().transactionHistory(for: order.account).count, 1)
      _ = try store.reconcile(positionID: order.requestID, expectedRevision: opened.revision, batch: replay, settledAt: settledAt)
      let restored = try LocalFuturesAccountRepository(fileURL: url).snapshot()
      let history = try restored.transactionHistory(for: order.account)
      XCTAssertEqual(history.count, 2)
      let liquidation = try XCTUnwrap(history.last)
      XCTAssertEqual(liquidation.kind, .liquidation)
      XCTAssertEqual(liquidation.realizedPnL, -100_000)
      XCTAssertEqual(liquidation.price, side == .long ? 90_000_000 : 110_000_000)
      XCTAssertEqual(liquidation.intervalStart, 60_000)
      XCTAssertEqual(liquidation.intervalEndExclusive, 120_000)
      XCTAssertEqual(liquidation.recordedAt, settledAt)
      let after = try restored.valuation(for: order.account, quotes: [:], now: order.executedAt)
      XCTAssertEqual(after.realizedPnL, -100_000)
      XCTAssertEqual(after.totalEquity, 9_900_000)
      XCTAssertEqual(after.availableBalance, 9_900_000)
      XCTAssertEqual(after.reservedMargin, 0)
      XCTAssertEqual(after.unrealizedPnL, 0)
      XCTAssertThrowsError(try store.reconcile(positionID: order.requestID, expectedRevision: restored.revision,
        batch: replay, settledAt: settledAt))
      XCTAssertEqual(try store.snapshot().transactionHistory(for: order.account), history)
    }
  }

  func testDomesticLifecycleRequestsHistoryOnlyAfterSavedCheckpoint() throws {
    let order = domesticFuturesOrder(price: 100)
    try store.ensureAccount(order.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let opened = try store.openTestPosition(order, expectedRevision: store.snapshot().revision)
    _ = try store.reconcile(positionID: order.requestID, expectedRevision: opened.revision,
      batch: batch(opened.positions[0]), settledAt: settledAt)
    let provider = ReplayProvider(instrument: order.instrument)
    provider.fundingHook = { XCTFail("Domestic replay must not request funding") }
    provider.timestamp = 185_000
    provider.candles = [candle(120_000)]
    let service = FuturesReconciliationService(store: { LocalFuturesAccountRepository(fileURL: self.url) },
      provider: { _ in provider }, now: { Date(timeIntervalSince1970: 185) })
    let finished = expectation(description: "resume domestic checkpoint")
    let subscription = service.status.subscribe(onNext: { status in
      if case .finished(let results) = status, !results.isEmpty {
        XCTAssertEqual(results[0].verifiedThrough, 180_000)
        XCTAssertEqual(results[0].hold, .currentInterval)
        finished.fulfill()
      }
    })
    defer { subscription.dispose(); service.suspend() }
    service.refresh()
    wait(for: [finished], timeout: 3)
    XCTAssertEqual(provider.candleStarts, [120_000])
    XCTAssertEqual(try store.snapshot().positions[0].order.executedAt, order.executedAt)
  }

  func testDomesticPreparedOrderRejectsDifferentExecutionPriceWithoutWriting() throws {
    let order = domesticFuturesOrder()
    try store.ensureAccount(order.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let snapshot = try store.snapshot()
    let bytes = try Data(contentsOf: url)
    let preflight = FuturesOrderPreflight(account: order.account, instrument: order.instrument,
      revision: snapshot.revision, mark: .init(instrument: order.instrument, price: 99_000_000, timestamp: 60_000))
    XCTAssertThrowsError(try store.openPosition(order, preflight: preflight, now: order.executedAt))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
  }

  func testDomesticFundingAndFailedCheckpointWritePreserveFile() throws {
    let order = domesticFuturesOrder(exchange: .bithumb)
    try store.ensureAccount(order.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let opened = try store.openTestPosition(order, expectedRevision: store.snapshot().revision)
    let position = opened.positions[0]
    let safe = FuturesMarkCandle(openTime: 60_000, closeTime: 119_999,
      open: 100_000_000, high: 105_000_000, low: 95_000_000, close: 100_000_000)
    let bytes = try Data(contentsOf: url)
    let foreignFunding = batch(position, candles: [safe], funding: [.init(timestamp: 60_001, rate: 0, markPrice: 100_000_000)])
    XCTAssertThrowsError(try store.reconcile(positionID: position.id, expectedRevision: opened.revision,
      batch: foreignFunding, settledAt: settledAt))
    let failing = LocalFuturesAccountRepository(fileURL: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    XCTAssertThrowsError(try failing.reconcile(positionID: position.id, expectedRevision: opened.revision,
      batch: batch(position, candles: [safe]), settledAt: settledAt))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    XCTAssertEqual(try store.snapshot(), opened)
  }

  func testPartialEntryCandleSafeRangeAdvancesButCrossingHolds() throws {
    let position = try FuturesCalculator.open(futuresOrder(date: Date(timeIntervalSince1970: 60.040)))
    let initial = try FuturesReconciliationState.initial(for: position)
    let safe = try FuturesReplayCalculator.replay(batch(position, start: initial.verifiedThrough), position: position, state: initial, settledAt: settledAt)
    XCTAssertEqual(safe.state.verifiedThrough, 120000)
    let risk = try FuturesReplayCalculator.replay(batch(position, start: initial.verifiedThrough, candles: [candle(low: 80)]), position: position, state: initial, settledAt: settledAt)
    XCTAssertEqual(risk.hold, .ambiguousEntryCandle)
    XCTAssertEqual(risk.state, initial)
  }

  func testShortUsesHighRatherThanClose() throws {
    let position = try FuturesCalculator.open(futuresOrder(side: .short, date: Date(timeIntervalSince1970: 60)))
    let result = try FuturesReplayCalculator.replay(batch(position, candles: [candle(high: 110)]), position: position,
                                                   state: .initial(for: position), settledAt: settledAt)
    XCTAssertNotNil(result.state.liquidation)
  }

  func testFundingUsesActualTimeAndPriceOnce() throws {
    let snapshot = try opened()
    let position = snapshot.positions[0]
    let event = FuturesFundingEvent(timestamp: 60001, rate: Decimal(string: "0.001")!, markPrice: 100)
    let result = try store.reconcile(positionID: position.id, expectedRevision: snapshot.revision,
                                     batch: batch(position, funding: [event]), settledAt: settledAt)
    XCTAssertEqual(result.state.netFunding, -1)
    XCTAssertEqual(result.state.fundingReceipts[0].event.timestamp, 60001)
    XCTAssertEqual(try store.snapshot().accounts[0].availableBalance, 900)
    XCTAssertThrowsError(try store.reconcile(positionID: position.id, expectedRevision: store.snapshot().revision,
                                            batch: batch(position, funding: [event]), settledAt: settledAt))
    XCTAssertEqual(try store.snapshot().reconciliations[0].netFunding, -1)
  }

  func testAmbiguousFundingDoesNotPartiallyCommitCandle() throws {
    let position = try position
    let initial = try FuturesReconciliationState.initial(for: position)
    for event in [FuturesFundingEvent(timestamp: 60000, rate: 0, markPrice: 100),
                  FuturesFundingEvent(timestamp: 60001, rate: Decimal(string: "0.2")!, markPrice: 100)] {
      let result = try FuturesReplayCalculator.replay(batch(position, funding: [event]), position: position, state: initial, settledAt: settledAt)
      XCTAssertEqual(result.hold, .ambiguousFundingOrder)
      XCTAssertEqual(result.state, initial)
    }
  }

  func testSplittingPagesMatchesSingleReplay() throws {
    let position = try position
    let initial = try FuturesReconciliationState.initial(for: position)
    let event = FuturesFundingEvent(timestamp: 120001, rate: Decimal(string: "-0.001")!, markPrice: 100)
    let whole = try FuturesReplayCalculator.replay(batch(position, end: 180000, candles: [candle(), candle(120000)], funding: [event]), position: position, state: initial, settledAt: settledAt)
    let first = try FuturesReplayCalculator.replay(batch(position), position: position, state: initial, settledAt: settledAt)
    let second = try FuturesReplayCalculator.replay(batch(position, start: 120000, end: 180000, candles: [candle(120000)], funding: [event]), position: position, state: first.state, settledAt: settledAt)
    XCTAssertEqual(whole.state, second.state)
    XCTAssertEqual(second.state.netFunding, 1)
  }

  func testSafePrefixPersistsBeforeAmbiguousFunding() throws {
    let snapshot = try opened()
    let position = snapshot.positions[0]
    let event = FuturesFundingEvent(timestamp: 120001, rate: Decimal(string: "0.2")!, markPrice: 100)
    let result = try store.reconcile(positionID: position.id, expectedRevision: snapshot.revision,
                                     batch: batch(position, end: 180000, candles: [candle(), candle(120000)], funding: [event]), settledAt: settledAt)
    XCTAssertEqual(result.state.verifiedThrough, 120000)
    XCTAssertEqual(result.hold, .ambiguousFundingOrder)
    XCTAssertEqual(try store.snapshot().reconciliations[0], result.state)
    XCTAssertEqual(result.state.fundingReceipts.count, 0)
  }

  func testMissingDuplicateNaNAndWrongInstrumentNeverAdvance() throws {
    let position = try position
    let initial = try FuturesReconciliationState.initial(for: position)
    for candles in [[], [candle(), candle()], [candle(low: .nan)], [candle(120000)]] {
      XCTAssertThrowsError(try FuturesReplayCalculator.replay(batch(position, candles: candles), position: position, state: initial, settledAt: settledAt))
    }
    let event = FuturesFundingEvent(timestamp: 60001, rate: 0, markPrice: 100)
    XCTAssertThrowsError(try FuturesReplayCalculator.replay(batch(position, funding: [event, event]), position: position, state: initial, settledAt: settledAt))
    let invalid = FuturesReplayBatch(instrument: .init(exchange: .okx, product: .perpetual, rawSymbol: "BTCUSDT", settlementCurrency: .usdt), start: 60000, endExclusive: 120000, candles: [candle()], funding: [])
    XCTAssertThrowsError(try FuturesReplayCalculator.replay(invalid, position: position, state: initial, settledAt: settledAt))
  }

  func testFailedWriteAndRewardRevisionConflictPreserveState() throws {
    let snapshot = try opened()
    let position = snapshot.positions[0]
    let bytes = try Data(contentsOf: url)
    let failing = LocalFuturesAccountRepository(fileURL: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    XCTAssertThrowsError(try failing.reconcile(positionID: position.id, expectedRevision: snapshot.revision, batch: batch(position), settledAt: settledAt))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    try store.applyAdvertisementReward(AdRewardClaim(account: position.order.account))
    XCTAssertThrowsError(try store.reconcile(positionID: position.id, expectedRevision: snapshot.revision, batch: batch(position), settledAt: settledAt))
    XCTAssertEqual(try store.snapshot().accounts[0].availableBalance, 1900)
    XCTAssertEqual(try store.snapshot().reconciliations, snapshot.reconciliations)
  }

  func testConcurrentReconciliationCommitsOnlyOnce() throws {
    let snapshot = try opened()
    let position = snapshot.positions[0]
    DispatchQueue.concurrentPerform(iterations: 20) { _ in
      do { _ = try store.reconcile(positionID: position.id, expectedRevision: snapshot.revision, batch: batch(position), settledAt: settledAt) }
      catch LocalFuturesAccountRepository.StoreError.revisionConflict { }
      catch { XCTFail("Unexpected error: \(error)") }
    }
    XCTAssertEqual(try store.snapshot().revision, snapshot.revision + 1)
    XCTAssertEqual(try store.snapshot().reconciliations[0].verifiedThrough, 120000)
  }

  func testLegacyPositionMigrationAndSchemaFourMissingStatePreservation() throws {
    let snapshot = try opened()
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
    object["schemaVersion"] = 3
    object.removeValue(forKey: "reconciliations")
    try JSONSerialization.data(withJSONObject: object).write(to: url)
    XCTAssertEqual(try store.snapshot().reconciliations[0].verifiedThrough, 60000)
    object["schemaVersion"] = 4
    let bytes = try JSONSerialization.data(withJSONObject: object)
    try bytes.write(to: url)
    XCTAssertThrowsError(try store.snapshot())
    XCTAssertEqual(try Data(contentsOf: url), bytes)
  }

  func testLiquidatedPositionAllowsNewEntryButOldRequestDoesNotReopen() throws {
    let snapshot = try opened()
    let old = snapshot.positions[0]
    _ = try store.reconcile(positionID: old.id, expectedRevision: snapshot.revision, batch: batch(old, candles: [candle(low: 80)]), settledAt: settledAt)
    let liquidated = try store.snapshot()
    XCTAssertEqual(try store.openTestPosition(old.order, expectedRevision: snapshot.revision), liquidated)
    let new = try store.openTestPosition(futuresOrder(date: settledAt), expectedRevision: liquidated.revision)
    XCTAssertEqual(new.positions.count, 2)
    XCTAssertEqual(new.accounts[0].availableBalance, 800)
  }

  func testUnverifiedExistingAccountBlocksAnotherInstrumentOrder() throws {
    let snapshot = try opened()
    let old = snapshot.positions[0].order
    let order = FuturesOpeningOrder(requestID: UUID(), account: old.account,
      instrument: .init(exchange: .binance, product: .perpetual, rawSymbol: "ETHUSDT", settlementCurrency: .usdt),
      side: old.side, margin: old.margin, leverage: old.leverage, executionPrice: old.executionPrice,
      entryFeeRate: old.entryFeeRate, executedAt: settledAt, contractRules: old.contractRules)
    XCTAssertThrowsError(try store.openTestPosition(order, expectedRevision: snapshot.revision)) {
      XCTAssertEqual($0 as? FuturesOrderPreflightError, .held(.currentInterval))
    }
    XCTAssertEqual(try store.snapshot(), snapshot)
  }

  func testLifecycleRewardDuringRequestRejectsOldRevision() throws {
    let snapshot = try opened()
    let provider = ReplayProvider(instrument: snapshot.positions[0].order.instrument)
    provider.candles = [candle()]
    provider.fundingHook = {
      do { try self.store.applyAdvertisementReward(AdRewardClaim(account: snapshot.positions[0].order.account)) }
      catch { XCTFail("Reward failed: \(error)") }
    }
    let service = FuturesReconciliationService(store: { self.store }, provider: { _ in provider }, now: { Date(timeIntervalSince1970: 125) })
    let finished = expectation(description: "revision conflict")
    let subscription = service.status.subscribe(onNext: { status in
      if case .finished(let results) = status, !results.isEmpty {
        XCTAssertEqual(results[0].hold, .revisionChanged)
        finished.fulfill()
      }
    })
    defer { subscription.dispose() }
    service.refresh()
    wait(for: [finished], timeout: 3)
    XCTAssertEqual(try store.snapshot().accounts[0].availableBalance, 1900)
    XCTAssertEqual(try store.snapshot().reconciliations[0].verifiedThrough, 60000)
  }

  func testWorkLimitSavesCheckpointForNextActivation() throws {
    let snapshot = try opened()
    let provider = ReplayProvider(instrument: snapshot.positions[0].order.instrument)
    provider.timestamp = 30_060_000
    provider.generateCandles = true
    let service = FuturesReconciliationService(store: { self.store }, provider: { _ in provider },
                                               now: { Date(timeIntervalSince1970: 30060) }, maximumPages: 1)
    let finished = expectation(description: "bounded replay")
    let subscription = service.status.subscribe(onNext: { status in
      if case .finished(let results) = status, !results.isEmpty {
        XCTAssertEqual(results[0].hold, .workLimit)
        XCTAssertEqual(results[0].verifiedThrough, 30_000_000)
        finished.fulfill()
      }
    })
    defer { subscription.dispose() }
    service.refresh()
    wait(for: [finished], timeout: 3)
    XCTAssertEqual(try store.snapshot().reconciliations[0].verifiedThrough, 30_000_000)
  }

  func testPreparedOrderCommitsOnceAndRejectsChangedRevision() throws {
    let order = futuresOrder(date: Date(timeIntervalSince1970: 125))
    try store.ensureAccount(order.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let before = try store.snapshot()
    let preflight = FuturesOrderPreflight(account: order.account, instrument: order.instrument, revision: before.revision,
      mark: .init(instrument: order.instrument, price: 100, timestamp: 125000))
    let after = try store.openPosition(order, preflight: preflight, now: order.executedAt)
    XCTAssertEqual(after.accounts[0].availableBalance, 900)
    XCTAssertEqual(try store.openPosition(order, preflight: preflight, now: order.executedAt), after)
    XCTAssertThrowsError(try preflight.validate(snapshot: after, now: order.executedAt)) {
      XCTAssertEqual($0 as? LocalFuturesAccountRepository.StoreError, .revisionConflict)
    }
  }

  func testPreflightRejectsCurrentGapFutureAndExpiredMark() throws {
    let snapshot = try opened()
    let position = snapshot.positions[0]
    for timestamp in [Int64(60000), 125000, 126000] {
      let preflight = FuturesOrderPreflight(account: position.order.account, instrument: position.order.instrument,
        revision: snapshot.revision, mark: .init(instrument: position.order.instrument, price: 100, timestamp: timestamp))
      XCTAssertThrowsError(try preflight.validate(snapshot: snapshot, now: Date(timeIntervalSince1970: 125)))
    }
    XCTAssertEqual(try store.snapshot(), snapshot)
  }

  func testPrepareEmptyAccountAndGuardPreparedSaveAfterReward() throws {
    let order = futuresOrder(date: Date(timeIntervalSince1970: 125))
    try store.ensureAccount(order.account)
    let provider = ReplayProvider(instrument: order.instrument)
    let service = FuturesReconciliationService(store: { self.store }, provider: { _ in provider }, now: { order.executedAt })
    let finished = expectation(description: "prepared")
    let subscription = service.prepareOrder(account: order.account, instrument: order.instrument).subscribe(onSuccess: { preflight in
      do {
        try self.store.applyAdvertisementReward(AdRewardClaim(account: order.account))
        XCTAssertThrowsError(try self.store.openPosition(order, preflight: preflight, now: order.executedAt)) {
          XCTAssertEqual($0 as? LocalFuturesAccountRepository.StoreError, .revisionConflict)
        }
      } catch { XCTFail("Unexpected error: \(error)") }
      finished.fulfill()
    }, onFailure: { error in XCTFail("Preparation failed: \(error)"); finished.fulfill() })
    defer { subscription.dispose() }
    wait(for: [finished], timeout: 3)
    XCTAssertEqual(try store.snapshot().accounts[0].availableBalance, 1000)
    XCTAssertTrue(try store.snapshot().positions.isEmpty)
  }

  func testPrepareExistingPositionDoesNotTreatCurrentQuoteAsHistory() throws {
    let snapshot = try opened()
    let position = snapshot.positions[0]
    let provider = ReplayProvider(instrument: position.order.instrument)
    provider.candles = [candle()]
    let service = FuturesReconciliationService(store: { self.store }, provider: { _ in provider }, now: { Date(timeIntervalSince1970: 125) })
    let finished = expectation(description: "gap rejected")
    let subscription = service.prepareOrder(account: position.order.account, instrument: position.order.instrument).subscribe(onSuccess: { _ in
      XCTFail("Current interval must not become verified"); finished.fulfill()
    }, onFailure: { error in
      XCTAssertEqual(error as? FuturesOrderPreflightError, .held(.currentInterval))
      finished.fulfill()
    })
    defer { subscription.dispose() }
    wait(for: [finished], timeout: 3)
    XCTAssertEqual(try store.snapshot().reconciliations[0].verifiedThrough, 120000)
  }

  func testAutomaticContinuationFinishesWithoutAnotherActivation() throws {
    let snapshot = try opened()
    let provider = ReplayProvider(instrument: snapshot.positions[0].order.instrument)
    provider.timestamp = 30_060_000
    provider.generateCandles = true
    let service = FuturesReconciliationService(store: { self.store }, provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 30060) }, maximumPages: 1)
    let finished = expectation(description: "automatically continued")
    let subscription = service.status.subscribe(onNext: { status in
      if case .finished(let results) = status, results.first?.hold == .currentInterval {
        XCTAssertEqual(results[0].verifiedThrough, 30_060_000)
        finished.fulfill()
      }
    })
    defer { subscription.dispose(); service.suspend() }
    service.refresh()
    wait(for: [finished], timeout: 4)
    XCTAssertEqual(provider.quoteRequests, 2)
  }

  func testSuspensionCancelsScheduledContinuationAndResumesFromSavedPoint() throws {
    let snapshot = try opened()
    let provider = ReplayProvider(instrument: snapshot.positions[0].order.instrument)
    provider.timestamp = 30_060_000
    provider.generateCandles = true
    let service = FuturesReconciliationService(store: { self.store }, provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 30060) }, maximumPages: 1)
    let paused = expectation(description: "paused")
    let first = service.status.subscribe(onNext: { status in
      if case .finished(let results) = status, results.first?.hold == .workLimit { service.suspend() }
      if case .paused = status { paused.fulfill() }
    })
    service.refresh()
    wait(for: [paused], timeout: 3)
    first.dispose()
    let delay = expectation(description: "scheduled continuation stays cancelled")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { delay.fulfill() }
    wait(for: [delay], timeout: 2)
    XCTAssertEqual(provider.quoteRequests, 1)
    XCTAssertEqual(try store.snapshot().reconciliations[0].verifiedThrough, 30_000_000)
    let finished = expectation(description: "resumed")
    let second = service.status.subscribe(onNext: { status in
      if case .finished(let results) = status, results.first?.hold == .currentInterval { finished.fulfill() }
    })
    defer { second.dispose() }
    service.refresh()
    wait(for: [finished], timeout: 3)
    XCTAssertEqual(try store.snapshot().reconciliations[0].verifiedThrough, 30_060_000)
  }

  func testLifecycleRefreshCoalescesAndDoesNotSkipCurrentInterval() throws {
    let snapshot = try opened()
    let provider = ReplayProvider(instrument: snapshot.positions[0].order.instrument)
    provider.candles = [candle()]
    let service = FuturesReconciliationService(store: { self.store }, provider: { _ in provider }, now: { Date(timeIntervalSince1970: 125) })
    let finished = expectation(description: "refresh finished")
    let subscription = service.status.subscribe(onNext: { status in
      if case .finished(let results) = status, !results.isEmpty {
        XCTAssertEqual(results[0].verifiedThrough, 120000)
        XCTAssertEqual(results[0].hold, .currentInterval)
        finished.fulfill()
      }
    })
    defer { subscription.dispose() }
    service.refresh()
    service.refresh()
    wait(for: [finished], timeout: 3)
    XCTAssertEqual(try store.snapshot().reconciliations[0].verifiedThrough, 120000)
    XCTAssertEqual(provider.quoteRequests, 1)
  }

  func testLifecycleIncompleteFundingPageAndStaleQuoteHold() throws {
    let snapshot = try opened()
    for stale in [false, true] {
      let provider = ReplayProvider(instrument: snapshot.positions[0].order.instrument)
      provider.candles = [candle()]
      provider.nextFunding = 60001
      provider.timestamp = stale ? 60000 : 125000
      let service = FuturesReconciliationService(store: { self.store }, provider: { _ in provider }, now: { Date(timeIntervalSince1970: 125) })
      let finished = expectation(description: "held")
      let subscription = service.status.subscribe(onNext: { status in
        if case .finished(let results) = status, !results.isEmpty {
          XCTAssertEqual(results[0].hold, stale ? .staleQuote : .missingHistory)
          finished.fulfill()
        }
      })
      service.refresh()
      wait(for: [finished], timeout: 3)
      subscription.dispose()
      XCTAssertEqual(try store.snapshot().reconciliations[0].verifiedThrough, 60000)
    }
  }
}

private final class ReplayProvider: FuturesMarketDataProviding {
  let instrument: TradingInstrumentID
  var candles: [FuturesMarkCandle] = []
  var timestamp: Int64 = 125000
  var nextFunding: Int64?
  var fundingHook: (() -> Void)?
  var generateCandles = false
  private let lock = NSLock()
  private var starts: [Int64] = []
  var candleStarts: [Int64] { lock.lock(); defer { lock.unlock() }; return starts }
  private var requests = 0
  var quoteRequests: Int { lock.lock(); defer { lock.unlock() }; return requests }
  init(instrument: TradingInstrumentID) { self.instrument = instrument }
  func markQuote(_ instrument: TradingInstrumentID) -> Single<FuturesMarkQuote> {
    lock.lock(); requests += 1; lock.unlock()
    return .just(.init(instrument: instrument, price: 100, timestamp: timestamp))
  }
  func contract(_ instrument: TradingInstrumentID) -> Single<FuturesMarketContract> { .error(FuturesMarketDataError.invalidRequest) }
  func markCandles(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<FuturesHistoryPage<FuturesMarkCandle>> {
    lock.lock(); starts.append(start); lock.unlock()
    let values = generateCandles ? stride(from: start, to: endExclusive, by: 60_000).map {
      FuturesMarkCandle(openTime: $0, closeTime: $0 + 59999, open: 100, high: 105, low: 95, close: 100)
    } : candles
    return .just(.init(instrument: instrument, values: values, nextStartTime: nil))
  }
  func funding(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<FuturesHistoryPage<FuturesFundingEvent>> {
    fundingHook?()
    return .just(.init(instrument: instrument, values: [], nextStartTime: nextFunding))
  }
}

final class FuturesPreUIIntegrationTests: XCTestCase {
  private var directory: URL!
  private var store: LocalFuturesAccountRepository { .init(fileURL: directory.appendingPathComponent("accounts.json")) }
  override func setUpWithError() throws { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
  override func tearDownWithError() throws {
    if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
  }
  private func value<T>(_ single: Single<T>) throws -> T {
    let finished = expectation(description: "trading result")
    var result: Result<T, Error>?
    let disposable = single.observe(on: MainScheduler.instance).subscribe(onSuccess: { result = .success($0); finished.fulfill() },
      onFailure: { result = .failure($0); finished.fulfill() })
    defer { disposable.dispose() }
    wait(for: [finished], timeout: 5)
    return try XCTUnwrap(result).get()
  }

  func testUIAccountPreparationStartsAtZeroAndPreservesRewardOnRevisit() throws {
    let order = domesticFuturesOrder()
    let service = FuturesReconciliationService(store: { self.store }, provider: { _ in nil })
    let useCase = FuturesTradingUseCase(store: { self.store }, reconciliation: service)
    defer { service.suspend() }
    XCTAssertEqual(try value(useCase.accountSnapshot(for: order.account)).accounts.first?.availableBalance, 0)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    XCTAssertEqual(try value(useCase.accountSnapshot(for: order.account)).accounts.first?.availableBalance, 10_000_000)
    XCTAssertThrowsError(try value(useCase.accountSnapshot(for: .init(exchange: .upbit, product: .perpetual, currency: .btc))))
  }

  func testUIFacingUseCaseAddsClosesAndRetriesWithStableRequestIDs() throws {
    let first = domesticFuturesOrder(margin: 100, price: 100)
    try store.ensureAccount(first.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: first.account))
    try store.openTestPosition(first, expectedRevision: store.snapshot().revision)
    let provider = DetailReplayProvider(instrument: first.instrument, timestamp: 65_123, adverse: 100)
    let service = FuturesReconciliationService(store: { self.store }, provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) })
    let useCase = FuturesTradingUseCase(store: { self.store }, reconciliation: service, now: { Date(timeIntervalSince1970: 66) })
    defer { service.suspend() }
    let id = UUID()
    let added = try value(useCase.open(requestID: id, account: first.account, instrument: first.instrument,
      side: .long, margin: 100, leverage: 10, addingTo: first.requestID))
    XCTAssertEqual(added.positions[0].executions.count, 2)
    XCTAssertEqual(added.positions[0].quantity, 20)
    XCTAssertEqual(added.reconciliations[0].verifiedThrough, 66_000)
    XCTAssertEqual(try value(useCase.open(requestID: id, account: first.account, instrument: first.instrument,
      side: .long, margin: 100, leverage: 10, addingTo: first.requestID)), added)
    XCTAssertThrowsError(try value(useCase.open(requestID: id, account: first.account, instrument: first.instrument,
      side: .short, margin: 100, leverage: 10)))
    let closeID = UUID()
    let closed = try value(useCase.close(requestID: closeID, positionID: first.requestID))
    XCTAssertEqual(closed.accounts[0].availableBalance, 10_000_000)
    XCTAssertEqual(try closed.transactionHistory(for: first.account).map(\.kind), [.opening, .addition, .closing])
    XCTAssertEqual(try value(useCase.close(requestID: closeID, positionID: first.requestID)), closed)
  }

  func testDipDuringPreflightLiquidatesInsteadOfAddingOrClosing() throws {
    let first = domesticFuturesOrder(margin: 100, price: 100)
    try store.ensureAccount(first.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: first.account))
    try store.openTestPosition(first, expectedRevision: store.snapshot().revision)
    let provider = DetailReplayProvider(instrument: first.instrument, timestamp: 65_123, adverse: 80)
    let service = FuturesReconciliationService(store: { self.store }, provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) })
    let useCase = FuturesTradingUseCase(store: { self.store }, reconciliation: service, now: { Date(timeIntervalSince1970: 66) })
    defer { service.suspend() }
    XCTAssertThrowsError(try value(useCase.open(requestID: UUID(), account: first.account, instrument: first.instrument,
      side: .long, margin: 100, leverage: 10, addingTo: first.requestID)))
    XCTAssertNotNil(try store.snapshot().reconciliations[0].liquidation)
    XCTAssertEqual(try store.snapshot().positions[0].executions.count, 1)
    XCTAssertThrowsError(try value(useCase.close(requestID: UUID(), positionID: first.requestID)))
    XCTAssertEqual(try store.snapshot().accounts[0].availableBalance, 9_999_900)
  }

  func testOrderWaitsForAutomaticRefreshThenRunsFreshPreflight() throws {
    let order = domesticFuturesOrder(margin: 100, price: 100)
    try store.ensureAccount(order.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    try store.openTestPosition(order, expectedRevision: store.snapshot().revision)
    let gate = PublishSubject<FuturesMarkQuote>()
    let started = expectation(description: "automatic quote started")
    var requests = 0
    var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_000, adverse: 100)
    provider.quoteOverride = {
      requests += 1
      if requests == 1 {
        return gate.take(1).asSingle().do(onSubscribe: { started.fulfill() })
      }
      return .just(.init(instrument: order.instrument, price: 100, timestamp: 65_000))
    }
    let service = FuturesReconciliationService(store: { self.store }, provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) })
    defer { service.suspend() }
    service.refresh()
    wait(for: [started], timeout: 3)
    let prepared = expectation(description: "order prepared after refresh")
    let subscription = service.prepareOrder(account: order.account, instrument: order.instrument).subscribe(onSuccess: { result in
      XCTAssertEqual(result.instrument, order.instrument)
      XCTAssertGreaterThan(requests, 1)
      prepared.fulfill()
    }, onFailure: { error in XCTFail("Queued preparation failed: \(error)"); prepared.fulfill() })
    defer { subscription.dispose() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      gate.onNext(.init(instrument: order.instrument, price: 100, timestamp: 65_000))
    }
    wait(for: [prepared], timeout: 3)
  }

  func testSuspendedServiceRejectsNewPreparationWithoutMutation() throws {
    let order = domesticFuturesOrder(margin: 100, price: 100)
    try store.ensureAccount(order.account)
    let before = try store.snapshot()
    let provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_000, adverse: 100)
    let service = FuturesReconciliationService(store: { self.store }, provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) })
    service.suspend()
    XCTAssertThrowsError(try value(service.prepareOrder(account: order.account, instrument: order.instrument))) {
      XCTAssertEqual($0 as? FuturesOrderPreflightError, .reconciliationInProgress)
    }
    XCTAssertEqual(try store.snapshot(), before)
  }

  func testLastQuoteMillisecondIsIncludedInLiquidationReplay() throws {
    let first = domesticFuturesOrder(margin: 100, price: 100)
    try store.ensureAccount(first.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: first.account))
    try store.openTestPosition(first, expectedRevision: store.snapshot().revision)
    let provider = DetailReplayProvider(instrument: first.instrument, timestamp: 65_123, adverse: 80, adverseAtEndOnly: true)
    let service = FuturesReconciliationService(store: { self.store }, provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) })
    defer { service.suspend() }
    _ = try value(service.prepareOrder(account: first.account, instrument: first.instrument))
    XCTAssertEqual(try store.snapshot().reconciliations[0].liquidation?.intervalStart, 65_123)
  }

}

private struct DetailReplayProvider: FuturesDetailedMarketDataProviding {
  let instrument: TradingInstrumentID
  let timestamp: Int64
  let adverse: Decimal
  var adverseAtEndOnly = false
  var quoteOverride: (() -> Single<FuturesMarkQuote>)?
  func markQuote(_ instrument: TradingInstrumentID) -> Single<FuturesMarkQuote> {
    quoteOverride?() ?? .just(.init(instrument: instrument, price: 100, timestamp: timestamp))
  }
  func contract(_ instrument: TradingInstrumentID) -> Single<FuturesMarketContract> { .error(FuturesMarketDataError.invalidRequest) }
  func funding(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<FuturesHistoryPage<FuturesFundingEvent>> {
    XCTFail("Domestic funding must not be requested")
    return .just(.init(instrument: instrument, values: [], nextStartTime: nil))
  }
  func markCandles(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<FuturesHistoryPage<FuturesMarkCandle>> {
    .just(.init(instrument: instrument, values: stride(from: start, to: endExclusive, by: 60_000).map {
      .init(openTime: $0, closeTime: $0 + 59_999, open: 100, high: 100, low: adverse, close: 100)
    }, nextStartTime: nil))
  }
  func boundaryHistory(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64,
                       initialEntry: Bool) -> Single<FuturesReplayBatch> {
    var candles: [FuturesMarkCandle] = []
    if adverseAtEndOnly, endExclusive - start > 1 {
      candles.append(.init(openTime: start, closeTime: endExclusive - 2, open: 100, high: 100, low: 100, close: 100))
    }
    candles.append(.init(openTime: adverseAtEndOnly ? endExclusive - 1 : start,
      closeTime: endExclusive - 1, open: 100, high: 100, low: adverse, close: 100))
    return .just(.init(instrument: instrument, start: start, endExclusive: endExclusive,
      candles: candles, funding: [], detailed: true))
  }
}
