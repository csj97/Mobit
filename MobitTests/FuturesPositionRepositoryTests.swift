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
    XCTAssertEqual(after.ledger[0].reservedMarginChange, 99)
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
    let time = try FuturesHistoryCheckState.milliseconds(order.executedAt)
    let bytes = try Data(contentsOf: url)
    for quote in [
      FuturesMarkQuote(instrument: order.instrument, price: order.executionPrice, timestamp: time - 5001),
      FuturesMarkQuote(instrument: order.instrument, price: order.executionPrice, timestamp: time + 1),
      FuturesMarkQuote(instrument: order.instrument, price: order.executionPrice + 1, timestamp: time),
      FuturesMarkQuote(instrument: order.instrument, price: 0, timestamp: time)
    ] {
      // 주문 시 확인할 가격·체결 시각·계좌 버전과 포지션 검증 상태다.
      let orderCheck = FuturesOrderCheck(account: order.account, instrument: order.instrument,
        revision: before.revision, mark: quote)
      XCTAssertThrowsError(try store.openPosition(order, orderCheck: orderCheck, now: order.executedAt))
      XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    let valid = FuturesOrderCheck(account: order.account, instrument: order.instrument,
      revision: before.revision, mark: .init(instrument: order.instrument, price: order.executionPrice, timestamp: time))
    XCTAssertNoThrow(try store.openPosition(order, orderCheck: valid, now: order.executedAt))
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
      XCTAssertEqual(migrated.schemaVersion, 6)
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
    let timestamp = try FuturesHistoryCheckState.milliseconds(order.executedAt)
    // 주문 시 확인할 가격·체결 시각·계좌 버전과 포지션 검증 상태다.
    let orderCheck = FuturesOrderCheck(account: order.account, instrument: order.instrument,
      revision: expectedRevision, mark: .init(instrument: order.instrument, price: order.executionPrice, timestamp: timestamp))
    return try openPosition(order, orderCheck: orderCheck, now: order.executedAt)
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
  private func open(_ side: FuturesSide = .long, price: Decimal = 100) throws -> FuturesPosition {
    let order = domesticFuturesOrder(side: side, margin: 100, price: price)
    try store.ensureAccount(order.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    return try store.openTestPosition(order, expectedRevision: store.snapshot().revision).positions[0]
  }
  private func verify(_ position: FuturesPosition, end: Int64, price: Decimal = 100) throws -> FuturesReplayResult {
    let snapshot = try store.snapshot()
    let start = try XCTUnwrap(snapshot.historyCheckStates.first(where: { $0.positionID == position.id })).verifiedThrough
    return try store.checkHistoryAndSettle(positionID: position.id, expectedRevision: snapshot.revision,
      batch: .init(instrument: position.order.instrument, start: start, endExclusive: end,
        candles: [.init(openTime: start, closeTime: end - 1, open: price, high: price, low: price, close: price)],
        funding: [], detailed: true), settledAt: Date(timeIntervalSince1970: Double(end) / 1000))
  }
  // 테스트에 필요한 시세·계좌 버전·검증 시점을 묶어 주문 검증 자료를 만든다.
  private func orderCheck(_ position: FuturesPosition, time: Int64, price: Decimal = 100,
                         proof: Bool = false) throws -> FuturesOrderCheck {
    .init(account: position.order.account, instrument: position.order.instrument, revision: try store.snapshot().revision,
      mark: .init(instrument: position.order.instrument, price: price, timestamp: time),
      verifiedPositions: proof ? [position.id: time] : [:])
  }

  func testAdditionPreservesFillsAndUsesWeightedCostRatherThanAverageOfPrices() throws {
    let first = try open()
    _ = try verify(first, end: 120_000)
    let second = domesticFuturesOrder(margin: 200, price: 200, date: Date(timeIntervalSince1970: 120))
    let ready = try orderCheck(first, time: 120_000, price: 200)
    let snapshot = try store.openPosition(second, orderCheck: ready, now: second.executedAt)
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
    XCTAssertEqual(try store.openPosition(second, orderCheck: ready, now: second.executedAt), snapshot)
    XCTAssertEqual(try store.snapshot(), snapshot)
  }

  func testDifferentDirectionLeverageAndUnverifiedAdditionPreserveFile() throws {
    let first = try open()
    let bytes = try Data(contentsOf: url)
    for order in [domesticFuturesOrder(side: .short, margin: 100, price: 100),
                  domesticFuturesOrder(leverage: 20, margin: 100, price: 100),
                  domesticFuturesOrder(margin: 100, price: 100, date: Date(timeIntervalSince1970: 61))] {
      XCTAssertThrowsError(try store.openPosition(order,
        orderCheck: orderCheck(first, time: FuturesHistoryCheckState.milliseconds(order.executedAt)), now: order.executedAt))
      XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
  }

  func testAdditionFailureAndAdRewardRaceDoNotSpendUnverifiedBalance() throws {
    let first = try open()
    _ = try verify(first, end: 120_000)
    let second = domesticFuturesOrder(margin: 100, price: 100, date: Date(timeIntervalSince1970: 120))
    let ready = try orderCheck(first, time: 120_000)
    let bytes = try Data(contentsOf: url)
    let failing = LocalFuturesAccountRepository(fileURL: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    XCTAssertThrowsError(try failing.openPosition(second, orderCheck: ready, now: second.executedAt))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    try store.applyAdvertisementReward(AdRewardClaim(account: first.order.account))
    XCTAssertThrowsError(try store.openPosition(second, orderCheck: ready, now: second.executedAt))
    XCTAssertEqual(try store.snapshot().positions[0].executions.count, 1)
  }

  func testSafeCurrentIntervalIsProofOnlyAndSurvivesAsCompletedMinuteCheckpoint() throws {
    let first = try open()
    let snapshot = try store.snapshot()
    let result = try verify(first, end: 65_123)
    XCTAssertEqual(result.state.verifiedThrough, 65_123)
    XCTAssertEqual(try store.snapshot(), snapshot)
    let ready = try orderCheck(first, time: 65_123, proof: true)
    XCTAssertNoThrow(try ready.validate(snapshot: snapshot, now: Date(timeIntervalSince1970: 66)))
    XCTAssertThrowsError(try orderCheck(first, time: 65_123).validate(snapshot: snapshot, now: Date(timeIntervalSince1970: 66)))
    XCTAssertThrowsError(try ready.validate(snapshot: snapshot, now: Date(timeIntervalSince1970: 71)))
  }

  func testLongAndShortManualCloseReturnMarginPlusPnLExactlyOnce() throws {
    for side in [FuturesSide.long, .short] {
      if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
      let position = try open(side)
      let price: Decimal = side == .long ? 105 : 95
      let result = try verify(position, end: 65_000, price: price)
      let ready = try orderCheck(position, time: result.state.verifiedThrough, price: price, proof: true)
      let close = FuturesClosingOrder(requestID: UUID(), positionID: position.id, executionPrice: price, executedAt: Date(timeIntervalSince1970: 65))
      let snapshot = try store.closePosition(close, orderCheck: ready, now: Date(timeIntervalSince1970: 66))
      XCTAssertEqual(snapshot.accounts[0].availableBalance, 10_000_050)
      XCTAssertFalse(snapshot.isActive(position))
      XCTAssertEqual(snapshot.closedPositions[0].realizedPnL, 50)
      XCTAssertEqual(try snapshot.transactionHistory(for: position.order.account).last?.kind, .closing)
      let value = try snapshot.valuation(for: position.order.account, quotes: [:], now: close.executedAt)
      XCTAssertEqual(value.realizedPnL, 50)
      XCTAssertEqual(value.totalEquity, 10_000_050)
      DispatchQueue.concurrentPerform(iterations: 12) { _ in
        do { XCTAssertEqual(try self.store.closePosition(close, orderCheck: ready, now: Date(timeIntervalSince1970: 80)), snapshot) }
        catch { XCTFail("Duplicate close failed: \(error)") }
      }
      XCTAssertEqual(try store.snapshot(), snapshot)
    }
  }

  func testClosingWriteFailurePreservesOpenPositionAndRetry() throws {
    let position = try open()
    _ = try verify(position, end: 65_000)
    let ready = try orderCheck(position, time: 65_000, proof: true)
    let order = FuturesClosingOrder(requestID: UUID(), positionID: position.id, executionPrice: 100, executedAt: Date(timeIntervalSince1970: 65))
    let bytes = try Data(contentsOf: url)
    let failing = LocalFuturesAccountRepository(fileURL: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    XCTAssertThrowsError(try failing.closePosition(order, orderCheck: ready, now: order.executedAt))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    XCTAssertEqual(try store.closePosition(order, orderCheck: ready, now: order.executedAt).accounts[0].availableBalance, 10_000_000)
  }

  func testCurrentIntervalLiquidationPersistsAndCannotBeManuallyClosed() throws {
    let position = try open()
    let ready = try orderCheck(position, time: 65_000, price: 100, proof: true)
    let result = try verify(position, end: 65_000, price: 80)
    XCTAssertNotNil(result.state.liquidation)
    XCTAssertEqual(try store.snapshot().historyCheckStates[0], result.state)
    let close = FuturesClosingOrder(requestID: UUID(), positionID: position.id, executionPrice: 100, executedAt: Date(timeIntervalSince1970: 65))
    XCTAssertThrowsError(try store.closePosition(close, orderCheck: ready, now: close.executedAt))
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
    XCTAssertTrue(value.needsHistoryCheck)
    for timestamp in [Int64(1), 66_000] {
      XCTAssertThrowsError(try snapshot.valuation(for: position.order.account,
        quotes: [instrument: .init(instrument: instrument, price: 100, timestamp: timestamp)], now: Date(timeIntervalSince1970: 65)))
    }
    XCTAssertThrowsError(try snapshot.valuation(for: position.order.account, quotes: [:], now: Date(timeIntervalSince1970: 65)))
  }

  func testLegacyUnverifiedMillisecondRoundingDoesNotMakeSavedAccountUnreadable() throws {
    let position = try open()
    let snapshot = try store.snapshot()
    var state = snapshot.historyCheckStates[0]
    state.verifiedThrough += 1
    let legacy = FuturesAccountSnapshot(schemaVersion: 4, revision: snapshot.revision, accounts: snapshot.accounts,
      rewardClaims: snapshot.rewardClaims, positions: snapshot.positions, ledger: snapshot.ledger, historyCheckStates: [state])
    try JSONEncoder().encode(legacy).write(to: url)
    let migrated = try store.snapshot()
    XCTAssertEqual(migrated.accounts, snapshot.accounts)
    XCTAssertEqual(migrated.historyCheckStates[0].verifiedThrough, try FuturesHistoryCheckState.milliseconds(position.order.executedAt))
  }

  func testEpochMillisecondsRoundTripDoesNotMoveEntryForward() throws {
    for time in [Int64(1_790_639_993_201), 1_780_272_034_123, 65_123] {
      XCTAssertEqual(try FuturesHistoryCheckState.milliseconds(Date(timeIntervalSince1970: Double(time) / 1000)), time)
    }
  }
}


extension DomesticFuturesTradingTests {
  private func closePart(
    _ position: FuturesPosition,
    quantity: Decimal,
    price: Decimal = 105,
    time: Int64 = 65_000,
    requestID: UUID = UUID(),
    repository: LocalFuturesAccountRepository? = nil
  ) throws -> FuturesAccountSnapshot {
    // 시트가 확인한 수량과 체결 시각을 담은 종료 주문이다.
    let order = FuturesClosingOrder(
      requestID: requestID,
      positionID: position.id,
      executionPrice: price,
      executedAt: Date(timeIntervalSince1970: Double(time) / 1000),
      quantity: quantity,
      expectedQuantity: position.quantity
    )
    return try (repository ?? store).closePosition(
      order,
      orderCheck: orderCheck(position, time: time, price: price, proof: true),
      now: order.executedAt
    )
  }

  func testPartialCloseUpdatesPositionCashHistoryAndTotalAssetsAtomically() throws {
    // 총 10개를 보유한 포지션 중 25%를 종료한다.
    let position = try open()
    // 원금 25와 손익 12.5가 잔액으로 돌아간다.
    let snapshot = try closePart(position, quantity: Decimal(string: "2.5")!)
    // 아직 열려 있는 잔여 포지션이다.
    let remaining = try XCTUnwrap(snapshot.positions.first)
    XCTAssertTrue(snapshot.isActive(remaining))
    XCTAssertEqual(remaining.quantity, Decimal(string: "7.5"))
    XCTAssertEqual(try remaining.margin, 75)
    XCTAssertEqual(remaining.entryTradeAmount, 750)
    XCTAssertEqual(try remaining.averageEntryPrice, 100)
    XCTAssertEqual(remaining.order.executedAt, position.order.executedAt)
    XCTAssertEqual(remaining.executions, position.executions)
    XCTAssertEqual(snapshot.accounts[0].availableBalance, Decimal(string: "9999937.5"))
    XCTAssertEqual(snapshot.ledger.last?.reservedMarginChange, -25)
    XCTAssertEqual(snapshot.ledger.count, 2)
    XCTAssertTrue(snapshot.closedPositions.isEmpty)
    XCTAssertEqual(snapshot.historyCheckStates[0].verifiedThrough, 65_000)
    // 잔여 평가손익과 실현 손익을 같은 스냅샷으로 집계한다.
    let valuation = try snapshot.valuation(
      for: position.order.account,
      quotes: [position.order.instrument: .init(instrument: position.order.instrument, price: 105, timestamp: 65_000)],
      now: Date(timeIntervalSince1970: 65)
    )
    XCTAssertEqual(valuation.reservedMargin, 75)
    XCTAssertEqual(valuation.unrealizedPnL, Decimal(string: "37.5"))
    XCTAssertEqual(valuation.realizedPnL, Decimal(string: "12.5"))
    XCTAssertEqual(valuation.totalEquity, 10_000_050)
    XCTAssertEqual(try valuation.positionsEquity, Decimal(string: "112.5"))
    XCTAssertEqual(try store.snapshot(), snapshot)
    XCTAssertEqual(try snapshot.transactionHistory(for: position.order.account).last?.quantity, Decimal(string: "2.5"))
  }

  func testRepeatedPartialCloseFinalCloseAndRetryNeverLoseOrDuplicateMargin() throws {
    // 나눗셈에 반복 소수가 생기는 수량 배분을 검증한다.
    let first = try open()
    // 동일 요청이 재시도돼도 부분 종료를 한 번만 적용한다.
    let requestID = UUID()
    // 첫 번째 종료 후 남은 수량이다.
    let one = try closePart(first, quantity: 3, price: 100, requestID: requestID)
    XCTAssertEqual(try closePart(first, quantity: 3, price: 100, requestID: requestID), one)
    // 첫 번째 종료의 남은 포지션이다.
    let second = one.positions[0]
    // 추가 부분 종료 후 남은 원금을 확인한다.
    let two = try closePart(second, quantity: 3, price: 100, time: 66_000)
    XCTAssertEqual(two.positions[0].quantity, 4)
    XCTAssertEqual(try two.positions[0].margin, 40)
    // 마지막 잔량은 정확히 모두 종료한다.
    let final = try closePart(two.positions[0], quantity: 4, price: 100, time: 67_000)
    XCTAssertFalse(final.isActive(final.positions[0]))
    XCTAssertEqual(final.accounts[0].availableBalance, 10_000_000)
    XCTAssertEqual(final.ledger.count, 4)
    XCTAssertEqual(try final.transactionHistory(for: first.order.account).filter { $0.kind == .closing }.map(\.quantity), [3, 3, 4])
    XCTAssertEqual(try store.snapshot(), final)
  }

  func testRepeatingDecimalMarginAllocationKeepsFinalAccountBalanceExact() throws {
    // 수량과 원금의 비율이 순환소수가 되는 포지션이다.
    let first = try open(price: 300)
    // 처음 종료한 1개에 해당하는 원금만 돌려준다.
    let one = try closePart(first, quantity: 1, price: 300)
    // 남은 수량에서 다시 1개만 종료한다.
    let two = try closePart(one.positions[0], quantity: 1, price: 300, time: 66_000)
    // 마지막 종료는 배분 차액까지 모두 반환한다.
    let final = try closePart(two.positions[0], quantity: two.positions[0].quantity, price: 300, time: 67_000)
    XCTAssertEqual(final.accounts[0].availableBalance, 10_000_000)
    XCTAssertEqual(try store.snapshot(), final)
  }

  func testPartialCloseThenAdditionPreservesOldProfitAndWeightedRemainingEntry() throws {
    // 최초 진입 중 절반을 종료한 뒤 다른 가격에 추가 진입한다.
    let first = try open()
    // 5개를 105에 종료해 25의 이익을 확정한다.
    let partial = try closePart(first, quantity: 5)
    // 이후 추가하는 5개 체결의 원가다.
    let added = domesticFuturesOrder(margin: 100, price: 200, date: Date(timeIntervalSince1970: 66))
    // 종료 이후에도 재검증된 주문만 합산한다.
    let snapshot = try store.openPosition(added, orderCheck: orderCheck(partial.positions[0], time: 66_000, price: 200, proof: true), now: added.executedAt)
    XCTAssertEqual(snapshot.positions[0].quantity, 10)
    XCTAssertEqual(try snapshot.positions[0].margin, 150)
    XCTAssertEqual(try snapshot.positions[0].averageEntryPrice, 150)
    // 과거 종료의 원금과 진입가는 이후 평균 진입가 변경의 영향을 받지 않는다.
    let record = try XCTUnwrap(snapshot.transactionHistory(for: first.order.account).first { $0.kind == .closing })
    XCTAssertEqual(record.realizedPnL, 25)
    XCTAssertEqual(record.margin, 50)
    XCTAssertEqual(record.entryPrice, 100)
    XCTAssertEqual(try FuturesText.shareUnit(record, position: snapshot.positions[0]).roi, 50)
    XCTAssertEqual(try store.snapshot(), snapshot)
  }

  func testLiquidationAfterPartialCloseLosesOnlyRemainingMarginAndKeepsRealizedProfit() throws {
    // 부분 종료로 원금 50과 이익 25를 이미 회수한 포지션이다.
    let first = try open()
    // 절반만 남겨 이후 청산을 검증한다.
    let snapshot = try closePart(first, quantity: 5)
    // 종료 이후 구간에서 남은 포지션만 청산한다.
    let result = try verify(snapshot.positions[0], end: 66_000, price: 90)
    XCTAssertNotNil(result.state.liquidation)
    // 실현 이익 25와 남은 원금 손실 50을 함께 집계한다.
    let liquidated = try store.snapshot()
    XCTAssertFalse(liquidated.isActive(liquidated.positions[0]))
    XCTAssertEqual(liquidated.accounts[0].availableBalance, 9_999_975)
    XCTAssertEqual(try liquidated.transactionHistory(for: first.order.account).compactMap(\.realizedPnL).reduce(0, +), -25)
  }

  func testFailedPartialCloseAndChangedQuantityKeepSavedBytes() throws {
    // 저장 실패와 잘못된 수량이 포지션을 부분 변경하지 않는지 확인한다.
    let first = try open()
    // 실패 전 파일 원문이다.
    let bytes = try Data(contentsOf: url)
    // 원자 저장이 실패하는 저장소다.
    let failing = LocalFuturesAccountRepository(fileURL: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    XCTAssertThrowsError(try closePart(first, quantity: 5, repository: failing))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    XCTAssertThrowsError(try closePart(first, quantity: 0))
    XCTAssertThrowsError(try closePart(first, quantity: 11))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    // 시트가 열렸던 때의 수량과 실제 보유 수량이 다르면 종료를 거절한다.
    let changed = FuturesClosingOrder(requestID: UUID(), positionID: first.id, executionPrice: 105, executedAt: Date(timeIntervalSince1970: 65), quantity: 5, expectedQuantity: 9)
    XCTAssertThrowsError(try store.closePosition(changed, orderCheck: orderCheck(first, time: 65_000, price: 105, proof: true), now: changed.executedAt))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
  }

  func testPartialCloseShortAndBithumbStayInTheirOwnKRWAccount() throws {
    // 업비트 포지션과 별개인 빗썸 숏 포지션을 준비한다.
    let upbit = try open()
    // 빗썸에서 10개 숏으로 진입한다.
    let order = domesticFuturesOrder(exchange: .bithumb, side: .short, margin: 100, price: 100)
    try store.ensureAccount(order.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    // 최초 진입에 대한 주문 검증 자료다.
    let ready = FuturesOrderCheck(account: order.account, instrument: order.instrument, revision: try store.snapshot().revision, mark: .init(instrument: order.instrument, price: 100, timestamp: 60_000))
    // 추가된 빗썸 포지션이다.
    let opened = try store.openPosition(order, orderCheck: ready, now: order.executedAt)
    // 빗썸 숏의 절반을 이익 구간에서 종료한다.
    let short = try XCTUnwrap(opened.positions.first { $0.order.account == order.account })
    // 다른 거래소의 자산과 수량은 그대로 유지한다.
    let partial = try closePart(short, quantity: 5, price: 95)
    XCTAssertEqual(partial.positions.first { $0.id == upbit.id }, upbit)
    XCTAssertEqual(partial.accounts.first { $0.id == upbit.order.account }?.availableBalance, 9_999_900)
    XCTAssertEqual(partial.accounts.first { $0.id == order.account }?.availableBalance, 9_999_975)
    XCTAssertEqual(try store.snapshot(), partial)
  }
}
