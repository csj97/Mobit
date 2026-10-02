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
    case reconciliationRequired
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
    return try load()
  }

  @discardableResult
  func ensureAccount(_ id: TradingAccountID) throws -> FuturesAccountSnapshot {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    let current = try load()
    if current.accounts.contains(where: { $0.id == id }) { return current }
    guard id.product == .perpetual, id.availability != .unsupported else { throw StoreError.invalidStoredData }
    var accounts = current.accounts
    accounts.append(FuturesCashAccount(id: id, availableBalance: 0))
    return try commit(accounts, previous: current)
  }

  @discardableResult
  func update(
    expectedRevision: UInt64,
    _ mutation: (inout [FuturesCashAccount]) throws -> Void
  ) throws -> FuturesAccountSnapshot {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    let current = try load()
    guard current.revision == expectedRevision else { throw StoreError.revisionConflict }
    var accounts = current.accounts
    try mutation(&accounts)
    return try commit(accounts, previous: current)
  }

  @discardableResult
  func openPosition(_ order: FuturesOpeningOrder, preflight: FuturesOrderPreflight, now: Date = Date()) throws -> FuturesAccountSnapshot {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    let current = try load()
    if let existing = current.positions.flatMap(\.executions).first(where: { $0.requestID == order.requestID }) {
      guard existing == order else { throw StoreError.conflictingOrder }
      return current
    }
    try preflight.validate(snapshot: current, now: now)
    guard order.account == preflight.account, order.instrument == preflight.instrument,
          order.executionPrice == preflight.mark.price,
          (try FuturesReconciliationState.milliseconds(order.executedAt)) == preflight.executionTime else { throw FuturesOrderPreflightError.invalidTarget }
    return try openPosition(order, expectedRevision: preflight.revision, current: current)
  }

  private func openPosition(_ order: FuturesOpeningOrder, expectedRevision: UInt64,
                            current: FuturesAccountSnapshot) throws -> FuturesAccountSnapshot {
    if let existing = current.positions.flatMap(\.executions).first(where: { $0.requestID == order.requestID }) {
      guard existing == order else { throw StoreError.conflictingOrder }
      return current
    }
    guard current.revision == expectedRevision else { throw StoreError.revisionConflict }
    let position = try FuturesCalculator.open(order)
    let activeIndex = current.positions.firstIndex { existing in
      existing.order.account == order.account && existing.order.instrument == order.instrument && current.isActive(existing)
    }
    if let activeIndex {
      let existing = current.positions[activeIndex]
      guard order.instrument.usesDomesticSpotPrice, existing.order.side == order.side, existing.order.leverage == order.leverage else {
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
    var reconciliations = current.reconciliations
    var entry = try FuturesCalculator.openingLedgerEntry(for: position)
    if let activeIndex {
      positions[activeIndex] = try FuturesCalculator.adding(order, to: positions[activeIndex])
      guard let stateIndex = reconciliations.firstIndex(where: { $0.positionID == positions[activeIndex].id }) else {
        throw StoreError.invalidStoredData
      }
      reconciliations[stateIndex].verifiedThrough = try FuturesReconciliationState.milliseconds(order.executedAt)
      reconciliations[stateIndex].lastVerifiedMark = nil
      entry = FuturesLedgerEntry(id: entry.id, positionID: positions[activeIndex].id, account: entry.account,
        occurredAt: entry.occurredAt, kind: entry.kind, cashDelta: entry.cashDelta,
        collateralDelta: entry.collateralDelta, feePaid: entry.feePaid)
    } else {
      positions.append(position)
      reconciliations.append(try FuturesReconciliationState.initial(for: position))
    }
    return try commit(accounts, previous: current, positions: positions,
      ledger: current.ledger + [entry], reconciliations: reconciliations)
  }

  @discardableResult
  func closePosition(_ order: FuturesClosingOrder, preflight: FuturesOrderPreflight,
                     now: Date = Date()) throws -> FuturesAccountSnapshot {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    let current = try load()
    if let existing = current.closedPositions.first(where: { $0.order.requestID == order.requestID }) {
      guard existing.order == order else { throw StoreError.conflictingOrder }
      return current
    }
    guard !current.ledger.contains(where: { $0.id == order.requestID }),
          let position = current.positions.first(where: { $0.id == order.positionID }),
          current.isActive(position),
          let state = current.reconciliations.first(where: { $0.positionID == position.id }) else { throw StoreError.positionClosed }
    try preflight.validate(snapshot: current, now: now)
    guard position.order.account == preflight.account, position.order.instrument == preflight.instrument,
          order.executionPrice == preflight.mark.price,
          try FuturesReconciliationState.milliseconds(order.executedAt) == preflight.executionTime else {
      throw FuturesOrderPreflightError.invalidTarget
    }
    let quote = try FuturesCalculator.closingQuote(position, executionPrice: order.executionPrice,
      exitFeeRate: 0, netFunding: state.netFunding)
    guard quote.returnedMargin > 0 else { throw StoreError.reconciliationRequired }
    var accounts = current.accounts
    guard let index = accounts.firstIndex(where: { $0.id == position.order.account }) else { throw StoreError.invalidStoredData }
    accounts[index].availableBalance = try FuturesDecimal.add(accounts[index].availableBalance, quote.returnedMargin)
    let closed = FuturesClosedPosition(order: order, returnedMargin: quote.returnedMargin, realizedPnL: quote.realizedPnL, settledAt: now)
    let entry = FuturesLedgerEntry(id: order.requestID, positionID: position.id, account: position.order.account,
      occurredAt: order.executedAt, kind: .close, cashDelta: quote.returnedMargin,
      collateralDelta: try FuturesDecimal.subtract(0, position.margin), feePaid: 0)
    var reconciliations = current.reconciliations
    guard let stateIndex = reconciliations.firstIndex(where: { $0.positionID == position.id }) else { throw StoreError.invalidStoredData }
    reconciliations[stateIndex].verifiedThrough = try FuturesReconciliationState.milliseconds(order.executedAt)
    if order.executedAt > position.lastExecutionAt { reconciliations[stateIndex].lastVerifiedMark = order.executionPrice }
    return try commit(accounts, previous: current, ledger: current.ledger + [entry], reconciliations: reconciliations,
      closedPositions: current.closedPositions + [closed])
  }

  func reconcile(positionID: UUID, expectedRevision: UInt64, batch: FuturesReplayBatch,
                 settledAt: Date) throws -> FuturesReplayResult {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    let current = try load()
    guard current.revision == expectedRevision else { throw StoreError.revisionConflict }
    guard let position = current.positions.first(where: { $0.id == positionID }),
          let index = current.reconciliations.firstIndex(where: { $0.positionID == positionID }) else {
      throw StoreError.invalidStoredData
    }
    guard current.isActive(position) else { throw StoreError.positionClosed }
    let result = try FuturesReplayCalculator.replay(batch, position: position,
                                                  state: current.reconciliations[index], settledAt: settledAt)
    // 완료되지 않은 분의 안전 판정은 주문 준비에서만 사용하고 장기 재개 체크포인트로 저장하지 않는다.
    let persist = !batch.detailed || result.state.verifiedThrough % 60_000 == 0 || result.state.liquidation != nil
    if persist, result.state != current.reconciliations[index] {
      var reconciliations = current.reconciliations
      reconciliations[index] = result.state
      // v1 청산은 예약 증거금만 소진한다. 광고로 늘어난 가용 잔액을 다시 차감하지 않는다.
      try commit(current.accounts, previous: current, reconciliations: reconciliations)
    }
    return result
  }

  func applyAdvertisementReward(_ claim: AdRewardClaim) throws {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    try claim.validate()
    guard claim.account.product == .perpetual, claim.account.availability != .unsupported else {
      throw AdRewardError.invalidClaim
    }
    let current = try load()
    if let existing = current.rewardClaims.first(where: { $0.id == claim.id }) {
      guard existing == claim else { throw AdRewardError.conflictingClaim }
      return
    }
    var accounts = current.accounts
    // 화면 방문 전에 획득한 보상도 계좌 생성과 지급 기록을 함께 저장해 재처리한다.
    if !accounts.contains(where: { $0.id == claim.account }) {
      accounts.append(FuturesCashAccount(id: claim.account, availableBalance: 0))
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

  private func load() throws -> FuturesAccountSnapshot {
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
    reconciliations: [FuturesReconciliationState]? = nil,
    closedPositions: [FuturesClosedPosition]? = nil
  ) throws -> FuturesAccountSnapshot {
    guard previous.revision < UInt64.max else { throw StoreError.revisionOverflow }
    let next = FuturesAccountSnapshot(revision: previous.revision + 1, accounts: accounts,
                                      rewardClaims: rewardClaims ?? previous.rewardClaims,
                                      positions: positions ?? previous.positions, ledger: ledger ?? previous.ledger,
                                      reconciliations: reconciliations ?? previous.reconciliations,
                                      closedPositions: closedPositions ?? previous.closedPositions)
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
    guard [1, 2, 3, 4, 5].contains(snapshot.schemaVersion) else { throw StoreError.unsupportedSchema }
    guard Set(snapshot.positions.map(\.id)).count == snapshot.positions.count,
          Set(snapshot.ledger.map(\.id)).count == snapshot.ledger.count,
          snapshot.ledger.count == snapshot.positions.flatMap(\.executions).count + snapshot.closedPositions.count else { throw StoreError.invalidStoredData }
    guard Set(snapshot.reconciliations.map(\.positionID)) == Set(snapshot.positions.map(\.id)),
          snapshot.reconciliations.count == snapshot.positions.count else { throw StoreError.invalidStoredData }
    guard Set(snapshot.closedPositions.map { $0.order.positionID }).count == snapshot.closedPositions.count,
          Set(snapshot.positions.flatMap(\.executions).map(\.requestID)).count == snapshot.positions.flatMap(\.executions).count else {
      throw StoreError.invalidStoredData
    }
    var instruments = Set<TradingInstrumentID>()
    var expectedLedger: [FuturesLedgerEntry] = []
    for position in snapshot.positions {
      guard let state = snapshot.reconciliations.first(where: { $0.positionID == position.id }) else { throw StoreError.invalidStoredData }
      try FuturesReplayCalculator.validate(state, position: position)
      guard snapshot.accounts.contains(where: { $0.id == position.order.account }),
            (!snapshot.isActive(position) || instruments.insert(position.order.instrument).inserted),
            state.verifiedThrough >= (try FuturesReconciliationState.milliseconds(position.lastExecutionAt)) else {
        throw StoreError.invalidStoredData
      }
      for order in position.executions {
        let fill = try FuturesCalculator.openingLedgerEntry(for: FuturesCalculator.storedFill(order))
        expectedLedger.append(FuturesLedgerEntry(id: fill.id, positionID: position.id, account: fill.account,
          occurredAt: fill.occurredAt, kind: .open, cashDelta: fill.cashDelta,
          collateralDelta: fill.collateralDelta, feePaid: fill.feePaid))
      }
      if let closed = snapshot.closedPositions.first(where: { $0.order.positionID == position.id }) {
        let time = try FuturesReconciliationState.milliseconds(closed.order.executedAt)
        guard state.liquidation == nil, try FuturesReconciliationState.milliseconds(closed.settledAt) >= time, time >= (try FuturesReconciliationState.milliseconds(position.lastExecutionAt)),
              state.verifiedThrough >= time else { throw StoreError.invalidStoredData }
        let quote = try FuturesCalculator.closingQuote(position, executionPrice: closed.order.executionPrice,
          exitFeeRate: 0, netFunding: state.netFunding)
        guard quote.returnedMargin > 0, quote.returnedMargin == closed.returnedMargin,
              quote.realizedPnL == closed.realizedPnL else { throw StoreError.invalidStoredData }
        expectedLedger.append(FuturesLedgerEntry(id: closed.order.requestID, positionID: position.id,
          account: position.order.account, occurredAt: closed.order.executedAt, kind: .close,
          cashDelta: closed.returnedMargin, collateralDelta: try FuturesDecimal.subtract(0, position.margin), feePaid: 0))
      }
    }
    guard expectedLedger.count == snapshot.ledger.count,
          expectedLedger.allSatisfy({ expected in snapshot.ledger.first(where: { $0.id == expected.id }) == expected }) else {
      throw StoreError.invalidStoredData
    }
    try AdRewardClaim.validateCollection(snapshot.rewardClaims)
    guard snapshot.rewardClaims.allSatisfy({ claim in
      claim.account.product == .perpetual && snapshot.accounts.contains(where: { $0.id == claim.account })
    }) else { throw StoreError.invalidStoredData }
    guard Set(snapshot.accounts.map(\.id)).count == snapshot.accounts.count,
          snapshot.accounts.allSatisfy({
            $0.id.product == .perpetual && ($0.id.currency == .usdt || $0.id.availability != .unsupported ||
              (($0.id.exchange == .upbit || $0.id.exchange == .bithumb) && $0.id.currency == .btc)) &&
            !$0.availableBalance.isNaN && $0.availableBalance >= 0
          }) else { throw StoreError.invalidStoredData }
  }
}
