import XCTest
import RxSwift
@testable import Mobit

final class FuturesHistoryCheckTests: XCTestCase {
  private var directory: URL!
  private var url: URL { directory.appendingPathComponent("accounts.json") }
  private var store: LocalFuturesAccountRepository { LocalFuturesAccountRepository(fileURL: url) }
  private var position: FuturesPosition {
    get throws { try FuturesCalculator.open(futuresOrder(date: Date(timeIntervalSince1970: 60))) }
  }
  private let settledAt = Date(timeIntervalSince1970: 300)

  func testReadyOrdersDoNotFetchHistoryAndDisconnectRevokesReadiness() throws {
    let order = domesticFuturesOrder(margin: 100, price: 100)
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    _ = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    let monitor = FuturesMonitorFixture()
    let requests = FuturesRequestCounter()
    var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 100)
    provider.didRequest = { requests.increment() }
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) },
      monitor: monitor
    )
    defer { service.suspend() }
    let connected = expectation(description: "Socket connection verification finished")
    let connectionSubscription = service.status.filter {
      if case .finished(let results) = $0 { return !results.isEmpty }
      return false
    }.take(1).subscribe(onNext: { _ in connected.fulfill() })
    monitor.subject.onNext(.connection(.upbit, true))
    wait(for: [connected], timeout: 3)
    connectionSubscription.dispose()
    let price = socketPrice(order.instrument, at: 66_000)
    XCTAssertThrowsError(
      try awaitValue(
        service.prepareOrder(
          account: order.account,
          instrument: order.instrument,
          price: price
        )
      )
    )
    monitor.subject.onNext(.quote(price.quote))
    let beforeOrders = requests.count
    for _ in 0..<2 {
      let prepared = try awaitValue(
        service.prepareOrder(
          account: order.account,
          instrument: order.instrument,
          price: price
        )
      )
      XCTAssertEqual(prepared.mark.price, 100)
      XCTAssertEqual(prepared.monitoredPositions[order.requestID], order.executedAt)
    }
    XCTAssertEqual(requests.count, beforeOrders)
    monitor.subject.onNext(.connection(.upbit, false))
    XCTAssertThrowsError(
      try awaitValue(
        service.prepareOrder(
          account: order.account,
          instrument: order.instrument,
          price: price
        )
      )
    )
    XCTAssertEqual(try repository.snapshot().positions[0].executions.count, 1)
  }

  func testMonitoredLiquidationIsStoredBeforeFollowingOrder() throws {
    let order = domesticFuturesOrder(margin: 100, price: 100)
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    _ = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    let monitor = FuturesMonitorFixture()
    let provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 100)
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) },
      monitor: monitor
    )
    defer { service.suspend() }
    monitor.subject.onNext(.connection(.upbit, true))
    refreshAndWait(service)
    monitor.subject.onNext(.quote(.init(instrument: order.instrument, price: 80, timestamp: 66_000)))
    _ = try awaitValue(
      service.prepareOrder(
        account: order.account,
        instrument: order.instrument,
        price: socketPrice(order.instrument, at: 66_000)
      )
    )
    let saved = try repository.snapshot()
    XCTAssertNotNil(saved.historyCheckStates[0].liquidation)
    XCTAssertEqual(try saved.transactionHistory(for: order.account).last?.kind, .liquidation)
  }

  private func awaitValue<T>(_ single: Single<T>) throws -> T {
    let completed = expectation(description: "Order result")
    var result: Result<T, Error>?
    let subscription = single.observe(on: MainScheduler.instance).subscribe(
      onSuccess: {
        result = .success($0); completed.fulfill()
      },
      onFailure: {
        result = .failure($0); completed.fulfill()
      }
    )
    defer { subscription.dispose() }
    wait(for: [completed], timeout: 3)
    return try XCTUnwrap(result).get()
  }

  func testLockedSocketOrderKeepsPriceAndTimestampWithoutTickerREST() throws {
    let order = domesticFuturesOrder(price: 100)
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let provider = ReplayProvider(instrument: order.instrument)
    provider.neverReturnsQuote = true
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { self.settledAt }
    )
    defer { service.suspend() }
    let useCase = FuturesTradingUseCase(
      store: { repository },
      historyCheck: service,
      now: { self.settledAt }
    )
    let price = FuturesOrderPrice(
      quote: .init(instrument: order.instrument, price: 123, timestamp: 290_000),
      requestedAt: 299_000
    )
    let saved = try awaitValue(
      useCase.open(
        requestID: order.requestID,
        account: order.account,
        instrument: order.instrument,
        side: .long,
        margin: 100_000,
        leverage: 10,
        price: price
      )
    )
    XCTAssertEqual(saved.positions[0].order.executionPrice, 123)
    XCTAssertEqual(saved.positions[0].order.executedAt, Date(timeIntervalSince1970: 299))
    XCTAssertEqual(provider.quoteRequests, 0)
  }

  func testLifecycleDetectsHistoricalDipBeforeSocketClose() throws {
    let order = domesticFuturesOrder(price: 100)
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    _ = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    let provider = ReplayProvider(instrument: order.instrument)
    provider.candles = [candle(60_000, low: 80), candle(120_000)]
    provider.timestamp = 180_000
    let date = Date(timeIntervalSince1970: 181)
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { date }
    )
    defer { service.suspend() }
    let useCase = FuturesTradingUseCase(store: { repository }, historyCheck: service, now: { date })
    refreshAndWait(service)
    XCTAssertThrowsError(
      try awaitValue(
        useCase.close(
          requestID: UUID(),
          positionID: order.requestID,
          price: .init(
            quote: .init(instrument: order.instrument, price: 105, timestamp: 179_999),
            requestedAt: 180_000
          )
        )
      )
    )
    let saved = try repository.snapshot()
    XCTAssertNotNil(saved.historyCheckStates[0].liquidation)
    XCTAssertTrue(saved.closedPositions.isEmpty)
    XCTAssertEqual(provider.quoteRequests, 1)
    XCTAssertEqual(try saved.transactionHistory(for: order.account).last?.kind, .liquidation)
  }

  func testLockedPriceExpiresAfterFiveSecondsAndCannotSkipMissingHistory() throws {
    let order = domesticFuturesOrder(price: 100)
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let before = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    let provider = ReplayProvider(instrument: order.instrument)
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { self.settledAt }
    )
    defer { service.suspend() }
    for requestedAt in [Int64(294_999), 300_000] {
      XCTAssertThrowsError(
        try awaitValue(
          service.prepareOrder(
            account: order.account,
            instrument: order.instrument,
            price: .init(
              quote: .init(instrument: order.instrument, price: 100, timestamp: 290_000),
              requestedAt: requestedAt
            )
          )
        )
      )
    }
    XCTAssertEqual(try repository.snapshot(), before)
    XCTAssertEqual(provider.quoteRequests, 0)
  }

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }
  override func tearDownWithError() throws {
    if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
  }

  private func candle(_ start: Int64 = 60000, low: Decimal = 95, high: Decimal = 105) -> FuturesMarkCandle {
    .init(openTime: start, closeTime: start + 59999, open: 100, high: high, low: low, close: 100)
  }
  private func batch(
    _ position: FuturesPosition,
    start: Int64 = 60000,
    end: Int64 = 120000,
    candles: [FuturesMarkCandle]? = nil,
    funding: [FuturesFundingEvent] = []
  ) -> FuturesReplayBatch {
    .init(
      instrument: position.order.instrument,
      start: start,
      endExclusive: end,
      candles: candles ?? [candle()],
      funding: funding
    )
  }
  private func opened() throws -> FuturesAccountSnapshot {
    let position = try position
    try store.ensureAccount(position.order.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: position.order.account))
    return try store.openTestPosition(position.order, expectedRevision: store.snapshot().revision)
  }

  func testOrderWithoutSocketPriceFailsWithoutRequestingREST() throws {
    let order = domesticFuturesOrder(price: 100)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let before = try store.snapshot()
    let repository = store
    let provider = ReplayProvider(instrument: order.instrument)
    provider.neverReturnsQuote = true
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { self.settledAt },
      orderPreparationTimeout: .milliseconds(20)
    )
    let completed = expectation(description: "Order preparation has a total deadline")
    let subscription = service.prepareOrder(account: order.account, instrument: order.instrument)
      .subscribe(
        onSuccess: { _ in XCTFail("Never-returning quote must time out") },
        onFailure: { error in
          XCTAssertEqual(error as? FuturesOrderCheckError, .staleQuote)
          completed.fulfill()
        }
      )
    wait(for: [completed], timeout: 3)
    subscription.dispose()
    service.suspend()
    XCTAssertEqual(try repository.snapshot(), before)
    XCTAssertEqual(provider.quoteRequests, 0)
  }

  func testConcurrentObservedLiquidationAndRewardDoNotLoseOrDuplicateMoney() throws {
    let order = domesticFuturesOrder()
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    _ = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    let reward = try AdRewardClaim(account: order.account)
    let quote = FuturesMarkQuote(instrument: order.instrument, price: 1, timestamp: 299_999)
    DispatchQueue.concurrentPerform(iterations: 20) { index in
      do {
        if index.isMultiple(of: 2) {
          try repository.applyAdvertisementReward(reward)
        } else {
          _ = try repository.liquidateObservedQuote(quote, settledAt: Date(timeIntervalSince1970: 300))
        }
      } catch { XCTFail("Concurrent settlement failed: \(error)") }
    }
    let saved = try repository.snapshot()
    XCTAssertEqual(saved.accounts[0].availableBalance, 19_900_000)
    XCTAssertEqual(try saved.transactionHistory(for: order.account).filter { $0.kind == .liquidation }.count, 1)
    XCTAssertEqual(saved.rewardClaims.count, 2)
  }

  // 실시간 청산이 다른 거래소에 영향을 주지 않고 과거 청산 근거를 보존하는지 확인한다.
  func testObservedQuoteCannotSettleOtherExchangeAndPreservesLiquidationPrice() throws {
    let order = domesticFuturesOrder()
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let before = try store.openTestPosition(order, expectedRevision: store.snapshot().revision)
    let other = domesticFuturesOrder(exchange: .bithumb).instrument
    XCTAssertTrue(
      try store.liquidateObservedQuote(
        .init(instrument: other, price: 1, timestamp: 299_999),
        settledAt: settledAt
      ).isEmpty
    )
    XCTAssertEqual(try store.snapshot(), before)
    let adverse = FuturesMarkCandle(
      openTime: 60_000,
      closeTime: 119_999,
      open: 100_000_000,
      high: 100_000_000,
      low: 80_000_000,
      close: 100_000_000
    )
    _ = try store.checkHistoryAndSettle(
      positionID: order.requestID,
      expectedRevision: before.revision,
      batch: batch(before.positions[0], candles: [adverse]),
      settledAt: settledAt
    )
    let historical = try store.snapshot()
    XCTAssertTrue(
      try store.liquidateObservedQuote(
        .init(instrument: order.instrument, price: 1, timestamp: 299_999),
        settledAt: settledAt
      ).isEmpty
    )
    XCTAssertEqual(try store.snapshot(), historical)
  }

  func testObservedLiquidationPreservesUnverifiedGapAndPersistsExactlyOnce() throws {
    for side in [FuturesSide.long, .short] {
      let order = domesticFuturesOrder(exchange: side == .long ? .upbit : .bithumb, side: side)
      try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
      let opened = try store.openTestPosition(order, expectedRevision: store.snapshot().revision)
      let price: Decimal = side == .long ? 89_000_000 : 111_000_000
      let quote = FuturesMarkQuote(instrument: order.instrument, price: price, timestamp: 299_999)
      let liquidated = try store.liquidateObservedQuote(quote, settledAt: settledAt)
      XCTAssertEqual(liquidated.map(\.id), [order.requestID])
      let saved = try store.snapshot()
      let state = try XCTUnwrap(saved.historyCheckStates.first { $0.positionID == order.requestID })
      XCTAssertEqual(state.verifiedThrough, 60_000)
      XCTAssertNil(state.lastVerifiedMark)
      XCTAssertEqual(state.liquidation?.observedAt, 299_999)
      XCTAssertEqual(state.liquidation?.intervalStart, 60_000)
      XCTAssertEqual(state.liquidation?.intervalEndExclusive, 300_000)
      XCTAssertEqual(saved.accounts, opened.accounts)
      let history = try saved.transactionHistory(for: order.account)
      XCTAssertEqual(history.last?.realizedPnL, -100_000)
      XCTAssertEqual(try saved.valuation(for: order.account, quotes: [:], now: settledAt).totalEquity, 9_900_000)
      XCTAssertTrue(try store.liquidateObservedQuote(quote, settledAt: settledAt).isEmpty)
      XCTAssertEqual(try store.snapshot().revision, saved.revision)
      XCTAssertEqual(try LocalFuturesAccountRepository(fileURL: url).snapshot(), saved)
    }
  }

  func testObservedSafeStaleFutureAndPreEntryQuotesCannotSettleOrAdvanceCheckpoint() throws {
    let order = domesticFuturesOrder(date: Date(timeIntervalSince1970: 290))
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let before = try store.openTestPosition(order, expectedRevision: store.snapshot().revision)
    for timestamp in [Int64(1), 300_001] {
      XCTAssertThrowsError(
        try store.liquidateObservedQuote(
          .init(instrument: order.instrument, price: 1, timestamp: timestamp),
          settledAt: settledAt
        )
      )
    }
    for (price, timestamp) in [
      (Decimal(1), Int64(289_999)), (Decimal(1), Int64(290_000)), (Decimal(100_000_000), Int64(299_999))
    ] {
      XCTAssertTrue(
        try store.liquidateObservedQuote(
          .init(instrument: order.instrument, price: price, timestamp: timestamp),
          settledAt: settledAt
        ).isEmpty
      )
    }
    XCTAssertEqual(try store.snapshot(), before)
  }

  func testObservedLiquidationWriteFailureLeavesAccountAndHistoryUntouched() throws {
    let order = domesticFuturesOrder()
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let before = try store.openTestPosition(order, expectedRevision: store.snapshot().revision)
    let failing = LocalFuturesAccountRepository(fileURL: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    let quote = FuturesMarkQuote(instrument: order.instrument, price: 1, timestamp: 299_999)
    XCTAssertThrowsError(try failing.liquidateObservedQuote(quote, settledAt: settledAt))
    XCTAssertEqual(try store.snapshot(), before)
    XCTAssertEqual(try store.liquidateObservedQuote(quote, settledAt: settledAt).count, 1)
  }

  func testSocketObservationSettlesWithoutHistoryRequestsAndEmitsOnce() throws {
    let order = domesticFuturesOrder()
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let repository = store
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in
        XCTFail("Socket must not request history"); return nil
      },
      now: { self.settledAt }
    )
    // 검증 완료 계좌의 신규 진입은 즉시 실시간 감시를 시작해야 한다.
    let useCase = FuturesTradingUseCase(store: { repository }, historyCheck: service, now: { self.settledAt })
    // 정상 주문 경로가 포지션을 같은 소켓 세션의 검증 완료 상태로 등록한다.
    let snapshot = try awaitValue(
      useCase.open(
        requestID: order.requestID,
        account: order.account,
        instrument: order.instrument,
        side: order.side,
        margin: order.margin,
        leverage: order.leverage,
        price: .init(
          quote: .init(instrument: order.instrument, price: order.executionPrice, timestamp: 299_000),
          requestedAt: 299_000
        )
      )
    )
    let notice = expectation(description: "Saved liquidation notification")
    notice.assertForOverFulfill = true
    let subscription = service.liquidationEvents.subscribe(onNext: { positions in
      XCTAssertEqual(positions.map(\.id), [order.requestID])
      XCTAssertNotNil(try? repository.snapshot().historyCheckStates[0].liquidation)
      notice.fulfill()
    })
    service.track(snapshot)
    let quote = FuturesMarkQuote(instrument: order.instrument, price: 1, timestamp: 299_999)
    service.observe(quote)
    service.observe(quote)
    wait(for: [notice], timeout: 3)
    subscription.dispose()
    service.suspend()
    XCTAssertFalse(try repository.snapshot().isActive(snapshot.positions[0]))
  }

  func testLiveQuotesPublishSafeHeldPricesWithoutWritingAndStopInBackground() throws {
    let order = domesticFuturesOrder(margin: 100, price: 100)
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let saved = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in XCTFail("Live valuation must not fetch REST/history"); return nil },
      now: { self.settledAt }
    )
    let paused = expectation(description: "Queued ticks processed before suspension")
    let bag = DisposeBag()
    var received: [FuturesMarkQuote] = []
    service.liveQuotes.subscribe(onNext: { quote in
      XCTAssertTrue(Thread.isMainThread)
      received.append(quote)
    }).disposed(by: bag)
    service.status.subscribe(onNext: { status in
      if case .paused = status { paused.fulfill() }
    }).disposed(by: bag)
    service.track(saved)
    let first = FuturesMarkQuote(instrument: order.instrument, price: 100, timestamp: 299_000)
    let next = FuturesMarkQuote(instrument: order.instrument, price: 105, timestamp: 299_999)
    let other = domesticFuturesOrder(exchange: .bithumb).instrument
    for quote in [
      first, first,
      .init(instrument: order.instrument, price: 0, timestamp: 299_000),
      .init(instrument: order.instrument, price: .nan, timestamp: 299_000),
      .init(instrument: order.instrument, price: 105, timestamp: 300_001),
      .init(instrument: other, price: 105, timestamp: 299_999),
      next
    ] { service.observe(quote) }
    service.suspend()
    service.observe(.init(instrument: order.instrument, price: 106, timestamp: 300_000))
    wait(for: [paused], timeout: 3)
    let drained = expectation(description: "Background quote queue drained")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { drained.fulfill() }
    wait(for: [drained], timeout: 1)
    XCTAssertEqual(received, [first, .init(instrument: order.instrument, price: 105, timestamp: 300_001), next])
    XCTAssertEqual(try repository.snapshot(), saved)
  }

  func testRESTAdverseQuoteCannotSkipUnavailableHistory() throws {
    let order = domesticFuturesOrder()
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    _ = try store.openTestPosition(order, expectedRevision: store.snapshot().revision)
    // 현재가가 청산 가격이어도 과거 검증 실패 시 저장 상태를 유지해야 한다.
    let before = try store.snapshot()
    let provider = ReplayProvider(instrument: order.instrument)
    provider.timestamp = 299_999
    let repository = store
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { self.settledAt }
    )
    let completed = expectation(description: "Historical validation holds")
    let subscription = service.status.subscribe(onNext: { status in
      if case .finished(let results) = status, !results.isEmpty {
        XCTAssertEqual(results[0].hold, .missingHistory)
        XCTAssertFalse(results[0].liquidated)
        completed.fulfill()
      }
    })
    service.refresh()
    wait(for: [completed], timeout: 3)
    subscription.dispose()
    service.suspend()
    XCTAssertEqual(provider.candleStarts, [60_000])
    XCTAssertEqual(try repository.snapshot(), before)
  }

  func testStartupAdverseQuoteFindsFirstHistoricalCrossingAndRefinesThatMinute() throws {
    for side in [FuturesSide.long, .short] {
      // 롱·숏 모두 현재가보다 먼저 발생한 청산 구간을 찾아야 한다.
      let order = domesticFuturesOrder(side: side, margin: 100, price: 100)
      // 두 방향의 계좌 파일은 독립적으로 검증한다.
      let repository = LocalFuturesAccountRepository(fileURL: directory.appendingPathComponent(side.rawValue + ".json"))
      try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
      // 청산까지 중간 저장 없이 한 번만 갱신되는지 확인할 기준이다.
      let before = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
      // 해당 방향의 증거금을 소진하는 가격이다.
      let adverse: Decimal = side == .long ? 80 : 120
      // 현재가도 청산 기준이며 더 이른 분봉·체결을 순서대로 제공한다.
      var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 299_999, adverse: adverse)
      provider.quoteOverride = { .just(.init(instrument: order.instrument, price: adverse, timestamp: 299_999)) }
      provider.minuteCandles = [60_000, 120_000, 180_000, 240_000].map { time in
        .init(
          openTime: time,
          closeTime: time + 59_999,
          open: 100,
          high: side == .short && time != 60_000 ? adverse : 100,
          low: side == .long && time != 60_000 ? adverse : 100,
          close: 100
        )
      }
      provider.boundaryOverride = { start, end in
        XCTAssertEqual(start, 120_000)
        XCTAssertEqual(end, 180_000)
        return .just(.init(
          instrument: order.instrument,
          start: start,
          endExclusive: end,
          candles: [
            .init(openTime: start, closeTime: 125_122, open: 100, high: 100, low: 100, close: 100),
            .init(openTime: 125_123, closeTime: 125_123, open: adverse, high: adverse, low: adverse, close: adverse),
            .init(openTime: 125_124, closeTime: end - 1, open: 100, high: 100, low: 100, close: 100)
          ],
          funding: [],
          detailed: true
        ))
      }
      // 앱 재진입을 대신하는 과거 검증 서비스다.
      let service = FuturesHistoryCheckService(store: { repository }, provider: { _ in provider }, now: { self.settledAt })
      defer { service.suspend() }
      refreshAndWait(service)
      // 정밀 검증 결과와 발생 분이 동일 스냅샷에 저장돼야 한다.
      let saved = try repository.snapshot()
      let liquidation = try XCTUnwrap(saved.historyCheckStates[0].liquidation)
      XCTAssertEqual(liquidation.intervalStart, 125_123)
      XCTAssertEqual(liquidation.intervalEndExclusive, 125_124)
      XCTAssertEqual(liquidation.occurredMinute, 120_000)
      XCTAssertNil(liquidation.observedAt)
      XCTAssertEqual(saved.revision, before.revision + 1)
      XCTAssertEqual(saved.accounts, before.accounts)
      XCTAssertEqual(try saved.transactionHistory(for: order.account).last?.occurredMinute, 120_000)
      XCTAssertEqual(try saved.transactionHistory(for: order.account).last?.realizedPnL, -100)
    }
  }

  func testStartupSocketQuoteCannotSettleBeforeHistoricalVerification() throws {
    // 재진입 시 저장돼 있던 미검증 포지션이다.
    let order = domesticFuturesOrder(margin: 100, price: 100)
    // 조회와 소켓 처리 사이에 저장 데이터가 바뀌지 않는지 확인한다.
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let before = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    // REST가 끝나기 전에 소켓이 먼저 도착하는 순서를 재현한다.
    let response = PublishSubject<FuturesMarkQuote>()
    // 과거 구간의 최초 청산은 현재 소켓보다 앞선 65.123초다.
    var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 80, adverseAtEndOnly: true)
    provider.quoteOverride = { response.take(1).asSingle() }
    // 초기 과거 검증 상태가 준비되지 않은 서비스다.
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) }
    )
    defer { service.suspend() }
    // 청산 정산을 기다리는 동안에도 화면 손익용 시세는 전달해야 한다.
    let live = expectation(description: "Unverified socket price remains visible")
    let subscription = service.liveQuotes.take(1).subscribe(onNext: { _ in live.fulfill() })
    service.refresh()
    service.observe(.init(instrument: order.instrument, price: 80, timestamp: 65_999))
    wait(for: [live], timeout: 3)
    subscription.dispose()
    XCTAssertEqual(try repository.snapshot(), before)
    XCTAssertThrowsError(
      try awaitValue(
        service.prepareOrder(
          account: order.account,
          instrument: order.instrument,
          price: socketPrice(order.instrument, at: 66_000)
        )
      )
    ) {
      XCTAssertEqual($0 as? FuturesOrderCheckError, .historyCheckInProgress)
    }
    // 현재가가 청산 가격이어도 과거 확인이 먼저 완료돼야 한다.
    let finished = expectation(description: "First historical liquidation saved")
    let completion = service.status.subscribe(onNext: { status in
      if case .finished(let results) = status, results.contains(where: { $0.liquidated }) { finished.fulfill() }
    })
    response.onNext(.init(instrument: order.instrument, price: 80, timestamp: 65_123))
    wait(for: [finished], timeout: 3)
    completion.dispose()
    XCTAssertEqual(try repository.snapshot().historyCheckStates[0].liquidation?.intervalStart, 65_123)
    XCTAssertNil(try repository.snapshot().historyCheckStates[0].liquidation?.observedAt)
  }

  func testHistoricalLiquidationFallsBackToProvenMinuteOnlyWhenDetailIsUnavailable() throws {
    for missing in [true, false] {
      // 분봉으로 이미 청산이 증명됐지만 정밀 조회만 실패하는 상황이다.
      let order = domesticFuturesOrder(margin: 100, price: 100)
      // 정밀 자료 부재와 네트워크 오류를 서로 다른 계좌에서 확인한다.
      let repository = LocalFuturesAccountRepository(fileURL: directory.appendingPathComponent(missing ? "missing.json" : "failed.json"))
      try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
      let before = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
      // 최초 청산 분은 60초이며 정밀 조회 결과만 달라진다.
      var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 179_999, adverse: 80)
      provider.boundaryOverride = { _, _ in
        .error(missing ? FuturesMarketDataError.incompleteHistory : URLError(.notConnectedToInternet))
      }
      // 과거 검증의 분 단위 대체와 오류 보류를 구분한다.
      let service = FuturesHistoryCheckService(store: { repository }, provider: { _ in provider }, now: { Date(timeIntervalSince1970: 180) })
      defer { service.suspend() }
      refreshAndWait(service)
      if missing {
        XCTAssertEqual(try repository.snapshot().historyCheckStates[0].liquidation?.occurredMinute, 60_000)
      } else {
        XCTAssertEqual(try repository.snapshot(), before)
      }
    }
  }

  func testLiquidationMinutePersistsAndLegacyRecordsDecodeWithoutChangingProofTimes() throws {
    // 초 단위의 검증 근거와 분 단위 표시 시각을 함께 보관한다.
    let liquidation = FuturesLiquidationRecord(
      intervalStart: 125_123,
      intervalEndExclusive: 126_000,
      observedLiquidationPrice: 80,
      settledAt: settledAt
    )
    // 새 저장 필드는 원래 검증 구간을 반올림하지 않는다.
    let data = try JSONEncoder().encode(liquidation)
    let decoded = try JSONDecoder().decode(FuturesLiquidationRecord.self, from: data)
    XCTAssertEqual(decoded.occurredMinute, 120_000)
    XCTAssertEqual(decoded.intervalStart, 125_123)
    XCTAssertEqual(decoded.intervalEndExclusive, 126_000)
    // 기존 앱의 저장 형식에는 발생 분 필드가 없다.
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(legacy.removeValue(forKey: "occurredMinute") as? Int, 120_000)
    let old = try JSONDecoder().decode(FuturesLiquidationRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
    XCTAssertEqual(old, decoded)
  }

  func testDetailedMinuteRejectsContradictionWrongRangeAndFailedWriteWithoutPartialSave() throws {
    for failure in ["safeDetail", "wrongRange", "writeFailed"] {
      // 안전 구간 저장과 청산 확정이 분리돼 일부만 저장되면 안 된다.
      let order = domesticFuturesOrder(margin: 100, price: 100)
      // 실패 조건마다 원본 파일과 버전을 독립적으로 보존한다.
      let file = directory.appendingPathComponent(failure + ".json")
      let repository = LocalFuturesAccountRepository(fileURL: file)
      try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
      let before = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
      // 파일이 실제로 덮어써지지 않았는지 확인한다.
      let bytes = try Data(contentsOf: file)
      // 최초 청산은 두 번째 분에서 발생한다.
      let minutes = FuturesReplayBatch(
        instrument: order.instrument,
        start: 60_000,
        endExclusive: 180_000,
        candles: [candle(60_000), candle(120_000, low: 80)],
        funding: []
      )
      // 분봉과 범위 또는 청산 판정이 모순되는 자료다.
      let start: Int64 = failure == "wrongRange" ? 121_000 : 120_000
      let detail = FuturesReplayBatch(
        instrument: order.instrument,
        start: start,
        endExclusive: 180_000,
        candles: [.init(
          openTime: start,
          closeTime: 179_999,
          open: 100,
          high: 100,
          low: failure == "safeDetail" ? 100 : 80,
          close: 100
        )],
        funding: [],
        detailed: true
      )
      // 계산이 성공해도 최종 저장 실패 시 원본 계좌가 유지돼야 한다.
      let target = failure == "writeFailed"
        ? LocalFuturesAccountRepository(fileURL: file, writeSnapshot: { _, _ in throw CocoaError(.fileWriteUnknown) })
        : repository
      XCTAssertThrowsError(
        try target.checkHistoryAndSettle(
          positionID: order.requestID,
          expectedRevision: before.revision,
          batch: minutes,
          settledAt: settledAt,
          detailBatch: detail
        )
      )
      XCTAssertEqual(try repository.snapshot(), before)
      XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
  }

  func testDipAndRecoveryStillLiquidatesWithoutDebitingFreeBalance() throws {
    let snapshot = try opened()
    let position = snapshot.positions[0]
    let outcome = try store.checkHistoryAndSettle(
      positionID: position.id,
      expectedRevision: snapshot.revision,
      batch: batch(position, candles: [candle(low: 80)]),
      settledAt: settledAt
    )
    XCTAssertEqual(outcome.state.liquidation?.intervalStart, 60000)
    XCTAssertEqual(outcome.state.liquidation?.intervalEndExclusive, 120000)
    XCTAssertEqual(try store.snapshot().accounts[0].availableBalance, 900)
    XCTAssertEqual(try store.snapshot().historyCheckStates[0], outcome.state)
    XCTAssertThrowsError(
      try store.checkHistoryAndSettle(
        positionID: position.id,
        expectedRevision: snapshot.revision,
        batch: batch(position),
        settledAt: settledAt
      )
    )
  }

  func testDomesticCheckpointSurvivesReopenAndResumesWithoutChangingEntry() throws {
    let order = domesticFuturesOrder()
    try store.ensureAccount(order.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let funded = try store.snapshot()
    // 주문 시 확인할 가격·체결 시각·계좌 버전과 포지션 검증 상태다.
    let orderCheck = FuturesOrderCheck(
      account: order.account,
      instrument: order.instrument,
      revision: funded.revision,
      mark: .init(instrument: order.instrument, price: order.executionPrice, timestamp: 60_000)
    )
    let opened = try store.openPosition(order, orderCheck: orderCheck, now: order.executedAt)
    let position = opened.positions[0]
    let safe = FuturesMarkCandle(
      openTime: 60_000,
      closeTime: 119_999,
      open: 100_000_000,
      high: 105_000_000,
      low: 95_000_000,
      close: 102_000_000
    )
    let firstBatch = batch(position, candles: [safe])
    _ = try store.checkHistoryAndSettle(
      positionID: position.id,
      expectedRevision: opened.revision,
      batch: firstBatch,
      settledAt: settledAt
    )
    let reopened = LocalFuturesAccountRepository(fileURL: url)
    let saved = try reopened.snapshot()
    XCTAssertEqual(saved.historyCheckStates[0].verifiedThrough, 120_000)
    XCTAssertEqual(saved.positions[0].order.executedAt, order.executedAt)
    XCTAssertEqual(saved.positions[0].leverageAtExecution, 10)
    XCTAssertThrowsError(
      try reopened.checkHistoryAndSettle(
        positionID: position.id,
        expectedRevision: saved.revision,
        batch: firstBatch,
        settledAt: settledAt
      )
    )
    let dip = FuturesMarkCandle(
      openTime: 120_000,
      closeTime: 179_999,
      open: 102_000_000,
      high: 110_000_000,
      low: 89_000_000,
      close: 110_000_000
    )
    let resumed = batch(position, start: saved.historyCheckStates[0].verifiedThrough, end: 180_000, candles: [dip])
    let result = try reopened.checkHistoryAndSettle(
      positionID: position.id,
      expectedRevision: saved.revision,
      batch: resumed,
      settledAt: settledAt
    )
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
      let before = try opened.valuation(
        for: order.account,
        quotes: [order.instrument: .init(instrument: order.instrument, price: 100_000_000, timestamp: 60_000)],
        now: order.executedAt
      )
      XCTAssertEqual(before.totalEquity, 10_000_000)
      XCTAssertEqual(before.availableBalance, 9_900_000)
      XCTAssertEqual(before.reservedMargin, 100_000)
      XCTAssertThrowsError(try opened.valuation(for: order.account, quotes: [:], now: order.executedAt))
      let adverse = FuturesMarkCandle(
        openTime: 60_000,
        closeTime: 119_999,
        open: 100_000_000,
        high: 120_000_000,
        low: 80_000_000,
        close: 100_000_000
      )
      let replay = batch(try XCTUnwrap(opened.positions.last), candles: [adverse])
      let bytes = try Data(contentsOf: url)
      let failing = LocalFuturesAccountRepository(fileURL: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
      XCTAssertThrowsError(
        try failing.checkHistoryAndSettle(
          positionID: order.requestID,
          expectedRevision: opened.revision,
          batch: replay,
          settledAt: settledAt
        )
      )
      XCTAssertEqual(try Data(contentsOf: url), bytes)
      XCTAssertEqual(try store.snapshot().transactionHistory(for: order.account).count, 1)
      _ = try store.checkHistoryAndSettle(
        positionID: order.requestID,
        expectedRevision: opened.revision,
        batch: replay,
        settledAt: settledAt
      )
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
      XCTAssertThrowsError(
        try store.checkHistoryAndSettle(
          positionID: order.requestID,
          expectedRevision: restored.revision,
          batch: replay,
          settledAt: settledAt
        )
      )
      XCTAssertEqual(try store.snapshot().transactionHistory(for: order.account), history)
    }
  }

  func testDomesticLifecycleRequestsHistoryOnlyAfterSavedCheckpoint() throws {
    let order = domesticFuturesOrder(price: 100)
    try store.ensureAccount(order.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let opened = try store.openTestPosition(order, expectedRevision: store.snapshot().revision)
    _ = try store.checkHistoryAndSettle(
      positionID: order.requestID,
      expectedRevision: opened.revision,
      batch: batch(opened.positions[0]),
      settledAt: settledAt
    )
    let provider = ReplayProvider(instrument: order.instrument)
    provider.fundingHook = { XCTFail("Domestic replay must not request funding") }
    provider.timestamp = 185_000
    provider.candles = [candle(120_000)]
    let service = FuturesHistoryCheckService(
      store: { LocalFuturesAccountRepository(fileURL: self.url) },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 185) }
    )
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
    // 주문 시 확인할 가격·체결 시각·계좌 버전과 포지션 검증 상태다.
    let orderCheck = FuturesOrderCheck(
      account: order.account,
      instrument: order.instrument,
      revision: snapshot.revision,
      mark: .init(instrument: order.instrument, price: 99_000_000, timestamp: 60_000)
    )
    XCTAssertThrowsError(try store.openPosition(order, orderCheck: orderCheck, now: order.executedAt))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
  }

  func testDomesticFundingAndFailedCheckpointWritePreserveFile() throws {
    let order = domesticFuturesOrder(exchange: .bithumb)
    try store.ensureAccount(order.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let opened = try store.openTestPosition(order, expectedRevision: store.snapshot().revision)
    let position = opened.positions[0]
    let safe = FuturesMarkCandle(
      openTime: 60_000,
      closeTime: 119_999,
      open: 100_000_000,
      high: 105_000_000,
      low: 95_000_000,
      close: 100_000_000
    )
    let bytes = try Data(contentsOf: url)
    let foreignFunding = batch(
      position,
      candles: [safe],
      funding: [.init(timestamp: 60_001, rate: 0, markPrice: 100_000_000)]
    )
    XCTAssertThrowsError(
      try store.checkHistoryAndSettle(
        positionID: position.id,
        expectedRevision: opened.revision,
        batch: foreignFunding,
        settledAt: settledAt
      )
    )
    let failing = LocalFuturesAccountRepository(fileURL: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    XCTAssertThrowsError(
      try failing.checkHistoryAndSettle(
        positionID: position.id,
        expectedRevision: opened.revision,
        batch: batch(position, candles: [safe]),
        settledAt: settledAt
      )
    )
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    XCTAssertEqual(try store.snapshot(), opened)
  }

  func testPartialEntryCandleSafeRangeAdvancesButCrossingHolds() throws {
    let position = try FuturesCalculator.open(futuresOrder(date: Date(timeIntervalSince1970: 60.040)))
    let initial = try FuturesHistoryCheckState.initial(for: position)
    let safe = try FuturesReplayCalculator.replay(
      batch(position, start: initial.verifiedThrough),
      position: position,
      state: initial,
      settledAt: settledAt
    )
    XCTAssertEqual(safe.state.verifiedThrough, 120000)
    let risk = try FuturesReplayCalculator.replay(
      batch(position, start: initial.verifiedThrough, candles: [candle(low: 80)]),
      position: position,
      state: initial,
      settledAt: settledAt
    )
    XCTAssertEqual(risk.hold, .ambiguousEntryCandle)
    XCTAssertEqual(risk.state, initial)
  }

  func testShortUsesHighRatherThanClose() throws {
    let position = try FuturesCalculator.open(futuresOrder(side: .short, date: Date(timeIntervalSince1970: 60)))
    let result = try FuturesReplayCalculator.replay(
      batch(position, candles: [candle(high: 110)]),
      position: position,
      state: .initial(for: position),
      settledAt: settledAt
    )
    XCTAssertNotNil(result.state.liquidation)
  }

  func testFundingUsesActualTimeAndPriceOnce() throws {
    let snapshot = try opened()
    let position = snapshot.positions[0]
    let event = FuturesFundingEvent(timestamp: 60001, rate: Decimal(string: "0.001")!, markPrice: 100)
    let result = try store.checkHistoryAndSettle(
      positionID: position.id,
      expectedRevision: snapshot.revision,
      batch: batch(position, funding: [event]),
      settledAt: settledAt
    )
    XCTAssertEqual(result.state.netFunding, -1)
    XCTAssertEqual(result.state.fundingReceipts[0].event.timestamp, 60001)
    XCTAssertEqual(try store.snapshot().accounts[0].availableBalance, 900)
    XCTAssertThrowsError(
      try store.checkHistoryAndSettle(
        positionID: position.id,
        expectedRevision: store.snapshot().revision,
        batch: batch(position, funding: [event]),
        settledAt: settledAt
      )
    )
    XCTAssertEqual(try store.snapshot().historyCheckStates[0].netFunding, -1)
  }

  func testAmbiguousFundingDoesNotPartiallyCommitCandle() throws {
    let position = try position
    let initial = try FuturesHistoryCheckState.initial(for: position)
    for event in [
      FuturesFundingEvent(timestamp: 60000, rate: 0, markPrice: 100),
      FuturesFundingEvent(timestamp: 60001, rate: Decimal(string: "0.2")!, markPrice: 100)
    ] {
      let result = try FuturesReplayCalculator.replay(
        batch(position, funding: [event]),
        position: position,
        state: initial,
        settledAt: settledAt
      )
      XCTAssertEqual(result.hold, .ambiguousFundingOrder)
      XCTAssertEqual(result.state, initial)
    }
  }

  func testSplittingPagesMatchesSingleReplay() throws {
    let position = try position
    let initial = try FuturesHistoryCheckState.initial(for: position)
    let event = FuturesFundingEvent(timestamp: 120001, rate: Decimal(string: "-0.001")!, markPrice: 100)
    let whole = try FuturesReplayCalculator.replay(
      batch(position, end: 180000, candles: [candle(), candle(120000)], funding: [event]),
      position: position,
      state: initial,
      settledAt: settledAt
    )
    let first = try FuturesReplayCalculator.replay(
      batch(position),
      position: position,
      state: initial,
      settledAt: settledAt
    )
    let second = try FuturesReplayCalculator.replay(
      batch(position, start: 120000, end: 180000, candles: [candle(120000)], funding: [event]),
      position: position,
      state: first.state,
      settledAt: settledAt
    )
    XCTAssertEqual(whole.state, second.state)
    XCTAssertEqual(second.state.netFunding, 1)
  }

  func testSafePrefixPersistsBeforeAmbiguousFunding() throws {
    let snapshot = try opened()
    let position = snapshot.positions[0]
    let event = FuturesFundingEvent(timestamp: 120001, rate: Decimal(string: "0.2")!, markPrice: 100)
    let result = try store.checkHistoryAndSettle(
      positionID: position.id,
      expectedRevision: snapshot.revision,
      batch: batch(position, end: 180000, candles: [candle(), candle(120000)], funding: [event]),
      settledAt: settledAt
    )
    XCTAssertEqual(result.state.verifiedThrough, 120000)
    XCTAssertEqual(result.hold, .ambiguousFundingOrder)
    XCTAssertEqual(try store.snapshot().historyCheckStates[0], result.state)
    XCTAssertEqual(result.state.fundingReceipts.count, 0)
  }

  func testMissingDuplicateNaNAndWrongInstrumentNeverAdvance() throws {
    let position = try position
    let initial = try FuturesHistoryCheckState.initial(for: position)
    for candles in [[], [candle(), candle()], [candle(low: .nan)], [candle(120000)]] {
      XCTAssertThrowsError(
        try FuturesReplayCalculator.replay(
          batch(position, candles: candles),
          position: position,
          state: initial,
          settledAt: settledAt
        )
      )
    }
    let event = FuturesFundingEvent(timestamp: 60001, rate: 0, markPrice: 100)
    XCTAssertThrowsError(
      try FuturesReplayCalculator.replay(
        batch(position, funding: [event, event]),
        position: position,
        state: initial,
        settledAt: settledAt
      )
    )
    let invalid = FuturesReplayBatch(
      instrument: .init(exchange: .okx, product: .perpetual, rawSymbol: "BTCUSDT", settlementCurrency: .usdt),
      start: 60000,
      endExclusive: 120000,
      candles: [candle()],
      funding: []
    )
    XCTAssertThrowsError(
      try FuturesReplayCalculator.replay(invalid, position: position, state: initial, settledAt: settledAt)
    )
  }

  func testFailedWriteAndRewardRevisionConflictPreserveState() throws {
    let snapshot = try opened()
    let position = snapshot.positions[0]
    let bytes = try Data(contentsOf: url)
    let failing = LocalFuturesAccountRepository(fileURL: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    XCTAssertThrowsError(
      try failing.checkHistoryAndSettle(
        positionID: position.id,
        expectedRevision: snapshot.revision,
        batch: batch(position),
        settledAt: settledAt
      )
    )
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    try store.applyAdvertisementReward(AdRewardClaim(account: position.order.account))
    XCTAssertThrowsError(
      try store.checkHistoryAndSettle(
        positionID: position.id,
        expectedRevision: snapshot.revision,
        batch: batch(position),
        settledAt: settledAt
      )
    )
    XCTAssertEqual(try store.snapshot().accounts[0].availableBalance, 1900)
    XCTAssertEqual(try store.snapshot().historyCheckStates, snapshot.historyCheckStates)
  }

  // 동시에 같은 이력을 검증해도 한 번만 저장되는지 확인한다.
  func testConcurrentHistoryCheckSavesOnlyOnce() throws {
    let snapshot = try opened()
    let position = snapshot.positions[0]
    DispatchQueue.concurrentPerform(iterations: 20) { _ in
      do {
        _ = try store.checkHistoryAndSettle(
          positionID: position.id,
          expectedRevision: snapshot.revision,
          batch: batch(position),
          settledAt: settledAt
        )
      } catch LocalFuturesAccountRepository.StoreError.revisionConflict {} catch {
        XCTFail("Unexpected error: \(error)")
      }
    }
    XCTAssertEqual(try store.snapshot().revision, snapshot.revision + 1)
    XCTAssertEqual(try store.snapshot().historyCheckStates[0].verifiedThrough, 120000)
  }

  func testLegacyPositionMigrationAndSchemaFourMissingStatePreservation() throws {
    let snapshot = try opened()
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
    object["schemaVersion"] = 3
    object.removeValue(forKey: "reconciliations")
    try JSONSerialization.data(withJSONObject: object).write(to: url)
    XCTAssertEqual(try store.snapshot().historyCheckStates[0].verifiedThrough, 60000)
    object["schemaVersion"] = 4
    let bytes = try JSONSerialization.data(withJSONObject: object)
    try bytes.write(to: url)
    XCTAssertThrowsError(try store.snapshot())
    XCTAssertEqual(try Data(contentsOf: url), bytes)
  }

  func testLiquidatedPositionAllowsNewEntryButOldRequestDoesNotReopen() throws {
    let snapshot = try opened()
    let old = snapshot.positions[0]
    _ = try store.checkHistoryAndSettle(
      positionID: old.id,
      expectedRevision: snapshot.revision,
      batch: batch(old, candles: [candle(low: 80)]),
      settledAt: settledAt
    )
    let liquidated = try store.snapshot()
    XCTAssertEqual(try store.openTestPosition(old.order, expectedRevision: snapshot.revision), liquidated)
    let new = try store.openTestPosition(futuresOrder(date: settledAt), expectedRevision: liquidated.revision)
    XCTAssertEqual(new.positions.count, 2)
    XCTAssertEqual(new.accounts[0].availableBalance, 800)
  }

  func testUnverifiedExistingAccountBlocksAnotherInstrumentOrder() throws {
    let snapshot = try opened()
    let old = snapshot.positions[0].order
    let order = FuturesOpeningOrder(
      requestID: UUID(),
      account: old.account,
      instrument: .init(exchange: .binance, product: .perpetual, rawSymbol: "ETHUSDT", settlementCurrency: .usdt),
      side: old.side,
      margin: old.margin,
      leverage: old.leverage,
      executionPrice: old.executionPrice,
      entryFeeRate: old.entryFeeRate,
      executedAt: settledAt,
      contractRules: old.contractRules
    )
    XCTAssertThrowsError(try store.openTestPosition(order, expectedRevision: snapshot.revision)) {
      XCTAssertEqual($0 as? FuturesOrderCheckError, .held(.currentInterval))
    }
    XCTAssertEqual(try store.snapshot(), snapshot)
  }

  func testLifecycleRewardDuringRequestRejectsOldRevision() throws {
    let snapshot = try opened()
    let provider = ReplayProvider(instrument: snapshot.positions[0].order.instrument)
    provider.candles = [candle()]
    provider.fundingHook = {
      do { try self.store.applyAdvertisementReward(AdRewardClaim(account: snapshot.positions[0].order.account)) } catch
      { XCTFail("Reward failed: \(error)") }
    }
    let service = FuturesHistoryCheckService(
      store: { self.store },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 125) }
    )
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
    XCTAssertEqual(try store.snapshot().historyCheckStates[0].verifiedThrough, 60000)
  }

  func testWorkLimitSavesCheckpointForNextActivation() throws {
    let snapshot = try opened()
    let provider = ReplayProvider(instrument: snapshot.positions[0].order.instrument)
    provider.timestamp = 30_060_000
    provider.generateCandles = true
    let service = FuturesHistoryCheckService(
      store: { self.store },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 30060) },
      maximumPages: 1
    )
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
    XCTAssertEqual(try store.snapshot().historyCheckStates[0].verifiedThrough, 30_000_000)
  }

  func testPreparedOrderCommitsOnceAndRejectsChangedRevision() throws {
    let order = futuresOrder(date: Date(timeIntervalSince1970: 125))
    try store.ensureAccount(order.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let before = try store.snapshot()
    // 주문 시 확인할 가격·체결 시각·계좌 버전과 포지션 검증 상태다.
    let orderCheck = FuturesOrderCheck(
      account: order.account,
      instrument: order.instrument,
      revision: before.revision,
      mark: .init(instrument: order.instrument, price: 100, timestamp: 125000)
    )
    let after = try store.openPosition(order, orderCheck: orderCheck, now: order.executedAt)
    XCTAssertEqual(after.accounts[0].availableBalance, 900)
    XCTAssertEqual(try store.openPosition(order, orderCheck: orderCheck, now: order.executedAt), after)
    XCTAssertThrowsError(try orderCheck.validate(snapshot: after, now: order.executedAt)) {
      XCTAssertEqual($0 as? LocalFuturesAccountRepository.StoreError, .revisionConflict)
    }
  }

  // 미검증 구간과 미래·만료 시세가 있으면 주문을 거절하는지 확인한다.
  func testOrderCheckRejectsCurrentGapFutureAndExpiredMark() throws {
    let snapshot = try opened()
    let position = snapshot.positions[0]
    for timestamp in [Int64(60000), 125000, 126000] {
      // 주문 시 확인할 가격·체결 시각·계좌 버전과 포지션 검증 상태다.
      let orderCheck = FuturesOrderCheck(
        account: position.order.account,
        instrument: position.order.instrument,
        revision: snapshot.revision,
        mark: .init(instrument: position.order.instrument, price: 100, timestamp: timestamp)
      )
      XCTAssertThrowsError(try orderCheck.validate(snapshot: snapshot, now: Date(timeIntervalSince1970: 125)))
    }
    XCTAssertEqual(try store.snapshot(), snapshot)
  }

  func testPrepareEmptyAccountAndGuardPreparedSaveAfterReward() throws {
    let order = futuresOrder(date: Date(timeIntervalSince1970: 125))
    try store.ensureAccount(order.account)
    let provider = ReplayProvider(instrument: order.instrument)
    let service = FuturesHistoryCheckService(
      store: { self.store },
      provider: { _ in provider },
      now: { order.executedAt }
    )
    let finished = expectation(description: "prepared")
    let subscription = service.prepareOrder(
      account: order.account,
      instrument: order.instrument,
      price: socketPrice(order.instrument, at: 125_000)
    ).subscribe(
      onSuccess: { orderCheck in
        do {
          try self.store.applyAdvertisementReward(AdRewardClaim(account: order.account))
          XCTAssertThrowsError(try self.store.openPosition(order, orderCheck: orderCheck, now: order.executedAt)) {
            XCTAssertEqual($0 as? LocalFuturesAccountRepository.StoreError, .revisionConflict)
          }
        } catch { XCTFail("Unexpected error: \(error)") }
        finished.fulfill()
      },
      onFailure: { error in
        XCTFail("Preparation failed: \(error)"); finished.fulfill()
      }
    )
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
    let service = FuturesHistoryCheckService(
      store: { self.store },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 125) }
    )
    let finished = expectation(description: "gap rejected")
    let subscription = service.prepareOrder(
      account: position.order.account,
      instrument: position.order.instrument,
      price: socketPrice(position.order.instrument, at: 125_000)
    )
    .subscribe(
      onSuccess: { _ in
        XCTFail("Current interval must not become verified"); finished.fulfill()
      },
      onFailure: { error in
        XCTAssertEqual(error as? FuturesOrderCheckError, .historyCheckInProgress)
        finished.fulfill()
      }
    )
    defer { subscription.dispose() }
    wait(for: [finished], timeout: 3)
    XCTAssertEqual(try store.snapshot().historyCheckStates[0].verifiedThrough, 60000)
  }

  func testAutomaticContinuationFinishesWithoutAnotherActivation() throws {
    let snapshot = try opened()
    let provider = ReplayProvider(instrument: snapshot.positions[0].order.instrument)
    provider.timestamp = 30_060_000
    provider.generateCandles = true
    let service = FuturesHistoryCheckService(
      store: { self.store },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 30060) },
      maximumPages: 1
    )
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
    let service = FuturesHistoryCheckService(
      store: { self.store },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 30060) },
      maximumPages: 1
    )
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
    XCTAssertEqual(try store.snapshot().historyCheckStates[0].verifiedThrough, 30_000_000)
    let finished = expectation(description: "resumed")
    let second = service.status.subscribe(onNext: { status in
      if case .finished(let results) = status, results.first?.hold == .currentInterval { finished.fulfill() }
    })
    defer { second.dispose() }
    service.refresh()
    wait(for: [finished], timeout: 3)
    XCTAssertEqual(try store.snapshot().historyCheckStates[0].verifiedThrough, 30_060_000)
  }

  func testLifecycleRefreshCoalescesAndDoesNotSkipCurrentInterval() throws {
    let snapshot = try opened()
    let provider = ReplayProvider(instrument: snapshot.positions[0].order.instrument)
    provider.candles = [candle()]
    let service = FuturesHistoryCheckService(
      store: { self.store },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 125) }
    )
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
    XCTAssertEqual(try store.snapshot().historyCheckStates[0].verifiedThrough, 120000)
    XCTAssertEqual(provider.quoteRequests, 1)
  }

  func testLifecycleIncompleteFundingPageAndStaleQuoteHold() throws {
    let snapshot = try opened()
    for stale in [false, true] {
      let provider = ReplayProvider(instrument: snapshot.positions[0].order.instrument)
      provider.candles = [candle()]
      provider.nextFunding = 60001
      provider.timestamp = stale ? 60000 : 125000
      let service = FuturesHistoryCheckService(
        store: { self.store },
        provider: { _ in provider },
        now: { Date(timeIntervalSince1970: 125) }
      )
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
      XCTAssertEqual(try store.snapshot().historyCheckStates[0].verifiedThrough, 60000)
    }
  }
}

private final class FuturesRequestCounter {
  private let lock = NSLock()
  private var value = 0
  var count: Int { lock.lock(); defer { lock.unlock() }; return value }
  func increment() { lock.lock(); defer { lock.unlock() }; value += 1 }
}

private final class FuturesMonitorFixture: FuturesPositionMonitoring {
  let subject = PublishSubject<FuturesMonitorEvent>()
  var events: Observable<FuturesMonitorEvent> { subject.asObservable() }
  func watch(_ instruments: [TradingInstrumentID]) {}
  func suspend() {}
}

private final class ReplayProvider: FuturesMarketDataProviding {
  let instrument: TradingInstrumentID
  var candles: [FuturesMarkCandle] = []
  var timestamp: Int64 = 125000
  var nextFunding: Int64?
  var fundingHook: (() -> Void)?
  var generateCandles = false
  var neverReturnsQuote = false
  private let lock = NSLock()
  private var starts: [Int64] = []
  var candleStarts: [Int64] { lock.lock(); defer { lock.unlock() }; return starts }
  private var requests = 0
  var quoteRequests: Int { lock.lock(); defer { lock.unlock() }; return requests }
  init(instrument: TradingInstrumentID) { self.instrument = instrument }
  func markQuote(_ instrument: TradingInstrumentID) -> Single<FuturesMarkQuote> {
    lock.lock(); requests += 1; lock.unlock()
    if neverReturnsQuote { return .never() }
    return .just(.init(instrument: instrument, price: 100, timestamp: timestamp))
  }
  func contract(_ instrument: TradingInstrumentID) -> Single<FuturesMarketContract> {
    .error(FuturesMarketDataError.invalidRequest)
  }
  func markCandles(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<
    FuturesHistoryPage<FuturesMarkCandle>
  > {
    lock.lock(); starts.append(start); lock.unlock()
    let values =
      generateCandles
      ? stride(from: start, to: endExclusive, by: 60_000).map {
        FuturesMarkCandle(openTime: $0, closeTime: $0 + 59999, open: 100, high: 105, low: 95, close: 100)
      } : candles
    return .just(.init(instrument: instrument, values: values, nextStartTime: nil))
  }
  func funding(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<
    FuturesHistoryPage<FuturesFundingEvent>
  > {
    fundingHook?()
    return .just(.init(instrument: instrument, values: [], nextStartTime: nextFunding))
  }
}

final class FuturesPreUIIntegrationTests: XCTestCase {
  private var directory: URL!
  private var store: LocalFuturesAccountRepository { .init(fileURL: directory.appendingPathComponent("accounts.json")) }
  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }
  override func tearDownWithError() throws {
    if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
  }
  private func value<T>(_ single: Single<T>) throws -> T {
    let finished = expectation(description: "trading result")
    var result: Result<T, Error>?
    let disposable = single.observe(on: MainScheduler.instance).subscribe(
      onSuccess: {
        result = .success($0); finished.fulfill()
      },
      onFailure: {
        result = .failure($0); finished.fulfill()
      }
    )
    defer { disposable.dispose() }
    wait(for: [finished], timeout: 5)
    return try XCTUnwrap(result).get()
  }

  func testUIAccountPreparationStartsAtZeroAndPreservesRewardOnRevisit() throws {
    let order = domesticFuturesOrder()
    let service = FuturesHistoryCheckService(store: { self.store }, provider: { _ in nil })
    let useCase = FuturesTradingUseCase(store: { self.store }, historyCheck: service)
    defer { service.suspend() }
    XCTAssertEqual(try value(useCase.accountSnapshot(for: order.account)).accounts.first?.availableBalance, 0)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    XCTAssertEqual(try value(useCase.accountSnapshot(for: order.account)).accounts.first?.availableBalance, 10_000_000)
    XCTAssertThrowsError(
      try value(useCase.accountSnapshot(for: .init(exchange: .upbit, product: .perpetual, currency: .btc)))
    )
  }

  func testUIFacingUseCaseAddsClosesAndRetriesWithStableRequestIDs() throws {
    let first = domesticFuturesOrder(margin: 100, price: 100)
    try store.ensureAccount(first.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: first.account))
    try store.openTestPosition(first, expectedRevision: store.snapshot().revision)
    let provider = DetailReplayProvider(instrument: first.instrument, timestamp: 65_123, adverse: 100)
    let service = FuturesHistoryCheckService(
      store: { self.store },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) }
    )
    let useCase = FuturesTradingUseCase(
      store: { self.store },
      historyCheck: service,
      now: { Date(timeIntervalSince1970: 66) }
    )
    defer { service.suspend() }
    refreshAndWait(service)
    let id = UUID()
    let added = try value(
      useCase.open(
        requestID: id,
        account: first.account,
        instrument: first.instrument,
        side: .long,
        margin: 100,
        leverage: 10,
        addingTo: first.requestID,
        price: socketPrice(first.instrument, at: 66_000)
      )
    )
    XCTAssertEqual(added.positions[0].executions.count, 2)
    XCTAssertEqual(added.positions[0].quantity, 20)
    XCTAssertEqual(added.historyCheckStates[0].verifiedThrough, 66_000)
    XCTAssertEqual(
      try value(
        useCase.open(
          requestID: id,
          account: first.account,
          instrument: first.instrument,
          side: .long,
          margin: 100,
          leverage: 10,
          addingTo: first.requestID,
          price: socketPrice(first.instrument, at: 66_000)
        )
      ),
      added
    )
    XCTAssertThrowsError(
      try value(
        useCase.open(
          requestID: id,
          account: first.account,
          instrument: first.instrument,
          side: .short,
          margin: 100,
          leverage: 10
        )
      )
    )
    let closeID = UUID()
    let closed = try value(
      useCase.close(requestID: closeID, positionID: first.requestID, price: socketPrice(first.instrument, at: 66_000))
    )
    XCTAssertEqual(closed.accounts[0].availableBalance, 10_000_000)
    XCTAssertEqual(try closed.transactionHistory(for: first.account).map(\.kind), [.opening, .addition, .closing])
    XCTAssertEqual(
      try value(
        useCase.close(requestID: closeID, positionID: first.requestID, price: socketPrice(first.instrument, at: 66_000))
      ),
      closed
    )
  }

  func testPartialCloseKeepsSocketMonitoringAndRetriesWithoutDuplicateSettlement() throws {
    // 첫 진입부터 전량 종료까지 같은 포지션을 유지하는 계좌다.
    let first = domesticFuturesOrder(margin: 100, price: 100)
    // 실제 저장 경로와 동일한 원자 저장소다.
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: first.account))
    try repository.openTestPosition(first, expectedRevision: repository.snapshot().revision)
    // 연결과 최신 시세 이벤트를 제어하는 소켓이다.
    let monitor = FuturesMonitorFixture()
    // 부분 종료마다 과거 조회를 반복하지 않는지 확인한다.
    let requests = FuturesRequestCounter()
    // 진입 이후 청산 경계를 넘지 않은 과거 자료다.
    var provider = DetailReplayProvider(instrument: first.instrument, timestamp: 65_123, adverse: 100)
    provider.didRequest = { requests.increment() }
    // 실제 주문 준비와 부분 종료 후 감시 이어가기를 검증한다.
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) },
      monitor: monitor
    )
    // 화면이 사용하는 종료 진입점이다.
    let useCase = FuturesTradingUseCase(
      store: { repository },
      historyCheck: service,
      now: { Date(timeIntervalSince1970: 66) }
    )
    defer { service.suspend() }
    monitor.subject.onNext(.connection(.upbit, true))
    refreshAndWait(service)
    // 일부 손실을 먼저 확정하는 최신 소켓 가격이다.
    let price = FuturesOrderPrice(quote: .init(instrument: first.instrument, price: 95, timestamp: 66_000), requestedAt: 66_000)
    monitor.subject.onNext(.quote(price.quote))
    // 같은 종료 요청의 재시도에 사용하는 식별자다.
    let requestID = UUID()
    // 최초 부분 종료 뒤의 수량·원금·잔액이다.
    let partial = try value(useCase.close(requestID: requestID, positionID: first.requestID, price: price, quantity: 2, expectedQuantity: 10))
    XCTAssertEqual(partial.positions[0].quantity, 8)
    XCTAssertEqual(try partial.positions[0].margin, 80)
    XCTAssertEqual(partial.accounts[0].availableBalance, 9_999_910)
    // 이미 저장한 종료 요청은 가격 재조회와 추가 정산 없이 반환한다.
    let before = requests.count
    XCTAssertEqual(try value(useCase.close(requestID: requestID, positionID: first.requestID, price: price, quantity: 2, expectedQuantity: 10)), partial)
    XCTAssertThrowsError(try value(useCase.close(requestID: requestID, positionID: first.requestID, price: price, quantity: 3, expectedQuantity: 10)))
    XCTAssertThrowsError(try value(useCase.close(requestID: UUID(), positionID: first.requestID, price: price, quantity: 2, expectedQuantity: 10)))
    XCTAssertEqual(try repository.snapshot(), partial)
    // 다음 종료는 같은 소켓 감시 상태에서 줄어든 수량을 기준으로 처리한다.
    let nextPrice = socketPrice(first.instrument, at: 66_000)
    monitor.subject.onNext(.quote(nextPrice.quote))
    _ = try value(useCase.close(requestID: UUID(), positionID: first.requestID, price: nextPrice, quantity: 2, expectedQuantity: 8))
    // 마지막 전량 종료에도 먼저 확정한 손실을 다시 더하거나 빼지 않는다.
    let final = try value(useCase.close(requestID: UUID(), positionID: first.requestID, price: nextPrice, quantity: 6, expectedQuantity: 6))
    XCTAssertEqual(final.accounts[0].availableBalance, 9_999_990)
    XCTAssertFalse(final.isActive(final.positions[0]))
    // 동일 밀리초의 종료는 정렬 순서와 관계없이 같은 손익 합계를 유지한다.
    let realized = try final.transactionHistory(for: first.account).compactMap(\.realizedPnL)
    XCTAssertEqual(realized.count, 3)
    XCTAssertEqual(realized.reduce(0, +), -10)
    XCTAssertEqual(requests.count, before)
  }

  // 주문 준비 중 청산 가격을 지나면 추가 진입·종료보다 청산을 먼저 처리하는지 확인한다.
  func testDipDuringOrderCheckLiquidatesInsteadOfAddingOrClosing() throws {
    let first = domesticFuturesOrder(margin: 100, price: 100)
    try store.ensureAccount(first.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: first.account))
    try store.openTestPosition(first, expectedRevision: store.snapshot().revision)
    let provider = DetailReplayProvider(instrument: first.instrument, timestamp: 65_123, adverse: 80)
    let service = FuturesHistoryCheckService(
      store: { self.store },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) }
    )
    let useCase = FuturesTradingUseCase(
      store: { self.store },
      historyCheck: service,
      now: { Date(timeIntervalSince1970: 66) }
    )
    defer { service.suspend() }
    refreshAndWait(service)
    XCTAssertThrowsError(
      try value(
        useCase.open(
          requestID: UUID(),
          account: first.account,
          instrument: first.instrument,
          side: .long,
          margin: 100,
          leverage: 10,
          addingTo: first.requestID,
          price: socketPrice(first.instrument, at: 66_000)
        )
      )
    )
    XCTAssertNotNil(try store.snapshot().historyCheckStates[0].liquidation)
    XCTAssertEqual(try store.snapshot().positions[0].executions.count, 1)
    XCTAssertThrowsError(try value(useCase.close(requestID: UUID(), positionID: first.requestID)))
    XCTAssertEqual(try store.snapshot().accounts[0].availableBalance, 9_999_900)
  }

  func testOrderDuringAutomaticRefreshFailsImmediatelyWithoutQueueing() throws {
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
    let service = FuturesHistoryCheckService(
      store: { self.store },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) }
    )
    defer { service.suspend() }
    service.refresh()
    wait(for: [started], timeout: 3)
    let prepared = expectation(description: "order prepared after refresh")
    let subscription = service.prepareOrder(
      account: order.account,
      instrument: order.instrument,
      price: socketPrice(order.instrument, at: 66_000)
    ).subscribe(
      onSuccess: { result in
        XCTFail("Order must not wait for verification: \(result)")
        prepared.fulfill()
      },
      onFailure: { error in
        XCTAssertEqual(error as? FuturesOrderCheckError, .historyCheckInProgress)
        prepared.fulfill()
      }
    )
    defer { subscription.dispose() }
    wait(for: [prepared], timeout: 3)
    XCTAssertEqual(requests, 1)
    gate.onNext(.init(instrument: order.instrument, price: 100, timestamp: 65_000))
    XCTAssertEqual(try store.snapshot().positions[0].executions.count, 1)
  }

  func testSuspendedServiceRejectsNewPreparationWithoutMutation() throws {
    let order = domesticFuturesOrder(margin: 100, price: 100)
    try store.ensureAccount(order.account)
    let before = try store.snapshot()
    let provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_000, adverse: 100)
    let service = FuturesHistoryCheckService(
      store: { self.store },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) }
    )
    service.suspend()
    XCTAssertThrowsError(try value(service.prepareOrder(account: order.account, instrument: order.instrument))) {
      XCTAssertEqual($0 as? FuturesOrderCheckError, .historyCheckInProgress)
    }
    XCTAssertEqual(try store.snapshot(), before)
  }

  func testLastQuoteMillisecondIsIncludedInLiquidationReplay() throws {
    let first = domesticFuturesOrder(margin: 100, price: 100)
    try store.ensureAccount(first.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: first.account))
    try store.openTestPosition(first, expectedRevision: store.snapshot().revision)
    let provider = DetailReplayProvider(
      instrument: first.instrument,
      timestamp: 65_123,
      adverse: 80,
      adverseAtEndOnly: true
    )
    let service = FuturesHistoryCheckService(
      store: { self.store },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) }
    )
    defer { service.suspend() }
    refreshAndWait(service)
    XCTAssertEqual(try store.snapshot().historyCheckStates[0].liquidation?.intervalStart, 65_123)
  }

}

private struct DetailReplayProvider: FuturesDetailedMarketDataProviding {
  let instrument: TradingInstrumentID
  let timestamp: Int64
  let adverse: Decimal
  var adverseAtEndOnly = false
  var quoteOverride: (() -> Single<FuturesMarkQuote>)?
  var didRequest: (() -> Void)?
  // 최초 청산 분을 찾을 분봉 응답을 테스트별로 지정한다.
  var minuteCandles: [FuturesMarkCandle]?
  // 특정 발생 분의 정밀 자료나 조회 실패를 재현한다.
  var boundaryOverride: ((Int64, Int64) -> Single<FuturesReplayBatch>)?
  func markQuote(_ instrument: TradingInstrumentID) -> Single<FuturesMarkQuote> {
    didRequest?()
    return quoteOverride?() ?? .just(.init(instrument: instrument, price: 100, timestamp: timestamp))
  }
  func contract(_ instrument: TradingInstrumentID) -> Single<FuturesMarketContract> {
    .error(FuturesMarketDataError.invalidRequest)
  }
  func funding(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<
    FuturesHistoryPage<FuturesFundingEvent>
  > {
    XCTFail("Domestic funding must not be requested")
    return .just(.init(instrument: instrument, values: [], nextStartTime: nil))
  }
  func markCandles(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<
    FuturesHistoryPage<FuturesMarkCandle>
  > {
    .just(
      .init(
        instrument: instrument,
        values: minuteCandles ?? stride(from: start, to: endExclusive, by: 60_000).map {
          .init(openTime: $0, closeTime: $0 + 59_999, open: 100, high: 100, low: adverse, close: 100)
        },
        nextStartTime: nil
      )
    )
  }
  func boundaryHistory(
    _ instrument: TradingInstrumentID,
    start: Int64,
    endExclusive: Int64,
    initialEntry: Bool
  ) -> Single<FuturesReplayBatch> {
    didRequest?()
    if let boundaryOverride { return boundaryOverride(start, endExclusive) }
    var candles: [FuturesMarkCandle] = []
    if adverseAtEndOnly, endExclusive - start > 1 {
      candles.append(.init(openTime: start, closeTime: endExclusive - 2, open: 100, high: 100, low: 100, close: 100))
    }
    candles.append(
      .init(
        openTime: adverseAtEndOnly ? endExclusive - 1 : start,
        closeTime: endExclusive - 1,
        open: 100,
        high: 100,
        low: adverse,
        close: 100
      )
    )
    return .just(
      .init(
        instrument: instrument,
        start: start,
        endExclusive: endExclusive,
        candles: candles,
        funding: [],
        detailed: true
      )
    )
  }
}

extension XCTestCase {
  fileprivate func refreshAndWait(_ service: FuturesHistoryCheckService) {
    let finished = expectation(description: "Lifecycle verification finished")
    let subscription = service.status.filter {
      if case .finished(let results) = $0 { return !results.isEmpty }
      return false
    }.take(1).subscribe(onNext: { _ in finished.fulfill() })
    service.refresh()
    wait(for: [finished], timeout: 3)
    subscription.dispose()
  }

  fileprivate func socketPrice(_ instrument: TradingInstrumentID, at timestamp: Int64) -> FuturesOrderPrice {
    .init(quote: .init(instrument: instrument, price: 100, timestamp: timestamp), requestedAt: timestamp)
  }

}
