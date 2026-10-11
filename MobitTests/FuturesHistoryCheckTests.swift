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

  func testFreshRestResponseVerifiesIdleHistoryButRejectsStaleResponseAndFutureTrade() throws {
    // 마지막 체결 이후 무체결 구간까지 확인할 정상 보유 포지션이다.
    let order = domesticFuturesOrder(margin: 100, price: 100)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    try store.openTestPosition(order, expectedRevision: store.snapshot().revision)
    // 체결 시각과 REST 응답 시각은 서로 다른 신뢰 조건을 갖는다.
    let cases: [(Int64, Int64?, FuturesHistoryCheckHold?)] = [
      (65_000, 125_000, nil),
      (65_000, 60_000, .staleQuote),
      (131_000, 125_000, .staleQuote),
      (65_000, nil, .staleQuote)
    ]
    for (tradeTimestamp, responseTimestamp, hold) in cases {
      // 같은 가격의 완전한 과거 이력을 제공한다.
      var provider = DetailReplayProvider(instrument: order.instrument, timestamp: tradeTimestamp, adverse: 100)
      provider.quoteOverride = {
        .just(.init(instrument: order.instrument, price: 100, timestamp: tradeTimestamp, responseTimestamp: responseTimestamp))
      }
      // 실제 주문 검증 서비스가 REST 응답의 신선도만 사용하도록 확인한다.
      let service = FuturesHistoryCheckService(
        store: { self.store },
        provider: { _ in provider },
        now: { Date(timeIntervalSince1970: 125) }
      )
      // 무체결 검증 완료 또는 올바른 시각 보류 결과를 기다린다.
      let finished = expectation(description: "REST freshness result")
      // 최초 완료 결과만 검사해 예약된 주기 조회와 구분한다.
      let subscription = service.status.filter {
        if case .finished(let results) = $0 { return !results.isEmpty }
        return false
      }.take(1).subscribe(onNext: { status in
        guard case .finished(let results) = status else { return }
        XCTAssertEqual(results.first?.hold, hold)
        if hold == nil { XCTAssertEqual(results.first?.verifiedThrough, 125_000) }
        finished.fulfill()
      })
      service.refresh()
      wait(for: [finished], timeout: 3)
      subscription.dispose()
      service.suspend()
    }
  }

  func testLaunchPreparationCompletesForEmptyAccountAndStorageFailure() {
    for fails in [false, true] {
      // 보유 포지션이 없거나 저장소 읽기가 실패해도 인트로는 종료할 수 있어야 한다.
      let service = FuturesHistoryCheckService(
        store: {
          if fails { throw LocalFuturesAccountRepository.StoreError.invalidStoredData }
          return self.store
        },
        provider: { _ in nil }
      )
      // 기본 finished 상태가 아니라 실제 조회 결과를 기다린다.
      let ready = expectation(description: "Launch preparation finished")
      // 최초 완료가 인트로를 여러 번 전환하지 않는지 확인한다.
      var completionCount = 0
      // 실제 앱과 같은 최소 표시 시간이 지켜지는지 측정한다.
      let startedAt = Date()
      // 화면 대기를 종료해도 서비스 수명은 독립적으로 유지한다.
      let subscription = service.prepareLaunch().subscribe(
        onNext: {
          completionCount += 1
          ready.fulfill()
        }
      )
      wait(for: [ready], timeout: 3)
      XCTAssertEqual(completionCount, 1)
      XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(startedAt), 1.45)
      XCTAssertLessThan(Date().timeIntervalSince(startedAt), 3)
      subscription.dispose()
      service.suspend()
    }
  }

  func testLaunchHeldHistoryWaitsUntilFiveSecondDeadline() throws {
    // 빠르게 실패한 이력 조회를 완료로 오인하던 진입 조건이다.
    let order = domesticFuturesOrder(margin: 100, price: 100)
    // 검증 보류 중 포지션이 임의로 바뀌지 않는지 확인한다.
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    // 미검증 상태에서 그대로 유지해야 할 저장 데이터다.
    let before = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    // 현재가는 받았으나 과거 자료는 누락된 실제 보류 흐름이다.
    var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 100)
    provider.boundaryOverride = { _, _ in .error(FuturesMarketDataError.incompleteHistory) }
    // 앱의 기본 1.5초·5초 설정을 그대로 검증한다.
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) }
    )
    defer { service.suspend() }
    // 응답은 즉시 도착했지만 검증이 완료되지 않은 시점이다.
    let held = expectation(description: "History check returned a hold")
    // 보류 응답이 인트로를 조기 종료하지 않아야 한다.
    let status = service.status.filter {
      if case .finished(let results) = $0 { return results.first?.hold == .missingHistory }
      return false
    }.take(1).subscribe(onNext: { _ in held.fulfill() })
    // 제한 시간까지 기다린 후 한 번만 메인 진입을 허용한다.
    let ready = expectation(description: "Launch reaches its five second deadline")
    // 실제 인트로 대기 시간을 재는 기준 시각이다.
    let startedAt = Date()
    // 타임아웃 전 화면 전환 여부를 확인한다.
    var launchFinished = false
    // 인트로 구독과 검증 구독의 수명을 분리한다.
    let launch = service.prepareLaunch().subscribe(
      onNext: {
        launchFinished = true
        ready.fulfill()
      }
    )
    wait(for: [held], timeout: 3)
    XCTAssertFalse(launchFinished)
    wait(for: [ready], timeout: 7)
    XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(startedAt), 4.9)
    XCTAssertLessThan(Date().timeIntervalSince(startedAt), 7)
    XCTAssertEqual(try repository.snapshot(), before)
    launch.dispose()
    status.dispose()
  }

  func testLaunchHeldHistoryCanFinishOnSuccessfulRetryBeforeDeadline() throws {
    // 첫 조회 보류 뒤 다음 조회에서 복구되는 포지션이다.
    let order = domesticFuturesOrder(margin: 100, price: 100)
    // 실제 검증 체크포인트를 저장할 계좌다.
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    _ = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    // 첫 상세 조회만 실패하도록 호출 횟수를 구분한다.
    var requests = 0
    // 자동 재시도에서 정상 응답이 도착할 시점을 제어한다.
    let response = PublishSubject<FuturesMarkQuote>()
    // 최초 현재가와 지연된 두 번째 현재가를 구분한다.
    var quoteRequests = 0
    // 재조회에서는 안전한 과거 범위를 정상 응답한다.
    var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 100)
    provider.quoteOverride = {
      quoteRequests += 1
      return quoteRequests == 1
        ? .just(.init(instrument: order.instrument, price: 100, timestamp: 65_123))
        : response.take(1).asSingle()
    }
    provider.boundaryOverride = { start, end in
      requests += 1
      if requests == 1 { return .error(FuturesMarketDataError.incompleteHistory) }
      return .just(
        .init(
          instrument: order.instrument,
          start: start,
          endExclusive: end,
          candles: [.init(openTime: start, closeTime: end - 1, open: 100, high: 100, low: 100, close: 100)],
          funding: [],
          detailed: true
        )
      )
    }
    // 기본 대기 제한 안에서 검증 결과가 바뀌는지 확인한다.
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) }
    )
    defer { service.suspend() }
    // 첫 보류로 종료되면 이 값이 재조회 전에 바뀐다.
    var launchFinished = false
    // 성공 결과를 받은 시점에 실제 화면 대기를 끝낸다.
    let ready = expectation(description: "Launch finishes on successful retry")
    // 최소 표시 시간 이후에도 보류 중에는 기다리는지 측정한다.
    let startedAt = Date()
    // 준비 완료 신호는 재조회 성공 후 한 번만 전달한다.
    let launch = service.prepareLaunch().subscribe(
      onNext: {
        launchFinished = true
        ready.fulfill()
      }
    )
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
      XCTAssertFalse(launchFinished)
      response.onNext(.init(instrument: order.instrument, price: 100, timestamp: 65_123))
    }
    wait(for: [ready], timeout: 4)
    XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(startedAt), 1.65)
    XCTAssertLessThan(Date().timeIntervalSince(startedAt), 4)
    XCTAssertEqual(requests, 2)
    XCTAssertEqual(quoteRequests, 2)
    launch.dispose()
  }

  func testLateAccountReactorRetainsCompletedVerificationDuringNextRefresh() throws {
    // 인트로에서 검증을 마친 뒤 메인 화면에서 사용할 포지션이다.
    let order = domesticFuturesOrder(margin: 100, price: 100)
    // 앱 진입과 메인 화면이 공유하는 실제 계좌다.
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    _ = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    // 두 번째 검증 응답은 메인 표시 이후까지 지연시킨다.
    let response = PublishSubject<FuturesMarkQuote>()
    // 최초 검증과 그 직후 주기 검증을 구분한다.
    var requests = 0
    // 최초 검증에서는 안전한 과거 구간을 정상 확인한다.
    var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 100)
    provider.quoteOverride = {
      requests += 1
      return requests == 1
        ? .just(.init(instrument: order.instrument, price: 100, timestamp: 65_123))
        : response.take(1).asSingle()
    }
    // 저장 간격 사이에 완료한 가격을 진입 가격과 다르게 만들어 유실을 확인한다.
    provider.boundaryOverride = { start, end in
      .just(
        .init(
          instrument: order.instrument,
          start: start,
          endExclusive: end,
          candles: [.init(openTime: start, closeTime: end - 1, open: 105, high: 105, low: 105, close: 105)],
          funding: [],
          detailed: true
        )
      )
    }
    // 새 화면 구독 전에 검증 결과를 보관해야 하는 서비스다.
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) }
    )
    defer { service.suspend() }
    refreshAndWait(service)
    // 다음 조회가 시작된 이후에 Reactor를 만들어 인트로 이후 순서를 재현한다.
    let refreshing = expectation(description: "Next refresh started")
    // 이미 완료된 첫 조회와 새로 진행 중인 조회를 구분한다.
    let status = service.status.filter {
      if case .refreshing = $0 { return true }
      return false
    }.take(1).subscribe(onNext: { _ in refreshing.fulfill() })
    service.refresh()
    wait(for: [refreshing], timeout: 3)
    status.dispose()
    // 거래소·상품을 연속 전환해도 진행 중인 검증의 REST 요청은 하나다.
    for _ in 0..<10 { service.refresh() }
    // 메인은 새 검증을 기다리지 않고 앞선 완료 결과를 표시 준비에 사용한다.
    let reactor = FuturesAccountReactor(
      account: order.account,
      useCase: FuturesTradingUseCase(store: { repository }, historyCheck: service),
      historyCheck: service,
      provider: provider
    )
    // 초기 스냅샷과 인트로에서 완료한 검증이 함께 반영된 시점이다.
    let loaded = expectation(description: "Late main reactor can display its verified position")
    // 실제 Reactor 구독을 사용해 수동 상태 주입으로 결과 유실을 숨기지 않는다.
    let subscription = reactor.state.filter {
      guard case .refreshing = $0.status else { return false }
      return $0.snapshot != nil && $0.lastCompletedVerification?.first?.hold == nil
        && $0.lastCompletedVerification?.first?.positionID == order.requestID
    }.take(1).subscribe(
      onNext: { _ in
        XCTAssertTrue(reactor.canDisplayValuation)
        XCTAssertEqual(reactor.valuationQuotes[order.instrument]?.price, 105)
        if case .refreshing = reactor.currentState.status {} else { XCTFail("Next refresh should still be pending") }
        loaded.fulfill()
      }
    )
    wait(for: [loaded], timeout: 3)
    // 새 Reactor 자체의 평가 시세 조회를 제외하고 검증 요청은 두 번째에서 합쳐진다.
    XCTAssertEqual(requests, 3)
    subscription.dispose()
    // 재조회 실패가 완료한 검증 가격까지 삭제해서는 안 된다.
    let held = expectation(description: "Failed refresh retains previously verified price")
    // 실제 상태 이벤트로 실패 이후의 자동 표시를 확인한다.
    let heldSubscription = reactor.state.filter {
      guard case .finished(let results) = $0.status else { return false }
      return results.first?.hold == .missingHistory
    }.take(1).subscribe(onNext: { _ in
      XCTAssertEqual(reactor.valuationQuotes[order.instrument]?.price, 105)
      XCTAssertFalse(reactor.canSubmit)
      held.fulfill()
    })
    defer { heldSubscription.dispose() }
    response.onError(FuturesMarketDataError.invalidResponse)
    wait(for: [held], timeout: 3)
  }

  func testLaunchTimeoutDoesNotCancelHistoricalLiquidation() throws {
    // 인트로 제한 시간을 넘겨 응답하는 과거 청산 포지션이다.
    let order = domesticFuturesOrder(margin: 100, price: 100)
    // 지연 중에도 저장 상태를 비교할 독립 계좌다.
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    // 현재가만 먼저 표시해 청산 전 이익을 오인하지 않도록 원본을 유지한다.
    let before = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    // 인트로 종료 이후 과거 검증을 재개할 응답이다.
    let response = PublishSubject<FuturesMarkQuote>()
    // 과거 가격 하락 후 현재가는 회복한 경우에도 청산을 확정한다.
    var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 80)
    provider.quoteOverride = { response.take(1).asSingle() }
    // 화면 대기와 별개로 검증 작업을 소유한다.
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) }
    )
    defer { service.suspend() }
    // 네트워크가 늦더라도 인트로 종료 신호를 전달해야 한다.
    let ready = expectation(description: "Launch waiting timed out")
    // 실제 앱의 기본 5초 제한 이후에도 검증 작업이 유지돼야 한다.
    let startedAt = Date()
    // 화면 대기 구독만 종료하고 서비스 소유 작업은 유지한다.
    let launch = service.prepareLaunch().subscribe(onNext: { ready.fulfill() })
    wait(for: [ready], timeout: 7)
    XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(startedAt), 4.9)
    XCTAssertLessThan(Date().timeIntervalSince(startedAt), 7)
    launch.dispose()
    XCTAssertEqual(try repository.snapshot(), before)
    // 인트로가 끝난 후 메인에서 같은 서비스를 구독하는 계좌 상태다.
    let reactor = FuturesAccountReactor(
      account: order.account,
      useCase: FuturesTradingUseCase(store: { repository }, historyCheck: service),
      historyCheck: service,
      provider: provider
    )
    // 메인 구독이 청산 저장 결과를 사용자 조작 없이 반영해야 한다.
    let updated = expectation(description: "Main account removes liquidated position automatically")
    // 지연 중에는 초기 계좌를 표시하고 완료 시 최신 스냅샷을 읽는다.
    let accountSubscription = reactor.state.filter { state in
      state.snapshot?.positions.contains(where: { $0.id == order.requestID }) == true
        && state.snapshot?.isActive(before.positions[0]) == false
    }.take(1).subscribe(onNext: { state in
      XCTAssertTrue(reactor.positions.isEmpty)
      XCTAssertTrue(reactor.canDisplayValuation)
      XCTAssertTrue(state.quotes.isEmpty)
      updated.fulfill()
    })
    defer { accountSubscription.dispose() }
    // 화면 대기 구독 해제가 검증을 취소하지 않았는지 확인한다.
    let liquidated = expectation(description: "Historical liquidation continues after launch timeout")
    // 청산 결과는 반드시 저장 후 메인 안내로 전달된다.
    let notices = service.liquidationEvents.take(1).subscribe(
      onNext: { positions in
        XCTAssertEqual(positions.first?.id, before.positions.first?.id)
        XCTAssertNotNil(try? repository.snapshot().historyCheckStates[0].liquidation)
        liquidated.fulfill()
      }
    )
    response.onNext(.init(instrument: order.instrument, price: 134, timestamp: 65_123))
    wait(for: [liquidated, updated], timeout: 3)
    notices.dispose()
  }

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

  func testForegroundResumeKeepsVerifiedPriceCoalescesConnectionsAndAutomaticallyUpdatesValuation() throws {
    try verifyForegroundResume(liquidates: false)
  }

  func testForegroundResumeSettlesBufferedDipEvenIfSocketRecoversWithoutAnotherTick() throws {
    try verifyForegroundResume(liquidates: true)
  }

  func testForegroundBufferedLiquidationWaitsForFailedHistoryRetryToComplete() throws {
    try verifyForegroundResume(liquidates: true, holdsFirst: true)
  }

  private func verifyForegroundResume(liquidates: Bool, holdsFirst: Bool = false) throws {
    // 같은 계좌와 Reactor를 유지해 앱 재실행이 아닌 백그라운드 복귀를 재현한다.
    let order = domesticFuturesOrder(margin: 100, price: 100)
    // 실제 정산을 검증할 테스트 저장소다.
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    _ = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    // 복귀 후 검증 응답은 소켓 가격보다 늦게 도착하도록 제어한다.
    let response = PublishSubject<FuturesMarkQuote>()
    // 검증 REST 조회와 화면 평가 REST 조회를 구분한다.
    var requests = 0
    // 백그라운드 중의 시간 경과를 모의한다.
    var now = Date(timeIntervalSince1970: 66)
    // 검증 재개가 저장된 경계에서 시작하는지 확인한다.
    var starts: [Int64] = []
    // 최초 완료 가격을 진입 가격과 다르게 만들어 캐시 소실을 검출한다.
    var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 100)
    provider.quoteOverride = {
      requests += 1
      return requests == 1
        ? .just(.init(instrument: order.instrument, price: 105, timestamp: 65_123))
        : response.take(1).asSingle()
    }
    provider.boundaryOverride = { start, end in
      starts.append(start)
      if holdsFirst, requests == 2 { return .error(FuturesMarketDataError.incompleteHistory) }
      return .just(
        .init(
          instrument: order.instrument,
          start: start,
          endExclusive: end,
          candles: [.init(openTime: start, closeTime: end - 1, open: 105, high: 105, low: 105, close: 105)],
          funding: [],
          detailed: true
        )
      )
    }
    // 최초 연결의 false·true 알림과 중복 연결 알림을 재현한다.
    let monitor = FuturesMonitorFixture()
    // SceneDelegate와 동일하게 suspend 후 refresh로 복귀한다.
    let service = FuturesHistoryCheckService(store: { repository }, provider: { _ in provider }, now: { now }, monitor: monitor)
    defer { service.suspend() }
    // 연결 자체가 최초 검증을 시작하므로 추가 refresh로 완료 직후 다음 검증을 만들지 않는다.
    let initial = expectation(description: "First connection completes history once")
    // 초기 finished([])는 포지션 검증 완료가 아니다.
    let initialSubscription = service.status.filter {
      if case .finished(let results) = $0 { return results.first?.hold == nil && results.first?.positionID == order.requestID }
      return false
    }.take(1).subscribe(onNext: { _ in initial.fulfill() })
    monitor.subject.onNext(.connection(.upbit, true))
    wait(for: [initial], timeout: 3)
    initialSubscription.dispose()
    // 화면 조회가 검증 요청 횟수를 늘리지 않도록 별도의 평가 제공자를 사용한다.
    var displayProvider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 100)
    displayProvider.quoteOverride = { .just(.init(instrument: order.instrument, price: 105, timestamp: 65_123)) }
    // 복귀 시 새로 만들지 않고 동일한 화면 상태를 구독한다.
    let reactor = FuturesAccountReactor(
      account: order.account,
      useCase: FuturesTradingUseCase(store: { repository }, historyCheck: service),
      historyCheck: service,
      provider: displayProvider
    )
    // 상태·시세·청산 구독을 테스트 종료 때 함께 해제한다.
    let disposeBag = DisposeBag()
    // 최초 가격 표시가 끝난 이후 백그라운드로 내려간다.
    let loaded = expectation(description: "Initial verified valuation loaded")
    reactor.state.filter { $0.snapshot != nil && $0.lastCompletedVerification?.first?.lastVerifiedMark == 105 }
      .take(1).subscribe(onNext: { _ in loaded.fulfill() }).disposed(by: disposeBag)
    wait(for: [loaded], timeout: 3)
    // 취소된 검증의 예약 작업과 tick이 백그라운드에서 반영되면 안 된다.
    let paused = expectation(description: "Background revokes readiness but retains price")
    reactor.state.filter { if case .paused = $0.status { return true }; return false }.take(1)
      .subscribe(onNext: { _ in
        XCTAssertEqual(reactor.valuationQuotes[order.instrument]?.price, 105)
        XCTAssertFalse(reactor.canSubmit)
        paused.fulfill()
      }).disposed(by: disposeBag)
    service.suspend()
    wait(for: [paused], timeout: 3)
    // 복귀 검증이 이어갈 실제 저장 경계다.
    let savedThrough = try repository.snapshot().historyCheckStates[0].verifiedThrough
    now = Date(timeIntervalSince1970: 67)
    // 검증 중에는 최신 소켓을 수신해도 확정 가격으로 손익을 계산한다.
    let received = expectation(description: "Foreground socket received while history is pending")
    reactor.state.filter { $0.quotes[order.instrument]?.price == 110 }.take(1)
      .subscribe(onNext: { _ in
        XCTAssertEqual(reactor.valuationQuotes[order.instrument]?.price, 105)
        XCTAssertEqual(try? FuturesText.valuation(reactor.positions[0], quotes: reactor.valuationQuotes)?.displayedPnL, 50)
        received.fulfill()
      }).disposed(by: disposeBag)
    service.refresh()
    monitor.subject.onNext(.connection(.upbit, false))
    monitor.subject.onNext(.connection(.upbit, true))
    monitor.subject.onNext(.connection(.upbit, true))
    if liquidates {
      monitor.subject.onNext(.quote(.init(instrument: order.instrument, price: 80, timestamp: 66_900)))
    }
    monitor.subject.onNext(.quote(.init(instrument: order.instrument, price: 110, timestamp: 66_999)))
    wait(for: [received], timeout: 3)
    XCTAssertEqual(requests, 2)
    XCTAssertEqual(try repository.snapshot().historyCheckStates[0].verifiedThrough, savedThrough)
    // 청산 안내와 완료 상태 모두 저장된 결과를 전달해야 한다.
    var noticeCount = 0
    service.liquidationEvents.subscribe(onNext: { positions in
      noticeCount += positions.count
      XCTAssertNotNil(try? repository.snapshot().historyCheckStates[0].liquidation)
    }).disposed(by: disposeBag)
    if holdsFirst {
      // 소켓 청산 가격이 있어도 과거 구간 미검증 상태에서 정산하지 않는다.
      let held = expectation(description: "Buffered liquidation waits for complete history")
      reactor.state.filter {
        if case .finished(let results) = $0.status { return results.first?.hold == .missingHistory }
        return false
      }.take(1).subscribe(onNext: { _ in held.fulfill() }).disposed(by: disposeBag)
      response.onNext(.init(instrument: order.instrument, price: 105, timestamp: 66_123))
      wait(for: [held], timeout: 3)
      XCTAssertNil(try repository.snapshot().historyCheckStates[0].liquidation)
      XCTAssertEqual(noticeCount, 0)
      XCTAssertEqual(reactor.valuationQuotes[order.instrument]?.price, 105)
      XCTAssertFalse(reactor.canSubmit)
      // 재시도 구독이 준비된 이후 응답해야 누락된 가격을 재사용할 수 있다.
      let retry = expectation(description: "History retry subscribes to response")
      reactor.state.filter { if case .refreshing = $0.status { return true }; return false }
        .take(1).subscribe(onNext: { _ in retry.fulfill() }).disposed(by: disposeBag)
      service.refresh()
      wait(for: [retry], timeout: 3)
    }
    // 다음 tick이나 화면 재진입 없이 완료 결과가 자동 반영되는지 확인한다.
    let completed = expectation(description: "Foreground result automatically reflected")
    reactor.state.filter {
      guard case .finished(let results) = $0.status else { return false }
      return results.first?.verifiedThrough == 66_124 || results.first?.liquidated == true
    }.filter { _ in liquidates ? reactor.positions.isEmpty : reactor.valuationQuotes[order.instrument]?.price == 110 }
      .take(1).subscribe(onNext: { _ in completed.fulfill() }).disposed(by: disposeBag)
    response.onNext(.init(instrument: order.instrument, price: 105, timestamp: 66_123))
    wait(for: [completed], timeout: 3)
    XCTAssertEqual(starts.last, savedThrough)
    XCTAssertEqual(requests, holdsFirst ? 3 : 2)
    XCTAssertEqual(noticeCount, liquidates ? 1 : 0)
    if liquidates {
      XCTAssertEqual(try repository.snapshot().historyCheckStates[0].liquidation?.observedAt, 66_900)
      XCTAssertEqual(try repository.snapshot().transactionHistory(for: order.account).filter { $0.kind == .liquidation }.count, 1)
    } else {
      XCTAssertEqual(try FuturesText.valuation(reactor.positions[0], quotes: reactor.valuationQuotes)?.displayedPnL, 100)
      XCTAssertEqual(try FuturesText.valuation(reactor.positions[0], quotes: reactor.valuationQuotes)?.displayedROEPercent, 100)
    }
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
    // 인트로는 현재가 수신이 아닌 청산 저장 완료를 기다린다.
    let launchReady = expectation(description: "Launch waits for saved historical liquidation")
    // 초기 finished([])를 준비 완료로 처리하면 이 값이 너무 일찍 바뀐다.
    var ready = false
    // 안내를 유실하지 않고 메인 진입 전에 저장되는지도 확인한다.
    let launch = service.prepareLaunch().subscribe(
      onNext: {
        ready = true
        XCTAssertNotNil(try? repository.snapshot().historyCheckStates[0].liquidation)
        launchReady.fulfill()
      }
    )
    service.observe(.init(instrument: order.instrument, price: 80, timestamp: 65_999))
    wait(for: [live], timeout: 3)
    subscription.dispose()
    XCTAssertFalse(ready)
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
    wait(for: [finished, launchReady], timeout: 3)
    completion.dispose()
    launch.dispose()
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
