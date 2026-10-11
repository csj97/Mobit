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

final class FuturesHistoryCheckService {
  static let shared = FuturesHistoryCheckService(
    store: { try LocalFuturesAccountRepository.applicationStore() },
    provider: { instrument in
      guard TradingRules.DomesticFutures.supportsHistoryInstrument(instrument) else { return nil }
      return DomesticFuturesMarketRepository()
    },
    monitor: FuturesPositionSocketMonitor()
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
  private var running = false
  private var active = true
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
      if active, monitoringGeneration == generation,
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
    if active { monitor?.watch(Array(watchedPositions.keys)) }
  }

  private func receive(_ event: FuturesMonitorEvent) {
    guard active else { return }
    switch event {
    case let .connection(exchange, connected):
      guard connectedExchanges.contains(exchange) != connected else { return }
      connectedExchanges.remove(exchange)
      receivedInstruments = receivedInstruments.filter { $0.exchange != exchange }
      readyPositions = readyPositions.filter { id, _ in
        watchedPositions.values.contains { $0.id == id && $0.order.account.exchange != exchange }
      }
      // 실제 단절만 이전 세션 검증을 무효화하고 최초 연결은 진행 중인 검증에 합친다.
      if !connected {
        pendingLiquidationQuotes = pendingLiquidationQuotes.filter { $0.key.exchange != exchange }
        generation &+= 1
        disposable?.dispose()
        running = false
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
    guard active, let position = watchedPositions[quote.instrument],
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
        lastFinishedResults = nil
        subject.onNext(.storageFailed)
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
    monitor: FuturesPositionMonitoring? = nil
  ) {
    self.storeFactory = store
    self.providerFactory = provider
    self.now = now
    self.maximumPages = max(1, maximumPages)
    self.orderPreparationTimeout = orderPreparationTimeout
    self.monitor = monitor
    let queue = DispatchQueue(label: "mobit.futures.reconciliation")
    self.queue = queue
    self.scheduler = SerialDispatchQueueScheduler(
      queue: queue,
      internalSerialQueueName: "mobit.futures.reconciliation.rx"
    )
    monitorSubscription = monitor?.events.observe(on: scheduler)
      .subscribe(onNext: { [weak self] in self?.receive($0) })
  }

  deinit { disposable?.dispose(); monitorSubscription?.dispose(); monitor?.suspend() }

  // Scene 활성화가 겹쳐도 한 실행으로 합친다. 네트워크 대기는 저장소 잠금 밖이다.
  func refresh() {
    queue.async { [weak self] in self?.startRefresh() }
  }

  // 보류된 조회는 완료가 아니며, 화면 대기가 끝나도 실제 검증은 계속한다.
  func prepareLaunch(
    minimumDuration: RxTimeInterval = .milliseconds(TradingRules.DomesticFutures.HistoryCheck.minimumIntroMilliseconds),
    timeout: RxTimeInterval = .seconds(TradingRules.DomesticFutures.HistoryCheck.maximumIntroSeconds)
  ) -> Observable<Void> {
    // 새 검증의 완료만 기다리며 화면 구독용 직전 결과는 사용하지 않는다.
    let completion = subject.asObservable().skip(1).observe(on: MainScheduler.instance)
      .flatMapLatest { [weak self] status -> Observable<Void> in
        switch status {
        case .finished(let results):
          if results.allSatisfy({ $0.liquidated || $0.hold == nil }) { return .just(()) }
          // 인트로 대기가 유지되는 동안 보류 구간을 재시도한다.
          return Observable<Int>.timer(.seconds(1), scheduler: MainScheduler.instance)
            .flatMap { [weak self] _ -> Observable<Void> in
              self?.refresh()
              return .empty()
            }
        case .storageFailed: return .just(())
        case .refreshing, .paused: return .empty()
        }
      }.take(1)
      .do(onSubscribed: { [weak self] in self?.refresh() })
      .timeout(timeout, other: Observable<Void>.just(()), scheduler: MainScheduler.instance)
    return Observable.combineLatest(
      Observable<Int>.timer(minimumDuration, scheduler: MainScheduler.instance),
      completion
    ).take(1).map { _ in () }
  }

  private func startRefresh() {
    guard !running else { return }
    active = true
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
          lastFinishedResults = results
          subject.onNext(.finished(results))
          if results.contains(where: {
            !$0.liquidated && $0.hold != .unsupportedInstrument && $0.hold != .storageFailed
          }) {
            let delay: TimeInterval =
              results.contains(where: { $0.hold == .workLimit })
              ? 1 : (results.contains(where: { $0.hold != nil }) ? 15 : 30)
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
              guard let self, active, generation == currentGeneration else { return }
              self.startRefresh()
            }
          }
        },
        onFailure: { [weak self] _ in
          guard let self, generation == currentGeneration else { return }
          running = false
          readyPositions.removeAll()
          lastFinishedResults = nil
          subject.onNext(.storageFailed)
        }
      )
    } catch {
      running = false
      readyPositions.removeAll()
      lastFinishedResults = nil
      subject.onNext(.storageFailed)
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
      readyPositions.removeAll()
      // 주문 가능 상태와 소켓 세션은 폐기하되 확인한 가격은 복귀 화면에 유지한다.
      pendingLiquidationQuotes.removeAll()
      lastFinishedResults = lastFinishedResults?.map { $0.requiringHistoryCheck() }
      connectedExchanges.removeAll()
      receivedInstruments.removeAll()
      monitor?.suspend()
      generation &+= 1
      disposable?.dispose()
      disposable = nil
      running = false
      subject.onNext(.paused)
    }
  }

  // 주문은 검증 결과만 소비한다. 네트워크 조회와 검증 완료 대기는 자동 검증의 책임이다.
  func prepareOrder(
    account: TradingAccountID,
    instrument: TradingInstrumentID,
    price: FuturesOrderPrice? = nil
  ) -> Single<FuturesOrderCheck> {
    Single.deferred { [self] in
      guard active else { throw FuturesOrderCheckError.historyCheckInProgress }
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
      }.catch { [self] error in .just(result(position.id, hold: reason(error))) }
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
      }.catch { [self] error in .just(result(position.id, state: state, hold: reason(error))) }
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

  private func reason(_ error: Error) -> FuturesHistoryCheckHold {
    if let error = error as? LocalFuturesAccountRepository.StoreError {
      return error == .revisionConflict ? .revisionChanged : .storageFailed
    }
    if error as? FuturesMarketDataError == .workLimit { return .workLimit }
    if error is CocoaError { return .storageFailed }
    if error is FuturesHistoryCheckError || error is FuturesCalculationError { return .missingHistory }
    if let error = error as? FuturesMarketDataError, error == .incompleteHistory || error == .invalidResponse {
      return .missingHistory
    }
    return .requestFailed
  }
}
