import Foundation

final class LocalFuturesAccountRepository {
  enum StoreError: Error, Equatable {
	case unsupportedSchema
	case invalidStoredData
	case revisionConflict
	case revisionOverflow
	case conflictingOrder
	case positionAlreadyOpen
	case insufficientBalance
	// 주문 처리 전에 포지션의 과거 가격 검증이 필요하다.
	case historyCheckRequired
	case positionClosed
  }

  // 같은 파일을 여는 여러 인스턴스도 읽기-변경-교체 전체를 직렬화한다.
  private static let lock = NSLock()
  private let fileURL: URL
  private let writeSnapshot: (Data, URL) throws -> Void

  init(
	fileURL: URL,
	writeSnapshot: @escaping (Data, URL) throws -> Void = { data, url in
	  try data.write(to: url, options: .atomic)
	}
  ) {
	self.fileURL = fileURL
	self.writeSnapshot = writeSnapshot
  }

  static func applicationStore() throws -> LocalFuturesAccountRepository {
	let directory = try FileManager.default.url(
	  for: .applicationSupportDirectory,
	  in: .userDomainMask,
	  appropriateFor: nil,
	  create: true
	).appendingPathComponent("Futures", isDirectory: true)
	return LocalFuturesAccountRepository(fileURL: directory.appendingPathComponent("accounts.json"))
  }

  func snapshot() throws -> FuturesAccountSnapshot {
	Self.lock.lock()
	defer { Self.lock.unlock() }
	return try fetchSnapshot()
  }

  @discardableResult
  func ensureAccount(_ id: TradingAccountID) throws -> FuturesAccountSnapshot {
	Self.lock.lock()
	defer { Self.lock.unlock() }
	let current = try fetchSnapshot()
	if current.accounts.contains(where: { $0.id == id }) { return current }
	guard TradingRules.Futures.canCreateAccount(id) else { throw StoreError.invalidStoredData }
	var accounts = current.accounts
	accounts.append(FuturesCashAccount(id: id, availableBalance: Decimal(TradingRules.Funding.unfundedAccountBalance)))
	return try commit(accounts, previous: current)
  }

  @discardableResult
  func update(
	expectedRevision: UInt64,
	_ mutation: (inout [FuturesCashAccount]) throws -> Void
  ) throws -> FuturesAccountSnapshot {
	Self.lock.lock()
	defer { Self.lock.unlock() }
	let current = try fetchSnapshot()
	guard current.revision == expectedRevision else { throw StoreError.revisionConflict }
	var accounts = current.accounts
	try mutation(&accounts)
	return try commit(accounts, previous: current)
  }

  @discardableResult
  func resetInvestment(for account: TradingAccountID) throws -> FuturesAccountSnapshot {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    guard account.product == .perpetual, account.currency == .krw,
      TradingRules.isDomesticExchange(account.exchange)
    else { throw StoreError.invalidStoredData }
    // 검증 중인 이전 스냅샷이 초기화 결과를 다시 덮지 않도록 같은 잠금과 revision을 쓴다.
    let current = try fetchSnapshot()
    // 미생성 계좌를 초기화해도 새 계좌나 자금을 만들지 않는다.
    guard let index = current.accounts.firstIndex(where: { $0.id == account }) else { return current }
    // 선택하지 않은 계좌의 잔고와 계좌 순서는 유지한다.
    var accounts = current.accounts
    accounts[index].availableBalance = Decimal(TradingRules.Funding.unfundedAccountBalance)
    // 포지션과 연결된 검증·종료 기록을 같은 저장 단위에서 제거한다.
    let positions = current.positions.filter { $0.order.account != account }
    // 계좌 식별자가 없는 검증·종료 기록의 보존 대상을 결정한다.
    let positionIDs = Set(positions.map(\.id))
    return try commit(
      accounts,
      previous: current,
      positions: positions,
      ledger: current.ledger.filter { $0.account != account },
      historyCheckStates: current.historyCheckStates.filter { positionIDs.contains($0.positionID) },
      closedPositions: current.closedPositions.filter { positionIDs.contains($0.order.positionID) }
    )
  }

  // 주문 검증 자료의 시세·계좌 버전을 재확인한 뒤 진입 결과를 저장한다.
  @discardableResult
  func openPosition(_ order: FuturesOpeningOrder, orderCheck: FuturesOrderCheck, now: Date = Date()) throws
	-> FuturesAccountSnapshot
  {
	Self.lock.lock()
	defer { Self.lock.unlock() }
	let current = try fetchSnapshot()
	if let existing = current.positions.flatMap(\.executions).first(where: { $0.requestID == order.requestID }) {
	  guard existing == order else { throw StoreError.conflictingOrder }
	  return current
	}
	try orderCheck.validate(snapshot: current, now: now)
	guard order.account == orderCheck.account, order.instrument == orderCheck.instrument,
	  order.executionPrice == orderCheck.mark.price,
	  (try FuturesHistoryCheckState.milliseconds(order.executedAt)) == orderCheck.executionTime
	else { throw FuturesOrderCheckError.invalidTarget }
	return try openPosition(order, expectedRevision: orderCheck.revision, current: current)
  }

  private func openPosition(
	_ order: FuturesOpeningOrder,
	expectedRevision: UInt64,
	current: FuturesAccountSnapshot
  ) throws -> FuturesAccountSnapshot {
	if let existing = current.positions.flatMap(\.executions).first(where: { $0.requestID == order.requestID }) {
	  guard existing == order else { throw StoreError.conflictingOrder }
	  return current
	}
	guard current.revision == expectedRevision else { throw StoreError.revisionConflict }
	let position = try FuturesCalculator.open(order)
	let activeIndex = current.positions.firstIndex { existing in
	  existing.order.account == order.account && existing.order.instrument == order.instrument
		&& current.isActive(existing)
	}
	if let activeIndex {
	  let existing = current.positions[activeIndex]
	  guard TradingRules.Futures.allowsAdditionalEntry(for: order.instrument), TradingRules.canCombine(order, with: existing.order)
	  else {
		throw StoreError.positionAlreadyOpen
	  }
	}
	var accounts = current.accounts
	guard let index = accounts.firstIndex(where: { $0.id == order.account }) else {
	  throw StoreError.invalidStoredData
	}
	guard accounts[index].availableBalance >= order.margin else { throw StoreError.insufficientBalance }
	accounts[index].availableBalance = try FuturesDecimal.subtract(accounts[index].availableBalance, order.margin)
	var positions = current.positions
	// 신규·추가 진입 결과와 함께 저장할 포지션별 검증 상태다.
	var historyCheckStates = current.historyCheckStates
	var entry = try FuturesCalculator.openingLedgerEntry(for: position)
	if let activeIndex {
	  positions[activeIndex] = try FuturesCalculator.adding(order, to: positions[activeIndex])
	  guard let stateIndex = historyCheckStates.firstIndex(where: { $0.positionID == positions[activeIndex].id }) else {
		throw StoreError.invalidStoredData
	  }
	  historyCheckStates[stateIndex].verifiedThrough = try FuturesHistoryCheckState.milliseconds(order.executedAt)
	  historyCheckStates[stateIndex].lastVerifiedMark = nil
	  entry = FuturesLedgerEntry(
		id: entry.id,
		positionID: positions[activeIndex].id,
		account: entry.account,
		occurredAt: entry.occurredAt,
		kind: entry.kind,
		cashDelta: entry.cashDelta,
		reservedMarginChange: entry.reservedMarginChange,
		feePaid: entry.feePaid
	  )
	} else {
	  positions.append(position)
	  historyCheckStates.append(try FuturesHistoryCheckState.initial(for: position))
	}
	return try commit(
	  accounts,
	  previous: current,
	  positions: positions,
	  ledger: current.ledger + [entry],
	  historyCheckStates: historyCheckStates
	)
  }

  @discardableResult
  func closePosition(
	_ order: FuturesClosingOrder,
	// 주문 시 확인할 가격·체결 시각·계좌 버전과 포지션 검증 상태다.
	orderCheck: FuturesOrderCheck,
	now: Date = Date()
  ) throws -> FuturesAccountSnapshot {
	Self.lock.lock()
	defer { Self.lock.unlock() }
	let current = try fetchSnapshot()
	if let existing = current.closedPositions.first(where: { $0.order.requestID == order.requestID }) {
	  guard existing.order == order else { throw StoreError.conflictingOrder }
	  return current
	}
    if let existing = current.positions.flatMap({ $0.partialClosings ?? [] }).first(where: { $0.order.requestID == order.requestID }) {
      guard existing.order == order else { throw StoreError.conflictingOrder }
      return current
    }
	guard !current.ledger.contains(where: { $0.id == order.requestID }),
	  let position = current.positions.first(where: { $0.id == order.positionID }),
	  current.isActive(position),
	  let state = current.historyCheckStates.first(where: { $0.positionID == position.id })
	else { throw StoreError.positionClosed }
	try orderCheck.validate(snapshot: current, now: now)
    guard order.expectedQuantity == nil || order.expectedQuantity == position.quantity,
      order.executedAt >= position.lastExecutionAt,
      try FuturesHistoryCheckState.milliseconds(order.executedAt) >= state.verifiedThrough
    else { throw StoreError.revisionConflict }
	guard position.order.account == orderCheck.account, position.order.instrument == orderCheck.instrument,
	  order.executionPrice == orderCheck.mark.price,
	  try FuturesHistoryCheckState.milliseconds(order.executedAt) == orderCheck.executionTime
	else {
	  throw FuturesOrderCheckError.invalidTarget
	}
	let quote = try FuturesCalculator.closingQuote(
	  position,
	  executionPrice: order.executionPrice,
	  exitFeeRate: TradingRules.Futures.closingFeeRate(for: position.order.instrument),
	  netFunding: state.netFunding,
      quantity: order.quantity
	)
	guard quote.returnedMargin > 0 else { throw StoreError.historyCheckRequired }
	var accounts = current.accounts
	guard let index = accounts.firstIndex(where: { $0.id == position.order.account }) else {
	  throw StoreError.invalidStoredData
	}
	accounts[index].availableBalance = try FuturesDecimal.add(accounts[index].availableBalance, quote.returnedMargin)
	let closed = FuturesClosedPosition(
	  order: order,
	  returnedMargin: quote.returnedMargin,
	  realizedPnL: quote.realizedPnL,
	  settledAt: now
	)
	let entry = FuturesLedgerEntry(
	  id: order.requestID,
	  positionID: position.id,
	  account: position.order.account,
	  occurredAt: order.executedAt,
	  kind: .close,
	  cashDelta: quote.returnedMargin,
	  reservedMarginChange: try FuturesDecimal.subtract(0, FuturesDecimal.subtract(quote.returnedMargin, quote.realizedPnL)),
	  feePaid: 0
	)
	// 포지션 종료 시점까지 반영해 함께 저장할 검증 상태다.
	var historyCheckStates = current.historyCheckStates
	guard let stateIndex = historyCheckStates.firstIndex(where: { $0.positionID == position.id }) else {
	  throw StoreError.invalidStoredData
	}
	historyCheckStates[stateIndex].verifiedThrough = try FuturesHistoryCheckState.milliseconds(order.executedAt)
    // 부분 종료는 검증된 체결 시각부터 줄어든 수량으로 다시 검증한다.
    let isPartial = (order.quantity ?? position.quantity) < position.quantity
    // 저장할 잔여 포지션과 기존 전체 종료 기록이다.
    var positions = current.positions
    if isPartial {
      guard let index = positions.firstIndex(where: { $0.id == position.id }) else { throw StoreError.invalidStoredData }
      positions[index] = try FuturesCalculator.reduce(position, closing: closed)
      historyCheckStates[stateIndex].lastVerifiedMark = nil
    } else if order.executedAt > position.lastExecutionAt {
      historyCheckStates[stateIndex].lastVerifiedMark = order.executionPrice
    }
	return try commit(
	  accounts,
	  previous: current,
      positions: positions,
	  ledger: current.ledger + [entry],
	  historyCheckStates: historyCheckStates,
	  closedPositions: isPartial ? current.closedPositions : current.closedPositions + [closed]
	)
  }

  // 가격 이력을 검증하고 검증 시점·청산 결과를 함께 저장한다.
  func checkHistoryAndSettle(
	positionID: UUID,
	expectedRevision: UInt64,
	batch: FuturesReplayBatch,
	settledAt: Date,
	// 최초 청산 분의 초봉·체결 자료가 있을 때 같은 저장 작업으로 확정한다.
	detailBatch: FuturesReplayBatch? = nil
  ) throws -> FuturesReplayResult {
	Self.lock.lock()
	defer { Self.lock.unlock() }
	let current = try fetchSnapshot()
	guard current.revision == expectedRevision else { throw StoreError.revisionConflict }
	guard let position = current.positions.first(where: { $0.id == positionID }),
	  let index = current.historyCheckStates.firstIndex(where: { $0.positionID == positionID })
	else {
	  throw StoreError.invalidStoredData
	}
	guard current.isActive(position) else { throw StoreError.positionClosed }
	let result = try FuturesReplayCalculator.replay(
	  batch,
	  position: position,
	  state: current.historyCheckStates[index],
	  settledAt: settledAt,
	  detailBatch: detailBatch
	)
	// 미완성 분의 안전 판정은 세션 준비 상태에만 사용하고 장기 재개 체크포인트로 저장하지 않는다.
	let persist = !batch.detailed || result.state.verifiedThrough % 60_000 == 0 || result.state.liquidation != nil
	if persist, result.state != current.historyCheckStates[index] {
	  // 이번 이력 검증 결과로 갱신해 저장할 포지션별 상태다.
	  var historyCheckStates = current.historyCheckStates
	  historyCheckStates[index] = result.state
	  // v1 청산은 예약 증거금만 소진한다. 광고로 늘어난 가용 잔액을 다시 차감하지 않는다.
	  try commit(current.accounts, previous: current, historyCheckStates: historyCheckStates)
	}
	return result
  }

  // 청산을 증명하는 현재가만 정산한다. 안전한 tick으로 과거 검증 경계를 건너뛰지 않는다.
  func liquidateObservedQuote(
	_ quote: FuturesMarkQuote,
	settledAt: Date
  ) throws -> [FuturesPosition] {
	Self.lock.lock()
	defer { Self.lock.unlock() }
	let timestamp = try FuturesHistoryCheckState.milliseconds(settledAt)
	guard TradingRules.Futures.allowsObservedLiquidation(for: quote.instrument),
	  quote.timestamp > 0, quote.timestamp <= timestamp,
	  quote.timestamp >= timestamp - TradingRules.Futures.HistoryCheck.quoteMaximumAgeMilliseconds,
	  !quote.price.isNaN, quote.price > 0
	else {
	  throw FuturesOrderCheckError.staleQuote
	}
	let current = try fetchSnapshot()
	var states = current.historyCheckStates
	var liquidated: [FuturesPosition] = []
	for position in current.positions where position.order.instrument == quote.instrument && current.isActive(position)
	{
	  guard let index = states.firstIndex(where: { $0.positionID == position.id }) else {
		throw StoreError.invalidStoredData
	  }
	  guard quote.timestamp >= states[index].verifiedThrough,
		quote.timestamp > (try FuturesHistoryCheckState.milliseconds(position.lastExecutionAt)),
		try FuturesCalculator.evaluate(position, markPrice: quote.price).shouldLiquidate
	  else { continue }
	  states[index].liquidation = FuturesLiquidationRecord(
		intervalStart: states[index].verifiedThrough,
		intervalEndExclusive: quote.timestamp + 1,
		observedLiquidationPrice: quote.price,
		settledAt: settledAt,
		observedAt: quote.timestamp
	  )
	  liquidated.append(position)
	}
	if !liquidated.isEmpty {
	  try commit(current.accounts, previous: current, historyCheckStates: states)
	}
	return liquidated
  }

  func applyAdvertisementReward(_ claim: AdRewardClaim) throws {
	Self.lock.lock()
	defer { Self.lock.unlock() }
	try claim.validate()
	guard TradingRules.Futures.canCreateAccount(claim.account) else {
	  throw AdRewardError.invalidClaim
	}
	let current = try fetchSnapshot()
	if let existing = current.rewardClaims.first(where: { $0.id == claim.id }) {
	  guard existing == claim else { throw AdRewardError.conflictingClaim }
	  return
	}
	var accounts = current.accounts
	// 화면 방문 전에 획득한 보상도 계좌 생성과 지급 기록을 함께 저장해 재처리한다.
	if !accounts.contains(where: { $0.id == claim.account }) {
	  accounts.append(FuturesCashAccount(id: claim.account, availableBalance: Decimal(TradingRules.Funding.unfundedAccountBalance)))
	}
	guard let index = accounts.firstIndex(where: { $0.id == claim.account }) else {
	  throw StoreError.invalidStoredData
	}
	var balance = accounts[index].availableBalance
	var amount = claim.amount
	var result = Decimal()
	guard NSDecimalAdd(&result, &balance, &amount, .plain) == .noError else { throw StoreError.invalidStoredData }
	accounts[index].availableBalance = result
	try commit(accounts, previous: current, rewardClaims: current.rewardClaims + [claim])
  }

  // 저장 파일에서 선물 계좌 상태를 읽고 형식과 데이터 정합성을 검증한다.
  private func fetchSnapshot() throws -> FuturesAccountSnapshot {
	let data: Data
	do {
	  data = try Data(contentsOf: fileURL)
	} catch let error as CocoaError where error.code == .fileReadNoSuchFile {
	  return .empty
	}
	let snapshot: FuturesAccountSnapshot
	do {
	  snapshot = try JSONDecoder().decode(FuturesAccountSnapshot.self, from: data)
	} catch {
	  throw StoreError.invalidStoredData
	}
	try validate(snapshot)
	return snapshot
  }

  @discardableResult
  private func commit(
	_ accounts: [FuturesCashAccount],
	previous: FuturesAccountSnapshot,
	rewardClaims: [AdRewardClaim]? = nil,
	positions: [FuturesPosition]? = nil,
	ledger: [FuturesLedgerEntry]? = nil,
	historyCheckStates: [FuturesHistoryCheckState]? = nil,
	closedPositions: [FuturesClosedPosition]? = nil
  ) throws -> FuturesAccountSnapshot {
	guard previous.revision < UInt64.max else { throw StoreError.revisionOverflow }
	let next = FuturesAccountSnapshot(
	  revision: previous.revision + 1,
	  accounts: accounts,
	  rewardClaims: rewardClaims ?? previous.rewardClaims,
	  positions: positions ?? previous.positions,
	  ledger: ledger ?? previous.ledger,
	  historyCheckStates: historyCheckStates ?? previous.historyCheckStates,
	  closedPositions: closedPositions ?? previous.closedPositions
	)
	try validate(next)
	let data = try JSONEncoder().encode(next)
	var directory = fileURL.deletingLastPathComponent()
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	var values = URLResourceValues()
	values.isExcludedFromBackup = true
	try directory.setResourceValues(values)
	try writeSnapshot(data, fileURL)
	return next
  }

  private func validate(_ snapshot: FuturesAccountSnapshot) throws {
	guard [1, 2, 3, 4, 5, 6].contains(snapshot.schemaVersion) else { throw StoreError.unsupportedSchema }
	guard Set(snapshot.positions.map(\.id)).count == snapshot.positions.count,
	  Set(snapshot.ledger.map(\.id)).count == snapshot.ledger.count,
	  snapshot.ledger.count == snapshot.positions.flatMap(\.executions).count + snapshot.positions.flatMap({ $0.partialClosings ?? [] }).count + snapshot.closedPositions.count
	else { throw StoreError.invalidStoredData }
	guard Set(snapshot.historyCheckStates.map(\.positionID)) == Set(snapshot.positions.map(\.id)),
	  snapshot.historyCheckStates.count == snapshot.positions.count
	else { throw StoreError.invalidStoredData }
	guard Set(snapshot.closedPositions.map { $0.order.positionID }).count == snapshot.closedPositions.count,
	  Set(snapshot.positions.flatMap(\.executions).map(\.requestID)).count
		== snapshot.positions.flatMap(\.executions).count
	else {
	  throw StoreError.invalidStoredData
	}
	var instruments = Set<TradingInstrumentID>()
	var expectedLedger: [FuturesLedgerEntry] = []
	for position in snapshot.positions {
	  guard let state = snapshot.historyCheckStates.first(where: { $0.positionID == position.id }) else {
		throw StoreError.invalidStoredData
	  }
	  try FuturesReplayCalculator.validate(state, position: position)
	  guard snapshot.accounts.contains(where: { $0.id == position.order.account }),
		(!snapshot.isActive(position) || instruments.insert(position.order.instrument).inserted),
		state.verifiedThrough >= (try FuturesHistoryCheckState.milliseconds(position.lastExecutionAt))
	  else {
		throw StoreError.invalidStoredData
	  }
	  for order in position.executions {
		let fill = try FuturesCalculator.openingLedgerEntry(for: FuturesCalculator.storedFill(order))
		expectedLedger.append(
		  FuturesLedgerEntry(
			id: fill.id,
			positionID: position.id,
			account: fill.account,
			occurredAt: fill.occurredAt,
			kind: .open,
			cashDelta: fill.cashDelta,
			reservedMarginChange: fill.reservedMarginChange,
			feePaid: fill.feePaid
		  )
		)
	  }
      for closed in position.partialClosings ?? [] {
        guard closed.order.executedAt <= position.lastExecutionAt else { throw StoreError.invalidStoredData }
        expectedLedger.append(
          FuturesLedgerEntry(
            id: closed.order.requestID,
            positionID: position.id,
            account: position.order.account,
            occurredAt: closed.order.executedAt,
            kind: .close,
            cashDelta: closed.returnedMargin,
            reservedMarginChange: try FuturesDecimal.subtract(0, FuturesDecimal.subtract(closed.returnedMargin, closed.realizedPnL)),
            feePaid: 0
          )
        )
      }
	  if let closed = snapshot.closedPositions.first(where: { $0.order.positionID == position.id }) {
		let time = try FuturesHistoryCheckState.milliseconds(closed.order.executedAt)
		guard state.liquidation == nil, try FuturesHistoryCheckState.milliseconds(closed.settledAt) >= time,
		  time >= (try FuturesHistoryCheckState.milliseconds(position.lastExecutionAt)),
		  state.verifiedThrough >= time
		else { throw StoreError.invalidStoredData }
        guard closed.order.quantity == nil || closed.order.quantity == position.quantity,
          closed.order.expectedQuantity == nil || closed.order.expectedQuantity == position.quantity
        else { throw StoreError.invalidStoredData }
		let quote = try FuturesCalculator.closingQuote(
		  position,
		  executionPrice: closed.order.executionPrice,
		  exitFeeRate: TradingRules.Futures.closingFeeRate(for: position.order.instrument),
		  netFunding: state.netFunding
		)
		guard quote.returnedMargin > 0, quote.returnedMargin == closed.returnedMargin,
		  quote.realizedPnL == closed.realizedPnL
		else { throw StoreError.invalidStoredData }
		expectedLedger.append(
		  FuturesLedgerEntry(
			id: closed.order.requestID,
			positionID: position.id,
			account: position.order.account,
			occurredAt: closed.order.executedAt,
			kind: .close,
			cashDelta: closed.returnedMargin,
			reservedMarginChange: try FuturesDecimal.subtract(0, position.margin),
			feePaid: 0
		  )
		)
	  }
	}
	guard expectedLedger.count == snapshot.ledger.count,
	  expectedLedger.allSatisfy({ expected in snapshot.ledger.first(where: { $0.id == expected.id }) == expected })
	else {
	  throw StoreError.invalidStoredData
	}
	try AdRewardClaim.validateCollection(snapshot.rewardClaims)
	guard
	  snapshot.rewardClaims.allSatisfy({ claim in
		claim.account.product == .perpetual && snapshot.accounts.contains(where: { $0.id == claim.account })
	  })
	else { throw StoreError.invalidStoredData }
	guard Set(snapshot.accounts.map(\.id)).count == snapshot.accounts.count,
	  snapshot.accounts.allSatisfy({
		TradingRules.Futures.canRestoreAccount($0.id)
		  && !$0.availableBalance.isNaN && $0.availableBalance >= 0
	  })
	else { throw StoreError.invalidStoredData }
  }
}
