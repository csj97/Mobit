import Foundation
import RxSwift

final class FuturesTradingUseCase {
  private let store: () throws -> LocalFuturesAccountRepository
  private let reconciliation: FuturesReconciliationService
  private let now: () -> Date
  private let scheduler = SerialDispatchQueueScheduler(qos: .userInitiated)

  init(store: @escaping () throws -> LocalFuturesAccountRepository = LocalFuturesAccountRepository.applicationStore,
       reconciliation: FuturesReconciliationService = .shared, now: @escaping () -> Date = Date.init) {
    self.store = store
    self.reconciliation = reconciliation
    self.now = now
  }

  func accountSnapshot(for account: TradingAccountID) -> Single<FuturesAccountSnapshot> {
    Single.deferred { [self] in
      guard account.product == .perpetual, account.currency == .krw,
            account.exchange == .upbit || account.exchange == .bithumb else {
        throw FuturesOrderPreflightError.invalidTarget
      }
      return .just(try store().ensureAccount(account))
    }.subscribe(on: scheduler)
  }

  func open(requestID: UUID, account: TradingAccountID, instrument: TradingInstrumentID,
            side: FuturesSide, margin: Decimal, leverage: Int, addingTo positionID: UUID? = nil) -> Single<FuturesAccountSnapshot> {
    Single.deferred { [self] in
      guard instrument.usesDomesticSpotPrice, account.supports(instrument),
            let maximum = instrument.maximumPaperLeverage else { throw FuturesOrderPreflightError.invalidTarget }
      try FuturesDecimal.positive(margin)
      guard (1...maximum).contains(leverage) else { throw FuturesCalculationError.invalidLeverage }
      let repository = try store()
      let snapshot = try repository.snapshot()
      if let position = snapshot.positions.first(where: { $0.executions.contains(where: { $0.requestID == requestID }) }),
         let order = position.executions.first(where: { $0.requestID == requestID }) {
        guard order.account == account, order.instrument == instrument, order.side == side,
              order.margin == margin, order.leverage == leverage, positionID == nil || positionID == position.id else {
          throw LocalFuturesAccountRepository.StoreError.conflictingOrder
        }
        return .just(snapshot)
      }
      return reconciliation.prepareOrder(account: account, instrument: instrument).map { [self] preflight in
        if let positionID {
          let current = try repository.snapshot()
          guard current.positions.contains(where: { $0.id == positionID && $0.order.instrument == instrument && current.isActive($0) }) else {
            throw LocalFuturesAccountRepository.StoreError.positionClosed
          }
        }
        let step = Decimal(sign: .plus, exponent: -8, significand: 1)
        let rules = FuturesContractRules(maximumLeverage: maximum, quantityStep: step, minimumQuantity: step,
          minimumNotional: Decimal(SettlementCurrency.krw.minimumOrderAmount))
        let order = FuturesOpeningOrder(requestID: requestID, account: account, instrument: instrument, side: side,
          margin: margin, leverage: leverage, executionPrice: preflight.mark.price, entryFeeRate: 0,
          executedAt: Date(timeIntervalSince1970: Double(preflight.executionTime) / 1000), contractRules: rules)
        return try repository.openPosition(order, preflight: preflight, now: now())
      }
    }.subscribe(on: scheduler)
  }

  func close(requestID: UUID, positionID: UUID) -> Single<FuturesAccountSnapshot> {
    Single.deferred { [self] in
      let repository = try store()
      let snapshot = try repository.snapshot()
      if let closed = snapshot.closedPositions.first(where: { $0.order.requestID == requestID }) {
        guard closed.order.positionID == positionID else { throw LocalFuturesAccountRepository.StoreError.conflictingOrder }
        return .just(snapshot)
      }
      guard let position = snapshot.positions.first(where: { $0.id == positionID }),
            position.order.instrument.usesDomesticSpotPrice, snapshot.isActive(position) else {
        throw LocalFuturesAccountRepository.StoreError.positionClosed
      }
      return reconciliation.prepareOrder(account: position.order.account, instrument: position.order.instrument).map { [self] preflight in
        let order = FuturesClosingOrder(requestID: requestID, positionID: positionID, executionPrice: preflight.mark.price,
          executedAt: Date(timeIntervalSince1970: Double(preflight.executionTime) / 1000))
        return try repository.closePosition(order, preflight: preflight, now: now())
      }
    }.subscribe(on: scheduler)
  }
}
