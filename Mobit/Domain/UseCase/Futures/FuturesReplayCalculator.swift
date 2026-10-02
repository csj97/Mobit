import Foundation

enum FuturesReplayCalculator {
  static func validate(_ state: FuturesReconciliationState, position: FuturesPosition) throws {
    try FuturesCalculator.validate(position)
    let start = try FuturesReconciliationState.milliseconds(position.lastExecutionAt)
    guard state.positionID == position.id, state.verifiedThrough >= start,
          state.verifiedThrough <= 253_402_300_799_000 else { throw FuturesReconciliationError.invalidState }
    guard !position.order.instrument.usesDomesticSpotPrice || state.fundingReceipts.isEmpty else {
      throw FuturesReconciliationError.invalidState
    }
    var total: Decimal = 0
    var previous = start - 1
    for receipt in state.fundingReceipts {
      guard receipt.event.timestamp > previous, receipt.event.timestamp >= start,
            receipt.event.timestamp < state.verifiedThrough,
            receipt.amount == (try FuturesCalculator.fundingPayment(position, markPrice: receipt.event.markPrice, rate: receipt.event.rate)) else {
        throw FuturesReconciliationError.invalidState
      }
      total = try FuturesDecimal.add(total, receipt.amount)
      previous = receipt.event.timestamp
    }
    guard total == state.netFunding else { throw FuturesReconciliationError.invalidState }
    if let mark = state.lastVerifiedMark { try FuturesDecimal.positive(mark) }
    if state.verifiedThrough > start {
      guard state.lastVerifiedMark != nil, (position.order.instrument.usesDomesticSpotPrice || state.verifiedThrough % 60_000 == 0) else { throw FuturesReconciliationError.invalidState }
    } else if state.lastVerifiedMark != nil || state.liquidation != nil { throw FuturesReconciliationError.invalidState }
    for fallback in state.entryCloseFallbacks ?? [] {
      guard position.order.instrument.usesDomesticSpotPrice, fallback.start % 60_000 != 0,
            try position.executions.contains(where: { try FuturesReconciliationState.milliseconds($0.executedAt) == fallback.start }),
            validFallbackBoundary(fallback, instrument: position.order.instrument),
            fallback.endExclusive <= state.verifiedThrough else { throw FuturesReconciliationError.invalidState }
    }
    if let liquidation = state.liquidation {
      guard liquidation.intervalStart >= start, liquidation.intervalStart < liquidation.intervalEndExclusive,
            liquidation.intervalEndExclusive == state.verifiedThrough,
            state.fundingReceipts.allSatisfy({ $0.event.timestamp < liquidation.intervalStart }),
            try FuturesReconciliationState.milliseconds(liquidation.settledAt) >= state.verifiedThrough,
            try FuturesCalculator.evaluate(position, markPrice: liquidation.witnessMarkPrice, netFunding: total).shouldLiquidate else {
        throw FuturesReconciliationError.invalidState
      }
    }
  }

  static func replay(_ batch: FuturesReplayBatch, position: FuturesPosition,
                     state: FuturesReconciliationState, settledAt: Date) throws -> FuturesReplayResult {
    try validate(state, position: position)
    if batch.detailed { return try replayDetail(batch, position: position, state: state, settledAt: settledAt) }
    guard !batch.entryCloseFallback else { throw FuturesReconciliationError.invalidHistory }
    guard state.liquidation == nil, batch.instrument == position.order.instrument,
          batch.start == state.verifiedThrough, batch.endExclusive > batch.start,
          batch.endExclusive % 60_000 == 0,
          batch.endExclusive <= (try FuturesReconciliationState.milliseconds(settledAt)),
          batch.endExclusive - batch.start <= 499 * 60_000 else { throw FuturesReconciliationError.invalidHistory }
    guard !position.order.instrument.usesDomesticSpotPrice || batch.funding.isEmpty else {
      throw FuturesReconciliationError.invalidHistory
    }
    let floorStart = batch.start - batch.start % 60_000
    let candles = batch.candles.sorted { $0.openTime < $1.openTime }
    guard candles.count == Int((batch.endExclusive - floorStart) / 60_000) else { throw FuturesReconciliationError.invalidHistory }
    for (index, candle) in candles.enumerated() {
      guard candle.openTime == floorStart + Int64(index) * 60_000, candle.closeTime == candle.openTime + 59_999 else {
        throw FuturesReconciliationError.invalidHistory
      }
      for price in [candle.open, candle.high, candle.low, candle.close] { try FuturesDecimal.positive(price) }
      guard candle.low <= min(candle.open, candle.close), candle.high >= max(candle.open, candle.close) else {
        throw FuturesReconciliationError.invalidHistory
      }
    }
    let events = batch.funding.sorted { $0.timestamp < $1.timestamp }
    guard Set(events.map(\.timestamp)).count == events.count else { throw FuturesReconciliationError.invalidHistory }
    for event in events {
      guard event.timestamp >= batch.start, event.timestamp < batch.endExclusive else { throw FuturesReconciliationError.invalidHistory }
      try FuturesDecimal.positive(event.markPrice)
      try FuturesDecimal.finite(event.rate)
    }
    var result = state
    var eventIndex = 0
    for candle in candles {
      let start = max(batch.start, candle.openTime)
      let end = candle.closeTime + 1
      let adverse = position.order.side == .long ? candle.low : candle.high
      var receipts: [FuturesFundingReceipt] = []
      var funding = result.netFunding
      var atRisk = try FuturesCalculator.evaluate(position, markPrice: adverse, netFunding: funding).shouldLiquidate
      while eventIndex < events.count, events[eventIndex].timestamp < end {
        let event = events[eventIndex]
        // 같은 Mark 자료끼리도 모순되면 시각 순서를 추정해 정산하지 않는다.
        guard event.markPrice >= candle.low, event.markPrice <= candle.high else { throw FuturesReconciliationError.invalidHistory }
        if event.timestamp == (try FuturesReconciliationState.milliseconds(position.lastExecutionAt)) {
          return FuturesReplayResult(state: result, hold: .ambiguousFundingOrder)
        }
        let amount = try FuturesCalculator.fundingPayment(position, markPrice: event.markPrice, rate: event.rate)
        funding = try FuturesDecimal.add(funding, amount)
        receipts.append(FuturesFundingReceipt(event: event, amount: amount))
        let riskAfterFunding = try FuturesCalculator.evaluate(position, markPrice: adverse, netFunding: funding).shouldLiquidate
        atRisk = atRisk || riskAfterFunding
        eventIndex += 1
      }
      if atRisk, !receipts.isEmpty { return FuturesReplayResult(state: result, hold: .ambiguousFundingOrder) }
      if atRisk, start != candle.openTime { return FuturesReplayResult(state: result, hold: .ambiguousEntryCandle) }
      result.netFunding = funding
      result.fundingReceipts += receipts
      result.verifiedThrough = end
      result.lastVerifiedMark = candle.close
      if atRisk {
        result.liquidation = FuturesLiquidationRecord(intervalStart: start, intervalEndExclusive: end,
                                                      witnessMarkPrice: adverse, settledAt: settledAt)
        break
      }
    }
    try validate(result, position: position)
    return FuturesReplayResult(state: result, hold: nil)
  }

  private static func validFallbackBoundary(
	_ fallback: FuturesBoundaryFallback,
	instrument: TradingInstrumentID
  ) -> Bool {
	let minuteEnd = fallback.start - fallback.start % 60_000 + 60_000
	let secondEnd = fallback.start - fallback.start % 1000 + 1000
	return fallback.endExclusive == minuteEnd || (
	  instrument.exchange == .upbit && fallback.start % 1000 != 0 && fallback.endExclusive == secondEnd
	)
  }

  private static func replayDetail(_ batch: FuturesReplayBatch, position: FuturesPosition,
                                   state: FuturesReconciliationState, settledAt: Date) throws -> FuturesReplayResult {
    guard position.order.instrument.usesDomesticSpotPrice, batch.instrument == position.order.instrument,
          state.liquidation == nil, batch.funding.isEmpty, batch.start == state.verifiedThrough,
          batch.endExclusive > batch.start, batch.endExclusive - batch.start <= 60_000,
          batch.endExclusive <= (try FuturesReconciliationState.milliseconds(settledAt)) else {
      throw FuturesReconciliationError.invalidHistory
    }
    if batch.entryCloseFallback {
      let entry = try FuturesReconciliationState.milliseconds(position.lastExecutionAt)
      guard batch.start == entry, entry % 60_000 != 0,
            batch.endExclusive == entry - entry % 60_000 + 60_000,
            let candle = batch.candles.first,
            validFallbackBoundary(
              .init(start: entry, endExclusive: candle.closeTime + 1),
              instrument: batch.instrument
            ),
            candle.open == candle.close, candle.low == candle.close, candle.high == candle.close else {
        throw FuturesReconciliationError.invalidHistory
      }
    }
    var cursor = batch.start
    for candle in batch.candles {
      guard candle.openTime == cursor, candle.closeTime >= cursor, candle.closeTime < batch.endExclusive else {
        throw FuturesReconciliationError.invalidHistory
      }
      for price in [candle.open, candle.high, candle.low, candle.close] { try FuturesDecimal.positive(price) }
      guard candle.low <= min(candle.open, candle.close), candle.high >= max(candle.open, candle.close) else {
        throw FuturesReconciliationError.invalidHistory
      }
      cursor = candle.closeTime + 1
    }
    guard cursor == batch.endExclusive else { throw FuturesReconciliationError.invalidHistory }
    var result = state
    for candle in batch.candles {
      result.verifiedThrough = candle.closeTime + 1
      result.lastVerifiedMark = candle.close
      if batch.entryCloseFallback, candle.openTime == batch.start {
        result.entryCloseFallbacks = (result.entryCloseFallbacks ?? []) + [
          .init(start: batch.start, endExclusive: candle.closeTime + 1)
        ]
      }
      let adverse = position.order.side == .long ? candle.low : candle.high
      if try FuturesCalculator.evaluate(position, markPrice: adverse).shouldLiquidate {
        result.liquidation = .init(intervalStart: candle.openTime, intervalEndExclusive: candle.closeTime + 1,
          witnessMarkPrice: adverse, settledAt: settledAt)
        break
      }
    }
    try validate(result, position: position)
    return FuturesReplayResult(state: result, hold: nil)
  }

}
