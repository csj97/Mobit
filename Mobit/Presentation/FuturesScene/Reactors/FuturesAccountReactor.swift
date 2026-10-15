import Foundation
import UIKit
import ReactorKit
import RxSwift

final class FuturesAccountReactor: Reactor {
  enum Action {
	case reload
	case open(TradingInstrumentID, FuturesSide, Decimal, Int, UUID?, FuturesOrderPrice? = nil)
	case close(UUID, FuturesOrderPrice? = nil)
    case closeQuantity(UUID, Decimal, Decimal, FuturesOrderPrice)
	case clearMessage
  }
  enum Mutation {
	case snapshot(FuturesAccountSnapshot, [TradingInstrumentID: FuturesMarkQuote]?)
	case quote(FuturesMarkQuote)
	case status(FuturesRefreshStatus)
	case submitting(Bool)
	case message(String?)
	case loadFailed
    case network(Bool)
    case dataFailure(FuturesDataFailure?)
  }
  struct State {
	var snapshot: FuturesAccountSnapshot?
	// 평가 화면용 시세이며, 주문·청산 검증에는 별도로 캡처한 원본 시세를 사용한다.
	var quotes: [TradingInstrumentID: FuturesMarkQuote] = [:]
	var status: FuturesRefreshStatus = .refreshing
	var lastCompletedVerification: [FuturesRefreshResult]?
	// 검증된 연결 구간에서 표시하던 값을 복귀·유실 시에도 보존한다.
    var confirmedQuotes: [TradingInstrumentID: FuturesMarkQuote] = [:]
    // 경로 확인 전에는 연결 여부를 단정하지 않는다.
    var networkAvailable: Bool?
    // 표시할 오류와 미검증 거래 제한을 별도로 관리한다.
    var dataFailure: FuturesDataFailure?
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
  // 과거 가격을 검증하고 청산 결과를 저장하는 서비스다.
  private let historyCheck: FuturesHistoryCheckService
  private let provider: FuturesMarketDataProviding
  // 화면과 주문이 동일한 네트워크 경로 상태를 사용한다.
  private let networkAvailability: Observable<Bool>
  private var pendingOpening: (Opening, UUID)?
  // 재시도는 같은 포지션·종료 수량·확인한 보유 수량일 때만 같은 요청 ID를 사용한다.
  private var pendingClosing: (UUID, Decimal?, Decimal?, UUID)?
  private let reloads = PublishSubject<Void>()

  init(
	account: TradingAccountID,
	useCase: FuturesTradingUseCase = FuturesTradingUseCase(),
	// 과거 가격을 검증하고 청산 결과를 저장하는 서비스다.
	historyCheck: FuturesHistoryCheckService = .shared,
	provider: FuturesMarketDataProviding = DomesticFuturesMarketRepository(),
    networkAvailability: Observable<Bool> = NetworkMonitor.shared.availability
  ) {
	self.account = account
	self.useCase = useCase
	self.historyCheck = historyCheck
	self.provider = provider
    self.networkAvailability = networkAvailability
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
      && currentState.networkAvailable != false
  }

  var canSubmit: Bool {
	canRequestOrder && hasVerifiedPositions
  }

  // 청산 저장 반영 전만 숨기며 조회 보류 자체로 평가값을 없애지 않는다.
  var canDisplayValuation: Bool {
	guard currentState.snapshot != nil else { return false }
	return !positions.contains { position in
	  currentState.lastCompletedVerification?.contains { $0.positionID == position.id && $0.liquidated } == true
	}
  }

  // 연결이 유지되는 주기 갱신은 현재 평가를 유지하고 미검증 구간에서는 확인값을 보존한다.
  var valuationQuotes: [TradingInstrumentID: FuturesMarkQuote] {
    guard canDisplayValuation else { return [:] }
    // 각 포지션의 확인 범위를 별도로 적용해 일부 완료를 계좌 전체 완료로 오인하지 않는다.
    var quotes = currentState.quotes
    for position in positions {
      // 복귀 후에는 직전 완료 결과가 재검증 필요 상태로 바뀌어 현재가 반영이 보류된다.
      let completed = currentState.lastCompletedVerification?.first { $0.positionID == position.id }
      if currentState.networkAvailable != false, let completed,
        TradingRules.Futures.HistoryCheck.isPositionReady(liquidated: completed.liquidated, hold: completed.hold) { continue }
      if let confirmed = currentState.confirmedQuotes[position.order.instrument] {
        quotes[position.order.instrument] = confirmed
        continue
      }
      // 최초 준비 시에는 저장 체크포인트나 진입가를 잠정값으로 표시한다.
      let verification = currentState.snapshot?.historyCheckStates.first { $0.positionID == position.id }
      guard let price = completed?.lastVerifiedMark ?? verification?.lastVerifiedMark ?? (try? position.averageEntryPrice),
        let timestamp = completed?.verifiedThrough ?? verification?.verifiedThrough
          ?? (try? FuturesHistoryCheckState.milliseconds(position.lastExecutionAt))
      else { quotes.removeValue(forKey: position.order.instrument); continue }
      quotes[position.order.instrument] = FuturesMarkQuote(instrument: position.order.instrument, price: price, timestamp: timestamp)
    }
    return quotes
  }

  // 화면 버튼과 실제 요청에 같은 계좌 준비 조건을 적용하며 저장 직전 검증은 UseCase가 수행한다.
  func canExecuteOrder(price: FuturesOrderPrice?, now: Date = Date()) -> Bool {
    guard canSubmit, let price, account.supports(price.quote.instrument),
      !price.quote.price.isNaN, price.quote.price > 0, price.quote.timestamp > 0,
      let timestamp = try? FuturesHistoryCheckState.milliseconds(now)
    else { return false }
    return price.quote.timestamp <= price.requestedAt && price.requestedAt <= timestamp
      && price.requestedAt >= timestamp - TradingRules.Futures.orderMaximumAgeMilliseconds
  }

  // 일시 실패는 자동 복구하고 반복 실패·저장 오류만 사용자에게 안내한다.
  var needsDataRetry: Bool {
    if currentState.loadFailed { return true }
    if case .storageFailed = currentState.status { return true }
    return currentState.dataFailure?.shouldNotify == true
  }

  func claimDataFailureNotice() -> Bool {
    guard let failure = currentState.dataFailure, failure.shouldNotify else { return false }
    return historyCheck.claimDataFailureNotice(failure.id)
  }

  // 첫 실패에도 복귀 인디케이터는 종료하되 거래 제한과 자동 재시도는 유지한다.
  var hasVerificationFailure: Bool {
    if currentState.loadFailed { return true }
    // 자동 재시도 중에도 직전 실제 오류를 유지해 안내가 깜빡이지 않게 한다.
    let verification: [FuturesRefreshResult]
    switch currentState.status {
    case .storageFailed: return true
    case .finished(let results): verification = currentState.lastCompletedVerification ?? results
    case .refreshing: verification = currentState.lastCompletedVerification ?? []
    case .paused: return false
    }
    return verification.contains { result in
      !result.liquidated && positions.contains(where: { $0.id == result.positionID })
        && result.hold.map(FuturesDataFailurePolicy.isFailure) == true
    }
  }

  // 주문 허용 여부는 현재 검증 결과를 확인한다.
  private var hasVerifiedPositions: Bool {
    // 진행 중인 주기 검증에서는 직전 완료 결과로 주문 가능 여부를 확인한다.
	let results: [FuturesRefreshResult]
	switch currentState.status {
	case .finished(let completed): results = currentState.lastCompletedVerification ?? completed
	case .refreshing:
	  guard let completed = currentState.lastCompletedVerification else { return false }
	  results = completed
	case .paused, .storageFailed: return false
	}
	return positions.allSatisfy { position in
	  results.contains {
		$0.positionID == position.id && TradingRules.Futures.HistoryCheck.isPositionReady(liquidated: $0.liquidated, hold: $0.hold)
	  }
	}
  }

  func mutate(action: Action) -> Observable<Mutation> {
	switch action {
	case .reload:
	  reloads.onNext(())
	  historyCheck.refresh()
	  return .empty()
	case .clearMessage: return .just(.message(nil))
	case let .open(instrument, side, margin, leverage, positionID, price):
	  guard canRequestOrder else { return .just(.message(FuturesText.text("futures_wait"))) }
	  let opening = Opening(
		instrument: instrument,
		side: side,
		margin: margin,
		leverage: leverage,
		positionID: positionID
	  )
	  if pendingOpening?.0 != opening { pendingOpening = (opening, UUID()) }
	  guard let requestID = pendingOpening?.1 else { return .empty() }
	  return execute(
		useCase.open(
		  requestID: requestID,
		  account: account,
		  instrument: instrument,
		  side: side,
		  margin: margin,
		  leverage: leverage,
		  addingTo: positionID,
		  price: price
		)
	  )
	case .close(let positionID, let price):
	  guard canRequestOrder else { return .just(.message(FuturesText.text("futures_wait"))) }
	  if pendingClosing?.0 != positionID || pendingClosing?.1 != nil { pendingClosing = (positionID, nil, nil, UUID()) }
	  guard let requestID = pendingClosing?.3 else { return .empty() }
	  return execute(useCase.close(requestID: requestID, positionID: positionID, price: price))
    case let .closeQuantity(positionID, quantity, expectedQuantity, price):
      guard canRequestOrder else { return .just(.message(FuturesText.text("futures_wait"))) }
      if pendingClosing?.0 != positionID || pendingClosing?.1 != quantity || pendingClosing?.2 != expectedQuantity {
        pendingClosing = (positionID, quantity, expectedQuantity, UUID())
      }
      guard let requestID = pendingClosing?.3 else { return .empty() }
      return execute(
        useCase.close(
          requestID: requestID,
          positionID: positionID,
          price: price,
          quantity: quantity,
          expectedQuantity: expectedQuantity
        )
      )
	}
  }

  private func execute(_ operation: Single<FuturesAccountSnapshot>) -> Observable<Mutation> {
	.concat(
	  .just(.submitting(true)),
	  operation.asObservable().observe(on: MainScheduler.instance)
		.flatMap { [weak self] snapshot -> Observable<Mutation> in
		  self?.pendingOpening = nil
		  self?.pendingClosing = nil
		  return .from([.snapshot(snapshot, [:]), .message(FuturesText.text("futures_order_done"))])
		}.catch { error in .just(.message(FuturesText.error(error))) },
	  .just(.submitting(false))
	)
  }

  func transform(mutation: Observable<Mutation>) -> Observable<Mutation> {
	let status = historyCheck.status.do(onNext: { [weak self] status in
	  if case .finished = status { self?.reloads.onNext(()) }
	}).map(Mutation.status)
	let rewards = NotificationCenter.default.rx.notification(.futuresAccountDidChange).map { _ in () }
	let quotes = historyCheck.liveQuotes.filter { [account] in account.supports($0.instrument) }.map(Mutation.quote)
	let loads = Observable.merge(reloads, rewards).startWith(()).flatMapLatest {
	  [weak self] _ -> Observable<Mutation> in
	  guard let self else { return .empty() }
	  return useCase.accountSnapshot(for: account).asObservable().flatMap { [self] snapshot -> Observable<Mutation> in
		let active = snapshot.positions.filter { $0.order.account == self.account && snapshot.isActive($0) }
		let valuation = Observable.from(active).concatMap { [self] position in
		  self.provider.markQuote(position.order.instrument).timeout(.seconds(15), scheduler: MainScheduler.instance)
			.map { Optional($0) }.catch { _ in .just(nil) }.asObservable()
		}.toArray().flatMap { [self] quotes in
		  // 조회 중 청산/광고/주문이 저장됐을 수 있으므로 최신 스냅샷으로 함께 표시한다.
		  self.useCase.accountSnapshot(for: self.account).map { latest in
			Mutation.snapshot(
			  latest,
			  Dictionary(quotes.compactMap { $0 }.map { ($0.instrument, $0) }, uniquingKeysWith: { _, new in new })
			)
		  }
		}
		// 저장된 청산·충전 결과는 시세 응답을 기다리지 않고 먼저 반영한다.
		return .concat(.just(.snapshot(snapshot, nil)), valuation.asObservable())
	  }.observe(on: MainScheduler.instance).catch { [weak self] error in
        self?.historyCheck.reportStorageFailure(error)
        return .just(.loadFailed)
      }
	}
	// 연결 복구 검증은 공통 서비스가 소유하고 화면은 연결·완료 상태만 반영한다.
    let network = networkAvailability.observe(on: MainScheduler.instance).map(Mutation.network)
    // 화면 재생성 시에도 공통 서비스가 보관한 오류 구간을 그대로 사용한다.
    let failures = historyCheck.dataFailure(for: account).map(Mutation.dataFailure)
    return .merge(mutation, loads, status, quotes, network, failures)
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
      state.confirmedQuotes = state.confirmedQuotes.filter { instruments.contains($0.key) }
	  for (instrument, quote) in quotes ?? [:] {
		guard instruments.contains(instrument), quote.instrument == instrument,
		  !quote.price.isNaN, quote.price > 0, quote.timestamp > 0,
		  quote.timestamp > (state.quotes[instrument]?.timestamp ?? 0)
		else { continue }
		state.quotes[instrument] = quote
	  }
	  // 조회 실패에도 마지막 시세를 유지하며, 재실행 시 저장된 검증 가격을 먼저 사용한다.
	  for position in active where state.quotes[position.order.instrument] == nil {
		if let verification = snapshot.historyCheckStates.first(where: { $0.positionID == position.id }),
		  let price = verification.lastVerifiedMark, !price.isNaN, price > 0
		{
		  state.quotes[position.order.instrument] = FuturesMarkQuote(
			instrument: position.order.instrument,
			price: price,
			timestamp: verification.verifiedThrough
		  )
		  continue
		}
		if let price = try? position.averageEntryPrice,
		  let timestamp = try? FuturesHistoryCheckState.milliseconds(position.order.executedAt)
		{
		  state.quotes[position.order.instrument] = FuturesMarkQuote(
			instrument: position.order.instrument,
			price: price,
			timestamp: timestamp
		  )
		}
	  }
	  state.loadFailed = false
	case .quote(let quote):
	  guard let snapshot = state.snapshot,
		account.supports(quote.instrument),
		snapshot.positions.contains(where: { $0.order.instrument == quote.instrument && snapshot.isActive($0) }),
		!quote.price.isNaN, quote.price > 0, quote.timestamp > 0,
		quote.timestamp >= (state.quotes[quote.instrument]?.timestamp ?? 0),
		state.quotes[quote.instrument] != quote
	  else { return state }
	  state.quotes[quote.instrument] = quote
	case .status(let status):
	  state.status = status
	  switch status {
	  case .finished(let results):
        // 유실 전에 시작한 요청의 늦은 완료가 재연결 검증을 대신하지 않게 한다.
        state.lastCompletedVerification = state.networkAvailable == false
          ? results.map { $0.requiringHistoryCheck() } : results
	  case .refreshing: break
	  case .paused:
		state.lastCompletedVerification = state.lastCompletedVerification?.map { $0.requiringHistoryCheck() }
	  case .storageFailed: state.lastCompletedVerification = nil
	  }
    case .dataFailure(let failure): state.dataFailure = failure
	case .submitting(let value): state.submitting = value
	case .message(let message): state.message = message
	case .network(let connected):
      state.networkAvailable = connected
      if !connected {
        state.status = .paused
        state.lastCompletedVerification = state.lastCompletedVerification?.map { $0.requiringHistoryCheck() }
      }
    case .loadFailed:
	  state.loadFailed = true
	  state.lastCompletedVerification = nil
	}
    // 확인된 연결 구간의 가격만 캐시에 넣어 미검증 시세가 복귀 표시값을 덮지 않게 한다.
    if state.networkAvailable != false {
      for result in state.lastCompletedVerification ?? [] where !result.liquidated && result.hold == nil {
        if let position = state.snapshot?.positions.first(where: { $0.id == result.positionID }),
          let current = state.quotes[position.order.instrument] {
          // 늦은 화면 구독의 진입가 캐시보다 이미 완료한 검증 가격을 우선한다.
          let quote: FuturesMarkQuote
          if let price = result.lastVerifiedMark, let timestamp = result.verifiedThrough,
            !price.isNaN, price > 0, timestamp >= current.timestamp {
            quote = FuturesMarkQuote(instrument: current.instrument, price: price, timestamp: timestamp)
            state.quotes[current.instrument] = quote
          } else { quote = current }
          state.confirmedQuotes[position.order.instrument] = quote
        }
      }
    }
	return state
  }
}
