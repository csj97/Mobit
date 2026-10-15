import XCTest
import UIKit
import RxSwift
import Moya
import Alamofire
@testable import Mobit

final class FuturesHistoryCheckTests: XCTestCase {
  private var directory: URL!
  private var url: URL { directory.appendingPathComponent("accounts.json") }
  private var store: LocalFuturesAccountRepository { LocalFuturesAccountRepository(fileURL: url) }
  private var position: FuturesPosition {
    get throws { try FuturesCalculator.open(futuresOrder(date: Date(timeIntervalSince1970: 60))) }
  }
  private let settledAt = Date(timeIntervalSince1970: 300)

  func testLaunchModeAndForegroundRequestsCoalesceAndStayStoppedInBackground() throws {
    // 진입 경로가 달라도 같은 저장 포지션을 검증한다.
    let repository = store
    // 검증 대기 중에도 보존할 원본 포지션이다.
    let order = domesticFuturesOrder(margin: 100, price: 100)
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    // 취소된 응답이 저장 자산을 바꾸지 않았는지 비교한다.
    let before = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    // 요청을 끝내지 않고 여러 진입 이벤트를 겹친다.
    let response = PublishSubject<FuturesMarkQuote>()
    // 실제 구독과 취소 횟수로 동시 요청 여부를 확인한다.
    let requests = FuturesRequestCounter()
    // 백그라운드에서 진행 중인 요청도 취소됐는지 확인한다.
    let cancellations = FuturesRequestCounter()
    // 최초 앱 시작과 실제 복귀에서만 요청을 허용한다.
    let started = expectation(description: "Launch request starts once")
    // 화면 갱신으로 재개하지 않고 Scene 활성화에서 재개한다.
    let resumed = expectation(description: "Active scene resumes once")
    // 검증 응답은 모든 진입 이벤트를 보낸 다음 반환한다.
    var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 100)
    provider.quoteOverride = {
      response.take(1).asSingle().do(onSubscribe: {
        requests.increment()
        if requests.count == 1 { started.fulfill() }
        if requests.count == 2 { resumed.fulfill() }
      }, onDispose: { cancellations.increment() })
    }
    // 네트워크 복구와 소켓 이벤트도 앱 중단 상태를 존중해야 한다.
    let availability = BehaviorSubject(value: true)
    // 최초 소켓 연결은 이미 시작한 REST 요청에 합쳐진다.
    let monitor = FuturesMonitorFixture()
    // 모든 진입 경로가 공유하는 실제 서비스다.
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) },
      monitor: monitor,
      networkAvailability: availability
    )
    defer { service.suspend() }
    // 앱 시작의 로컬 준비 구독 수명을 유지한다.
    let disposeBag = DisposeBag()
    service.prepareLaunch().subscribe().disposed(by: disposeBag)
    for _ in 0..<10 { service.resume(); service.refresh() }
    monitor.subject.onNext(.connection(.upbit, true))
    wait(for: [started], timeout: 3)
    // 대기 중 요청을 앱 비활성화로 취소한다.
    let paused = expectation(description: "Scene suspends outstanding work")
    service.status.filter { if case .paused = $0 { return true }; return false }.take(1)
      .subscribe(onNext: { _ in paused.fulfill() }).disposed(by: disposeBag)
    service.suspend()
    wait(for: [paused], timeout: 3)
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(cancellations.count, 1)
    for _ in 0..<10 { service.refresh() }
    service.prepareLaunch().subscribe().disposed(by: disposeBag)
    availability.onNext(false)
    availability.onNext(true)
    availability.onNext(true)
    monitor.subject.onNext(.connection(.upbit, true))
    response.onNext(.init(instrument: order.instrument, price: 80, timestamp: 65_123))
    // 지연된 화면 준비·복구·응답이 모두 처리될 시간을 준다.
    let quiet = expectation(description: "Background requests stay cancelled")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { quiet.fulfill() }
    wait(for: [quiet], timeout: 2)
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(try repository.snapshot(), before)
    for _ in 0..<10 { service.resume(); service.refresh() }
    wait(for: [resumed], timeout: 3)
    // 복귀 검증 완료도 한 번만 전달돼야 한다.
    let completed = expectation(description: "One resumed verification completes")
    service.status.filter {
      if case .finished(let results) = $0 { return results.first?.positionID == order.requestID && results.first?.hold == nil }
      return false
    }.take(1).subscribe(onNext: { _ in completed.fulfill() }).disposed(by: disposeBag)
    response.onNext(.init(instrument: order.instrument, price: 100, timestamp: 65_123))
    wait(for: [completed], timeout: 3)
    XCTAssertEqual(requests.count, 2)
  }

  func testOfflineLaunchAutomaticallyRecoversWithoutAnAccountScreen() throws {
    // 화면 구독 없이도 공통 서비스가 복구해야 한다.
    let repository = store
    // 최초 네트워크 연결 전에 로컬 자산은 읽을 수 있다.
    let order = domesticFuturesOrder(margin: 100, price: 100)
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    // 오프라인 시작과 복구 알림을 제어한다.
    let availability = BehaviorSubject(value: false)
    // 연결 복구 전후 실제 원격 요청 횟수를 확인한다.
    let requests = FuturesRequestCounter()
    // 최초 정상 연결에서 준비된 이력을 반환한다.
    var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 100)
    provider.quoteOverride = {
      requests.increment()
      return .just(.init(instrument: order.instrument, price: 100, timestamp: 65_123))
    }
    // 네트워크 복구를 맡은 서비스에는 화면을 연결하지 않는다.
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) },
      networkAvailability: availability
    )
    defer { service.suspend() }
    // 로컬 준비와 네트워크 검증은 별도로 끝난다.
    let ready = expectation(description: "Offline launch reads local account")
    // 테스트 이벤트 구독을 함께 해제한다.
    let disposeBag = DisposeBag()
    service.prepareLaunch().subscribe(onNext: { ready.fulfill() }).disposed(by: disposeBag)
    service.resume()
    service.refresh()
    wait(for: [ready], timeout: 3)
    XCTAssertEqual(requests.count, 0)
    // 화면과 무관하게 도메인 주문 준비도 오프라인에서는 막는다.
    let blocked = expectation(description: "Offline order is blocked")
    service.prepareOrder(account: order.account, instrument: order.instrument, price: socketPrice(order.instrument, at: 66_000))
      .subscribe(onSuccess: { _ in XCTFail("Offline order must stay blocked"); blocked.fulfill() }, onFailure: {
        XCTAssertEqual($0 as? FuturesOrderCheckError, .historyCheckInProgress)
        blocked.fulfill()
      }).disposed(by: disposeBag)
    wait(for: [blocked], timeout: 3)
    // 화면 이동 없이 연결 알림만으로 실제 검증을 완료한다.
    let completed = expectation(description: "Network restoration completes verification")
    service.status.filter {
      if case .finished(let results) = $0 { return results.first?.positionID == order.requestID && results.first?.hold == nil }
      return false
    }.take(1).subscribe(onNext: { _ in completed.fulfill() }).disposed(by: disposeBag)
    availability.onNext(true)
    availability.onNext(true)
    wait(for: [completed], timeout: 3)
    XCTAssertEqual(requests.count, 1)
  }

  func testReconnectRejectsOldResponseAndUnlocksAssetsAndOrdersOnlyAfterNewHistoryCompletes() throws {
    try verifyConnectionRecovery(networkLoss: true)
  }

  func testSocketDisconnectInvalidatesExistingAndRecreatedScreenUntilNewHistoryCompletes() throws {
    try verifyConnectionRecovery(networkLoss: false)
  }

  private func verifyConnectionRecovery(networkLoss: Bool) throws {
    // 실제 자산 저장·검증·화면 표시를 함께 연결한다.
    let repository = store
    // 검증 가격과 실시간 가격이 다른 포지션이다.
    let order = domesticFuturesOrder(margin: 100, price: 100)
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    // 첫 검증 이후 시간 경과를 재현한다.
    var now = Date(timeIntervalSince1970: 66)
    // 취소된 이전 연결의 응답을 복구 이후 반환한다.
    let oldResponse = PublishSubject<FuturesMarkQuote>()
    // 복구 후 현재가 수신과 과거 검증 완료 시점을 분리한다.
    let historyPrice = PublishSubject<Decimal>()
    // 실제 검증 시도만 계수하고 화면 평가 요청은 제외한다.
    let requests = FuturesRequestCounter()
    // 기존 연결에서 진행 중이던 요청을 확인한다.
    let oldStarted = expectation(description: "Old connection request is pending")
    // 새 연결의 과거 검증이 아직 끝나지 않은 시점을 확인한다.
    let historyStarted = expectation(description: "New history is pending after reconnect")
    // 최초 검증은 완료하고 다음 요청은 이전·현재 연결로 분리한다.
    var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 100)
    provider.quoteOverride = {
      requests.increment()
      if requests.count == 2 {
        return oldResponse.take(1).asSingle().do(onSubscribe: { oldStarted.fulfill() })
      }
      return .just(.init(instrument: order.instrument, price: 105, timestamp: requests.count == 1 ? 65_123 : 66_123))
    }
    provider.boundaryOverride = { start, end in
      // 첫 검증은 105원, 복구 검증은 별도의 과거 이력 응답을 기다린다.
      let prices: Single<Decimal> = requests.count == 1
        ? .just(105)
        : historyPrice.take(1).asSingle().do(onSubscribe: { historyStarted.fulfill() })
      return prices.map { price in
        .init(
          instrument: order.instrument,
          start: start,
          endExclusive: end,
          candles: [.init(openTime: start, closeTime: end - 1, open: price, high: price, low: price, close: price)],
          funding: [],
          detailed: true
        )
      }
    }
    // 실제 소켓 감시 조건까지 주문 준비에 적용한다.
    let monitor = FuturesMonitorFixture()
    // 동일한 네트워크 이벤트를 서비스와 화면에 전달한다.
    let availability = BehaviorSubject(value: true)
    // 네트워크 세션을 구분하는 실제 검증 서비스다.
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { now },
      monitor: monitor,
      networkAvailability: availability
    )
    defer { service.suspend() }
    // 자산 화면 REST는 105원을 유지하고 소켓에서만 새 가격을 보낸다.
    var display = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 100)
    display.quoteOverride = { .just(.init(instrument: order.instrument, price: 105, timestamp: 65_123)) }
    func makeReactor() -> FuturesAccountReactor {
      FuturesAccountReactor(
        account: order.account,
        useCase: FuturesTradingUseCase(store: { repository }, historyCheck: service),
        historyCheck: service,
        provider: display,
        networkAvailability: availability
      )
    }
    // 연결 유실을 직접 경험하는 기존 화면이다.
    let reactor = makeReactor()
    // 모든 화면·서비스 구독을 테스트 종료까지 유지한다.
    let disposeBag = DisposeBag()
    // 최초 검증 완료 가격을 확보한다.
    let initial = expectation(description: "Initial verified account is ready")
    reactor.state.filter { _ in reactor.canSubmit && reactor.valuationQuotes[order.instrument]?.price == 105 }.take(1)
      .subscribe(onNext: { _ in initial.fulfill() }).disposed(by: disposeBag)
    monitor.subject.onNext(.connection(.upbit, true))
    wait(for: [initial], timeout: 3)
    now = Date(timeIntervalSince1970: 67)
    service.refresh()
    wait(for: [oldStarted], timeout: 3)
    // 재연결 이후에도 이 저장 경계를 건너뛰면 안 된다.
    let before = try repository.snapshot()
    // 연결 유실은 기존 화면의 완료 상태도 폐기한다.
    let paused = expectation(description: "Network loss invalidates verified state")
    reactor.state.filter {
      if case .paused = $0.status { return !reactor.canSubmit }
      return false
    }.take(1).subscribe(onNext: { _ in paused.fulfill() }).disposed(by: disposeBag)
    if networkLoss { availability.onNext(false) }
    else { monitor.subject.onNext(.connection(.upbit, false)) }
    wait(for: [paused], timeout: 3)
    if networkLoss {
      availability.onNext(true)
      availability.onNext(true)
    }
    wait(for: [historyStarted], timeout: 3)
    // 복구 중 모드 전환으로 생성된 화면도 이전 완료 결과를 재사용하면 안 된다.
    let next = makeReactor()
    // 화면의 로컬 포지션 구독이 준비된 뒤 소켓 가격을 전달한다.
    let nextLoaded = expectation(description: "Recreated screen receives invalidated verification")
    next.state.filter {
      guard case .refreshing = $0.status else { return false }
      return $0.snapshot != nil && $0.lastCompletedVerification?.first?.hold != nil
    }.take(1).subscribe(onNext: { _ in
      XCTAssertFalse(next.canSubmit)
      nextLoaded.fulfill()
    }).disposed(by: disposeBag)
    wait(for: [nextLoaded], timeout: 3)
    // 새 화면과 기존 화면이 같은 실시간 가격을 수신한다.
    let received = expectation(description: "Both screens receive unverified live quote")
    received.expectedFulfillmentCount = 2
    for screen in [reactor, next] {
      screen.state.filter { $0.snapshot != nil && $0.quotes[order.instrument]?.price == 110 }.take(1)
        .subscribe(onNext: { _ in
          XCTAssertFalse(screen.canSubmit)
          XCTAssertEqual(screen.valuationQuotes[order.instrument]?.price, 105)
          received.fulfill()
        }).disposed(by: disposeBag)
    }
    monitor.subject.onNext(.connection(.upbit, true))
    monitor.subject.onNext(.quote(.init(instrument: order.instrument, price: 110, timestamp: 66_999)))
    oldResponse.onNext(.init(instrument: order.instrument, price: 80, timestamp: 66_123))
    wait(for: [received], timeout: 3)
    // 화면 버튼뿐 아니라 실제 주문 검증도 완료 전까지 거부한다.
    let blocked = expectation(description: "New connection alone cannot unlock orders")
    service.prepareOrder(account: order.account, instrument: order.instrument, price: socketPrice(order.instrument, at: 67_000))
      .subscribe(onSuccess: { _ in XCTFail("History is not complete"); blocked.fulfill() }, onFailure: {
        XCTAssertEqual($0 as? FuturesOrderCheckError, .historyCheckInProgress)
        blocked.fulfill()
      }).disposed(by: disposeBag)
    wait(for: [blocked], timeout: 3)
    XCTAssertEqual(try repository.snapshot(), before)
    XCTAssertEqual(requests.count, 3)
    // 새로운 과거 이력 검증이 끝나야 두 화면의 평가와 거래 가능 상태가 함께 바뀐다.
    let recovered = expectation(description: "Verified recovery updates both accounts")
    recovered.expectedFulfillmentCount = 2
    for screen in [reactor, next] {
      screen.state.filter { _ in screen.canSubmit && screen.valuationQuotes[order.instrument]?.price == 110 }.take(1)
        .subscribe(onNext: { _ in recovered.fulfill() }).disposed(by: disposeBag)
    }
    historyPrice.onNext(110)
    wait(for: [recovered], timeout: 3)
    // 완료 이벤트 뒤 도메인 주문 준비도 같은 기준으로 허용한다.
    let prepared = expectation(description: "Verified connection unlocks domain orders")
    service.prepareOrder(account: order.account, instrument: order.instrument, price: socketPrice(order.instrument, at: 67_000))
      .subscribe(onSuccess: { _ in prepared.fulfill() }, onFailure: {
        XCTFail("Verified order failed: \($0)"); prepared.fulfill()
      }).disposed(by: disposeBag)
    wait(for: [prepared], timeout: 3)
    XCTAssertEqual(requests.count, 3)
  }

  func testManualRetryInvalidatesOldTimerAndNetworkLossStopsRetryLoop() throws {
    // 요청 실패 후 자동 예약이 남아 있는 상황을 재현한다.
    let repository = store
    // 재시도 대상인 실제 미검증 포지션이다.
    let order = domesticFuturesOrder(margin: 100, price: 100)
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    // 재시도와 중복 연결 알림을 실제 요청 횟수로 비교한다.
    let requests = FuturesRequestCounter()
    // 첫 실패 이후 모든 요청은 응답을 대기시킨다.
    let response = PublishSubject<FuturesMarkQuote>()
    // 수동 재시도가 기존 자동 예약을 무효화해야 한다.
    let retried = expectation(description: "Manual retry starts once")
    // 오프라인 중단 뒤 연결 복구만 새 요청을 허용한다.
    let restored = expectation(description: "Restoration starts one new request")
    // 요청 생성 시점과 구독을 함께 확인한다.
    var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 100)
    provider.quoteOverride = {
      requests.increment()
      if requests.count == 1 { return .error(URLError(.timedOut)) }
      return response.take(1).asSingle().do(onSubscribe: {
        if requests.count == 2 { retried.fulfill() }
        if requests.count == 3 { restored.fulfill() }
      })
    }
    // 최초 연결 상태는 자동 검증을 별도로 시작하지 않는다.
    let availability = BehaviorSubject(value: true)
    // 예약 기한을 짧게 해 이전 예약의 무효화를 실제 확인한다.
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) },
      networkAvailability: availability,
      failureRetryDelay: { _ in 0.15 }
    )
    defer { service.suspend() }
    refreshAndWait(service)
    for _ in 0..<10 { service.refresh() }
    wait(for: [retried], timeout: 3)
    // 예약 시각이 지나도 수동 재시도와 병렬 요청을 만들지 않는다.
    let timerElapsed = expectation(description: "Old retry timer has expired")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { timerElapsed.fulfill() }
    wait(for: [timerElapsed], timeout: 2)
    XCTAssertEqual(requests.count, 2)
    availability.onNext(false)
    for _ in 0..<10 { service.refresh() }
    // 오프라인에서는 앱이 활성 상태여도 요청을 반복하지 않는다.
    let offlineElapsed = expectation(description: "Offline stays idle beyond retry interval")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { offlineElapsed.fulfill() }
    wait(for: [offlineElapsed], timeout: 2)
    XCTAssertEqual(requests.count, 2)
    for _ in 0..<10 { availability.onNext(true) }
    wait(for: [restored], timeout: 3)
    XCTAssertEqual(requests.count, 3)
  }

  func testLaunchAutomaticallyRetriesTransientFailuresWithoutSkippingHistoryOrShowingError() throws {
    // 실패와 복구를 같은 저장 계좌에서 검증한다.
    let repository = store
    // 검증 이전 상태를 유지해야 하는 실제 보유 포지션이다.
    let order = domesticFuturesOrder(margin: 100, price: 100)
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    // 실패 중 자산과 검증 경계가 변경되지 않았는지 비교한다.
    let before = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    // 실패한 검증 경계를 다음 요청에서도 재사용하는지 기록한다.
    var starts: [Int64] = []
    // 첫 두 번만 실패하고 세 번째 자동 요청에서 정상 이력을 반환한다.
    var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 100)
    provider.boundaryOverride = { start, end in
      starts.append(start)
      if starts.count < 3 { return .error(URLError(.timedOut)) }
      return .just(.init(
        instrument: order.instrument,
        start: start,
        endExclusive: end,
        candles: [.init(openTime: start, closeTime: end - 1, open: 100, high: 100, low: 100, close: 100)],
        funding: [],
        detailed: true
      ))
    }
    // 테스트에서는 실제 자동 재시도 예약만 짧게 실행한다.
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) },
      failureRetryDelay: { _ in 0.05 }
    )
    defer { service.suspend() }
    // 앱 화면 구독 없이도 서비스가 자동 검증을 끝내야 한다.
    let recovered = expectation(description: "Automatic launch recovery")
    // 사용자에게 공개된 모든 오류 상태를 관찰한다.
    var notified = false
    // 짧은 검증 구간은 저장 체크포인트 간격과 별도로 완료 결과에서 확인한다.
    var verifiedThrough: Int64?
    // 초기 빈 결과와 실제 보유 포지션 검증을 구분한다.
    let status = service.status.subscribe(onNext: { status in
      guard case .finished(let results) = status, let result = results.first else { return }
      if result.hold == nil {
        verifiedThrough = result.verifiedThrough
        recovered.fulfill()
      } else { XCTAssertEqual(try? repository.snapshot(), before) }
    })
    // 일시 실패는 사용자 안내 대상으로 승격되면 안 된다.
    let failures = service.dataFailure(for: order.account).subscribe(onNext: { notified = notified || $0?.shouldNotify == true })
    // 인트로의 로컬 준비 경로가 자동 재시도를 시작한다.
    let launch = service.prepareLaunch().subscribe()
    wait(for: [recovered], timeout: 3)
    XCTAssertEqual(starts.count, 3)
    XCTAssertEqual(Set(starts).count, 1)
    XCTAssertFalse(notified)
    XCTAssertGreaterThan(try XCTUnwrap(verifiedThrough), before.historyCheckStates[0].verifiedThrough)
    status.dispose(); failures.dispose(); launch.dispose()
  }

  func testFailureEpisodeSurvivesRetryModeRecreationAndForegroundUntilSuccessfulVerification() throws {
    // 모드 전환 전후 같은 저장 계좌를 사용한다.
    let repository = store
    // 상세 이력이 필요한 실제 포지션이다.
    let order = domesticFuturesOrder(margin: 100, price: 100)
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    // 서비스 큐에서만 변경하는 요청 횟수다.
    var requests = 0
    // 세 번의 실패 다음 요청은 복구 응답을 직접 제어한다.
    let response = PublishSubject<FuturesMarkQuote>()
    // HTTP 제한 오류를 반복한 후 새 검증 요청을 대기시킨다.
    var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 100)
    provider.quoteOverride = {
      requests += 1
      if requests <= 3 { return .error(FuturesMarketDataError.httpStatus(429)) }
      return response.take(1).asSingle()
    }
    // 공통 서비스가 안내 소유권과 자동 재시도를 함께 유지한다.
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) },
      failureRetryDelay: { $0 < 3 ? 0.03 : 60 }
    )
    defer { service.suspend() }
    // 정상 표시용 가격 조회와 실패 검증을 분리한다.
    let display = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 100)
    func makeReactor() -> FuturesAccountReactor {
      FuturesAccountReactor(
        account: order.account,
        useCase: FuturesTradingUseCase(store: { repository }, historyCheck: service),
        historyCheck: service,
        provider: display,
        networkAvailability: .just(true)
      )
    }
    // 최초 화면에서 지속 실패를 한 번만 알린다.
    let first = makeReactor()
    // 세 번 실제 실패 후에만 안내를 허용한다.
    let failed = expectation(description: "Persistent validation failure")
    // 화면 소유의 구독 수명과 서비스의 오류 수명을 분리한다.
    let firstSubscription = first.state.filter { $0.dataFailure?.shouldNotify == true }.take(1)
      .subscribe(onNext: { _ in failed.fulfill() })
    service.refresh()
    wait(for: [failed], timeout: 3)
    XCTAssertTrue(first.claimDataFailureNotice())
    XCTAssertFalse(first.canSubmit)
    // 같은 검증 수동 재시도는 기존 안내 식별자를 유지한다.
    let failureID = first.currentState.dataFailure?.id
    first.action.onNext(.reload)
    service.suspend()
    service.resume()
    // 선물 모드 재진입으로 새 Reactor를 만들어도 안내를 반복하지 않는다.
    let next = makeReactor()
    // 직전 오류와 복귀 검증이 모두 전달될 때까지 기다린다.
    let resumed = expectation(description: "Recreated account receives same failure")
    // 새 화면의 검증·거래 상태를 실제 서비스와 연결한다.
    let nextSubscription = next.state.filter {
      guard case .refreshing = $0.status else { return false }
      return $0.dataFailure?.id == failureID && $0.snapshot != nil
    }.take(1).subscribe(onNext: { _ in resumed.fulfill() })
    wait(for: [resumed], timeout: 3)
    XCTAssertFalse(next.claimDataFailureNotice())
    XCTAssertFalse(next.canSubmit)
    // 자동 복구가 오류를 지우고 실제 검증 완료에만 거래를 허용한다.
    let recovered = expectation(description: "Recovery clears failure")
    // 시작 시 기본 finished([])를 복구로 오인하지 않는다.
    let recovery = next.state.filter { _ in next.canSubmit && next.currentState.dataFailure == nil }.take(1)
      .subscribe(onNext: { _ in recovered.fulfill() })
    response.onNext(.init(instrument: order.instrument, price: 100, timestamp: 65_123))
    wait(for: [recovered], timeout: 3)
    XCTAssertFalse(next.needsDataRetry)
    firstSubscription.dispose(); nextSubscription.dispose(); recovery.dispose()
  }

  func testFailurePolicySeparatesAccountsAndResetsNoticeOnlyAfterVerification() throws {
    // 오류를 한 계좌에 국한하고 진행 보류를 실패 횟수에 포함하지 않는다.
    let position = try FuturesCalculator.open(domesticFuturesOrder())
    // 다른 거래소의 검증 완료 계좌가 함께 있어도 오류는 전파하지 않는다.
    let other = try FuturesCalculator.open(domesticFuturesOrder(exchange: .bithumb))
    // 정상 계좌는 실패한 계좌와 별도로 준비 상태를 유지한다.
    let healthy = FuturesRefreshResult(positionID: other.id, verifiedThrough: nil, liquidated: false, hold: nil)
    // 화면이 재생성돼도 공유할 안내 정책이다.
    var policy = FuturesDataFailurePolicy()
    // 첫 요청 실패를 재사용해 동일 오류 구간을 재현한다.
    let failed = FuturesRefreshResult(positionID: position.id, verifiedThrough: nil, liquidated: false, hold: .requestFailed)
    policy.complete([failed, healthy], positions: [position, other])
    XCTAssertFalse(try XCTUnwrap(policy.failures.first).shouldNotify)
    policy.complete([.init(positionID: position.id, verifiedThrough: nil, liquidated: false, hold: .workLimit), healthy], positions: [position, other])
    XCTAssertEqual(policy.failures.first?.attempts, 1)
    policy.complete([failed, healthy], positions: [position, other])
    XCTAssertFalse(try XCTUnwrap(policy.failures.first).shouldNotify)
    policy.complete([failed, healthy], positions: [position, other])
    // 같은 안내는 계좌 화면 수명과 무관하게 한 번만 소비한다.
    let failure = try XCTUnwrap(policy.failures.first)
    XCTAssertTrue(failure.shouldNotify)
    XCTAssertEqual(failure.account, position.order.account)
    XCTAssertFalse(policy.failures.contains { $0.account == other.order.account })
    XCTAssertTrue(policy.claimNotice(failure.id))
    XCTAssertFalse(policy.claimNotice(failure.id))
    policy.complete([.init(positionID: position.id, verifiedThrough: nil, liquidated: false, hold: nil), healthy], positions: [position, other])
    XCTAssertTrue(policy.failures.isEmpty)
    policy.complete([failed, healthy], positions: [position, other])
    XCTAssertNotEqual(policy.failures.first?.id, failure.id)
    policy.recordStorageFailure()
    XCTAssertTrue(policy.failures.contains { $0.account == nil && $0.shouldNotify })
  }

  func testBackgroundCancelsScheduledRetryAndForegroundResumesSameFailure() throws {
    // 예약된 재시도를 중단할 실제 로컬 계좌다.
    let repository = store
    // 미검증 구간을 가진 포지션을 유지한다.
    let order = domesticFuturesOrder(margin: 100, price: 100)
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    // 백그라운드 중 추가 요청이 없는지 안전하게 계수한다.
    let counter = FuturesRequestCounter()
    // 복귀 전후 동일한 일시적 HTTP 오류를 재현한다.
    var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 100)
    provider.quoteOverride = { counter.increment(); return .error(FuturesMarketDataError.httpStatus(503)) }
    // 시간 경과와 명시적 refresh를 구분한다.
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) },
      failureRetryDelay: { _ in 0.15 }
    )
    defer { service.suspend() }
    // 처음 실패한 직후 실제 앱처럼 서비스를 중단한다.
    let paused = expectation(description: "Background cancels retry")
    // suspend 처리 완료를 확인한 뒤 자동 재시도 시간을 넘긴다.
    let status = service.status.subscribe(onNext: { status in
      if case .finished(let results) = status, !results.isEmpty { service.suspend() }
      if case .paused = status { paused.fulfill() }
    })
    service.refresh()
    wait(for: [paused], timeout: 3)
    status.dispose()
    // 실제 예약 기한이 지나도 inactive 서비스는 요청하지 않는다.
    let deadline = expectation(description: "Retry deadline elapsed")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { deadline.fulfill() }
    wait(for: [deadline], timeout: 2)
    XCTAssertEqual(counter.count, 1)
    // 실제 포그라운드 진입에서만 다음 실패 횟수를 이어간다.
    let resumed = expectation(description: "Foreground resumes failure episode")
    // 두 번째 실패는 여전히 조용히 복구하는 단계다.
    let failures = service.dataFailure(for: order.account).filter { $0?.attempts == 2 }.take(1)
      .subscribe(onNext: { failure in
        XCTAssertFalse(failure?.shouldNotify ?? true)
        resumed.fulfill()
      })
    service.resume()
    wait(for: [resumed], timeout: 3)
    XCTAssertEqual(counter.count, 2)
    failures.dispose()
  }

  func testLaunchStorageFailureIsAnnouncedAndAutomaticallyClearsAfterReadRecovery() {
    // 최초 인트로 읽기만 실패하도록 조회 횟수를 기록한다.
    var reads = 0
    // 실제 로컬 읽기 복구가 오류 구간을 종료한다.
    let service = FuturesHistoryCheckService(
      store: {
        reads += 1
        if reads == 1 { throw LocalFuturesAccountRepository.StoreError.invalidStoredData }
        return self.store
      },
      provider: { _ in nil },
      failureRetryDelay: { _ in 0.03 }
    )
    defer { service.suspend() }
    // 저장 실패는 일시적 네트워크 오류와 달리 즉시 안내한다.
    var sawStorageFailure = false
    // 자동 읽기 복구 뒤 오류가 제거될 때까지 기다린다.
    let recovered = expectation(description: "Storage read recovered automatically")
    // 계좌를 읽기 전에 발생한 전역 오류도 선물 화면에서 구독할 수 있다.
    let account = domesticFuturesOrder().account
    // initial nil과 실제 복구 nil을 구분한다.
    let failures = service.dataFailure(for: account).subscribe(onNext: { failure in
      if let failure {
        sawStorageFailure = true
        XCTAssertTrue(failure.shouldNotify)
        XCTAssertEqual(failure.hold, .storageFailed)
      } else if sawStorageFailure { recovered.fulfill() }
    })
    // 실패해도 인트로 준비는 완료되고 자동 복구는 서비스가 계속 수행한다.
    let launch = service.prepareLaunch().subscribe()
    wait(for: [recovered], timeout: 3)
    XCTAssertGreaterThanOrEqual(reads, 2)
    failures.dispose(); launch.dispose()
  }

  func testValidationDiagnosticsRetainFailureCodesWithoutSensitiveDescriptions() {
    XCTAssertEqual(FuturesHistoryCheckService.diagnosticCode(URLError(.timedOut)), "url.-1001")
    XCTAssertEqual(FuturesHistoryCheckService.diagnosticCode(FuturesMarketDataError.httpStatus(429)), "market.httpStatus(429)")
    XCTAssertEqual(FuturesHistoryCheckService.diagnosticCode(FuturesMarketDataError.incompleteHistory), "market.incompleteHistory")
    XCTAssertEqual(FuturesHistoryCheckService.diagnosticCode(RxError.timeout), "request.timeout")
    XCTAssertEqual(DomesticFuturesMarketRepository.networkFailureCode(
      MoyaError.underlying(AFError.sessionTaskFailed(error: URLError(.notConnectedToInternet)), nil)
    ), "url.-1009")
    XCTAssertEqual(DomesticFuturesMarketRepository.networkFailureCode(
      MoyaError.statusCode(Response(statusCode: 503, data: Data("private response".utf8)))
    ), "http.503")
    // NSError에 포함된 경로·응답 본문은 진단 문자열에 포함하지 않는다.
    let sensitive = NSError(domain: "test", code: 7, userInfo: [NSLocalizedDescriptionKey: "private-account-file-and-response"])
    XCTAssertFalse(FuturesHistoryCheckService.diagnosticCode(sensitive).contains("private-account"))
  }

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
      // 로컬 읽기 뒤 추가 대기를 하지 않는지 측정한다.
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
      XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1.4)
      XCTAssertLessThan(Date().timeIntervalSince(startedAt), 3)
      subscription.dispose()
      service.suspend()
    }
  }

  func testLaunchDoesNotWaitForMissingHistoryAndManualRetryVerifiesWithoutSkipping() throws {
    // 검증이 보류돼도 로컬 계좌가 준비되면 화면을 탐색할 수 있다.
    let order = domesticFuturesOrder(margin: 100, price: 100)
    // 검증 경계와 포지션 원본을 비교할 저장소다.
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    // 실패한 구간을 건너뛰지 않는지 확인한다.
    let before = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    // 첫 상세 요청만 실패시켜 재시도 결과를 확인한다.
    var requests = 0
    // 현재가 복구와 무관하게 과거 자료부터 재검증한다.
    var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 65_123, adverse: 100)
    provider.boundaryOverride = { start, end in
      requests += 1
      if requests == 1 { return .error(URLError(.notConnectedToInternet)) }
      return .just(.init(instrument: order.instrument, start: start, endExclusive: end,
        candles: [.init(openTime: start, closeTime: end - 1, open: 100, high: 100, low: 100, close: 100)], funding: [], detailed: true))
    }
    // 화면 준비와 과거 검증 수명이 다른 실제 서비스를 사용한다.
    let service = FuturesHistoryCheckService(store: { repository }, provider: { _ in provider }, now: { Date(timeIntervalSince1970: 66) })
    defer { service.suspend() }
    // 네트워크 오류가 발생한 보류 결과다.
    let held = expectation(description: "History held")
    // 준비는 검증 완료로 오인되지 않아야 한다.
    let first = service.status.filter { if case .finished(let results) = $0 { return results.first?.hold != nil }; return false }
      .take(1).subscribe(onNext: { _ in held.fulfill() })
    // 로컬 결과로만 메인 진입한다.
    let ready = expectation(description: "Local launch ready")
    // 인위적인 최소 표시 시간도 적용하지 않는다.
    let startedAt = Date()
    // 검증 구독과 독립된 화면 준비 신호다.
    let launch = service.prepareLaunch().subscribe(onNext: { ready.fulfill() })
    wait(for: [ready, held], timeout: 3)
    XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1.4)
    XCTAssertEqual(try repository.snapshot(), before)
    launch.dispose()
    first.dispose()
    // 사용자가 선택한 재시도는 실제 검증 완료 이후에만 거래 준비가 된다.
    let verified = expectation(description: "Retry verified")
    // 최초 기본 finished([])나 보류 결과를 성공으로 처리하지 않는다.
    let retry = service.status.filter { if case .finished(let results) = $0 { return results.first?.hold == nil && !results.isEmpty }; return false }
      .take(1).subscribe(onNext: { _ in verified.fulfill() })
    service.refresh()
    wait(for: [verified], timeout: 3)
    retry.dispose()
    XCTAssertGreaterThan(requests, 1)
    XCTAssertGreaterThanOrEqual(try repository.snapshot().historyCheckStates[0].verifiedThrough, before.historyCheckStates[0].verifiedThrough)
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
    // 화면 REST 재조회 횟수와 과거 검증 중복을 혼동하지 않도록 평가 제공자를 분리한다.
    var displayProvider = provider
    displayProvider.quoteOverride = { .error(FuturesMarketDataError.invalidResponse) }
    let reactor = FuturesAccountReactor(
      account: order.account,
      useCase: FuturesTradingUseCase(store: { repository }, historyCheck: service),
      historyCheck: service,
      provider: displayProvider,
      networkAvailability: .empty()
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
    // 반복된 refresh는 과거 검증 요청을 추가하지 않는다.
    XCTAssertEqual(requests, 2)
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

  func testLocalLaunchDoesNotCancelDelayedHistoricalLiquidation() throws {
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
    let ready = expectation(description: "Launch local read completed")
    // 화면 진입 이후에도 검증 작업이 유지돼야 한다.
    let startedAt = Date()
    // 화면 대기 구독만 종료하고 서비스 소유 작업은 유지한다.
    let launch = service.prepareLaunch().subscribe(onNext: { ready.fulfill() })
    wait(for: [ready], timeout: 7)
    XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1.4)
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
    let liquidated = expectation(description: "Historical liquidation continues after local launch")
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
    // SceneDelegate와 동일하게 suspend 후 resume으로 복귀한다.
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
    service.resume()
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
    // 인트로 종료가 청산 저장 완료를 의미하지 않는지 확인한다.
    let launchReady = expectation(description: "Launch completes before historical liquidation")
    // 로컬 화면 준비와 거래 검증 완료 신호를 구분한다.
    var ready = false
    // 메인 진입 시점에는 아직 과거 검증을 기다리는지 확인한다.
    let launch = service.prepareLaunch().subscribe(
      onNext: {
        ready = true
        XCTAssertNil(try? repository.snapshot().historyCheckStates[0].liquidation)
        launchReady.fulfill()
      }
    )
    service.observe(.init(instrument: order.instrument, price: 80, timestamp: 65_999))
    wait(for: [live], timeout: 3)
    subscription.dispose()
    wait(for: [launchReady], timeout: 3)
    XCTAssertTrue(ready)
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
    defer { second.dispose(); service.suspend() }
    service.resume()
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

  @MainActor
  func testEntryFormRecoversAfterInputNetworkAndStoreFailuresAndCommitsOnce() throws {
    for side in [FuturesSide.long, .short] { try verifyFormRecovery(closing: false, side: side) }
  }

  @MainActor
  func testCloseFormRecoversAfterInputNetworkAndStoreFailuresAndCommitsOnce() throws {
    for side in [FuturesSide.long, .short] { try verifyFormRecovery(closing: true, side: side) }
  }

  @MainActor
  private func verifyFormRecovery(closing: Bool, side: FuturesSide) throws {
    // 각 폼·방향의 실제 저장 결과를 독립된 파일로 확인한다.
    let repository = LocalFuturesAccountRepository(fileURL: directory.appendingPathComponent(UUID().uuidString + ".json"))
    // 가격을 고정해 주문 건수와 잔액 변화만 비교한다.
    let order = domesticFuturesOrder(side: side, margin: 1_000, price: 100, date: Date().addingTimeInterval(-2))
    try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
    try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
    // 재연결과 실제 이력 검증 완료를 서로 다른 시점으로 만든다.
    let availability = BehaviorSubject(value: true)
    // 통신 복구 직후 검증 응답을 대기시킬 수 있다.
    let historyAvailable = BehaviorSubject(value: true)
    // 과거 가격 조회만 제어하고 검증·저장·Reactor는 실제 구현을 사용한다.
    var provider = DetailReplayProvider(instrument: order.instrument, timestamp: 1, adverse: 100)
    provider.quoteOverride = {
      historyAvailable.filter { $0 }.take(1).map { _ in
        .init(instrument: order.instrument, price: 100, timestamp: try FuturesHistoryCheckState.milliseconds(Date()))
      }.asSingle()
    }
    // 같은 연결 상태를 공유하는 실제 검증 서비스다.
    let service = FuturesHistoryCheckService(store: { repository }, provider: { _ in provider }, networkAvailability: availability)
    defer { service.suspend() }
    // 제출 후 저장소 접근 실패를 한 번만 주입한다.
    let failureLock = NSLock()
    // 조회 시점과 테스트 스레드 사이에서 실패 주입을 보호한다.
    var failNextAccess = false
    // 계좌 조회와 주문 저장은 같은 실제 저장소를 사용한다.
    let useCase = FuturesTradingUseCase(
      store: {
        failureLock.lock()
        defer { failureLock.unlock() }
        if failNextAccess {
          failNextAccess = false
          throw LocalFuturesAccountRepository.StoreError.invalidStoredData
        }
        return repository
      },
      historyCheck: service
    )
    // UI의 미검증 제한과 실패 후 submitting 해제를 실제 상태 전이로 검사한다.
    let reactor = FuturesAccountReactor(account: order.account, useCase: useCase, historyCheck: service, provider: provider, networkAvailability: availability)
    // 버튼 탭 시점마다 최신 주문 시각을 사용한다.
    let capture: () -> FuturesOrderPrice? = {
      guard let timestamp = try? FuturesHistoryCheckState.milliseconds(Date()) else { return nil }
      return .init(quote: .init(instrument: order.instrument, price: 100, timestamp: timestamp), requestedAt: timestamp)
    }
    // 성공 콜백도 중복 탭으로 여러 번 호출되면 안 된다.
    var completions = 0
    // 진입과 종료에 같은 실패·복구 순서를 적용한다.
    let controller: UIViewController
    if closing {
      // 실제 시트 해제까지 확인한다.
      let sheet = FuturesCloseViewController(reactor: reactor, positionID: order.requestID, captureOrderPrice: capture)
      sheet.tradeCompletedCallBack = { completions += 1 }
      controller = sheet
    } else {
      // 롱과 숏 모두 같은 제출 경로를 사용한다.
      let entry = FuturesOrderViewController(reactor: reactor, instrument: order.instrument)
      entry.captureOrderPrice = capture
      entry.tradeCompletedCallBack = { completions += 1 }
      entry.selectTab(side == .long ? 0 : 1)
      controller = entry
    }
    // 알럿을 닫은 뒤 동일한 화면에 다시 주문한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 667))
    window.rootViewController = closing ? UIViewController() : controller
    window.makeKeyAndVisible()
    if closing { window.rootViewController?.present(controller, animated: false) }
    defer { window.rootViewController?.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil }
    service.refresh()
    waitForForm { reactor.canSubmit && reactor.currentState.quotes[order.instrument] != nil }
    // 현재 화면에서 수량 또는 증거금을 수정한다.
    let input = try XCTUnwrap(findFormView(controller.view, id: closing ? "futuresCloseQuantity" : "futuresMargin") as? UITextField)
    // 실제 UIKit 버튼으로 중복 제출까지 검사한다.
    let button = try XCTUnwrap(findFormView(controller.view, id: closing ? "futuresCloseSubmit" : "futuresSubmit") as? UIButton)
    func setInput(_ text: String) { input.text = text; input.sendActions(for: .editingChanged) }
    func dismissAlert(_ key: String) throws {
      waitForForm { controller.presentedViewController is UIAlertController && !reactor.currentState.submitting }
      // 표시 애니메이션이 끝나야 실제 확인 이후의 상태와 같아진다.
      let alert = try XCTUnwrap(controller.presentedViewController as? UIAlertController)
      waitForForm { !alert.isBeingPresented }
      XCTAssertEqual(alert.message, FuturesText.text(key))
      XCTAssertTrue(button.isEnabled)
      controller.dismiss(animated: false)
      waitForForm { controller.presentedViewController == nil }
    }
    setInput("0")
    button.sendActions(for: .touchUpInside)
    try dismissAlert(closing ? "futures_close_invalid" : "futures_input_error")
    setInput(closing ? "10" : "100")
    historyAvailable.onNext(false)
    availability.onNext(false)
    waitForForm { reactor.currentState.networkAvailable == false && !reactor.canSubmit }
    button.sendActions(for: .touchUpInside)
    try dismissAlert("network_lost")
    availability.onNext(true)
    waitForForm { reactor.currentState.networkAvailable == true && !reactor.canSubmit }
    button.sendActions(for: .touchUpInside)
    try dismissAlert("futures_order_not_ready")
    historyAvailable.onNext(true)
    waitForForm { reactor.canSubmit }
    // 연결 복구는 주문을 자동 체결하지 않는다.
    XCTAssertEqual(try repository.snapshot().positions[0].executions.count, 1)
    XCTAssertTrue(try repository.snapshot().positions[0].partialClosings?.isEmpty != false)
    failureLock.lock(); failNextAccess = true; failureLock.unlock()
    button.sendActions(for: .touchUpInside)
    for _ in 0..<10 { button.sendActions(for: .touchUpInside) }
    try dismissAlert("futures_storage_error")
    XCTAssertEqual(input.text, closing ? "10" : "100")
    XCTAssertTrue(input.isEnabled)
    XCTAssertFalse(controller.isModalInPresentation)
    XCTAssertEqual(try repository.snapshot().positions[0].executions.count, 1)
    XCTAssertTrue(try repository.snapshot().positions[0].partialClosings?.isEmpty != false)
    button.sendActions(for: .touchUpInside)
    for _ in 0..<10 { button.sendActions(for: .touchUpInside) }
    waitForForm { completions == 1 && !reactor.currentState.submitting }
    // 화면 상태가 아닌 디스크의 체결 건수·수량·잔액을 최종 비교한다.
    let saved = try repository.snapshot()
    XCTAssertEqual(saved.positions[0].executions.count, closing ? 1 : 2)
    XCTAssertEqual(saved.positions[0].partialClosings?.count ?? 0, closing ? 1 : 0)
    XCTAssertEqual(saved.positions[0].quantity, closing ? 90 : 110)
    XCTAssertEqual(saved.accounts.first?.availableBalance, closing ? 9_999_100 : 9_998_900)
    if closing { XCTAssertNil(window.rootViewController?.presentedViewController) }
    else { XCTAssertTrue(button.isEnabled); XCTAssertTrue(input.isEnabled) }
  }

  @MainActor
  private func waitForForm(_ condition: @escaping () -> Bool) {
    // 임의의 긴 대기 대신 실제 UI·저장 완료 조건을 기다린다.
    let completed = expectation(description: "Form state transition")
    // UIKit 상태는 메인 스레드에서만 확인한다.
    let subscription = Observable<Int>.interval(.milliseconds(10), scheduler: MainScheduler.instance)
      .filter { _ in condition() }.take(1).subscribe(onNext: { _ in completed.fulfill() })
    defer { subscription.dispose() }
    wait(for: [completed], timeout: 5)
  }

  @MainActor
  private func findFormView(_ view: UIView, id: String) -> UIView? {
    if view.accessibilityIdentifier == id { return view }
    return view.subviews.lazy.compactMap { self.findFormView($0, id: id) }.first
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
