import Foundation
import RxSwift

final class FuturesTradingUseCase {
  private let store: () throws -> LocalFuturesAccountRepository
  // 과거 가격을 검증하고 청산 결과를 저장하는 서비스다.
  private let historyCheck: FuturesHistoryCheckService
  private let now: () -> Date
  private let scheduler = SerialDispatchQueueScheduler(qos: .userInitiated)

  init(
	store: @escaping () throws -> LocalFuturesAccountRepository = LocalFuturesAccountRepository.applicationStore,
	// 과거 가격을 검증하고 청산 결과를 저장하는 서비스다.
	historyCheck: FuturesHistoryCheckService = .shared,
	now: @escaping () -> Date = Date.init
  ) {
	self.store = store
	self.historyCheck = historyCheck
	self.now = now
  }

  func accountSnapshot(for account: TradingAccountID) -> Single<FuturesAccountSnapshot> {
	Single.deferred { [self] in
	  guard account.product == .perpetual, account.currency == .krw,
		account.exchange == .upbit || account.exchange == .bithumb
	  else {
		throw FuturesOrderCheckError.invalidTarget
	  }
	  return .just(try store().ensureAccount(account))
	}.subscribe(on: scheduler)
  }

  func open(
	requestID: UUID,
	account: TradingAccountID,
	instrument: TradingInstrumentID,
	side: FuturesSide,
	margin: Decimal,
	leverage: Int,
	addingTo positionID: UUID? = nil,
	price: FuturesOrderPrice? = nil
  ) -> Single<FuturesAccountSnapshot> {
	Single.deferred { [self] in
	  guard instrument.usesDomesticSpotPrice, account.supports(instrument),
		let maximum = instrument.maximumPaperLeverage
	  else { throw FuturesOrderCheckError.invalidTarget }
	  try FuturesDecimal.positive(margin)
	  guard (1...maximum).contains(leverage) else { throw FuturesCalculationError.invalidLeverage }
	  let repository = try store()
	  let snapshot = try repository.snapshot()
	  if let position = snapshot.positions.first(where: { $0.executions.contains(where: { $0.requestID == requestID }) }
	  ),
		let order = position.executions.first(where: { $0.requestID == requestID })
	  {
		guard order.account == account, order.instrument == instrument, order.side == side,
		  order.margin == margin, order.leverage == leverage, positionID == nil || positionID == position.id
		else {
		  throw LocalFuturesAccountRepository.StoreError.conflictingOrder
		}
		return .just(snapshot)
	  }
	  // 주문 시 확인할 가격·체결 시각·계좌 버전과 포지션 검증 상태다.
	  return historyCheck.prepareOrder(account: account, instrument: instrument, price: price).map { [self] orderCheck in
		if let positionID {
		  let current = try repository.snapshot()
		  guard
			current.positions.contains(where: {
			  $0.id == positionID && $0.order.instrument == instrument && current.isActive($0)
			})
		  else {
			throw LocalFuturesAccountRepository.StoreError.positionClosed
		  }
		}
		let step = Decimal(sign: .plus, exponent: -8, significand: 1)
		let rules = FuturesContractRules(
		  maximumLeverage: maximum,
		  quantityStep: step,
		  minimumQuantity: step,
		  minimumOrderAmount: Decimal(SettlementCurrency.krw.minimumOrderAmount)
		)
		let order = FuturesOpeningOrder(
		  requestID: requestID,
		  account: account,
		  instrument: instrument,
		  side: side,
		  margin: margin,
		  leverage: leverage,
		  executionPrice: orderCheck.mark.price,
		  entryFeeRate: 0,
		  executedAt: Date(timeIntervalSince1970: Double(orderCheck.executionTime) / 1000),
		  contractRules: rules
		)
		let saved = try repository.openPosition(order, orderCheck: orderCheck, now: now())
		historyCheck.track(
		  saved,
		  openingRequestID: requestID,
		  monitoringGeneration: orderCheck.monitoringGeneration
		)
		return saved
	  }
	}.subscribe(on: scheduler)
  }

  func close(
	requestID: UUID,
	positionID: UUID,
	price: FuturesOrderPrice? = nil,
    // nil은 전량 종료이며 지정한 수량은 주문 준비 후에도 초과 체결하지 않는다.
    quantity: Decimal? = nil,
    // 시트에서 확인한 보유 수량으로 주문 준비 중 변경을 감지한다.
    expectedQuantity: Decimal? = nil
  ) -> Single<FuturesAccountSnapshot> {
	Single.deferred { [self] in
	  let repository = try store()
	  let snapshot = try repository.snapshot()
	  if let closed = snapshot.closedPositions.first(where: { $0.order.requestID == requestID }) {
		guard closed.order.positionID == positionID, closed.order.quantity == quantity,
          closed.order.expectedQuantity == expectedQuantity else {
		  throw LocalFuturesAccountRepository.StoreError.conflictingOrder
		}
		return .just(snapshot)
	  }
      if let closed = snapshot.positions.flatMap({ $0.partialClosings ?? [] }).first(where: { $0.order.requestID == requestID }) {
        guard closed.order.positionID == positionID, closed.order.quantity == quantity,
          closed.order.expectedQuantity == expectedQuantity
        else { throw LocalFuturesAccountRepository.StoreError.conflictingOrder }
        return .just(snapshot)
      }
	  guard let position = snapshot.positions.first(where: { $0.id == positionID }),
		position.order.instrument.usesDomesticSpotPrice, snapshot.isActive(position)
	  else {
		throw LocalFuturesAccountRepository.StoreError.positionClosed
	  }
	  return historyCheck.prepareOrder(
		account: position.order.account,
		instrument: position.order.instrument,
		price: price
	  ).map {
		// 주문 시 확인할 가격·체결 시각·계좌 버전과 포지션 검증 상태다.
		[self] orderCheck in
		let order = FuturesClosingOrder(
		  requestID: requestID,
		  positionID: positionID,
		  executionPrice: orderCheck.mark.price,
		  executedAt: Date(timeIntervalSince1970: Double(orderCheck.executionTime) / 1000),
          quantity: quantity,
          expectedQuantity: expectedQuantity
		)
		let saved = try repository.closePosition(order, orderCheck: orderCheck, now: now())
		historyCheck.track(
          saved,
          closingRequestID: requestID,
          monitoringGeneration: orderCheck.monitoringGeneration
        )
		return saved
	  }
	}.subscribe(on: scheduler)
  }
}
