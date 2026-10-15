import Foundation
import RxSwift

enum FuturesMonitorEvent {
  case connection(Exchange, Bool)
  case quote(FuturesMarkQuote, displayTimestamp: Int64? = nil)
}

protocol FuturesPositionMonitoring: AnyObject {
  var events: Observable<FuturesMonitorEvent> { get }
  func watch(_ instruments: [TradingInstrumentID])
  func suspend()
}

struct FuturesRefreshResult: Equatable {
  let positionID: UUID
  let verifiedThrough: Int64?
  let liquidated: Bool
  let hold: FuturesHistoryCheckHold?
  // 저장 간격 사이에 완료한 검증 가격도 화면 전환 후 다시 사용할 수 있게 보관한다.
  var lastVerifiedMark: Decimal? = nil

  // 가격은 유지하되 새 세션의 과거 구간을 확인하기 전 주문 허용 근거로 쓰지 않는다.
  func requiringHistoryCheck() -> Self {
    Self(
      positionID: positionID,
      verifiedThrough: verifiedThrough,
      liquidated: liquidated,
      hold: liquidated ? hold : (hold ?? .currentInterval),
      lastVerifiedMark: lastVerifiedMark
    )
  }
}

enum FuturesRefreshStatus {
  case refreshing
  case paused
  case finished([FuturesRefreshResult])
  case storageFailed
}

// 화면 수명과 분리해 같은 실패 구간의 안내 여부를 공유한다.
struct FuturesDataFailure: Equatable {
  // 검증 성공 전까지 유지하는 오류 안내 식별자다.
  let id: UUID
  // nil이면 계좌 구분 전 발생한 로컬 저장소 오류다.
  let account: TradingAccountID?
  // 실제 실패로 끝난 검증 횟수이며 진행 보류는 세지 않는다.
  var attempts: Int
  // 사용자 안내 수준과 진단에 사용하는 마지막 실패 사유다.
  var hold: FuturesHistoryCheckHold

  var shouldNotify: Bool {
    hold == .storageFailed || hold == .unsupportedInstrument || attempts >= 3
  }
}

struct FuturesDataFailurePolicy {
  // 계좌별 오류 구간은 완전한 검증 성공 또는 포지션 소멸 때만 종료한다.
  private(set) var failures: [FuturesDataFailure] = []
  // 화면 재생성·수동 재시도에서도 이미 알린 오류를 다시 띄우지 않는다.
  private var presentedIDs: Set<UUID> = []

  mutating func recordStorageFailure() {
    record(account: nil, hold: .storageFailed)
  }

  mutating func complete(_ results: [FuturesRefreshResult], positions: [FuturesPosition]) {
    // 한 계좌에 여러 포지션이 있어도 검증 한 회를 한 번의 실패로 센다.
    let accounts = Dictionary(grouping: positions, by: { $0.order.account })
    // 로컬 읽기 복구 및 포지션 소멸은 기존 오류 구간을 끝낸다.
    failures.removeAll { failure in failure.account.map { accounts[$0] == nil } ?? true }
    for (account, positions) in accounts {
      // 다른 계좌의 실패가 정상 계좌의 화면을 막지 않도록 결과를 분리한다.
      let completed = results.filter { result in positions.contains { $0.id == result.positionID } }
      if completed.count == positions.count,
        completed.allSatisfy({ TradingRules.Futures.HistoryCheck.isPositionReady(liquidated: $0.liquidated, hold: $0.hold) }) {
        failures.removeAll { $0.account == account }
      } else {
        // 복수 실패 중 로컬 저장소·미지원 오류를 우선해 즉시 조치가 필요한 실패를 숨기지 않는다.
        let holds = completed.compactMap { $0.liquidated ? nil : $0.hold }.filter(Self.isFailure)
        if let hold = holds.first(where: { $0 == .storageFailed || $0 == .unsupportedInstrument }) ?? holds.first {
          record(account: account, hold: hold)
        }
      }
    }
    presentedIDs.formIntersection(Set(failures.map(\.id)))
  }

  mutating func claimNotice(_ id: UUID) -> Bool {
    presentedIDs.insert(id).inserted
  }

  static func isFailure(_ hold: FuturesHistoryCheckHold) -> Bool {
    switch hold {
    case .workLimit, .currentInterval, .revisionChanged: return false
    default: return true
    }
  }

  private mutating func record(account: TradingAccountID?, hold: FuturesHistoryCheckHold) {
    if let index = failures.firstIndex(where: { $0.account == account }) {
      failures[index].attempts += 1
      failures[index].hold = hold
    } else {
      failures.append(.init(id: UUID(), account: account, attempts: 1, hold: hold))
    }
  }
}

final class FuturesHistoryCheckService {
  static let shared = FuturesHistoryCheckService(
    store: { try LocalFuturesAccountRepository.applicationStore() },
    provider: { instrument in
      guard TradingRules.DomesticFutures.supportsHistoryInstrument(instrument) else { return nil }
      return DomesticFuturesMarketRepository()
    },
    monitor: FuturesPositionSocketMonitor(),
    networkAvailability: NetworkMonitor.shared.availability
  )

  private let storeFactory: () throws -> LocalFuturesAccountRepository
  private let providerFactory: (TradingInstrumentID) -> FuturesMarketDataProviding?
  private let now: () -> Date
  private let maximumPages: Int
  private let orderPreparationTimeout: RxTimeInterval
  private let queue: DispatchQueue
  private let scheduler: SerialDispatchQueueScheduler
  private let subject = BehaviorSubject<FuturesRefreshStatus>(value: .finished([]))
  // 인트로 완료 직후 재조회가 시작돼도 새 화면에 직전 검증 결과를 전달한다.
  private var lastFinishedResults: [FuturesRefreshResult]?
  // 오류의 수명과 표시 권한은 서비스 직렬 큐에서만 변경한다.
  private var failurePolicy = FuturesDataFailurePolicy()
  // 늦게 구독한 화면에도 현재 오류 구간을 그대로 전달한다.
  private let failuresSubject = BehaviorSubject<[FuturesDataFailure]>(value: [])
  // 일시 실패는 2초·5초 후 재시도하고 지속 실패는 기존 15초 간격을 사용한다.
  private let failureRetryDelay: (Int) -> TimeInterval
  private var running = false
  private var active = true
  // 연결 복구는 앱 활성 상태와 별도로 판단해 백그라운드 검증을 재개하지 않는다.
  private var networkAvailable: Bool?
  // 화면 수명과 무관하게 네트워크 유실·복구를 한 번만 처리한다.
  private var networkSubscription: Disposable?
  private var generation: UInt64 = 0
  private var disposable: Disposable?
  private var watchedPositions: [TradingInstrumentID: FuturesPosition] = [:]
  private var watchedRevision: UInt64 = 0
  private let liquidations = PublishSubject<[FuturesPosition]>()
  private let quotes = PublishSubject<FuturesMarkQuote>()
  private let monitor: FuturesPositionMonitoring?
  private var monitorSubscription: Disposable?
  private var connectedExchanges: Set<Exchange> = []
  private var receivedInstruments: Set<TradingInstrumentID> = []
  private var readyPositions: [UUID: Date] = [:]
  // 검증 중 수신한 최초 청산 가격을 보관해 다음 tick 없이도 완료 직후 정산한다.
  private var pendingLiquidationQuotes: [TradingInstrumentID: FuturesMarkQuote] = [:]

  var liquidationEvents: Observable<[FuturesPosition]> {
    liquidations.asObservable().observe(on: MainScheduler.instance)
  }

  var liveQuotes: Observable<FuturesMarkQuote> {
    quotes.asObservable().distinctUntilChanged().observe(on: MainScheduler.instance)
  }

  func track(
    _ snapshot: FuturesAccountSnapshot,
    openingRequestID: UUID? = nil,
    // 검증을 마친 부분 종료 직후에도 같은 소켓 세션의 감시를 이어간다.
    closingRequestID: UUID? = nil,
    monitoringGeneration: UInt64? = nil
  ) {
    queue.async { [weak self] in
      guard let self else { return }
      updateWatchedPositions(snapshot)
      if active, networkAvailable != false, monitoringGeneration == generation,
        let position = watchedPositions.values.first(where: { position in
          (openingRequestID.map { id in position.executions.contains { $0.requestID == id } } ?? false)
            || (closingRequestID.map { id in (position.partialClosings ?? []).contains { $0.order.requestID == id } } ?? false)
        })
      {
        readyPositions[position.id] = position.lastExecutionAt
      }
    }
  }

  private func updateWatchedPositions(_ snapshot: FuturesAccountSnapshot) {
    guard snapshot.revision >= watchedRevision else { return }
    watchedRevision = snapshot.revision
    watchedPositions = Dictionary(
      snapshot.positions.filter { snapshot.isActive($0) }.map { ($0.order.instrument, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    pendingLiquidationQuotes = pendingLiquidationQuotes.filter { watchedPositions[$0.key] != nil }
    readyPositions = readyPositions.filter { id, execution in
      watchedPositions.values.contains { $0.id == id && $0.lastExecutionAt == execution }
    }
    if active, networkAvailable != false { monitor?.watch(Array(watchedPositions.keys)) }
  }

  private func receive(_ event: FuturesMonitorEvent) {
    guard active, networkAvailable != false else { return }
    switch event {
    case let .connection(exchange, connected):
      guard connectedExchanges.contains(exchange) != connected else { return }
      connectedExchanges.remove(exchange)
      receivedInstruments = receivedInstruments.filter { $0.exchange != exchange }
      // 실제 단절만 이전 세션 검증을 무효화하고 최초 연결은 진행 중인 검증에 합친다.
      if !connected {
        invalidateVerification()
      }
      if connected { connectedExchanges.insert(exchange) }
      startRefresh()
    case let .quote(quote, displayTimestamp):
      guard connectedExchanges.contains(quote.instrument.exchange),
        quote.price > 0, !quote.price.isNaN
      else { return }
      receivedInstruments.insert(quote.instrument)
      processQuote(quote, displayTimestamp: displayTimestamp)
    }
  }

  func observe(
    _ quote: FuturesMarkQuote,
    // 화면 시세 정렬에는 체결 시각 대신 같은 ticker의 갱신 시각을 사용한다.
    displayTimestamp: Int64? = nil
  ) {
    queue.async { [weak self] in self?.processQuote(quote, displayTimestamp: displayTimestamp) }
  }

  private func processQuote(_ quote: FuturesMarkQuote, displayTimestamp: Int64?) {
    guard active, networkAvailable != false, let position = watchedPositions[quote.instrument],
      !quote.price.isNaN, quote.price > 0,
      let timestamp = try? FuturesHistoryCheckState.milliseconds(now())
    else { return }
    // 화면에 표시할 가격의 순서를 구분하며, 시각이 없는 구형 ticker는 수신 시각을 사용한다.
    let displayTime = displayTimestamp ?? quote.timestamp
    // 표시용 시각을 바꾸더라도 주문·청산에는 원래 체결 시각만 전달한다.
    quotes.onNext(
      FuturesMarkQuote(
        instrument: quote.instrument,
        price: quote.price,
        timestamp: displayTime > 0 ? displayTime : timestamp
      )
    )
    guard quote.timestamp > 0, quote.timestamp <= timestamp else { return }
    guard (try? FuturesCalculator.evaluate(position, markPrice: quote.price).shouldLiquidate) == true else { return }
    // 재진입·재연결 검증을 끝내기 전에는 현재가로 과거 최초 청산 구간을 덮어쓰지 않는다.
    guard readyPositions[position.id] == position.lastExecutionAt else {
      // 만료된 tick은 새 가격으로 교체하고 같은 구간에서는 첫 청산 시각을 보존한다.
      if quote.timestamp >= timestamp - TradingRules.Futures.HistoryCheck.quoteMaximumAgeMilliseconds,
        pendingLiquidationQuotes[quote.instrument].map({
          $0.timestamp < timestamp - TradingRules.Futures.HistoryCheck.quoteMaximumAgeMilliseconds || quote.timestamp < $0.timestamp
        }) ?? true
      { pendingLiquidationQuotes[quote.instrument] = quote }
      return
    }
    do {
      let store = try storeFactory()
      let closed = try store.liquidateObservedQuote(quote, settledAt: now())
      updateWatchedPositions(try store.snapshot())
      publishLiquidations(closed)
    } catch {
      // 저장 실패는 포지션을 유지해 다음 tick/REST에서 재시도한다.
      if reason(error) == .storageFailed {
        readyPositions.removeValue(forKey: position.id)
        failStorage(error, stage: "liveSettlement")
      }
    }
  }

  private func publishLiquidations(_ positions: [FuturesPosition]) {
    guard !positions.isEmpty else { return }
    liquidations.onNext(positions)
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .futuresAccountDidChange, object: nil)
    }
  }

  var status: Observable<FuturesRefreshStatus> {
    Observable.deferred { [self] in
      guard case .refreshing = try subject.value(), let lastFinishedResults else {
        return subject.asObservable()
      }
      return subject.asObservable().startWith(.finished(lastFinishedResults))
    }.subscribe(on: scheduler).observe(on: MainScheduler.instance)
  }

  init(
    store: @escaping () throws -> LocalFuturesAccountRepository,
    provider: @escaping (TradingInstrumentID) -> FuturesMarketDataProviding?,
    now: @escaping () -> Date = Date.init,
    maximumPages: Int = 8,
    orderPreparationTimeout: RxTimeInterval = .seconds(5),
    monitor: FuturesPositionMonitoring? = nil,
    networkAvailability: Observable<Bool> = .empty(),
    failureRetryDelay: @escaping (Int) -> TimeInterval = { $0 == 1 ? 2 : ($0 == 2 ? 5 : 15) }
  ) {
    self.storeFactory = store
    self.providerFactory = provider
    self.now = now
    self.maximumPages = max(1, maximumPages)
    self.orderPreparationTimeout = orderPreparationTimeout
    self.monitor = monitor
    self.failureRetryDelay = failureRetryDelay
    let queue = DispatchQueue(label: "mobit.futures.reconciliation")
    self.queue = queue
    self.scheduler = SerialDispatchQueueScheduler(
      queue: queue,
      internalSerialQueueName: "mobit.futures.reconciliation.rx"
    )
    networkSubscription = networkAvailability.distinctUntilChanged().observe(on: scheduler)
      .subscribe(onNext: { [weak self] in self?.updateNetworkAvailability($0) })
    monitorSubscription = monitor?.events.observe(on: scheduler)
      .subscribe(onNext: { [weak self] in self?.receive($0) })
  }

  deinit { disposable?.dispose(); networkSubscription?.dispose(); monitorSubscription?.dispose(); monitor?.suspend() }

  // 활성화 권한은 Scene만 변경하고 화면 갱신·자동 재시도는 중단 상태를 존중한다.
  func resume() {
    queue.async { [weak self] in
      guard let self else { return }
      active = true
      startRefresh()
    }
  }

  private func updateNetworkAvailability(_ connected: Bool) {
    // 최초 연결 알림은 진행 중인 앱 시작 검증을 중복 시작하지 않는다.
    let wasDisconnected = networkAvailable == false
    networkAvailable = connected
    if !connected {
      invalidateVerification()
      connectedExchanges.removeAll()
      receivedInstruments.removeAll()
      monitor?.suspend()
    } else if wasDisconnected {
      startRefresh()
    }
  }

  private func invalidateVerification() {
    generation &+= 1
    disposable?.dispose()
    disposable = nil
    running = false
    readyPositions.removeAll()
    pendingLiquidationQuotes.removeAll()
    // 마지막 가격은 보존하지만 이전 세션의 거래 허용 상태는 화면에도 재사용하지 않는다.
    lastFinishedResults = lastFinishedResults?.map { $0.requiringHistoryCheck() }
    subject.onNext(.paused)
  }

  // Scene 활성화가 겹쳐도 한 실행으로 합친다. 네트워크 대기는 저장소 잠금 밖이다.
  func refresh() {
    queue.async { [weak self] in self?.startRefresh() }
  }

  // 인트로는 로컬 저장소의 읽기 결과만 기다리고 네트워크 검증은 독립적으로 계속한다.
  func prepareLaunch() -> Observable<Void> {
    Observable.create { [weak self] observer in
      guard let self else { observer.onCompleted(); return Disposables.create() }
      self.queue.async {
        do {
          _ = try self.storeFactory().snapshot()
          observer.onNext(())
          observer.onCompleted()
          self.startRefresh()
        } catch {
          self.failStorage(error, stage: "launchSnapshot")
          observer.onNext(())
          observer.onCompleted()
        }
      }
      return Disposables.create()
    }.observe(on: MainScheduler.instance)
  }

  func dataFailure(for account: TradingAccountID) -> Observable<FuturesDataFailure?> {
    failuresSubject.map { failures in
      failures.first { $0.account == nil } ?? failures.first { $0.account == account }
    }.distinctUntilChanged().observe(on: MainScheduler.instance)
  }

  func claimDataFailureNotice(_ id: UUID) -> Bool {
    queue.sync { failurePolicy.claimNotice(id) }
  }

  // 화면의 로컬 읽기 오류도 공통 저장소 오류 구간으로 합친다.
  func reportStorageFailure(_ error: Error) {
    Log.warning("stage=accountSnapshot cause=\(Self.diagnosticCode(error))", tag: "FuturesHistoryCheck")
    queue.async { [weak self] in
      guard let self else { return }
      if !failurePolicy.failures.contains(where: { $0.account == nil }) {
        failurePolicy.recordStorageFailure()
        failuresSubject.onNext(failurePolicy.failures)
      }
      if active, !running { scheduleRefresh(after: failureRetryDelay(1)) }
    }
  }

  private func failStorage(_ error: Error, stage: String) {
    generation &+= 1
    disposable?.dispose()
    disposable = nil
    running = false
    readyPositions.removeAll()
    lastFinishedResults = nil
    failurePolicy.recordStorageFailure()
    failuresSubject.onNext(failurePolicy.failures)
    Log.warning("stage=\(stage) cycle=\(generation) cause=\(Self.diagnosticCode(error))", tag: "FuturesHistoryCheck")
    subject.onNext(.storageFailed)
    scheduleRefresh(after: failureRetryDelay(failurePolicy.failures.map(\.attempts).max() ?? 1))
  }

  private func scheduleRefresh(after delay: TimeInterval) {
    // 새 요청·백그라운드 전환은 기존 예약의 실행 권한을 무효화한다.
    let scheduledGeneration = generation
    queue.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self, active, !running, generation == scheduledGeneration else { return }
      startRefresh()
    }
  }

  private func startRefresh() {
    guard active, networkAvailable != false, !running else { return }
    running = true
    generation &+= 1
    let currentGeneration = generation
    subject.onNext(.refreshing)
    do {
      let store = try storeFactory()
      let snapshot = try store.snapshot()
      updateWatchedPositions(snapshot)
      let positions = snapshot.positions.filter { position in
        snapshot.isActive(position)
      }
      disposable = Observable.from(positions).concatMap { [self] position in
        self.refresh(position, store: store).asObservable()
      }.toArray().observe(on: scheduler).map { [self] results in
        guard active, generation == currentGeneration else { return results }
        return try settlePendingLiquidationQuotes(results, store: store)
      }.subscribe(
        onSuccess: { [weak self] results in
          guard let self, active, generation == currentGeneration else { return }
          running = false
          for result in results {
            guard let position = positions.first(where: { $0.id == result.positionID }) else { continue }
            if TradingRules.Futures.HistoryCheck.isPositionReady(liquidated: result.liquidated, hold: result.hold) {
              readyPositions[position.id] = position.lastExecutionAt
            } else {
              readyPositions.removeValue(forKey: position.id)
            }
          }
          // 오류 구간이 실제 검증 성공으로 끝났는지 진단한다.
          let previousFailures = failurePolicy.failures
          failurePolicy.complete(results, positions: positions)
          for failure in previousFailures where !failurePolicy.failures.contains(where: { $0.id == failure.id }) {
            Log.info("stage=recovered cycle=\(currentGeneration) attempts=\(failure.attempts)", tag: "FuturesHistoryCheck")
          }
          failuresSubject.onNext(failurePolicy.failures)
          for result in results where result.hold.map(FuturesDataFailurePolicy.isFailure) == true {
            // 원본 자산·응답 대신 검증 종류와 누적 실패 횟수만 기록한다.
            let account = positions.first { $0.id == result.positionID }?.order.account
            // 같은 계좌의 실패는 실행당 한 번씩 집계한다.
            let attempts = failurePolicy.failures.first { $0.account == account }?.attempts ?? 0
            Log.warning("stage=verification cycle=\(currentGeneration) hold=\(result.hold?.rawValue ?? "unknown") attempts=\(attempts)", tag: "FuturesHistoryCheck")
          }
          lastFinishedResults = results
          subject.onNext(.finished(results))
          if results.contains(where: { !$0.liquidated && $0.hold != .unsupportedInstrument }) {
            // 실패 재시도를 우선 제한해 workLimit 포지션과 섞여도 서버 요청이 폭주하지 않게 한다.
            let hasFailure = results.contains { result in
              !result.liquidated && result.hold != .unsupportedInstrument
                && result.hold.map(FuturesDataFailurePolicy.isFailure) == true
            }
            // 이전 실패 후 정상 이어받기 중이면 진행 간격을 다시 적용한다.
            let attempts = hasFailure ? failurePolicy.failures.filter { $0.hold != .unsupportedInstrument }.map(\.attempts).max() : nil
            // 현재 실행의 실패·진행·정상 완료에 맞춘 다음 조회 간격이다.
            let delay = attempts.map(failureRetryDelay)
              ?? (results.contains(where: { $0.hold == .workLimit }) ? 1 : (results.contains(where: { $0.hold != nil }) ? 15 : 30))
            scheduleRefresh(after: delay)
          }
        },
        onFailure: { [weak self] error in
          guard let self, generation == currentGeneration else { return }
          failStorage(error, stage: "settlement")
        }
      )
    } catch {
      failStorage(error, stage: "snapshot")
    }
  }

  private func settlePendingLiquidationQuotes(
    _ results: [FuturesRefreshResult],
    store: LocalFuturesAccountRepository
  ) throws -> [FuturesRefreshResult] {
    // 검증 완료 이벤트에는 대기 중인 소켓 청산까지 저장된 최종 결과를 전달한다.
    var completed = results
    // 저장소의 현재가 정산과 동일한 유효 시간만 허용한다.
    let timestamp = try FuturesHistoryCheckState.milliseconds(now())
    for (index, result) in results.enumerated() where TradingRules.Futures.HistoryCheck.isPositionReady(liquidated: result.liquidated, hold: result.hold) {
      guard let position = watchedPositions.values.first(where: { $0.id == result.positionID }),
        let quote = pendingLiquidationQuotes.removeValue(forKey: position.order.instrument),
        let verifiedThrough = result.verifiedThrough,
        quote.timestamp >= verifiedThrough,
        quote.timestamp >= timestamp - TradingRules.Futures.HistoryCheck.quoteMaximumAgeMilliseconds, quote.timestamp <= timestamp
      else { continue }
      // 과거 검증 경계 이후에 수신한 가격만 사용해 더 이른 청산 이력을 덮어쓰지 않는다.
      let closed = try store.liquidateObservedQuote(quote, settledAt: now())
      guard !closed.isEmpty else { continue }
      // 계좌와 알림보다 먼저 청산이 원자적으로 저장됐는지 확인한다.
      let snapshot = try store.snapshot()
      updateWatchedPositions(snapshot)
      completed[index] = self.result(
        position.id,
        state: snapshot.historyCheckStates.first { $0.positionID == position.id }
      )
      publishLiquidations(closed)
    }
    return completed
  }

  func suspend() {
    queue.async { [weak self] in
      guard let self else { return }
      active = false
      invalidateVerification()
      connectedExchanges.removeAll()
      receivedInstruments.removeAll()
      monitor?.suspend()
    }
  }

  // 주문은 검증 결과만 소비한다. 네트워크 조회와 검증 완료 대기는 자동 검증의 책임이다.
  func prepareOrder(
    account: TradingAccountID,
    instrument: TradingInstrumentID,
    price: FuturesOrderPrice? = nil
  ) -> Single<FuturesOrderCheck> {
    Single.deferred { [self] in
      guard active, networkAvailable != false else { throw FuturesOrderCheckError.historyCheckInProgress }
      guard let price else { throw FuturesOrderCheckError.staleQuote }
      guard account.supports(instrument), price.quote.instrument == instrument else {
        throw FuturesOrderCheckError.invalidTarget
      }
      let snapshot = try storeFactory().snapshot()
      let positions = snapshot.positions.filter { $0.order.account == account && snapshot.isActive($0) }
      for position in positions {
        guard readyPositions[position.id] == position.lastExecutionAt,
          monitor == nil
            || (connectedExchanges.contains(account.exchange)
              && receivedInstruments.contains(position.order.instrument))
        else {
          throw FuturesOrderCheckError.historyCheckInProgress
        }
      }
      // 주문 시 확인할 가격·체결 시각·계좌 버전과 포지션 검증 상태다.
      let orderCheck = FuturesOrderCheck(
        account: account,
        instrument: instrument,
        revision: snapshot.revision,
        mark: price.quote,
        executionTimestamp: price.requestedAt,
        priceLockedAt: price.requestedAt,
        monitoredPositions: readyPositions,
        monitoringGeneration: generation
      )
      try orderCheck.validate(snapshot: snapshot, now: now())
      return .just(orderCheck)
    }.timeout(orderPreparationTimeout, scheduler: scheduler).subscribe(on: scheduler)
  }

  private func refresh(_ position: FuturesPosition, store: LocalFuturesAccountRepository) -> Single<
    FuturesRefreshResult
  > {
    guard let provider = providerFactory(position.order.instrument) else {
      return .just(result(position.id, hold: .unsupportedInstrument))
    }
    return provider.markQuote(position.order.instrument)
      .timeout(.seconds(20), scheduler: scheduler).observe(on: scheduler)
      .flatMap { [self] quote -> Single<FuturesRefreshResult> in
        let current = try FuturesHistoryCheckState.milliseconds(now())
        // 무체결로 체결 시각이 멈춰도 새 REST 응답이면 과거 구간 검증을 진행한다.
        let freshnessTimestamp = quote.responseTimestamp ?? quote.timestamp
        guard quote.instrument == position.order.instrument, quote.timestamp > 0,
          quote.timestamp <= current + TradingRules.Futures.HistoryCheck.restClockAheadMilliseconds,
          freshnessTimestamp <= current + TradingRules.Futures.HistoryCheck.restClockAheadMilliseconds,
          freshnessTimestamp >= current - TradingRules.Futures.HistoryCheck.quoteMaximumAgeMilliseconds,
          !quote.price.isNaN, quote.price > 0
        else {
          return .just(result(position.id, hold: .staleQuote))
        }
        // REST 현재가는 검증 종료 경계로만 사용하고 청산은 과거 가격 순서로 확정한다.
        let end =
          provider is FuturesDetailedMarketDataProviding
          ? min(max(quote.timestamp + 1, quote.responseTimestamp ?? 0), current)
          : quote.timestamp - quote.timestamp % 60_000
        return process(position, store: store, provider: provider, end: end, pages: 0)
      }.catch { [self] error in
        logFailure(error, stage: "quote", instrument: position.order.instrument)
        return .just(result(position.id, hold: reason(error)))
      }
  }

  private func process(
    _ position: FuturesPosition,
    store: LocalFuturesAccountRepository,
    provider: FuturesMarketDataProviding,
    end: Int64,
    pages: Int
  ) -> Single<FuturesRefreshResult> {
    Single.deferred { [self] in
      let snapshot = try store.snapshot()
      guard let state = snapshot.historyCheckStates.first(where: { $0.positionID == position.id }) else {
        throw LocalFuturesAccountRepository.StoreError.invalidStoredData
      }
      if !snapshot.isActive(position) { return .just(result(position.id, state: state)) }
      guard state.verifiedThrough < end else {
        return .just(
          result(
            position.id,
            state: state,
            hold: provider is FuturesDetailedMarketDataProviding ? nil : .currentInterval
          )
        )
      }
      guard pages < maximumPages else { return .just(result(position.id, state: state, hold: .workLimit)) }
      let start = state.verifiedThrough
      let floorStart = start - start % 60_000
      let batch: Single<FuturesReplayBatch>
      let pageEnd: Int64
      if let detail = provider as? FuturesDetailedMarketDataProviding, start % 60_000 != 0 || end < start + 60_000 {
        pageEnd = min(end, floorStart + 60_000)
        batch = detail.boundaryHistory(
          position.order.instrument,
          start: start,
          endExclusive: pageEnd,
          initialEntry: start == (try FuturesHistoryCheckState.milliseconds(position.lastExecutionAt))
        )
      } else {
        pageEnd = min(end - end % 60_000, floorStart + 499 * 60_000)
        guard pageEnd > start else { return .just(result(position.id, state: state, hold: .currentInterval)) }
        let funding: Single<FuturesHistoryPage<FuturesFundingEvent>> =
          !TradingRules.Futures.allowsFunding(for: position.order.instrument)
          ? .just(.init(instrument: position.order.instrument, values: [], nextStartTime: nil))
          : provider.funding(position.order.instrument, start: start, endExclusive: pageEnd)
        batch = Single.zip(
          provider.markCandles(position.order.instrument, start: floorStart, endExclusive: pageEnd),
          funding
        )
        .map { candles, funding in
          guard candles.instrument == position.order.instrument, funding.instrument == position.order.instrument,
            candles.nextStartTime == nil, funding.nextStartTime == nil
          else { throw FuturesMarketDataError.incompleteHistory }
          return .init(
            instrument: position.order.instrument,
            start: start,
            endExclusive: pageEnd,
            candles: candles.values,
            funding: funding.values
          )
        }
      }
      return batch.timeout(.seconds(20), scheduler: scheduler).observe(on: scheduler).flatMap { [self] batch in
        checkHistory(
          batch,
          position: position,
          state: state,
          store: store,
          expectedRevision: snapshot.revision,
          provider: provider
        )
      }.flatMap { [self] outcome in
        if outcome.state.liquidation != nil {
          updateWatchedPositions(try store.snapshot())
          publishLiquidations([position])
        }
        if outcome.state.liquidation != nil || outcome.hold != nil
          || (provider is FuturesDetailedMarketDataProviding && pageEnd == end) {
          return .just(result(position.id, state: outcome.state, hold: outcome.hold))
        }
        return process(position, store: store, provider: provider, end: end, pages: pages + 1)
      }.catch { [self] error in
        logFailure(error, stage: "history", instrument: position.order.instrument)
        return .just(result(position.id, state: state, hold: reason(error)))
      }
    }
  }

  private func checkHistory(
    _ batch: FuturesReplayBatch,
    position: FuturesPosition,
    state: FuturesHistoryCheckState,
    store: LocalFuturesAccountRepository,
    expectedRevision: UInt64,
    provider: FuturesMarketDataProviding
  ) -> Single<FuturesReplayResult> {
    Single.deferred { [self] in
      // 최초 청산 분을 찾은 뒤 해당 분만 정밀 조회해 불필요한 전체 초봉 조회를 피한다.
      let minuteResult = try FuturesReplayCalculator.replay(batch, position: position, state: state, settledAt: now())
      guard !batch.detailed, TradingRules.Futures.HistoryCheck.allowsDetailedHistory(for: position.order.instrument),
        let liquidation = minuteResult.state.liquidation,
        let detail = provider as? FuturesDetailedMarketDataProviding
      else {
        return .just(
          try store.checkHistoryAndSettle(
            positionID: position.id,
            expectedRevision: expectedRevision,
            batch: batch,
            settledAt: now()
          )
        )
      }
      return detail.boundaryHistory(
        position.order.instrument,
        start: liquidation.intervalStart,
        endExclusive: liquidation.intervalEndExclusive,
        initialEntry: liquidation.intervalStart == (try FuturesHistoryCheckState.milliseconds(position.lastExecutionAt))
      ).timeout(.seconds(20), scheduler: scheduler).observe(on: scheduler).map { [self] detailBatch in
        try store.checkHistoryAndSettle(
          positionID: position.id,
          expectedRevision: expectedRevision,
          batch: batch,
          settledAt: now(),
          detailBatch: detailBatch
        )
      }.catch { [self] error in
        // 정밀 이력이 없더라도 진입 이후의 온전한 분봉이 증명한 청산은 분 단위로 확정한다.
        guard error as? FuturesMarketDataError == .incompleteHistory else { return .error(error) }
        return .just(
          try store.checkHistoryAndSettle(
            positionID: position.id,
            expectedRevision: expectedRevision,
            batch: batch,
            settledAt: now()
          )
        )
      }
    }
  }

  private func result(
    _ id: UUID,
    state: FuturesHistoryCheckState? = nil,
    hold: FuturesHistoryCheckHold? = nil
  ) -> FuturesRefreshResult {
    // REST 오류로 새 이력 상태가 없더라도 앞선 검증 가격은 표시용으로 유지한다.
    let previous = lastFinishedResults?.first { $0.positionID == id }
    return FuturesRefreshResult(
      positionID: id,
      verifiedThrough: state?.verifiedThrough ?? previous?.verifiedThrough,
      liquidated: state?.liquidation != nil,
      hold: hold,
      lastVerifiedMark: state?.lastVerifiedMark ?? previous?.lastVerifiedMark
    )
  }

  private func logFailure(_ error: Error, stage: String, instrument: TradingInstrumentID) {
    Log.warning("stage=\(stage) cycle=\(generation) exchange=\(instrument.exchange.rawValue) market=\(instrument.rawSymbol) cause=\(Self.diagnosticCode(error))", tag: "FuturesHistoryCheck")
  }

  // 응답 본문·URL·자산 값 대신 오류 유형과 코드만 남긴다.
  static func diagnosticCode(_ error: Error) -> String {
    if let error = error as? FuturesMarketDataError { return "market.\(error)" }
    if let error = error as? LocalFuturesAccountRepository.StoreError { return "storage.\(error)" }
    if let error = error as? FuturesHistoryCheckError { return "history.\(error)" }
    if let error = error as? FuturesCalculationError { return "calculation.\(error)" }
    if let error = error as? RxError, case .timeout = error { return "request.timeout" }
    if let error = error as? URLError { return "url.\(error.code.rawValue)" }
    // NSError 메시지와 userInfo에는 파일 경로나 원본 응답이 포함될 수 있다.
    let code = (error as NSError).code
    return "\(String(reflecting: type(of: error))).\(code)"
  }

  private func reason(_ error: Error) -> FuturesHistoryCheckHold {
    if let error = error as? LocalFuturesAccountRepository.StoreError {
      return error == .revisionConflict ? .revisionChanged : .storageFailed
    }
    if error as? FuturesMarketDataError == .workLimit { return .workLimit }
    if error as? FuturesMarketDataError == .unsupportedInstrument { return .unsupportedInstrument }
    if error is CocoaError { return .storageFailed }
    if error is FuturesHistoryCheckError || error is FuturesCalculationError { return .missingHistory }
    if let error = error as? FuturesMarketDataError, error == .incompleteHistory || error == .invalidResponse {
      return .missingHistory
    }
    return .requestFailed
  }
}
