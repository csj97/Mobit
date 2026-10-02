import Foundation
import ReactorKit
import RxSwift

final class FuturesAccountReactor: Reactor {
  enum Action {
    case reload
    case open(TradingInstrumentID, FuturesSide, Decimal, Int, UUID?)
    case close(UUID)
    case clearMessage
  }
  enum Mutation {
    case snapshot(FuturesAccountSnapshot, [TradingInstrumentID: FuturesMarkQuote]?)
    case status(FuturesRefreshStatus)
    case submitting(Bool)
    case message(String?)
    case loadFailed
  }
  struct State {
    var snapshot: FuturesAccountSnapshot?
    var quotes: [TradingInstrumentID: FuturesMarkQuote] = [:]
    var status: FuturesRefreshStatus = .refreshing
    var lastCompletedVerification: [FuturesRefreshResult]?
    var submitting = false
    var loadFailed = false
    var message: String?
  }
  struct Opening: Equatable {
    let instrument: TradingInstrumentID
    let side: FuturesSide
    let margin: Decimal
    let leverage: Int
    let positionID: UUID?
  }
  let initialState = State()
  let account: TradingAccountID
  private let useCase: FuturesTradingUseCase
  private let reconciliation: FuturesReconciliationService
  private let provider: FuturesMarketDataProviding
  private var pendingOpening: (Opening, UUID)?
  private var pendingClosing: (UUID, UUID)?
  private let reloads = PublishSubject<Void>()

  init(account: TradingAccountID, useCase: FuturesTradingUseCase = FuturesTradingUseCase(),
       reconciliation: FuturesReconciliationService = .shared,
       provider: FuturesMarketDataProviding = DomesticFuturesMarketRepository()) {
    self.account = account
    self.useCase = useCase
    self.reconciliation = reconciliation
    self.provider = provider
  }

  var positions: [FuturesPosition] {
    guard let snapshot = currentState.snapshot else { return [] }
    return snapshot.positions.filter { $0.order.account == self.account && snapshot.isActive($0) }
  }

  func position(for instrument: TradingInstrumentID) -> FuturesPosition? {
    positions.first { $0.order.instrument == instrument }
  }

  var canRequestOrder: Bool {
    !currentState.submitting && !currentState.loadFailed && currentState.snapshot != nil
  }

  var canSubmit: Bool {
    guard canRequestOrder else { return false }
    let results: [FuturesRefreshResult]
    switch currentState.status {
    case .finished(let completed): results = completed
    case .refreshing:
      guard let completed = currentState.lastCompletedVerification else { return false }
      results = completed
    case .paused, .storageFailed: return false
    }
    return positions.allSatisfy { position in
      results.contains { $0.positionID == position.id && !$0.liquidated && $0.hold == nil }
    }
  }

  func mutate(action: Action) -> Observable<Mutation> {
    switch action {
    case .reload:
      reloads.onNext(())
      reconciliation.refresh()
      return .empty()
    case .clearMessage: return .just(.message(nil))
    case let .open(instrument, side, margin, leverage, positionID):
      guard canRequestOrder else { return .just(.message(FuturesText.text("futures_wait"))) }
      let opening = Opening(instrument: instrument, side: side, margin: margin, leverage: leverage, positionID: positionID)
      if pendingOpening?.0 != opening { pendingOpening = (opening, UUID()) }
      guard let requestID = pendingOpening?.1 else { return .empty() }
      return execute(useCase.open(requestID: requestID, account: account, instrument: instrument,
        side: side, margin: margin, leverage: leverage, addingTo: positionID))
    case .close(let positionID):
      guard canRequestOrder else { return .just(.message(FuturesText.text("futures_wait"))) }
      if pendingClosing?.0 != positionID { pendingClosing = (positionID, UUID()) }
      guard let requestID = pendingClosing?.1 else { return .empty() }
      return execute(useCase.close(requestID: requestID, positionID: positionID))
    }
  }

  private func execute(_ operation: Single<FuturesAccountSnapshot>) -> Observable<Mutation> {
    .concat(.just(.submitting(true)), operation.asObservable().observe(on: MainScheduler.instance)
      .flatMap { [weak self] snapshot -> Observable<Mutation> in
        self?.pendingOpening = nil
        self?.pendingClosing = nil
        self?.reconciliation.refresh()
        return .from([.snapshot(snapshot, [:]), .message(FuturesText.text("futures_order_done"))])
      }.catch { error in .just(.message(FuturesText.error(error))) }, .just(.submitting(false)))
  }

  func transform(mutation: Observable<Mutation>) -> Observable<Mutation> {
    let status = reconciliation.status.do(onNext: { [weak self] status in
      if case .finished = status { self?.reloads.onNext(()) }
    }).map(Mutation.status)
    let rewards = NotificationCenter.default.rx.notification(.futuresAccountDidChange).map { _ in () }
    let loads = Observable.merge(reloads, rewards).startWith(()).flatMapLatest { [weak self] _ -> Observable<Mutation> in
      guard let self else { return .empty() }
      return useCase.accountSnapshot(for: account).asObservable().flatMap { [self] snapshot -> Observable<Mutation> in
        let active = snapshot.positions.filter { $0.order.account == self.account && snapshot.isActive($0) }
        let valuation = Observable.from(active).concatMap { [self] position in
          self.provider.markQuote(position.order.instrument).timeout(.seconds(15), scheduler: MainScheduler.instance)
            .map { Optional($0) }.catch { _ in .just(nil) }.asObservable()
        }.toArray().flatMap { [self] quotes in
          // 조회 중 청산/광고/주문이 저장됐을 수 있으므로 최신 스냅샷으로 함께 표시한다.
          self.useCase.accountSnapshot(for: self.account).map { latest in
            Mutation.snapshot(latest, Dictionary(quotes.compactMap { $0 }.map { ($0.instrument, $0) }, uniquingKeysWith: { _, new in new }))
          }
        }
        // 저장된 청산·충전 결과는 시세 응답을 기다리지 않고 먼저 반영한다.
        return .concat(.just(.snapshot(snapshot, nil)), valuation.asObservable())
      }.observe(on: MainScheduler.instance).catch { _ in .just(.loadFailed) }
    }
    return .merge(mutation, loads, status)
  }

  func reduce(state: State, mutation: Mutation) -> State {
    var state = state
    switch mutation {
    case let .snapshot(snapshot, quotes):
      guard snapshot.revision >= (state.snapshot?.revision ?? 0) else { return state }
      state.snapshot = snapshot
	  let active = snapshot.positions.filter { $0.order.account == account && snapshot.isActive($0) }
	  let instruments = Set(active.map { $0.order.instrument })
	  state.quotes = state.quotes.filter { instruments.contains($0.key) }
	  for (instrument, quote) in quotes ?? [:] {
		guard instruments.contains(instrument), quote.instrument == instrument,
			  !quote.price.isNaN, quote.price > 0, quote.timestamp > 0,
			  quote.timestamp >= (state.quotes[instrument]?.timestamp ?? 0) else { continue }
		state.quotes[instrument] = quote
	  }
	  // 조회 실패에도 마지막 시세를 유지하며, 재실행 시 저장된 검증 가격을 먼저 사용한다.
	  for position in active where state.quotes[position.order.instrument] == nil {
		if let verification = snapshot.reconciliations.first(where: { $0.positionID == position.id }),
		   let price = verification.lastVerifiedMark, !price.isNaN, price > 0 {
		  state.quotes[position.order.instrument] = FuturesMarkQuote(
			instrument: position.order.instrument,
			price: price,
			timestamp: verification.verifiedThrough
		  )
		  continue
		}
		if let price = try? position.averageEntryPrice,
		   let timestamp = try? FuturesReconciliationState.milliseconds(position.order.executedAt) {
		  state.quotes[position.order.instrument] = FuturesMarkQuote(
			instrument: position.order.instrument,
			price: price,
			timestamp: timestamp
		  )
		}
	  }
      state.loadFailed = false
    case .status(let status):
      state.status = status
      switch status {
      case .finished(let results): state.lastCompletedVerification = results
      case .refreshing: break
      case .paused, .storageFailed: state.lastCompletedVerification = nil
      }
    case .submitting(let value): state.submitting = value
    case .message(let message): state.message = message
    case .loadFailed: state.loadFailed = true; state.lastCompletedVerification = nil
    }
    return state
  }
}
