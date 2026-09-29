import Foundation
import RxSwift

struct FuturesRefreshResult: Equatable {
  let positionID: UUID
  let verifiedThrough: Int64?
  let liquidated: Bool
  let hold: FuturesReconciliationHold?
}

enum FuturesRefreshStatus {
  case refreshing
  case paused
  case finished([FuturesRefreshResult])
  case storageFailed
}

final class FuturesReconciliationService {
  static let shared = FuturesReconciliationService(
    store: { try LocalFuturesAccountRepository.applicationStore() },
    provider: { instrument in
      guard instrument.usesDomesticSpotPrice, instrument.settlementCurrency == .krw else { return nil }
      return DomesticFuturesMarketRepository()
    }
  )

  private let storeFactory: () throws -> LocalFuturesAccountRepository
  private let providerFactory: (TradingInstrumentID) -> FuturesMarketDataProviding?
  private let now: () -> Date
  private let maximumPages: Int
  private let queue: DispatchQueue
  private let scheduler: SerialDispatchQueueScheduler
  private let suspended = PublishSubject<Void>()
  private let subject = BehaviorSubject<FuturesRefreshStatus>(value: .finished([]))
  private var running = false
  private var active = true
  private var generation: UInt64 = 0
  private var disposable: Disposable?

  var status: Observable<FuturesRefreshStatus> { subject.asObservable().observe(on: MainScheduler.instance) }

  init(store: @escaping () throws -> LocalFuturesAccountRepository,
       provider: @escaping (TradingInstrumentID) -> FuturesMarketDataProviding?,
       now: @escaping () -> Date = Date.init, maximumPages: Int = 8) {
    self.storeFactory = store
    self.providerFactory = provider
    self.now = now
    self.maximumPages = max(1, maximumPages)
    let queue = DispatchQueue(label: "mobit.futures.reconciliation")
    self.queue = queue
    self.scheduler = SerialDispatchQueueScheduler(queue: queue, internalSerialQueueName: "mobit.futures.reconciliation.rx")
  }

  deinit { disposable?.dispose() }

  // Scene 활성화가 겹쳐도 한 실행으로 합친다. 네트워크 대기는 저장소 잠금 밖이다.
  func refresh() {
    queue.async { [weak self] in self?.startRefresh() }
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
      let positions = snapshot.positions.filter { position in
        snapshot.isActive(position)
      }
      disposable = Observable.from(positions).concatMap { [self] position in
        self.refresh(position, store: store).asObservable()
      }.toArray().observe(on: scheduler).subscribe(onSuccess: { [weak self] results in
        guard let self, active, generation == currentGeneration else { return }
        running = false
        subject.onNext(.finished(results))
        if results.contains(where: { !$0.liquidated && $0.hold != .unsupportedInstrument && $0.hold != .storageFailed }) {
          let delay: TimeInterval = results.contains(where: { $0.hold == .workLimit }) ? 1 :
            (results.contains(where: { $0.hold == .requestFailed || $0.hold == .missingHistory }) ? 15 : 3)
          queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, active, generation == currentGeneration else { return }
            self.startRefresh()
          }
        }
      }, onFailure: { [weak self] _ in
        guard let self, generation == currentGeneration else { return }
        running = false
        subject.onNext(.storageFailed)
      })
    } catch {
      running = false
      subject.onNext(.storageFailed)
    }
  }

  func suspend() {
    queue.async { [weak self] in
      guard let self else { return }
      active = false
      generation &+= 1
      suspended.onNext(())
      disposable?.dispose()
      disposable = nil
      running = false
      subject.onNext(.paused)
    }
  }

  // 준비 결과는 계좌 revision에 묶인다. 실제 저장 시 다시 검증해야 한다.
  func prepareOrder(account: TradingAccountID, instrument: TradingInstrumentID) -> Single<FuturesOrderPreflight> {
    Single.deferred { [self] in
      guard active, !running else { throw FuturesOrderPreflightError.reconciliationInProgress }
      guard account.supports(instrument),
            let provider = providerFactory(instrument) else { throw FuturesOrderPreflightError.invalidTarget }
      running = true
      generation &+= 1
      let currentGeneration = generation
      let work: Single<FuturesOrderPreflight> = Single.deferred { [self] in
        let store = try storeFactory()
        let snapshot = try store.snapshot()
        let positions = snapshot.positions.filter { position in
          position.order.account == account && snapshot.isActive(position)
        }
        return Observable.from(positions).concatMap { [self] position in
          self.refresh(position, store: store).asObservable()
        }.toArray().flatMap { [self] results -> Single<FuturesOrderPreflight> in
          if let hold = results.first(where: { $0.hold != nil && $0.hold != .currentInterval })?.hold {
            throw FuturesOrderPreflightError.held(hold)
          }
          return provider.markQuote(instrument).timeout(.seconds(20), scheduler: scheduler).observe(on: scheduler)
            .flatMap { [self] quote -> Single<FuturesOrderPreflight> in
              let executionTime = provider is FuturesDetailedMarketDataProviding
                ? try FuturesReconciliationState.milliseconds(now()) : quote.timestamp
              let current = try store.snapshot()
              let activePositions = current.positions.filter { $0.order.account == account && current.isActive($0) }
              return Observable.from(activePositions).concatMap { [self] position -> Observable<FuturesRefreshResult> in
                guard let source = providerFactory(position.order.instrument) else {
                  throw FuturesOrderPreflightError.invalidTarget
                }
                return process(position, store: store, provider: source, end: executionTime, pages: 0).asObservable()
              }.toArray().map { [self] results in
                if let hold = results.first(where: { $0.hold != nil })?.hold { throw FuturesOrderPreflightError.held(hold) }
                let final = try store.snapshot()
                guard final.revision == current.revision else { throw LocalFuturesAccountRepository.StoreError.revisionConflict }
                let preflight = FuturesOrderPreflight(account: account, instrument: instrument,
                  revision: final.revision, mark: quote,
                  verifiedPositions: Dictionary(uniqueKeysWithValues: results.compactMap { result in
                    result.verifiedThrough.map { (result.positionID, $0) }
                  }), executionTimestamp: executionTime)
                try preflight.validate(snapshot: final, now: now())
                return preflight
              }
            }
        }
      }
      return work.asObservable().take(until: suspended).asSingle().do(onDispose: { [weak self] in
        self?.queue.async { [weak self] in
          guard let self, generation == currentGeneration else { return }
          running = false
          if active {
            queue.asyncAfter(deadline: .now() + 3) { [weak self] in
              guard let self, active, generation == currentGeneration else { return }
              startRefresh()
            }
          }
        }
      })
    }.subscribe(on: scheduler)
  }

  private func refresh(_ position: FuturesPosition, store: LocalFuturesAccountRepository) -> Single<FuturesRefreshResult> {
    guard let provider = providerFactory(position.order.instrument) else {
      return .just(result(position.id, hold: .unsupportedInstrument))
    }
    return provider.markQuote(position.order.instrument)
      .timeout(.seconds(20), scheduler: scheduler).observe(on: scheduler)
      .flatMap { [self] quote -> Single<FuturesRefreshResult> in
        let current = try FuturesReconciliationState.milliseconds(now())
        guard quote.instrument == position.order.instrument, quote.timestamp > 0,
              quote.timestamp <= current + 5_000, quote.timestamp >= current - 30_000,
              !quote.price.isNaN, quote.price > 0 else {
          return .just(result(position.id, hold: .staleQuote))
        }
        let end = provider is FuturesDetailedMarketDataProviding ? quote.timestamp + 1 : quote.timestamp - quote.timestamp % 60_000
        return process(position, store: store, provider: provider, end: end, pages: 0)
      }.catch { [self] error in .just(result(position.id, hold: reason(error))) }
  }

  private func process(_ position: FuturesPosition, store: LocalFuturesAccountRepository,
                       provider: FuturesMarketDataProviding, end: Int64, pages: Int) -> Single<FuturesRefreshResult> {
    Single.deferred { [self] in
      let snapshot = try store.snapshot()
      guard let state = snapshot.reconciliations.first(where: { $0.positionID == position.id }) else {
        throw LocalFuturesAccountRepository.StoreError.invalidStoredData
      }
      if !snapshot.isActive(position) { return .just(result(position.id, state: state)) }
      guard state.verifiedThrough < end else {
        return .just(result(position.id, state: state, hold: provider is FuturesDetailedMarketDataProviding ? nil : .currentInterval))
      }
      guard pages < maximumPages else { return .just(result(position.id, state: state, hold: .workLimit)) }
      let start = state.verifiedThrough
      let floorStart = start - start % 60_000
      let batch: Single<FuturesReplayBatch>
      let pageEnd: Int64
      if let detail = provider as? FuturesDetailedMarketDataProviding, start % 60_000 != 0 || end < start + 60_000 {
        pageEnd = min(end, floorStart + 60_000)
        batch = detail.boundaryHistory(position.order.instrument, start: start, endExclusive: pageEnd,
          initialEntry: start == (try FuturesReconciliationState.milliseconds(position.lastExecutionAt)))
      } else {
        pageEnd = min(end - end % 60_000, floorStart + 499 * 60_000)
        guard pageEnd > start else { return .just(result(position.id, state: state, hold: .currentInterval)) }
        let funding: Single<FuturesHistoryPage<FuturesFundingEvent>> = position.order.instrument.usesDomesticSpotPrice
          ? .just(.init(instrument: position.order.instrument, values: [], nextStartTime: nil))
          : provider.funding(position.order.instrument, start: start, endExclusive: pageEnd)
        batch = Single.zip(provider.markCandles(position.order.instrument, start: floorStart, endExclusive: pageEnd), funding)
          .map { candles, funding in
            guard candles.instrument == position.order.instrument, funding.instrument == position.order.instrument,
                  candles.nextStartTime == nil, funding.nextStartTime == nil else { throw FuturesMarketDataError.incompleteHistory }
            return .init(instrument: position.order.instrument, start: start, endExclusive: pageEnd,
              candles: candles.values, funding: funding.values)
          }
      }
      return batch.timeout(.seconds(20), scheduler: scheduler).observe(on: scheduler).flatMap { [self] batch in
        let outcome = try store.reconcile(positionID: position.id, expectedRevision: snapshot.revision,
                                          batch: batch, settledAt: now())
        if outcome.state.liquidation != nil || outcome.hold != nil || (batch.detailed && pageEnd == end) {
          return .just(result(position.id, state: outcome.state, hold: outcome.hold))
        }
        return process(position, store: store, provider: provider, end: end, pages: pages + 1)
      }.catch { [self] error in .just(result(position.id, state: state, hold: reason(error))) }
    }
  }

  private func result(_ id: UUID, state: FuturesReconciliationState? = nil,
                      hold: FuturesReconciliationHold? = nil) -> FuturesRefreshResult {
    FuturesRefreshResult(positionID: id, verifiedThrough: state?.verifiedThrough,
                         liquidated: state?.liquidation != nil, hold: hold)
  }

  private func reason(_ error: Error) -> FuturesReconciliationHold {
    if let error = error as? LocalFuturesAccountRepository.StoreError {
      return error == .revisionConflict ? .revisionChanged : .storageFailed
    }
    if error as? FuturesMarketDataError == .workLimit { return .workLimit }
    if error is CocoaError { return .storageFailed }
    if error is FuturesReconciliationError || error is FuturesCalculationError { return .missingHistory }
    if let error = error as? FuturesMarketDataError, error == .incompleteHistory || error == .invalidResponse {
      return .missingHistory
    }
    return .requestFailed
  }
}
