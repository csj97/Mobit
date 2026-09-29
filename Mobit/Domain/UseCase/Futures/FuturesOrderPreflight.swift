import Foundation

enum FuturesOrderPreflightError: Error, Equatable {
  case reconciliationInProgress
  case invalidTarget
  case staleQuote
  case held(FuturesReconciliationHold)
}

struct FuturesOrderPreflight {
  let account: TradingAccountID
  let instrument: TradingInstrumentID
  let revision: UInt64
  let mark: FuturesMarkQuote
  var verifiedPositions: [UUID: Int64] = [:]
  var executionTimestamp: Int64? = nil
  var executionTime: Int64 { executionTimestamp ?? mark.timestamp }

  func validate(snapshot: FuturesAccountSnapshot, now: Date) throws {
    guard snapshot.revision == revision else { throw LocalFuturesAccountRepository.StoreError.revisionConflict }
    guard account.supports(instrument),
          mark.instrument == instrument, snapshot.accounts.contains(where: { $0.id == account }) else {
      throw FuturesOrderPreflightError.invalidTarget
    }
    let timestamp = try FuturesReconciliationState.milliseconds(now)
    guard mark.timestamp > 0, mark.timestamp <= timestamp, mark.timestamp >= timestamp - 5_000,
          executionTime >= mark.timestamp, executionTime <= timestamp, executionTime >= timestamp - 5_000,
          !mark.price.isNaN, mark.price > 0 else { throw FuturesOrderPreflightError.staleQuote }
    for position in snapshot.positions where position.order.account == account {
      guard let state = snapshot.reconciliations.first(where: { $0.positionID == position.id }) else {
        throw LocalFuturesAccountRepository.StoreError.invalidStoredData
      }
      if !snapshot.isActive(position) { continue }
      // 국내 모의 체결은 준비 시 고정한 시각에 묶고 저장 시 신선도와 revision을 재검사한다.
      let requiredThrough = instrument.usesDomesticSpotPrice ? executionTime : timestamp
      guard max(state.verifiedThrough, verifiedPositions[position.id] ?? 0) >= requiredThrough else { throw FuturesOrderPreflightError.held(.currentInterval) }
      if position.order.instrument == instrument,
         try FuturesCalculator.evaluate(position, markPrice: mark.price, netFunding: state.netFunding).shouldLiquidate {
        throw FuturesOrderPreflightError.held(.currentInterval)
      }
    }
  }
}
