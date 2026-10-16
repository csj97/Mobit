import XCTest
import UIKit
import ReactorKit
import RxSwift
@testable import Mobit

final class FuturesReleaseQATests: XCTestCase {
  // 실제 사용자 저장소와 분리한 QA 전용 계좌 파일이다.
  private var directory: URL!
  // 모든 선물 계좌가 공유하는 실제 저장소 구현을 검증한다.
  private var store: LocalFuturesAccountRepository {
    LocalFuturesAccountRepository(fileURL: directory.appendingPathComponent("accounts.json"))
  }

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  override func tearDownWithError() throws {
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }

  func testTwoExchangeAccountsPreserveCashAndHistoryThroughCompleteTradingJourney() throws {
    // 양 거래소에서 같은 종목을 반대 방향으로 동시에 보유한다.
    let upbit = try order(exchange: .upbit, side: .long, margin: 100, price: 100, time: 60_000)
    // 빗썸의 원금은 업비트 거래 단계마다 동일해야 한다.
    let bithumb = try order(exchange: .bithumb, side: .short, margin: 200, price: 100, time: 60_000)
    try store.applyAdvertisementReward(AdRewardClaim(account: upbit.account))
    try store.applyAdvertisementReward(AdRewardClaim(account: bithumb.account))
    try store.openPosition(upbit, orderCheck: check(upbit, time: 60_000), now: upbit.executedAt)
    try store.openPosition(bithumb, orderCheck: check(bithumb, time: 60_000), now: bithumb.executedAt)
    // 업비트 30% 종료 후 빗썸 포지션과 잔액을 비교한다.
    let first = try XCTUnwrap(store.snapshot().positions.first { $0.id == upbit.requestID })
    // 수량 3개는 원금 30과 이익 15만 계좌에 반환한다.
    let partial = FuturesClosingOrder(
      requestID: UUID(),
      positionID: first.id,
      executionPrice: 105,
      executedAt: Date(timeIntervalSince1970: 65),
      quantity: 3,
      expectedQuantity: 10
    )
    try store.closePosition(partial, orderCheck: check(upbit, time: 65_000, price: 105), now: partial.executedAt)
    // 종료된 원가를 제외하고 새로운 체결 원가만 합산한다.
    let added = try order(exchange: .upbit, side: .long, margin: 200, price: 200, time: 66_000)
    try store.openPosition(added, orderCheck: check(added, time: 66_000), now: added.executedAt)
    // 계좌 파일을 다시 읽어 체결 이력과 잔여 원가를 검증한다.
    let combined = try store.snapshot()
    // 최초 포지션 식별자와 진입 시각이 유지되어야 한다.
    let remaining = try XCTUnwrap(combined.positions.first { $0.id == first.id })
    XCTAssertEqual(remaining.order.executedAt, upbit.executedAt)
    XCTAssertEqual(remaining.quantity, 17)
    XCTAssertEqual(try remaining.margin, 270)
    XCTAssertEqual(remaining.entryTradeAmount, 2_700)
    XCTAssertEqual(remaining.executions.map(\.requestID), [upbit.requestID, added.requestID])
    XCTAssertEqual(combined.accounts.first { $0.id == bithumb.account }?.availableBalance, 9_999_800)
    XCTAssertEqual(combined.positions.first { $0.id == bithumb.requestID }?.quantity, 20)
    // 남은 17개를 200원에 종료하면 총 실현 이익은 715원이다.
    let close = FuturesClosingOrder(
      requestID: UUID(),
      positionID: remaining.id,
      executionPrice: 200,
      executedAt: Date(timeIntervalSince1970: 67),
      quantity: remaining.quantity,
      expectedQuantity: remaining.quantity
    )
    // 중복 완료 콜백은 동일한 검증 자료로 반복해도 한 번만 반영한다.
    let closeCheck = try check(added, time: 67_000)
    // 전체 종료 결과는 이후 광고나 다른 거래소 정산과 독립적이다.
    let closed = try store.closePosition(close, orderCheck: closeCheck, now: close.executedAt)
    XCTAssertEqual(try store.closePosition(close, orderCheck: closeCheck, now: close.executedAt), closed)
    XCTAssertEqual(closed.accounts.first { $0.id == upbit.account }?.availableBalance, 10_000_715)
    XCTAssertEqual(try closed.transactionHistory(for: upbit.account).compactMap(\.realizedPnL).reduce(0, +), 715)
    // 동일 종목을 반대 방향으로 재진입할 때 이전 종료 이력을 보존한다.
    let reentry = try order(exchange: .upbit, side: .short, margin: 100, price: 200, time: 68_000)
    try store.openPosition(reentry, orderCheck: check(reentry, time: 68_000), now: reentry.executedAt)
    // 두 거래소의 청산 가격은 각각의 상품 식별자에만 적용한다.
    let upbitLiquidation = FuturesMarkQuote(instrument: reentry.instrument, price: 220, timestamp: 69_000)
    XCTAssertEqual(try store.liquidateObservedQuote(upbitLiquidation, settledAt: Date(timeIntervalSince1970: 69)).map(\.id), [reentry.requestID])
    XCTAssertTrue(try store.liquidateObservedQuote(upbitLiquidation, settledAt: Date(timeIntervalSince1970: 69)).isEmpty)
    // 빗썸 숏 포지션은 별도 시세로만 청산된다.
    let bithumbLiquidation = FuturesMarkQuote(instrument: bithumb.instrument, price: 110, timestamp: 69_000)
    XCTAssertEqual(try store.liquidateObservedQuote(bithumbLiquidation, settledAt: Date(timeIntervalSince1970: 69)).map(\.id), [bithumb.requestID])
    // 재시작 후 각 계좌의 현금·실현 손익·누적 거래 수가 일치해야 한다.
    let final = try store.snapshot()
    // 종료된 포지션에는 현재가가 없어도 확정 자산을 조회할 수 있다.
    let upbitValue = try final.valuation(for: upbit.account, quotes: [:], now: Date(timeIntervalSince1970: 70))
    // 다른 거래소의 손실은 해당 계좌에서만 실현된다.
    let bithumbValue = try final.valuation(for: bithumb.account, quotes: [:], now: Date(timeIntervalSince1970: 70))
    XCTAssertEqual(upbitValue.totalEquity, 10_000_615)
    XCTAssertEqual(upbitValue.realizedPnL, 615)
    XCTAssertEqual(bithumbValue.totalEquity, 9_999_800)
    XCTAssertEqual(bithumbValue.realizedPnL, -200)
    XCTAssertEqual(try final.transactionHistory(for: upbit.account).count, 6)
    XCTAssertEqual(try final.transactionHistory(for: bithumb.account).count, 2)
    XCTAssertEqual(final.ledger.count, 6)
    XCTAssertTrue(final.positions.allSatisfy { !final.isActive($0) })
  }

  func testBithumbDisconnectDoesNotBlockHealthyUpbitOrder() throws {
    try verifyExchangeDisconnect(healthyExchange: .upbit, interruptedExchange: .bithumb)
  }

  func testUpbitDisconnectDoesNotBlockHealthyBithumbOrder() throws {
    try verifyExchangeDisconnect(healthyExchange: .bithumb, interruptedExchange: .upbit)
  }

  private func verifyExchangeDisconnect(healthyExchange: Exchange, interruptedExchange: Exchange) throws {
    // 양 거래소 계좌가 검증된 상태에서 한 거래소 연결만 끊는다.
    let healthy = try order(exchange: healthyExchange, side: .long, margin: 100, price: 100, time: 60_000)
    // 독립 계좌에 동일 종목을 보유해 연결 상태를 구분한다.
    let interrupted = try order(exchange: interruptedExchange, side: .long, margin: 100, price: 100, time: 60_000)
    for opening in [healthy, interrupted] {
      try store.applyAdvertisementReward(AdRewardClaim(account: opening.account))
      try store.openPosition(opening, orderCheck: check(opening, time: 60_000), now: opening.executedAt)
    }
    // 지연된 빗썸 요청이 진행 중임을 확인하는 신호다.
    let stalled = expectation(description: "Interrupted exchange refresh is stalled after disconnect")
    // 정상 응답과 지연 응답을 순서대로 제공한다.
    let provider = ReleaseHistoryProvider(onStalled: { stalled.fulfill() })
    // 두 거래소 연결과 가격 이벤트를 개별 전송한다.
    let monitor = ReleaseMonitor()
    // 테스트 파일을 소켓·과거 검증·주문 준비 흐름에 연결한다.
    let repository = store
    // 기기 네트워크는 계속 정상이다.
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) },
      monitor: monitor
    )
    defer { service.suspend() }
    // 비동기 구독을 테스트가 끝날 때 해제한다.
    let disposeBag = DisposeBag()
    // 최초 두 계좌의 과거 검증 완료를 기다린다.
    let ready = expectation(description: "Both exchange accounts are verified")
    service.status.filter {
      if case .finished(let results) = $0 { return results.count == 2 && results.allSatisfy { $0.hold == nil } }
      return false
    }.take(1).subscribe(onNext: { _ in ready.fulfill() }).disposed(by: disposeBag)
    monitor.subject.onNext(.connection(healthyExchange, true))
    monitor.subject.onNext(.connection(interruptedExchange, true))
    wait(for: [ready], timeout: 3)
    monitor.subject.onNext(.quote(.init(instrument: healthy.instrument, price: 100, timestamp: 66_000)))
    monitor.subject.onNext(.quote(.init(instrument: interrupted.instrument, price: 100, timestamp: 66_000)))
    // 장애 전에는 동일한 업비트 주문을 허용한다.
    let initiallyAllowed = expectation(description: "Healthy exchange order is initially allowed")
    service.prepareOrder(account: healthy.account, instrument: healthy.instrument, price: lockedPrice(healthy.instrument))
      .subscribe(onSuccess: { _ in initiallyAllowed.fulfill() }, onFailure: {
        XCTFail("Initial Healthy exchange verification failed: \($0)")
        initiallyAllowed.fulfill()
      }).disposed(by: disposeBag)
    wait(for: [initiallyAllowed], timeout: 3)
    provider.stall(interruptedExchange)
    monitor.subject.onNext(.connection(interruptedExchange, false))
    wait(for: [stalled], timeout: 3)
    monitor.subject.onNext(.quote(.init(instrument: healthy.instrument, price: 100, timestamp: 66_000)))
    // 한 거래소의 단절이 검증된 다른 거래소 주문을 차단하면 안 된다.
    let independent = expectation(description: "Healthy Healthy exchange order remains available during Interrupted exchange disconnect")
    service.prepareOrder(account: healthy.account, instrument: healthy.instrument, price: lockedPrice(healthy.instrument))
      .subscribe(onSuccess: { _ in
        independent.fulfill()
      }, onFailure: {
        XCTFail("Healthy Healthy exchange order was blocked by Interrupted exchange disconnect: \($0)")
        independent.fulfill()
      }).disposed(by: disposeBag)
    wait(for: [independent], timeout: 3)
    // 단절된 거래소는 정상 계좌의 준비 상태를 공유해서 주문하면 안 된다.
    let blocked = expectation(description: "Disconnected account remains blocked")
    service.prepareOrder(account: interrupted.account, instrument: interrupted.instrument, price: lockedPrice(interrupted.instrument))
      .subscribe(onSuccess: { _ in XCTFail("Disconnected account must verify its own connection"); blocked.fulfill() }, onFailure: {
        XCTAssertEqual($0 as? FuturesOrderCheckError, .historyCheckInProgress)
        blocked.fulfill()
      }).disposed(by: disposeBag)
    wait(for: [blocked], timeout: 3)
    // 새 연결과 해당 거래소 이력 완료 이후에만 주문 제한을 해제한다.
    let recovered = expectation(description: "Interrupted account verifies after reconnect")
    service.status.filter {
      if case .finished(let results) = $0 {
        return results.contains { $0.positionID == interrupted.requestID && $0.hold == nil }
      }
      return false
    }.take(1).subscribe(onNext: { _ in recovered.fulfill() }).disposed(by: disposeBag)
    monitor.subject.onNext(.connection(interruptedExchange, true))
    provider.resume(interruptedExchange)
    wait(for: [recovered], timeout: 3)
    monitor.subject.onNext(.quote(.init(instrument: interrupted.instrument, price: 100, timestamp: 66_000)))
    // 복구가 다른 계좌의 현금·포지션·거래 이력을 변경하지 않는다.
    let restored = expectation(description: "Reconnected account becomes independently tradeable")
    service.prepareOrder(account: interrupted.account, instrument: interrupted.instrument, price: lockedPrice(interrupted.instrument))
      .subscribe(onSuccess: { _ in restored.fulfill() }, onFailure: { XCTFail("Reconnected account stayed blocked: \($0)"); restored.fulfill() })
      .disposed(by: disposeBag)
    wait(for: [restored], timeout: 3)
    XCTAssertEqual(try repository.snapshot().accounts.first { $0.id == healthy.account }?.availableBalance, 9_999_900)
    XCTAssertEqual(try repository.snapshot().accounts.first { $0.id == interrupted.account }?.availableBalance, 9_999_900)
    XCTAssertEqual(try repository.snapshot().transactionHistory(for: healthy.account).count, 1)
    XCTAssertEqual(try repository.snapshot().transactionHistory(for: interrupted.account).count, 1)
  }

  func testSecondInstrumentOpeningImmediatelyAllowsOrdersAndLiveValuation() throws {
    try verifySecondInstrumentOpening(exchange: .upbit)
  }

  func testBithumbSecondInstrumentOpeningImmediatelyAllowsOrdersAndLiveValuation() throws {
    try verifySecondInstrumentOpening(exchange: .bithumb)
  }

  func testInitialUpbitVerificationCompletesWhileBithumbHistoryIsDelayed() throws {
    try verifyIndependentInitialHistory(healthyExchange: .upbit, interruptedExchange: .bithumb)
  }

  func testInitialBithumbVerificationCompletesWhileUpbitHistoryIsDelayed() throws {
    try verifyIndependentInitialHistory(healthyExchange: .bithumb, interruptedExchange: .upbit)
  }

  func testOtherExchangeRewardDoesNotInvalidateHealthyHistory() throws {
    // 업비트 검증 요청 중 빗썸 계좌에 새 보상이 저장되는 경우다.
    let opening = try order(exchange: .upbit, side: .long, margin: 100, price: 100, time: 60_001)
    // 보상만 받는 별도 거래소에는 포지션을 만들지 않는다.
    let otherAccount = TradingAccountID(exchange: .bithumb, product: .perpetual, currency: .krw)
    // 재확인과 실제 commit에서 같은 저장소 잠금·revision을 사용한다.
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: opening.account))
    try repository.openPosition(opening, orderCheck: check(opening, time: 60_001), now: opening.executedAt)
    try repository.ensureAccount(otherAccount)
    // 다른 거래소 보상과 현재 계좌 체크포인트가 각각 한 번씩 저장되는지 비교한다.
    let before = try repository.snapshot()
    // 이력 응답 직전 다른 거래소만 수정한다.
    let provider = ReleaseHistoryProvider(
      onStalled: {},
      beforeHistory: { instrument in
        XCTAssertEqual(instrument, opening.instrument)
        do { try repository.applyAdvertisementReward(AdRewardClaim(account: otherAccount)) }
        catch { XCTFail("Independent reward failed: \(error)") }
      },
      quoteTimestamp: { 119_999 }
    )
    // 같은 계좌 변경은 기존 회귀의 revisionChanged로 유지하고 다른 거래소 저장만 허용한다.
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 120) }
    )
    defer { service.suspend() }
    // 다른 거래소 저장이 정상 계좌 검증을 보류시키지 않는다.
    let ready = expectation(description: "Healthy history rebases only another exchange revision")
    // 완료 조건과 실제 체크포인트 저장을 함께 확인한다.
    let subscription = service.status.filter {
      if case .finished(let results) = $0 { return results.contains { $0.positionID == opening.requestID && $0.hold == nil } }
      return false
    }.take(1).subscribe(onNext: { _ in ready.fulfill() })
    defer { subscription.dispose() }
    service.refresh()
    wait(for: [ready], timeout: 3)
    // 재확인 후에도 보상과 검증 저장을 서로 덮어쓰지 않는다.
    let final = try repository.snapshot()
    XCTAssertEqual(final.revision, before.revision + 2)
    XCTAssertEqual(final.historyCheckStates.first { $0.positionID == opening.requestID }?.verifiedThrough, 120_000)
    XCTAssertEqual(final.accounts.first { $0.id == opening.account }?.availableBalance, 9_999_900)
    XCTAssertEqual(final.accounts.first { $0.id == otherAccount }?.availableBalance, 10_000_000)
    XCTAssertEqual(try final.transactionHistory(for: opening.account).count, 1)
    XCTAssertTrue(try final.transactionHistory(for: otherAccount).isEmpty)
  }

  private func verifyIndependentInitialHistory(healthyExchange: Exchange, interruptedExchange: Exchange) throws {
    // 최초 검증부터 한 거래소 이력 응답이 없는 두 독립 계좌다.
    let healthy = try order(exchange: healthyExchange, side: .long, margin: 100, price: 100, time: 60_000)
    // 다른 거래소의 검증이 먼저 시작돼도 정상 계좌 완료를 막으면 안 된다.
    let interrupted = try order(exchange: interruptedExchange, side: .short, margin: 200, price: 100, time: 60_000)
    // 한 파일을 공유하되 검증과 주문 준비는 계좌별로 수행한다.
    let repository = store
    for opening in [interrupted, healthy] {
      try repository.applyAdvertisementReward(AdRewardClaim(account: opening.account))
      try repository.openPosition(opening, orderCheck: check(opening, time: 60_000), now: opening.executedAt)
    }
    // 지연된 거래소도 실제 API 구독까지 시작했음을 확인한다.
    let stalled = expectation(description: "Other exchange starts its delayed verification")
    // 지연은 선택한 거래소에만 적용한다.
    let provider = ReleaseHistoryProvider(onStalled: { stalled.fulfill() })
    provider.stall(interruptedExchange)
    // 서로 다른 거래소 소켓 세션을 같은 서비스에 전달한다.
    let monitor = ReleaseMonitor()
    // 지연된 API 타임아웃 20초를 기다리지 않고 정상 검증이 끝나야 한다.
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) },
      monitor: monitor
    )
    defer { service.suspend() }
    // 실제 화면 상태에서도 부분 완료한 자기 계좌를 사용할 수 있어야 한다.
    let reactor = FuturesAccountReactor(
      account: healthy.account,
      useCase: .init(store: { repository }, historyCheck: service),
      historyCheck: service,
      provider: provider,
      networkAvailability: .just(true)
    )
    // 상태 및 주문 구독의 수명을 테스트 범위로 제한한다.
    let disposeBag = DisposeBag()
    // 전체 완료 이벤트가 없어도 정상 계좌 화면과 주문 준비가 먼저 완료된다.
    let ready = expectation(description: "Healthy account finishes independently")
    reactor.state.filter { _ in reactor.canSubmit }.take(1)
      .subscribe(onNext: { _ in ready.fulfill() }).disposed(by: disposeBag)
    monitor.subject.onNext(.connection(interruptedExchange, true))
    monitor.subject.onNext(.connection(healthyExchange, true))
    wait(for: [stalled, ready], timeout: 3)
    monitor.subject.onNext(.quote(.init(instrument: healthy.instrument, price: 100, timestamp: 66_000)))
    // 정상 계좌와 미검증 계좌의 실제 도메인 주문 조건도 각각 적용한다.
    let prepared = expectation(description: "Healthy order uses its completed verification")
    service.prepareOrder(account: healthy.account, instrument: healthy.instrument, price: lockedPrice(healthy.instrument))
      .subscribe(onSuccess: { _ in prepared.fulfill() }, onFailure: { XCTFail("Delayed other exchange blocked initial order: \($0)"); prepared.fulfill() })
      .disposed(by: disposeBag)
    // 동일 시세가 있어도 이력이 없는 다른 계좌를 대신 검증하지 않는다.
    let blocked = expectation(description: "Delayed account still requires its own history")
    service.prepareOrder(account: interrupted.account, instrument: interrupted.instrument, price: lockedPrice(interrupted.instrument))
      .subscribe(onSuccess: { _ in XCTFail("Unverified account became tradeable"); blocked.fulfill() }, onFailure: {
        XCTAssertEqual($0 as? FuturesOrderCheckError, .historyCheckInProgress)
        blocked.fulfill()
      }).disposed(by: disposeBag)
    wait(for: [prepared, blocked], timeout: 3)
    XCTAssertEqual(reactor.currentState.lastCompletedVerification?.first { $0.positionID == healthy.requestID }?.verifiedThrough, 66_000)
    XCTAssertEqual(try repository.snapshot().historyCheckStates.first { $0.positionID == healthy.requestID }?.verifiedThrough, 60_000)
    XCTAssertEqual(try repository.snapshot().historyCheckStates.first { $0.positionID == interrupted.requestID }?.verifiedThrough, 60_000)
    XCTAssertEqual(try repository.snapshot().accounts.first { $0.id == healthy.account }?.availableBalance, 9_999_900)
    XCTAssertEqual(try repository.snapshot().accounts.first { $0.id == interrupted.account }?.availableBalance, 9_999_800)
  }

  func testOtherExchangeDisconnectBetweenOrderPreparationAndTrackingPreservesSuccessfulEntry() throws {
    // 주문 준비 직후 다른 거래소만 단절되는 경합을 실제 저장소로 재현한다.
    let healthy = try order(exchange: .upbit, side: .long, margin: 100, price: 100, time: 60_000)
    // 정상 계좌와 독립적으로 연결이 무효화될 거래소다.
    let interrupted = try order(exchange: .bithumb, side: .long, margin: 100, price: 100, time: 60_000)
    // 주문 완료와 소켓 단절 순서를 제어할 원자 저장소다.
    let repository = store
    for opening in [healthy, interrupted] {
      try repository.applyAdvertisementReward(AdRewardClaim(account: opening.account))
      try repository.openPosition(opening, orderCheck: check(opening, time: 60_000), now: opening.executedAt)
    }
    // 새 검증으로 우연히 주문 준비가 복구되지 않도록 양쪽 API를 멈춘다.
    let stalled = expectation(description: "Both restarted verifications wait for responses")
    stalled.expectedFulfillmentCount = 2
    // 기존 계좌의 준비 상태는 최초 검증으로 만든다.
    let provider = ReleaseHistoryProvider(onStalled: { stalled.fulfill() })
    // 단절 이벤트와 신규 종목 시세를 분리한다.
    let monitor = ReleaseMonitor()
    // 전체 검증 주기와 주문 감시 세션의 권한을 구분하는 서비스다.
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) },
      monitor: monitor
    )
    defer { service.suspend() }
    // 비동기 결과를 테스트 종료까지 유지한다.
    let disposeBag = DisposeBag()
    // 양 계좌의 최초 준비를 완료한다.
    let ready = expectation(description: "Both initial positions finish verification")
    service.status.filter {
      if case .finished(let results) = $0 { return results.count == 2 && results.allSatisfy { $0.hold == nil } }
      return false
    }.take(1).subscribe(onNext: { _ in ready.fulfill() }).disposed(by: disposeBag)
    monitor.subject.onNext(.connection(.upbit, true))
    monitor.subject.onNext(.connection(.bithumb, true))
    wait(for: [ready], timeout: 3)
    monitor.subject.onNext(.quote(.init(instrument: healthy.instrument, price: 100, timestamp: 66_000)))
    // 새 종목을 저장하기 직전 서비스에서 캡처한 주문 검증 근거다.
    var preparedCheck: FuturesOrderCheck?
    // 실제 주문 성공 전에 검증 결과가 확보됐는지 확인한다.
    let prepared = expectation(description: "Order captures the healthy exchange session")
    // 새로 저장할 종목은 기존 포지션과 구분한다.
    let instrument = TradingInstrumentID(exchange: .upbit, product: .perpetual, rawSymbol: "KRW-ETH", settlementCurrency: .krw)
    service.prepareOrder(account: healthy.account, instrument: instrument, price: lockedPrice(instrument))
      .subscribe(onSuccess: { preparedCheck = $0; prepared.fulfill() }, onFailure: { XCTFail("Preparation failed: \($0)"); prepared.fulfill() })
      .disposed(by: disposeBag)
    wait(for: [prepared], timeout: 3)
    // 주문 저장은 성공했지만 서비스 track 콜백은 아직 보내지 않는다.
    let opening = FuturesOpeningOrder(
      requestID: UUID(),
      account: healthy.account,
      instrument: instrument,
      side: .long,
      margin: 100,
      leverage: 10,
      executionPrice: 100,
      entryFeeRate: 0,
      executedAt: Date(timeIntervalSince1970: 66),
      contractRules: try XCTUnwrap(TradingRules.DomesticFutures.contractRules(for: instrument))
    )
    // 다른 거래소 단절 이후에도 이 성공한 주문을 같은 정상 세션에서 감시해야 한다.
    let saved = try repository.openPosition(opening, orderCheck: XCTUnwrap(preparedCheck), now: opening.executedAt)
    provider.stall(.upbit)
    provider.stall(.bithumb)
    monitor.subject.onNext(.connection(.bithumb, false))
    wait(for: [stalled], timeout: 3)
    // 재조회가 막혀도 서비스가 성공한 신규 진입의 준비 상태를 즉시 방송한다.
    let tracked = expectation(description: "Successful healthy entry survives other exchange invalidation")
    service.status.filter {
      if case .finished(let results) = $0 { return results.contains { $0.positionID == opening.requestID && $0.hold == nil } }
      return false
    }.take(1).subscribe(onNext: { _ in tracked.fulfill() }).disposed(by: disposeBag)
    service.track(saved, openingRequestID: opening.requestID, monitoringGeneration: preparedCheck?.monitoringGeneration)
    wait(for: [tracked], timeout: 3)
    monitor.subject.onNext(.quote(.init(instrument: instrument, price: 100, timestamp: 66_000)))
    // 기존 BTC와 신규 ETH 모두 같은 정상 계좌에서 다음 주문을 허용한다.
    let following = expectation(description: "Next order does not wait for stalled refresh")
    service.prepareOrder(account: healthy.account, instrument: instrument, price: lockedPrice(instrument))
      .subscribe(onSuccess: { _ in following.fulfill() }, onFailure: { XCTFail("Healthy entry lost monitoring: \($0)"); following.fulfill() })
      .disposed(by: disposeBag)
    wait(for: [following], timeout: 3)
    XCTAssertEqual(try repository.snapshot(), saved)
  }

  private func verifySecondInstrumentOpening(exchange: Exchange) throws {
    // 기존 BTC가 검증된 계좌에서 다른 종목을 새로 진입한다.
    let opening = try order(exchange: exchange, side: .long, margin: 100, price: 100, time: 60_000)
    try store.applyAdvertisementReward(AdRewardClaim(account: opening.account))
    try store.openPosition(opening, orderCheck: check(opening, time: 60_000), now: opening.executedAt)
    // 실제 서비스와 화면 상태가 같은 계좌 파일을 사용한다.
    let repository = store
    // 두 종목의 정상 이력 및 현재가를 제공한다.
    let provider = ReleaseHistoryProvider(onStalled: {})
    // 최초 검증 이후 자동 갱신 전 구간의 상태를 확인한다.
    let service = FuturesHistoryCheckService(
      store: { repository },
      provider: { _ in provider },
      now: { Date(timeIntervalSince1970: 66) }
    )
    defer { service.suspend() }
    // 화면의 실제 주문 UseCase와 상태 변환을 함께 실행한다.
    let reactor = FuturesAccountReactor(
      account: opening.account,
      useCase: .init(store: { repository }, historyCheck: service, now: { Date(timeIntervalSince1970: 66) }),
      historyCheck: service,
      provider: provider,
      networkAvailability: .just(true)
    )
    // 상태 구독을 유지해 Reactor의 Action과 비동기 Mutation을 활성화한다.
    let disposeBag = DisposeBag()
    // 첫 포지션 검증 완료와 화면 반영을 함께 기다린다.
    let ready = expectation(description: "Existing BTC is verified and tradeable")
    reactor.state.filter { state in
      state.snapshot?.positions.count == 1 && state.lastCompletedVerification?.contains { $0.positionID == opening.requestID && $0.hold == nil } == true
    }.take(1).subscribe(onNext: { _ in ready.fulfill() }).disposed(by: disposeBag)
    service.refresh()
    wait(for: [ready], timeout: 3)
    XCTAssertTrue(reactor.canSubmit)
    // 같은 거래소에 새로 추가할 상품으로, 기존 BTC에 합산하지 않는다.
    let instrument = TradingInstrumentID(exchange: exchange, product: .perpetual, rawSymbol: "KRW-ETH", settlementCurrency: .krw)
    // 새 진입의 실제 저장과 화면 완료 상태가 모두 반영돼야 한다.
    let opened = expectation(description: "ETH opening completes in actual Reactor")
    reactor.state.filter { state in
      state.snapshot?.positions.count == 2 && !state.submitting && state.message == FuturesText.text("futures_order_done")
    }.take(1).subscribe(onNext: { _ in opened.fulfill() }).disposed(by: disposeBag)
    reactor.action.onNext(.open(instrument, .long, 100, 10, nil, lockedPrice(instrument)))
    wait(for: [opened], timeout: 3)
    // 새 포지션을 서비스가 추적한 뒤 도착한 실제 시세를 사용한다.
    let priceReceived = expectation(description: "ETH live quote reaches Reactor")
    reactor.state.filter { $0.quotes[instrument]?.price == 105 }.take(1)
      .subscribe(onNext: { _ in priceReceived.fulfill() }).disposed(by: disposeBag)
    service.observe(.init(instrument: instrument, price: 105, timestamp: 66_000))
    wait(for: [priceReceived], timeout: 3)
    XCTAssertTrue(reactor.canSubmit, "Successful new entry must not block the account until the next periodic refresh")
    XCTAssertEqual(reactor.valuationQuotes[instrument]?.price, 105, "A newly opened position must use subsequent live prices immediately")
  }

  func testSameMillisecondPartialCloseKeepsReadinessWhenOlderHistoryResponseFinishes() throws {
    // 같은 체결 시각의 부분 종료 두 건도 잔여 수량으로 구분해야 한다.
    let opening = try order(exchange: .upbit, side: .long, margin: 100, price: 100, time: 60_000)
    // 주문 저장과 지연된 이력 저장이 공유하는 실제 파일이다.
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: opening.account))
    try repository.openPosition(opening, orderCheck: check(opening, time: 60_000), now: opening.executedAt)
    // 최초 검증·부분 종료·주기 갱신을 다른 시점에 진행한다.
    var now = Date(timeIntervalSince1970: 66)
    // 최초 검증을 마친 뒤에만 이력 응답을 지연한다.
    var delaysHistory = false
    // 이전 잔여 수량으로 요청한 응답을 새 부분 종료 뒤 반환한다.
    let historyResponse = PublishSubject<FuturesReplayBatch>()
    // 요청 구간을 그대로 반환해 revision 충돌만 재현한다.
    var pendingBatch: FuturesReplayBatch?
    // 과거 요청이 두 번째 종료보다 먼저 시작했음을 확인한다.
    let historyStarted = expectation(description: "Older quantity history response is pending")
    // 현재 시각에 맞춘 정상 이력이며 청산 경계는 넘지 않는다.
    let provider = ReleaseHistoryProvider(
      onStalled: {},
      quoteTimestamp: { Int64(now.timeIntervalSince1970 * 1_000) - 1 },
      historyResponse: { batch in
        guard delaysHistory else { return .just(batch) }
        pendingBatch = batch
        return historyResponse.take(1).asSingle().do(onSubscribe: { historyStarted.fulfill() })
      }
    )
    // 동일 소켓 세션에서 검증과 종료를 수행한다.
    let service = FuturesHistoryCheckService(store: { repository }, provider: { _ in provider }, now: { now })
    defer { service.suspend() }
    // 실제 종료 진입점으로 두 부분 종료의 감시 승계를 실행한다.
    let useCase = FuturesTradingUseCase(store: { repository }, historyCheck: service, now: { now })
    // 최초 검증이 끝나기 전에 첫 종료를 요청하지 않는다.
    let ready = expectation(description: "Initial position verification completes")
    // 서비스 완료 구독을 테스트 종료까지 유지한다.
    let disposeBag = DisposeBag()
    service.status.filter {
      if case .finished(let results) = $0 { return results.first?.positionID == opening.requestID && results.first?.hold == nil }
      return false
    }.take(1).subscribe(onNext: { _ in ready.fulfill() }).disposed(by: disposeBag)
    service.refresh()
    wait(for: [ready], timeout: 3)
    now = Date(timeIntervalSince1970: 67)
    // 두 번의 부분 종료는 동일 밀리초에 확인한 가격을 사용한다.
    let price = FuturesOrderPrice(quote: .init(instrument: opening.instrument, price: 100, timestamp: 67_000), requestedAt: 67_000)
    // 첫 부분 종료의 잔여 8개를 대상으로 다음 과거 검증을 시작한다.
    let first = try awaitValue(useCase.close(requestID: UUID(), positionID: opening.requestID, price: price, quantity: 2, expectedQuantity: 10))
    now = Date(timeIntervalSince1970: 68)
    delaysHistory = true
    service.refresh()
    wait(for: [historyStarted], timeout: 3)
    // 이전 검증이 진행 중이어도 검증된 같은 세션의 종료는 즉시 저장한다.
    let second = try awaitValue(useCase.close(requestID: UUID(), positionID: opening.requestID, price: price, quantity: 2, expectedQuantity: 8))
    XCTAssertEqual(first.positions.first?.lastExecutionAt, second.positions.first?.lastExecutionAt)
    XCTAssertEqual(second.positions.first?.quantity, 6)
    _ = try awaitValue(service.prepareOrder(account: opening.account, instrument: opening.instrument, price: price))
    // 직전 완료 결과의 재방송은 넘기고 실제 지연 응답 처리 완료를 기다린다.
    let completed = expectation(description: "Stale history does not revoke the newer partial close readiness")
    service.status.filter {
      if case .finished = $0 { return true }
      return false
    }.skip(1).take(1).subscribe(onNext: { _ in completed.fulfill() }).disposed(by: disposeBag)
    historyResponse.onNext(try XCTUnwrap(pendingBatch))
    wait(for: [completed], timeout: 3)
    _ = try awaitValue(service.prepareOrder(account: opening.account, instrument: opening.instrument, price: price))
    XCTAssertEqual(try repository.snapshot(), second)
    XCTAssertEqual(try repository.snapshot().transactionHistory(for: opening.account).count, 3)
  }

  private func awaitValue<Value>(_ operation: Single<Value>) throws -> Value {
    // 비동기 주문의 실제 성공·실패를 호출한 테스트로 전달한다.
    var result: Result<Value, Error>?
    // 단일 작업의 완료 후에만 다음 경합 단계를 진행한다.
    let completed = expectation(description: "Asynchronous trading operation completes")
    // 대기가 끝나면 진행 중 작업의 구독을 해제한다.
    let subscription = operation.subscribe(
      onSuccess: { result = .success($0); completed.fulfill() },
      onFailure: { result = .failure($0); completed.fulfill() }
    )
    defer { subscription.dispose() }
    wait(for: [completed], timeout: 3)
    return try XCTUnwrap(result).get()
  }

  #if DEBUG
  @MainActor
  func testFuturesDirectionTabAnalyticsMatchTheNewlySelectedSide() throws {
    // 실제 탭 전환의 표시 방향과 이벤트 방향을 같은 계좌에서 비교한다.
    let account = TradingAccountID(exchange: .bithumb, product: .perpetual, currency: .krw)
    // 화면 구성 중 실제 저장소나 외부 네트워크를 사용하지 않는다.
    let repository = store
    // 이 테스트의 계좌를 명시한 로컬 검증 서비스다.
    let service = FuturesHistoryCheckService(store: { repository }, provider: { _ in nil })
    defer { service.suspend() }
    // 화면 입력과 계측만 확인하도록 Reactor 상태를 고정한다.
    let reactor = FuturesAccountReactor(account: account, historyCheck: service, networkAvailability: .empty())
    reactor.isStubEnabled = true
    // 자산 조회 없이 빈 계좌 화면의 상태를 준비한다.
    var state = reactor.initialState
    state.snapshot = try repository.ensureAccount(account)
    reactor.stub.state.value = state
    // 탭에서 선택할 실제 선물 종목이다.
    let instrument = TradingInstrumentID(exchange: .bithumb, product: .perpetual, rawSymbol: "KRW-BTC", settlementCurrency: .krw)
    // 화면이 표시된 상태에서만 방향 선택을 계측한다.
    let controller = FuturesOrderViewController(reactor: reactor, instrument: instrument)
    // UIKit의 실제 표시 상태를 제공하는 테스트 창이다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 667))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 시세나 화면 진입 이벤트 대신 실제 방향 선택 이벤트만 수집한다.
    let events = ReleaseAnalyticsEvents(prefix: "선물_방향_선택")
    // 전송 대체 콜백은 다른 테스트가 남긴 값으로 복원한다.
    let previousCallBack = MobitAnalyticsUtil.eventCallBack
    MobitAnalyticsUtil.eventCallBack = { events.record($0, parameters: $1) }
    defer { MobitAnalyticsUtil.eventCallBack = previousCallBack }
    controller.selectTab(1)
    controller.selectTab(0)
    controller.selectTab(0)
    controller.selectTab(2)
    controller.selectTab(1)
    XCTAssertEqual(events.parameters.compactMap { $0["Step_depth_03"] as? String }, ["숏", "롱", "숏"])
    XCTAssertEqual(events.parameters.compactMap { $0["position_side"] as? String }, ["숏", "롱", "숏"])
    XCTAssertTrue(events.parameters.allSatisfy { $0["exchange"] as? String == "bithumb" && $0["product"] as? String == "perpetual" })
  }

  func testFuturesAnalyticsKeepRequestedAccountAndRecordEachActualTradeOnlyOnce() throws {
    // 다른 화면의 선택 계좌가 바뀌어도 실제 주문 계좌의 계측을 유지한다.
    let account = TradingAccountID(exchange: .upbit, product: .perpetual, currency: .krw)
    // 실제 사용자 저장소 대신 테스트 파일에만 체결한다.
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: account))
    // Firebase 업로드 없이 실제 Reactor 이벤트만 수집한다.
    let events = ReleaseAnalyticsEvents()
    // 기존 테스트의 업로드 대체 콜백을 종료 시 원복한다.
    let previousCallBack = MobitAnalyticsUtil.eventCallBack
    // 테스트 이전의 거래소 선택 저장값을 그대로 복원한다.
    let previousExchange = UserDefaults.standard.object(forKey: "selected-exchange")
    // 테스트 이전의 상품 선택 저장값도 원복한다.
    let previousProduct = UserDefaults.standard.object(forKey: "selected-trading-product")
    MobitAnalyticsUtil.eventCallBack = { name, parameters in
      events.record(name, parameters: parameters)
      if parameters["Step_depth_02"] as? String == "선물_주문_요청" {
        ExchangeSelectionStore.currentExchange = .bithumb
        ExchangeSelectionStore.currentProduct = .spot
      }
    }
    defer {
      MobitAnalyticsUtil.eventCallBack = previousCallBack
      UserDefaults.standard.set(previousExchange, forKey: "selected-exchange")
      UserDefaults.standard.set(previousProduct, forKey: "selected-trading-product")
    }
    // 체결·검증·현재가 갱신을 같은 실제 서비스로 연결한다.
    let provider = ReleaseHistoryProvider(onStalled: {})
    // 시계는 가격 유효기간 안에서 고정한다.
    let service = FuturesHistoryCheckService(store: { repository }, provider: { _ in provider }, now: { Date(timeIntervalSince1970: 66) })
    defer { service.suspend() }
    // 실제 화면처럼 Action·Mutation·State 전체 흐름을 활성화한다.
    let reactor = FuturesAccountReactor(
      account: account,
      useCase: .init(store: { repository }, historyCheck: service, now: { Date(timeIntervalSince1970: 66) }),
      historyCheck: service,
      provider: provider,
      networkAvailability: .just(true)
    )
    // 계좌 파일의 최초 로드가 끝난 뒤 사용자 주문을 보낸다.
    let loaded = expectation(description: "Analytics account is loaded")
    // 실제 상태 구독과 이후 거래 완료 조건을 유지한다.
    let disposeBag = DisposeBag()
    reactor.state.filter { $0.snapshot != nil }.take(1)
      .subscribe(onNext: { _ in loaded.fulfill() }).disposed(by: disposeBag)
    wait(for: [loaded], timeout: 3)
    // 신규·추가 진입은 동일 종목에서 체결 종류만 구분한다.
    let instrument = TradingInstrumentID(exchange: .upbit, product: .perpetual, rawSymbol: "KRW-BTC", settlementCurrency: .krw)
    try performAnalyticsTrade(.open(instrument, .long, 100, 10, nil, lockedPrice(instrument)), reactor: reactor, historyCount: 1)
    // 다음 주문의 실제 포지션만 사용하며 식별자는 계측 파라미터에 포함하지 않는다.
    let positionID = try XCTUnwrap(reactor.position(for: instrument)?.id)
    try performAnalyticsTrade(.open(instrument, .long, 100, 10, positionID, lockedPrice(instrument)), reactor: reactor, historyCount: 2)
    try performAnalyticsTrade(.closeQuantity(positionID, 5, 20, lockedPrice(instrument)), reactor: reactor, historyCount: 3)
    try performAnalyticsTrade(.close(positionID, lockedPrice(instrument)), reactor: reactor, historyCount: 4)
    // 거래 결과와 무관한 시세·완료 상태 갱신은 추가 주문 이벤트를 만들지 않는다.
    let refreshed = expectation(description: "Read-only refresh completes without new order events")
    service.status.filter {
      if case .finished = $0 { return true }
      return false
    }.skip(1).take(1).subscribe(onNext: { _ in refreshed.fulfill() }).disposed(by: disposeBag)
    service.observe(.init(instrument: instrument, price: 101, timestamp: 66_000))
    service.refresh()
    wait(for: [refreshed], timeout: 3)
    XCTAssertEqual(events.parameters.compactMap { $0["Step_depth_02"] as? String }, [
      "선물_주문_요청", "선물_주문_성공", "선물_주문_요청", "선물_주문_성공",
      "선물_주문_요청", "선물_주문_성공", "선물_주문_요청", "선물_주문_성공"
    ])
    XCTAssertEqual(events.parameters.compactMap { $0["order_type"] as? String }, [
      "신규_진입", "신규_진입", "추가_진입", "추가_진입", "부분_종료", "부분_종료", "전량_종료", "전량_종료"
    ])
    XCTAssertTrue(events.parameters.allSatisfy { $0["exchange"] as? String == "upbit" && $0["product"] as? String == "perpetual" && $0["market"] as? String == "KRW-BTC" })
    assertAnalyticsParametersContainNoPrivateValues(events.parameters)
  }

  func testFuturesAnalyticsClassifyFailuresAndBlocksWithoutErrorTextOrPrivateValues() throws {
    // 실패도 선택된 화면이 아닌 명시한 빗썸 선물 계좌에 연결한다.
    let account = TradingAccountID(exchange: .bithumb, product: .perpetual, currency: .krw)
    // 실제 앱 자산과 분리한 주문 저장소다.
    let repository = store
    try repository.applyAdvertisementReward(AdRewardClaim(account: account))
    // 오류 원문 대신 고정 사유만 전달되는지 수집한다.
    let events = ReleaseAnalyticsEvents()
    // 다른 테스트의 Firebase 대체 콜백을 보존한다.
    let previousCallBack = MobitAnalyticsUtil.eventCallBack
    MobitAnalyticsUtil.eventCallBack = { events.record($0, parameters: $1) }
    defer { MobitAnalyticsUtil.eventCallBack = previousCallBack }
    // 실제 오류 뒤 기기 연결까지 끊어 별도 차단 경로를 검증한다.
    let availability = BehaviorSubject(value: true)
    // 주문 검증은 테스트 계좌 파일을 사용한다.
    let service = FuturesHistoryCheckService(store: { repository }, provider: { _ in nil }, now: { Date(timeIntervalSince1970: 66) })
    defer { service.suspend() }
    // 잘못된 레버리지 검증은 실제 UseCase에서 실패해야 한다.
    let reactor = FuturesAccountReactor(
      account: account,
      useCase: .init(store: { repository }, historyCheck: service, now: { Date(timeIntervalSince1970: 66) }),
      historyCheck: service,
      networkAvailability: availability
    )
    // 상태 구독을 유지한다.
    let disposeBag = DisposeBag()
    // 초기 계좌 로드 전 차단과 실제 계산 오류를 구분한다.
    let loaded = expectation(description: "Failure analytics account is loaded")
    reactor.state.filter { $0.snapshot != nil }.take(1)
      .subscribe(onNext: { _ in loaded.fulfill() }).disposed(by: disposeBag)
    wait(for: [loaded], timeout: 3)
    // 레버리지 상한을 초과하는 요청이며 실제 금액은 계측하지 않는다.
    let instrument = TradingInstrumentID(exchange: .bithumb, product: .perpetual, rawSymbol: "KRW-BTC", settlementCurrency: .krw)
    // 실제 실패 완료 이후에만 연결 단절 차단을 실행한다.
    let failed = expectation(description: "Invalid leverage fails in the actual use case")
    reactor.state.filter { !$0.submitting && $0.message == FuturesText.text("futures_leverage_error") }.take(1)
      .subscribe(onNext: { _ in failed.fulfill() }).disposed(by: disposeBag)
    reactor.action.onNext(.open(instrument, .short, 100, 101, nil, lockedPrice(instrument)))
    wait(for: [failed], timeout: 3)
    // 네트워크 유실이 화면 상태에 도착한 뒤 다음 요청을 차단한다.
    let offline = expectation(description: "Network loss reaches the reactor")
    reactor.state.filter { $0.networkAvailable == false }.take(1)
      .subscribe(onNext: { _ in offline.fulfill() }).disposed(by: disposeBag)
    availability.onNext(false)
    wait(for: [offline], timeout: 3)
    // 차단 Mutation이 반영된 뒤 이벤트 개수를 확인한다.
    let blocked = expectation(description: "Offline request is blocked without starting a trade")
    reactor.state.filter { !$0.submitting && $0.message == FuturesText.text("futures_wait") }.take(1)
      .subscribe(onNext: { _ in blocked.fulfill() }).disposed(by: disposeBag)
    reactor.action.onNext(.open(instrument, .short, 100, 10, nil, lockedPrice(instrument)))
    wait(for: [blocked], timeout: 3)
    XCTAssertEqual(events.parameters.compactMap { $0["Step_depth_02"] as? String }, ["선물_주문_요청", "선물_주문_실패", "선물_주문_차단"])
    XCTAssertEqual(events.parameters.compactMap { $0["Step_depth_03"] as? String }, ["레버리지_오류", "네트워크_연결끊김"])
    XCTAssertEqual(events.parameters.compactMap { $0["failure_reason"] as? String }, ["레버리지_오류", "네트워크_연결끊김"])
    XCTAssertTrue(events.parameters.allSatisfy { $0["exchange"] as? String == "bithumb" && $0["product"] as? String == "perpetual" })
    XCTAssertTrue(try repository.snapshot().positions.isEmpty)
    assertAnalyticsParametersContainNoPrivateValues(events.parameters)
  }

  private func performAnalyticsTrade(_ action: FuturesAccountReactor.Action, reactor: FuturesAccountReactor, historyCount: Int) throws {
    // 각 실제 저장 완료를 구분해 이전 성공 메시지가 다음 요청을 대신하지 않게 한다.
    let completed = expectation(description: "Actual trade \(historyCount) completes")
    // 계좌 내 누적 거래 수까지 확인한 뒤 다음 사용자 행동을 진행한다.
    let subscription = reactor.state.filter { state in
      !state.submitting && state.message == FuturesText.text("futures_order_done")
        && (try? state.snapshot?.transactionHistory(for: reactor.account).count) == historyCount
    }.take(1).subscribe(onNext: { _ in completed.fulfill() })
    defer { subscription.dispose() }
    reactor.action.onNext(.clearMessage)
    reactor.action.onNext(action)
    wait(for: [completed], timeout: 3)
  }

  private func assertAnalyticsParametersContainNoPrivateValues(_ events: [[String: Any]]) {
    // 허용된 행동 분류·계좌·마켓 키 외의 금액·식별자·오류 원문은 허용하지 않는다.
    let allowedKeys: Set<String> = [
      "location", "Step_depth_01", "Step_depth_02", "Step_depth_03", "exchange", "exchange_name",
      "product", "product_name", "account_name", "currency", "market", "market_currency", "order_type", "position_side", "leverage", "failure_reason"
    ]
    for event in events { XCTAssertTrue(Set(event.keys).isSubset(of: allowedKeys)) }
  }
  #endif

  private func order(
    exchange: Exchange,
    side: FuturesSide,
    margin: Decimal,
    price: Decimal,
    time: Int64
  ) throws -> FuturesOpeningOrder {
    // 실제 국내 거래 규약을 적용할 상품 식별자다.
    let instrument = TradingInstrumentID(exchange: exchange, product: .perpetual, rawSymbol: "KRW-BTC", settlementCurrency: .krw)
    return FuturesOpeningOrder(
      requestID: UUID(),
      account: .init(exchange: exchange, product: .perpetual, currency: .krw),
      instrument: instrument,
      side: side,
      margin: margin,
      leverage: 10,
      executionPrice: price,
      entryFeeRate: 0,
      executedAt: Date(timeIntervalSince1970: Double(time) / 1_000),
      contractRules: try XCTUnwrap(TradingRules.DomesticFutures.contractRules(for: instrument))
    )
  }

  private func check(_ order: FuturesOpeningOrder, time: Int64, price: Decimal? = nil) throws -> FuturesOrderCheck {
    // 저장소의 실제 버전과 계좌별 검증 완료 시각을 준비한다.
    let snapshot = try store.snapshot()
    return FuturesOrderCheck(
      account: order.account,
      instrument: order.instrument,
      revision: snapshot.revision,
      mark: .init(instrument: order.instrument, price: price ?? order.executionPrice, timestamp: time),
      verifiedPositions: Dictionary(uniqueKeysWithValues: snapshot.positions.filter { $0.order.account == order.account && snapshot.isActive($0) }.map { ($0.id, time) })
    )
  }

  private func lockedPrice(_ instrument: TradingInstrumentID) -> FuturesOrderPrice {
    .init(quote: .init(instrument: instrument, price: 100, timestamp: 66_000), requestedAt: 66_000)
  }
}

private final class ReleaseMonitor: FuturesPositionMonitoring {
  // 연결·체결 순서를 테스트에서 직접 제어한다.
  let subject = PublishSubject<FuturesMonitorEvent>()
  // 실제 서비스가 구독할 감시 이벤트다.
  var events: Observable<FuturesMonitorEvent> { subject.asObservable() }
  func watch(_ instruments: [TradingInstrumentID]) {}
  func suspend() {}
}

#if DEBUG
private final class ReleaseAnalyticsEvents {
  // 이벤트가 서로 다른 비동기 경로에서 도착해도 수집과 조회를 보호한다.
  private let lock = NSLock()
  // 실제 주문 행동 이벤트만 보관하며 계좌 화면의 자동 갱신은 제외한다.
  private var storedParameters: [[String: Any]] = []
  // 회귀 대상 사용자 행동만 선택해 수집한다.
  private let prefix: String

  init(prefix: String = "선물_주문_") { self.prefix = prefix }

  var parameters: [[String: Any]] {
    lock.lock()
    defer { lock.unlock() }
    return storedParameters
  }

  func record(_ name: String, parameters: [String: Any]) {
    guard name == "mobit_click_event", (parameters["Step_depth_02"] as? String)?.hasPrefix(prefix) == true else { return }
    lock.lock()
    defer { lock.unlock() }
    storedParameters.append(parameters)
  }
}
#endif

private final class ReleaseHistoryProvider: FuturesDetailedMarketDataProviding {
  // 테스트 스레드와 검증 큐 사이의 응답 모드 전환을 보호한다.
  private let lock = NSLock()
  // 한 거래소만 느린 API 응답으로 전환한다.
  private var stalledExchanges: Set<Exchange> = []
  // 연결 복구 시 지연 중인 해당 거래소 요청만 완료한다.
  private let recoveries = PublishSubject<Exchange>()
  // 지연 요청 구독 시점을 테스트에 알린다.
  private let onStalled: () -> Void
  // 검증 스냅샷을 읽은 뒤 저장소 변경이 끼어드는 경합을 재현한다.
  private let beforeHistory: (TradingInstrumentID) -> Void
  // 현재 시각을 바꿔 새 검증 구간을 재현한다.
  private let quoteTimestamp: () -> Int64
  // 요청 당시의 이력 응답을 주문 완료 뒤까지 지연시킨다.
  private let historyResponse: (FuturesReplayBatch) -> Single<FuturesReplayBatch>

  init(
    onStalled: @escaping () -> Void,
    beforeHistory: @escaping (TradingInstrumentID) -> Void = { _ in },
    quoteTimestamp: @escaping () -> Int64 = { 65_999 },
    historyResponse: @escaping (FuturesReplayBatch) -> Single<FuturesReplayBatch> = { .just($0) }
  ) {
    self.onStalled = onStalled
    self.beforeHistory = beforeHistory
    self.quoteTimestamp = quoteTimestamp
    self.historyResponse = historyResponse
  }

  func stall(_ exchange: Exchange) {
    lock.lock()
    stalledExchanges.insert(exchange)
    lock.unlock()
  }

  func resume(_ exchange: Exchange) {
    lock.lock()
    stalledExchanges.remove(exchange)
    lock.unlock()
    recoveries.onNext(exchange)
  }

  func markQuote(_ instrument: TradingInstrumentID) -> Single<FuturesMarkQuote> {
    lock.lock()
    // 정상 업비트 응답에는 지연 상태가 전파되지 않는다.
    let shouldStall = stalledExchanges.contains(instrument.exchange)
    lock.unlock()
    if shouldStall {
      return recoveries.filter { $0 == instrument.exchange }.take(1)
        .map { [self] _ in FuturesMarkQuote(instrument: instrument, price: 100, timestamp: quoteTimestamp()) }
        .asSingle().do(onSubscribe: onStalled)
    }
    return .just(.init(instrument: instrument, price: 100, timestamp: quoteTimestamp()))
  }

  func contract(_ instrument: TradingInstrumentID) -> Single<FuturesMarketContract> {
    .error(FuturesMarketDataError.invalidRequest)
  }

  func markCandles(
    _ instrument: TradingInstrumentID,
    start: Int64,
    endExclusive: Int64
  ) -> Single<FuturesHistoryPage<FuturesMarkCandle>> {
    .error(FuturesMarketDataError.invalidRequest)
  }

  func funding(
    _ instrument: TradingInstrumentID,
    start: Int64,
    endExclusive: Int64
  ) -> Single<FuturesHistoryPage<FuturesFundingEvent>> {
    .just(.init(instrument: instrument, values: [], nextStartTime: nil))
  }

  func boundaryHistory(
    _ instrument: TradingInstrumentID,
    start: Int64,
    endExclusive: Int64,
    initialEntry: Bool
  ) -> Single<FuturesReplayBatch> {
    beforeHistory(instrument)
    return historyResponse(.init(
      instrument: instrument,
      start: start,
      endExclusive: endExclusive,
      candles: [.init(openTime: start, closeTime: endExclusive - 1, open: 100, high: 100, low: 100, close: 100)],
      funding: [],
      detailed: true
    ))
  }
}
