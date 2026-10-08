import Foundation

enum FuturesOrderCheckError: Error, Equatable {
  // 과거 가격 검증이 진행 중이거나 주문 준비가 완료되지 않았다.
  case historyCheckInProgress
  case invalidTarget
  case staleQuote
  case held(FuturesHistoryCheckHold)
}

struct FuturesOrderPrice: Equatable {
  let quote: FuturesMarkQuote
  let requestedAt: Int64
}

struct FuturesOrderCheck {
  let account: TradingAccountID
  let instrument: TradingInstrumentID
  let revision: UInt64
  let mark: FuturesMarkQuote
  var verifiedPositions: [UUID: Int64] = [:]
  var executionTimestamp: Int64? = nil
  var priceLockedAt: Int64? = nil
  var monitoredPositions: [UUID: Date] = [:]
  var monitoringGeneration: UInt64? = nil
  var executionTime: Int64 { executionTimestamp ?? mark.timestamp }

  func validate(snapshot: FuturesAccountSnapshot, now: Date) throws {
    guard snapshot.revision == revision else { throw LocalFuturesAccountRepository.StoreError.revisionConflict }
    guard account.supports(instrument),
      mark.instrument == instrument, snapshot.accounts.contains(where: { $0.id == account })
    else {
      throw FuturesOrderCheckError.invalidTarget
    }
	
    let timestamp = try FuturesHistoryCheckState.milliseconds(now)
    let priceReferenceTime = priceLockedAt ?? mark.timestamp
	
    guard priceLockedAt == nil || priceLockedAt == executionTime,
      mark.timestamp > 0, mark.timestamp <= priceReferenceTime,
      priceReferenceTime <= timestamp, priceReferenceTime >= timestamp - 5_000,
      executionTime >= mark.timestamp, executionTime <= timestamp, executionTime >= timestamp - 5_000,
      !mark.price.isNaN, mark.price > 0
    else { throw FuturesOrderCheckError.staleQuote }
	
    for position in snapshot.positions where position.order.account == account {
      guard let state = snapshot.historyCheckStates.first(where: { $0.positionID == position.id }) else {
        throw LocalFuturesAccountRepository.StoreError.invalidStoredData
      }
	  
      if !snapshot.isActive(position) { continue }
	  
      // 국내 모의 체결은 준비 시 고정한 시각에 묶고 저장 시 신선도와 revision을 재검사한다.
      let requiredThrough = instrument.usesDomesticSpotPrice ? executionTime : timestamp
      
	  guard
        monitoredPositions[position.id] == position.lastExecutionAt
          || max(state.verifiedThrough, verifiedPositions[position.id] ?? 0) >= requiredThrough
      else { throw FuturesOrderCheckError.held(.currentInterval) }
      
	  if position.order.instrument == instrument,
        try FuturesCalculator.evaluate(
          position,
          markPrice: mark.price,
          netFunding: state.netFunding
        ).shouldLiquidate
      {
        throw FuturesOrderCheckError.held(.currentInterval)
      }
    }
  }
}
