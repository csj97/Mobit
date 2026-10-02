import XCTest
import UIKit
import ReactorKit
import RxSwift
@testable import Mobit

final class FuturesAccountReactorTests: XCTestCase {
  private let account = TradingAccountID(exchange: .upbit, product: .perpetual, currency: .krw)

  private func reactor() -> FuturesAccountReactor {
    let reactor = FuturesAccountReactor(account: account)
    reactor.isStubEnabled = true
    return reactor
  }

  @MainActor
  func testLeverageSliderPercentagesFineAdjustmentAndLock() throws {
    let control = FuturesLeverageControl()
    let slider = try XCTUnwrap(control.subviews.compactMap { $0 as? UISlider }.first)
    var changes = 0
    control.addAction(UIAction { _ in changes += 1 }, for: .valueChanged)
    for maximum in [20.0, 50.0, 100.0] {
      control.maximumValue = maximum
      for percent in [0, 20, 40, 60, 80, 100] {
        slider.value = Float(percent) / 100
        slider.sendActions(for: .valueChanged)
        XCTAssertEqual(control.value, max(1, maximum * Double(percent) / 100))
      }
    }
    control.value = 40
    let beforeProgrammaticUpdate = changes
    control.value = 50
    XCTAssertEqual(changes, beforeProgrammaticUpdate)
    slider.value = 0.514
    slider.sendActions(for: .valueChanged)
    XCTAssertEqual(control.value, 51)
    let beforeSameStep = changes
    slider.value = 0.511
    slider.sendActions(for: .valueChanged)
    XCTAssertEqual(changes, beforeSameStep)
    control.accessibilityIncrement()
    XCTAssertEqual(control.value, 52)
    control.accessibilityDecrement()
    XCTAssertEqual(control.value, 51)
    control.isEnabled = false
    XCTAssertFalse(slider.isEnabled)
    slider.value = 1
    slider.sendActions(for: .valueChanged)
    control.accessibilityIncrement()
    XCTAssertEqual(control.value, 51)
    control.maximumValue = 20
    XCTAssertEqual(control.value, 20)
  }

	func testDisplayRetainsLastQuoteWhileStrictValuationRejectsStalePrice() throws {
	  let reactor = reactor()
	  let position = try FuturesCalculator.open(domesticFuturesOrder())
	  let snapshot = FuturesAccountSnapshot(
		revision: 0,
		accounts: [.init(id: account, availableBalance: 900_000)],
		positions: [position],
		reconciliations: [try .initial(for: position)]
	  )
	  let now = Date()
	  let timestamp = try FuturesReconciliationState.milliseconds(now) - 60_000
	  let quote = FuturesMarkQuote(instrument: position.order.instrument, price: 110_000_000, timestamp: timestamp)
	  var state = reactor.reduce(state: reactor.initialState, mutation: .snapshot(snapshot, [:]))
	  XCTAssertEqual(state.quotes[position.order.instrument]?.price, try position.averageEntryPrice)
	  state = reactor.reduce(state: state, mutation: .snapshot(snapshot, [quote.instrument: quote]))
	  state = reactor.reduce(state: state, mutation: .snapshot(snapshot, [:]))
	  state = reactor.reduce(state: state, mutation: .loadFailed)
	  reactor.stub.state.value = state
	  XCTAssertFalse(reactor.canSubmit)
	  XCTAssertEqual(state.quotes[quote.instrument], quote)
	  XCTAssertEqual(try FuturesText.valuation(position, quotes: state.quotes, now: now)?.displayedEquity, 200_000)
	  XCTAssertThrowsError(try snapshot.valuation(for: account, quotes: state.quotes, now: now))
	  XCTAssertEqual(
		try snapshot.valuation(for: account, quotes: state.quotes, now: now, allowStaleQuotes: true).totalEquity,
		1_100_000
	  )
	  var verification = try FuturesReconciliationState.initial(for: position)
	  verification.verifiedThrough = timestamp
	  verification.lastVerifiedMark = quote.price
	  let restoredSnapshot = FuturesAccountSnapshot(
		revision: 0,
		accounts: snapshot.accounts,
		positions: [position],
		reconciliations: [verification]
	  )
	  let restored = reactor.reduce(state: reactor.initialState, mutation: .snapshot(restoredSnapshot, [:]))
	  XCTAssertEqual(restored.quotes[quote.instrument], quote)
	  let replacement = FuturesMarkQuote(instrument: quote.instrument, price: 120_000_000, timestamp: timestamp + 1)
	  state = reactor.reduce(state: state, mutation: .snapshot(snapshot, [quote.instrument: replacement]))
	  XCTAssertEqual(try FuturesText.valuation(position, quotes: state.quotes, now: now)?.displayedEquity, 300_000)
	  let empty = FuturesAccountSnapshot(revision: 1, accounts: [.init(id: account, availableBalance: 1_000_000)])
	  state = reactor.reduce(state: state, mutation: .snapshot(empty, [:]))
	  XCTAssertTrue(state.quotes.isEmpty)
	}

	func testBackgroundVerificationIsSilentAndDoesNotHideLastValuation() throws {
	  let reactor = reactor()
	  let position = try FuturesCalculator.open(domesticFuturesOrder())
	  let snapshot = FuturesAccountSnapshot(
		revision: 1,
		accounts: [.init(id: account, availableBalance: 900_000)],
		positions: [position],
		reconciliations: [try .initial(for: position)]
	  )
	  var state = reactor.reduce(state: reactor.initialState, mutation: .snapshot(snapshot, [:]))
	  for status in [FuturesRefreshStatus.refreshing, .paused, .finished([
		FuturesRefreshResult(positionID: position.id, verifiedThrough: 120_000, liquidated: false, hold: .missingHistory)
	  ])] {
		state = reactor.reduce(state: state, mutation: .status(status))
		reactor.stub.state.value = state
		XCTAssertTrue(FuturesText.status(reactor).isEmpty)
		XCTAssertTrue(reactor.canRequestOrder)
		XCTAssertNotNil(try FuturesText.valuation(position, quotes: state.quotes))
	  }
	  let description = try FuturesText.position(position, snapshot: snapshot, quotes: state.quotes)
	  XCTAssertFalse(description.contains(FuturesText.text("futures_checkpoint")))
	  state = reactor.reduce(state: state, mutation: .status(.storageFailed))
	  reactor.stub.state.value = state
	  XCTAssertEqual(FuturesText.status(reactor), FuturesText.text("futures_storage_error"))
	  state = reactor.reduce(state: state, mutation: .submitting(true))
	  reactor.stub.state.value = state
	  XCTAssertFalse(reactor.canRequestOrder)
	}

  func testLateSnapshotCannotRestoreOldBalanceOrPosition() {
    let reactor = reactor()
    let latest = FuturesAccountSnapshot(revision: 9, accounts: [.init(id: account, availableBalance: 900)])
    let stale = FuturesAccountSnapshot(revision: 8, accounts: [.init(id: account, availableBalance: 1000)])
    let state = reactor.reduce(state: reactor.initialState, mutation: .snapshot(latest, [:]))
    let reduced = reactor.reduce(state: state, mutation: .snapshot(stale, [:]))
    XCTAssertEqual(reduced.snapshot, latest)
  }

  func testFailedReadPreservesAssetsAndBlocksOrders() {
    let reactor = reactor()
    let snapshot = FuturesAccountSnapshot(revision: 2, accounts: [.init(id: account, availableBalance: 1000)])
    var state = reactor.reduce(state: reactor.initialState, mutation: .snapshot(snapshot, [:]))
    state = reactor.reduce(state: state, mutation: .status(.finished([])))
    reactor.stub.state.value = state
    XCTAssertTrue(reactor.canSubmit)
    state = reactor.reduce(state: state, mutation: .loadFailed)
    reactor.stub.state.value = state
    XCTAssertEqual(reactor.currentState.snapshot, snapshot)
    XCTAssertFalse(reactor.canSubmit)
  }

  func testEveryActivePositionNeedsSuccessfulVerification() throws {
    let reactor = reactor()
    let position = try FuturesCalculator.open(domesticFuturesOrder())
    let snapshot = FuturesAccountSnapshot(revision: 1, accounts: [.init(id: account, availableBalance: 1000)],
      positions: [position], reconciliations: [try .initial(for: position)])
    var state = reactor.reduce(state: reactor.initialState, mutation: .snapshot(snapshot, [:]))
    for status in [FuturesRefreshStatus.refreshing, .paused, .storageFailed, .finished([]),
      .finished([.init(positionID: position.id, verifiedThrough: 120_000, liquidated: false, hold: .missingHistory)])] {
      state = reactor.reduce(state: state, mutation: .status(status))
      reactor.stub.state.value = state
      XCTAssertFalse(reactor.canSubmit)
    }
    state = reactor.reduce(state: state, mutation: .status(.finished([
      .init(positionID: position.id, verifiedThrough: 120_000, liquidated: false, hold: nil)])))
    reactor.stub.state.value = state
    XCTAssertTrue(reactor.canSubmit)
    state = reactor.reduce(state: state, mutation: .submitting(true))
    reactor.stub.state.value = state
    XCTAssertFalse(reactor.canSubmit)
  }

  @MainActor
  func testAutomaticRefreshKeepsVerifiedOrdersAvailableButPauseAndHoldsBlockThem() throws {
    func flushDisplay() {
      let rendered = expectation(description: "Order state rendered")
      DispatchQueue.main.async { rendered.fulfill() }
      wait(for: [rendered], timeout: 3)
    }
    let reactor = reactor()
    let position = try FuturesCalculator.open(domesticFuturesOrder())
    let snapshot = FuturesAccountSnapshot(revision: 1, accounts: [.init(id: account, availableBalance: 1000)],
      positions: [position], reconciliations: [try .initial(for: position)])
    var state = reactor.reduce(state: reactor.initialState, mutation: .snapshot(snapshot, [:]))
    let verified = FuturesRefreshResult(positionID: position.id, verifiedThrough: 120_000, liquidated: false, hold: nil)
    state = reactor.reduce(state: state, mutation: .status(.finished([verified])))
    state = reactor.reduce(state: state, mutation: .status(.refreshing))
    reactor.stub.state.value = state
    flushDisplay()
    XCTAssertTrue(reactor.canSubmit)
    XCTAssertTrue(FuturesText.status(reactor).isEmpty)
    let controller = FuturesOrderViewController(reactor: reactor, instrument: position.order.instrument)
    controller.loadViewIfNeeded()
    flushDisplay()
    let buttons = descendants(controller.view).compactMap { $0 as? UIButton }
    let submit = try XCTUnwrap(buttons.first { $0.accessibilityIdentifier == "futuresSubmit" })
    let close = try XCTUnwrap(buttons.first { $0.accessibilityIdentifier == "futuresClose" })
    XCTAssertTrue(submit.isEnabled)
    XCTAssertTrue(close.isEnabled)
    XCTAssertEqual(submit.configuration?.title, FuturesText.text("futures_enter_long"))
    XCTAssertEqual(close.configuration?.title, FuturesText.text("futures_close"))
    state = reactor.reduce(state: state, mutation: .submitting(true))
    reactor.stub.state.value = state
    flushDisplay()
    XCTAssertFalse(submit.isEnabled)
    XCTAssertFalse(close.isEnabled)
    state = reactor.reduce(state: state, mutation: .submitting(false))
    state = reactor.reduce(state: state, mutation: .status(.paused))
    state = reactor.reduce(state: state, mutation: .status(.refreshing))
    reactor.stub.state.value = state
    flushDisplay()
    XCTAssertFalse(reactor.canSubmit)
    XCTAssertTrue(reactor.canRequestOrder)
    XCTAssertTrue(FuturesText.status(reactor).isEmpty)
    XCTAssertTrue(submit.isEnabled)
    XCTAssertTrue(close.isEnabled)
    state = reactor.reduce(state: state, mutation: .status(.finished([
      .init(positionID: position.id, verifiedThrough: 120_000, liquidated: false, hold: .missingHistory)])))
    state = reactor.reduce(state: state, mutation: .status(.refreshing))
    reactor.stub.state.value = state
    flushDisplay()
    XCTAssertFalse(reactor.canSubmit)
    XCTAssertTrue(reactor.canRequestOrder)
    XCTAssertTrue(FuturesText.status(reactor).isEmpty)
    XCTAssertTrue(submit.isEnabled)
    XCTAssertTrue(close.isEnabled)
  }

  func testPositionsAreScopedToSelectedAccountAndExcludeLiquidatedPosition() throws {
    let reactor = reactor()
    let first = try FuturesCalculator.open(domesticFuturesOrder())
    let other = try FuturesCalculator.open(domesticFuturesOrder(exchange: .bithumb))
    var closed = try FuturesReconciliationState.initial(for: first)
    closed.liquidation = .init(intervalStart: 60_000, intervalEndExclusive: 120_000, witnessMarkPrice: 1, settledAt: Date())
    let snapshot = FuturesAccountSnapshot(revision: 3, accounts: [.init(id: account, availableBalance: 1000)],
      positions: [first, other], reconciliations: [closed, try .initial(for: other)])
    reactor.stub.state.value = reactor.reduce(state: reactor.initialState, mutation: .snapshot(snapshot, [:]))
    XCTAssertTrue(reactor.positions.isEmpty)
  }

  func testOrderBlocksOppositeDirectionAndLocksLeverageAndBlocksAfterLiquidation() throws {
    let reactor = reactor()
    let position = try FuturesCalculator.open(domesticFuturesOrder(side: .short, leverage: 50))
    let reconciliation = try FuturesReconciliationState.initial(for: position)
    let snapshot = FuturesAccountSnapshot(revision: 3, accounts: [.init(id: account, availableBalance: 1000)],
      positions: [position], reconciliations: [reconciliation])
    var state = reactor.reduce(state: reactor.initialState, mutation: .snapshot(snapshot, [:]))
    state.status = .finished([.init(positionID: position.id, verifiedThrough: 120_000, liquidated: false, hold: nil)])
    reactor.stub.state.value = state
    let controller = FuturesOrderViewController(reactor: reactor, instrument: position.order.instrument)
    controller.loadViewIfNeeded()
    let controls = descendants(controller.view)
    let direction = try XCTUnwrap(controls.compactMap { $0 as? UISegmentedControl }.first)
    let leverage = try XCTUnwrap(controls.compactMap { $0 as? FuturesLeverageControl }.first)
    let submit = try XCTUnwrap(controls.first { $0.accessibilityIdentifier == "futuresSubmit" } as? UIButton)
    XCTAssertTrue(direction.isEnabled)
    XCTAssertEqual(direction.selectedSegmentIndex, 1)
    XCTAssertFalse(leverage.isEnabled)
    XCTAssertEqual(leverage.value, 50)
    XCTAssertTrue(submit.isEnabled)
    controller.selectTab(0)
    XCTAssertEqual(direction.selectedSegmentIndex, 0)
    XCTAssertFalse(submit.isEnabled)
    controller.selectTab(1)
    XCTAssertTrue(submit.isEnabled)
    var liquidated = reconciliation
    liquidated.liquidation = .init(intervalStart: 60_000, intervalEndExclusive: 120_000, witnessMarkPrice: 200_000_000, settledAt: Date())
    let after = FuturesAccountSnapshot(revision: 4, accounts: snapshot.accounts, positions: [position], reconciliations: [liquidated])
    reactor.stub.state.value = reactor.reduce(state: state, mutation: .snapshot(after, [:]))
    XCTAssertFalse(submit.isEnabled)
  }

  func testNewOrderScreenDoesNotReopenAfterItsFirstPositionIsLiquidated() throws {
    let reactor = reactor()
    let position = try FuturesCalculator.open(domesticFuturesOrder())
    let cash = [FuturesCashAccount(id: account, availableBalance: 1_000_000)]
    var state = reactor.reduce(state: reactor.initialState, mutation: .snapshot(.init(revision: 1, accounts: cash), [:]))
    state.status = .finished([])
    reactor.stub.state.value = state
    let controller = FuturesOrderViewController(reactor: reactor, instrument: position.order.instrument)
    controller.loadViewIfNeeded()
    let submit = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresSubmit" } as? UIButton)
    var verification = try FuturesReconciliationState.initial(for: position)
    let opened = FuturesAccountSnapshot(revision: 2, accounts: cash, positions: [position], reconciliations: [verification])
    state = reactor.reduce(state: state, mutation: .snapshot(opened, [:]))
    reactor.stub.state.value = state
    verification.liquidation = .init(intervalStart: 60_000, intervalEndExclusive: 120_000, witnessMarkPrice: 1, settledAt: Date())
    let liquidated = FuturesAccountSnapshot(revision: 3, accounts: cash, positions: [position], reconciliations: [verification])
    state = reactor.reduce(state: state, mutation: .snapshot(liquidated, [:]))
    reactor.stub.state.value = state
    XCTAssertTrue(reactor.canSubmit)
    XCTAssertFalse(submit.isEnabled)
  }

  func testFuturesOrderReusesOrderBookAndFitsCompactWidth() throws {
    let futures = reactor()
    var state = futures.initialState
    state.snapshot = .init(revision: 1, accounts: [.init(id: account, availableBalance: 1_000_000)])
    state.status = .finished([])
    futures.stub.state.value = state
    let instrument = domesticFuturesOrder().instrument
    let controller = FuturesOrderViewController(reactor: futures, instrument: instrument)
    let trade = TradeReactor(selectCrypto: .init(cryptoName: "Bitcoin", market: "BTC/KRW", tradePrice: 100_000_000),
      cmcInformation: nil, cryptoDetailUseCase: CryptoDetailUseCase(cryptoDetailRepository: CryptoDetailRepository()),
      mainUseCase: MainUseCase(mainRepository: MainRepository()))
    trade.isStubEnabled = true
    let host = UIViewController()
    host.addChild(controller)
    let orderView = TradeOrderView.instanceFromNib(reactor: trade, futuresOrderController: controller) { _ in }
    host.view.addSubview(orderView)
    controller.didMove(toParent: host)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 480))
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    orderView.overrideUserInterfaceStyle = .dark
    orderView.frame = CGRect(x: 0, y: 0, width: 375, height: 480)
    orderView.layoutIfNeeded()
    controller.view.layoutIfNeeded()
    XCTAssertEqual(orderView.segmentedControl.segments, ["futures_long", "futures_short", "futures_history"].map(FuturesText.text))
    XCTAssertTrue(orderView.investLiveView.isHidden)
    XCTAssertNil(orderView.bidView)
    XCTAssertNil(orderView.askView)
    XCTAssertGreaterThan(controller.view.bounds.height, 300)
    XCTAssertGreaterThan(controller.view.bounds.width, 0)
    let submit = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresSubmit" } as? UIButton)
    orderView.segmentedControl.onSegmentChanged?(1)
    XCTAssertTrue(submit.configuration?.title?.contains(FuturesText.text("futures_short")) == true)
    orderView.segmentedControl.onSegmentChanged?(2)
    XCTAssertTrue(descendants(controller.view).compactMap { $0 as? UILabel }.contains { $0.text == FuturesText.text("futures_empty_history") })
    orderView.segmentedControl.onSegmentChanged?(0)
    window.layoutIfNeeded()
    orderView.layoutIfNeeded()
    controller.view.layoutIfNeeded()
    let scroll = try XCTUnwrap(controller.view.subviews.first as? UIScrollView)
    XCTAssertGreaterThan(scroll.bounds.height, 200)
    scroll.layoutIfNeeded()
    let image = UIGraphicsImageRenderer(bounds: orderView.bounds).image { context in orderView.layer.render(in: context.cgContext) }
    let attachment = XCTAttachment(image: image)
    attachment.name = "Futures order compact layout"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func testSavedBalanceIsPublishedBeforeSlowMarketQuote() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalFuturesAccountRepository(fileURL: directory.appendingPathComponent("accounts.json"))
    let order = domesticFuturesOrder()
    try store.ensureAccount(order.account)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let saved = try store.openTestPosition(order, expectedRevision: store.snapshot().revision)
    let provider = PendingFuturesQuoteProvider()
    let service = FuturesReconciliationService(store: { store }, provider: { _ in provider })
    let useCase = FuturesTradingUseCase(store: { store }, reconciliation: service)
    let reactor = FuturesAccountReactor(account: account, useCase: useCase, reconciliation: service, provider: provider)
    let loaded = expectation(description: "Persisted assets appear before price response")
    let subscription = reactor.state.filter { $0.snapshot?.revision == saved.revision }.take(1)
      .subscribe(onNext: { state in
        XCTAssertEqual(state.snapshot, saved)
        XCTAssertEqual(state.quotes[order.instrument]?.price, try? saved.positions.first?.averageEntryPrice)
        loaded.fulfill()
      })
    wait(for: [loaded], timeout: 3)
    subscription.dispose()
    provider.quotes.onError(FuturesMarketDataError.invalidResponse)
    service.suspend()
  }

  func testFloatingSelectionRemainsRoundedAfterInitialLayout() throws {
    let controller = MobitTabBarViewController()
    controller.setViewControllers([UIViewController()])
    controller.view.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
    controller.view.layoutIfNeeded()
    let button = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "selectSpot" })
    XCTAssertGreaterThan(button.bounds.height, 0)
    XCTAssertEqual(button.layer.cornerRadius, button.bounds.height / 2, accuracy: 0.1)
  }

  @MainActor
  func testFuturesMainSummaryAndHoldUseOnlyActiveFuturesPositions() throws {
    let previousExchange = ExchangeSelectionStore.currentExchange
    let previousProduct = ExchangeSelectionStore.currentProduct
    let previousHoldingsData = UserDefaults.standard.object(forKey: UserDataManager.Keys.userCryptoList)
    let previousHoldings = UserDataManager.userCryptoList
    func flushDisplay() {
      let displayed = expectation(description: "Queued diffable snapshot applied")
      DispatchQueue.main.async { displayed.fulfill() }
      wait(for: [displayed], timeout: 2)
    }
    UserDataManager.userCryptoList = []
    flushDisplay()
    defer {
      UserDataManager.userCryptoList = previousHoldings ?? []
      UserDefaults.standard.set(previousHoldingsData, forKey: UserDataManager.Keys.userCryptoList)
      ExchangeSelectionStore.currentExchange = previousExchange
      ExchangeSelectionStore.currentProduct = previousProduct
    }
    ExchangeSelectionStore.currentExchange = .upbit
    ExchangeSelectionStore.currentProduct = .perpetual
    let futures = reactor()
    let position = try FuturesCalculator.open(domesticFuturesOrder(symbol: "KRW-ETH"))
    let other = try FuturesCalculator.open(domesticFuturesOrder(exchange: .bithumb))
    let snapshot = FuturesAccountSnapshot(
      revision: 1,
      accounts: [.init(id: account, availableBalance: 900_000), .init(id: other.order.account, availableBalance: 50_000_000)],
      positions: [position, other],
      reconciliations: [try .initial(for: position), try .initial(for: other)]
    )
    let time = try FuturesReconciliationState.milliseconds(Date())
    let quotes = [position.order.instrument: FuturesMarkQuote(instrument: position.order.instrument, price: 110_000_000, timestamp: time)]
    futures.stub.state.value = futures.reduce(state: futures.initialState, mutation: .snapshot(snapshot, quotes))
    let spotHolding = CryptoTransactionDataModel(
      staticData: .init(exchange: .upbit, marketName: "BTC/KRW", cryptoName: "Bitcoin", holdingQuantity: 5, averageBuyPrice: 1, buyAmount: 5),
      dynamicData: .init(exchange: .upbit, marketName: "BTC/KRW", profitRate: 0, evaluationProfitLoss: 0, evaluationPrice: 500_000_000)
    )
    UserDataManager.userCryptoList = [spotHolding]
    let market = MainReactor(
      mainUseCase: try FuturesMainFixtureUseCase(),
      tickerSocketService: FuturesMainFixtureSocket()
    )
    let controller = MainViewController(reactor: market, futuresReactor: futures)
    controller.selectedTab = .hold
    controller.loadViewIfNeeded()
    market.action.onNext(.loadCryptoList)
    market.action.onNext(.loadUserCryptos)
    let displayed = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        controller.dataSource?.snapshot().itemIdentifiers.map(\.market) == ["ETH/KRW"]
      },
      object: nil
    )
    wait(for: [displayed], timeout: 3)
    let items = try XCTUnwrap(controller.dataSource?.snapshot().itemIdentifiers)
    XCTAssertEqual(items.map(\.market), ["ETH/KRW"])
    XCTAssertEqual(items.first?.evaluationPrice, 200_000)
    XCTAssertEqual(items.first?.evaluationProfitLoss, 100_000)
    XCTAssertEqual(items.first?.profitRate, 100)
    func summary(_ identifier: String) throws -> String {
      let label = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == identifier } as? UILabel)
      return label.attributedText?.string ?? label.text ?? ""
    }
    XCTAssertTrue(try summary("futures.main.margin").contains("100,000"))
    XCTAssertTrue(try summary("futures.main.equity").contains("1,100,000"))
    XCTAssertTrue(try summary("futures.main.pnl").contains("100,000"))
    XCTAssertTrue(try summary("futures.main.roe").contains("100"))
    let stale = [position.order.instrument: FuturesMarkQuote(instrument: position.order.instrument, price: 110_000_000, timestamp: time - 31_000)]
    futures.stub.state.value = futures.reduce(state: futures.currentState, mutation: .snapshot(snapshot, stale))
    XCTAssertEqual(controller.selectedTab, .hold)
    XCTAssertEqual(market.currentState.totalCryptoList.count, 2)
    XCTAssertEqual(futures.currentState.quotes[position.order.instrument]?.timestamp, time)
    futures.stub.state.value = futures.reduce(state: futures.currentState, mutation: .snapshot(snapshot, [:]))
    futures.stub.state.value = futures.reduce(state: futures.currentState, mutation: .status(.refreshing))
    flushDisplay()
    XCTAssertEqual(controller.dataSource?.snapshot().itemIdentifiers.first?.evaluationPrice, 200_000)
    XCTAssertTrue(try summary("futures.main.equity").contains("1,100,000"))
    let cashOnly = FuturesAccountSnapshot(revision: 2, accounts: [.init(id: account, availableBalance: 10_000_000)])
    futures.stub.state.value = futures.reduce(state: futures.currentState, mutation: .snapshot(cashOnly, [:]))
    flushDisplay()
    XCTAssertTrue(controller.tableView.isHidden)
    XCTAssertTrue(try summary("futures.main.equity").contains("10,000,000"))
    XCTAssertTrue(try summary("futures.main.margin").contains("0"))
  }

  @MainActor
  func testFuturesShareIdentifiesExchangeProductAndCurrencyInRenderedCard() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      let position = try FuturesCalculator.open(domesticFuturesOrder(exchange: exchange, side: .short))
      let record = FuturesTransactionRecord(
        eventID: UUID(),
        positionID: position.id,
        kind: .closing,
        instrument: position.order.instrument,
        side: .short,
        leverage: position.order.leverage,
        quantity: position.quantity,
        intervalStart: 120_000,
        intervalEndExclusive: nil,
        recordedAt: Date(timeIntervalSince1970: 300),
        price: 90_000_000,
        realizedPnL: 100_000
      )
      let unit = try FuturesText.shareUnit(record, position: position)
      XCTAssertEqual(unit.exchange, exchange)
      XCTAssertTrue(unit.marketDescription.contains(exchange.rawValue.capitalized))
      XCTAssertTrue(unit.marketDescription.contains(FuturesText.text("futures_product")))
      XCTAssertTrue(unit.marketDescription.contains("KRW"))
      let share = PNLShareView.instanceFromNib(pnlShareUnit: unit) { _ in }
      share.frame = CGRect(x: 0, y: 0, width: 375, height: 812)
      share.layoutIfNeeded()
      XCTAssertEqual(share.marketName.text, unit.marketDescription)
      XCTAssertGreaterThan(share.marketName.bounds.height, 35)
      let image = UIGraphicsImageRenderer(bounds: share.bounds).image { share.layer.render(in: $0.cgContext) }
      let attachment = XCTAttachment(image: image)
      attachment.name = "Futures share \(exchange.rawValue)"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }

  @MainActor
  func testFuturesInvestmentReusesSpotLayoutAndShowsOnlyCurrentAccountAssets() throws {
    func flushDisplay() {
      let rendered = expectation(description: "Investment state rendered")
      DispatchQueue.main.async { rendered.fulfill() }
      wait(for: [rendered], timeout: 3)
    }
    let reactor = reactor()
    let position = try FuturesCalculator.open(domesticFuturesOrder())
    let other = try FuturesCalculator.open(domesticFuturesOrder(exchange: .bithumb))
    let snapshot = FuturesAccountSnapshot(revision: 1, accounts: [.init(id: account, availableBalance: 900_000),
      .init(id: other.order.account, availableBalance: 50_000_000)], positions: [position, other],
      reconciliations: [try .initial(for: position), try .initial(for: other)])
    let timestamp = try FuturesReconciliationState.milliseconds(Date())
    let quotes = [position.order.instrument: FuturesMarkQuote(instrument: position.order.instrument, price: 110_000_000, timestamp: timestamp)]
    reactor.stub.state.value = reactor.reduce(state: reactor.initialState, mutation: .snapshot(snapshot, quotes))
    let market = MainReactor(mainUseCase: MainUseCase(mainRepository: MainRepository()))
    market.isStubEnabled = true
    let controller = FuturesInvestmentViewController(reactor: reactor, marketReactor: market)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    controller.view.layoutIfNeeded()
    XCTAssertEqual(controller.nibName, "InvestmentViewController")
    XCTAssertEqual(controller.totalBuyTitle.text, FuturesText.text("futures_total_margin"))
    flushDisplay()
    XCTAssertEqual(controller.totalUserBalance.text, "1,100,000 KRW")
    XCTAssertEqual(controller.availableUserBalance.text, "900,000 KRW")
    XCTAssertEqual(controller.totalBuyPrice.text, "100,000 KRW")
    XCTAssertEqual(controller.totalEvalProfitLoss.text, "100,000 KRW")
    XCTAssertEqual(controller.totalProfitRate.text, "100 %")
    XCTAssertTrue(controller.noResultView.isHidden)
    XCTAssertEqual(controller.transactionTableview.numberOfRows(inSection: 0), 1)
    let cell = try XCTUnwrap(controller.transactionTableview.dataSource?.tableView(controller.transactionTableview,
      cellForRowAt: IndexPath(row: 0, section: 0)) as? InvestmentTableViewCell)
    XCTAssertTrue(cell.cryptoName.text?.contains(FuturesText.text("futures_long")) == true)
    XCTAssertEqual(cell.cryptoBuyPrice.text, "100,000 KRW")
    XCTAssertEqual(cell.cryptoEvalPrice.text, "200,000 KRW")
    XCTAssertEqual(cell.cryptoProfitRate.text, "100 %")
    XCTAssertEqual(cell.averagePriceTitle.text, FuturesText.text("futures_entry") + " : ")
    for style in [UIUserInterfaceStyle.dark, .light] {
      controller.overrideUserInterfaceStyle = style
      controller.view.layoutIfNeeded()
      let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { controller.view.layer.render(in: $0.cgContext) }
      let attachment = XCTAttachment(image: image)
      attachment.name = "Futures investment \(style == .dark ? "dark" : "light")"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    let stale = [position.order.instrument: FuturesMarkQuote(instrument: position.order.instrument, price: 110_000_000, timestamp: timestamp - 31_000)]
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .snapshot(snapshot, stale))
    flushDisplay()
    XCTAssertEqual(controller.totalUserBalance.text, "1,100,000 KRW")
    XCTAssertEqual(controller.totalProfitRate.text, "100 %")
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .snapshot(snapshot, [:]))
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .status(.refreshing))
    flushDisplay()
    XCTAssertEqual(controller.totalUserBalance.text, "1,100,000 KRW")
    XCTAssertEqual(controller.totalEvalProfitLoss.text, "100,000 KRW")
    XCTAssertEqual(controller.totalBuyPrice.text, "100,000 KRW")
    XCTAssertEqual(controller.availableUserBalance.text, "900,000 KRW")
    let empty = FuturesAccountSnapshot(revision: 2, accounts: [.init(id: account, availableBalance: 1_000_000)])
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .snapshot(empty, [:]))
    flushDisplay()
    XCTAssertEqual(controller.totalUserBalance.text, "1,000,000 KRW")
    XCTAssertEqual(controller.totalBuyPrice.text, "0 KRW")
    XCTAssertEqual(controller.totalProfitRate.text, "0 %")
    XCTAssertFalse(controller.noResultView.isHidden)
    XCTAssertEqual(controller.emptyLabel.text, FuturesText.text("futures_no_position"))
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .loadFailed)
    flushDisplay()
    XCTAssertEqual(controller.emptyLabel.text, FuturesText.text("futures_storage_error"))
  }

  @MainActor
  func testFuturesRealizedHistoryUsesExistingCellsAndSeparatesLiquidationOccurrenceFromSettlement() throws {
    let reactor = reactor()
    let position = try FuturesCalculator.open(domesticFuturesOrder(side: .short))
    var reconciliation = try FuturesReconciliationState.initial(for: position)
    reconciliation.verifiedThrough = 120_000
    reconciliation.lastVerifiedMark = 120_000_000
    reconciliation.liquidation = .init(intervalStart: 60_000, intervalEndExclusive: 120_000,
      witnessMarkPrice: 120_000_000, settledAt: Date(timeIntervalSince1970: 300))
    let snapshot = FuturesAccountSnapshot(revision: 1, accounts: [.init(id: account, availableBalance: 900_000)],
      positions: [position], reconciliations: [reconciliation])
    reactor.stub.state.value = reactor.reduce(state: reactor.initialState, mutation: .snapshot(snapshot, [:]))
    let controller = PNLViewController()
    controller.futuresReactor = reactor
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    controller.overrideUserInterfaceStyle = .dark
    controller.view.layoutIfNeeded()
    XCTAssertEqual(controller.tableView(controller.pnlTableView, numberOfRowsInSection: 0), 1)
    let cell = try XCTUnwrap(controller.tableView(controller.pnlTableView, cellForRowAt: IndexPath(row: 0, section: 0)) as? PNLTableViewCell)
    XCTAssertEqual(cell.pnlLabel.text, "-100,000 KRW")
    XCTAssertTrue(cell.marketNameLabel.text?.contains(FuturesText.text("futures_short")) == true)
    XCTAssertTrue(cell.marketNameLabel.text?.contains(FuturesText.text("futures_liquidation")) == true)
    XCTAssertEqual(cell.exitTitle.text, FuturesText.text("futures_liquidation_price") + " :")
    XCTAssertEqual(cell.dateTitle.text, FuturesText.text("futures_occurrence") + " :")
    XCTAssertTrue(cell.transactionDateLabel.text?.contains(FuturesText.date(Date(timeIntervalSince1970: 300))) == true)
    XCTAssertNotNil(cell.shareCallBack)
    let record = try XCTUnwrap(snapshot.transactionHistory(for: account).last)
    let unit = try FuturesText.shareUnit(record, position: position)
    XCTAssertEqual(unit.roi, -100)
    XCTAssertEqual(unit.product, .perpetual)
    let share = PNLShareView.instanceFromNib(pnlShareUnit: unit) { _ in }
    XCTAssertEqual(share.entryTitle.text, FuturesText.text("futures_entry"))
    let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { controller.view.layer.render(in: $0.cgContext) }
    let attachment = XCTAttachment(image: image)
    attachment.name = "Futures realized liquidation history"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func testShortRealizedShareUsesMarginReturnRatherThanSpotPriceChange() throws {
    let position = try FuturesCalculator.open(domesticFuturesOrder(side: .short, leverage: 10))
    let record = FuturesTransactionRecord(eventID: UUID(), positionID: position.id, kind: .closing,
      instrument: position.order.instrument, side: .short, leverage: 10, quantity: position.quantity,
      intervalStart: 120_000, intervalEndExclusive: nil, recordedAt: Date(timeIntervalSince1970: 300),
      price: 90_000_000, realizedPnL: 100_000)
    let unit = try FuturesText.shareUnit(record, position: position)
    XCTAssertEqual(unit.roi, 100)
    XCTAssertEqual(unit.pnl, 100_000)
    XCTAssertEqual(unit.entryPrice, 100_000_000)
    XCTAssertEqual(unit.exitPrice, 90_000_000)
  }

  @MainActor
  func testSpotInvestmentStillLoadsItsOriginalXIBCaptions() throws {
    let spot = InvestReactor(mainUseCase: MainUseCase(mainRepository: MainRepository()))
    spot.isStubEnabled = true
    let controller = InvestmentViewController(reactor: spot)
    controller.loadViewIfNeeded()
    XCTAssertEqual(controller.totalBuyTitle.text, "총 매수금액")
    XCTAssertEqual(controller.emptyLabel.text, "보유중인 코인이 없습니다.")
    let cell = try XCTUnwrap(UINib(nibName: "InvestmentTableViewCell", bundle: nil).instantiate(withOwner: nil).first as? InvestmentTableViewCell)
    XCTAssertEqual(cell.buyPriceTitle.text, "매수금액 : ")
  }

  private func descendants(_ view: UIView) -> [UIView] {
    view.subviews.flatMap { [$0] + descendants($0) }
  }

  func testFloatingSwitchHidesOnOtherTabsAndDetail() {
    let controller = MobitTabBarViewController()
    controller.setViewControllers([UIViewController(), UIViewController(), UIViewController()])
    controller.setProduct(.perpetual)
    XCTAssertEqual(controller.children.first?.additionalSafeAreaInsets.bottom, 76)
    controller.switchToTab(index: 2)
    XCTAssertEqual(controller.children.first?.additionalSafeAreaInsets.bottom, 0)
    controller.switchToTab(index: 1)
    XCTAssertEqual(controller.children.first?.additionalSafeAreaInsets.bottom, 76)
    controller.setTradingChromeHidden(true)
    XCTAssertEqual(controller.children.first?.additionalSafeAreaInsets.bottom, 0)
    XCTAssertTrue(controller.mobitTabBar.isHidden)
  }
}

private final class PendingFuturesQuoteProvider: FuturesMarketDataProviding {
  let quotes = PublishSubject<FuturesMarkQuote>()
  func markQuote(_ instrument: TradingInstrumentID) -> Single<FuturesMarkQuote> { quotes.take(1).asSingle() }
  func contract(_ instrument: TradingInstrumentID) -> Single<FuturesMarketContract> { .error(FuturesMarketDataError.unsupportedInstrument) }
  func markCandles(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<FuturesHistoryPage<FuturesMarkCandle>> {
    .error(FuturesMarketDataError.unsupportedInstrument)
  }
  func funding(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<FuturesHistoryPage<FuturesFundingEvent>> {
    .error(FuturesMarketDataError.unsupportedInstrument)
  }
}

private final class FuturesMainFixtureUseCase: MainUseCase {
  private let markets: CryptoList
  private let tickers: CryptoTickerList

  init() throws {
    let event = MarketEvent(
      warning: false,
      caution: .init(
        priceFluctuations: false,
        tradingVolumeSoaring: false,
        depositAmountSoaring: false,
        globalPriceDifferences: false,
        concentrationOfSmallAccounts: false
      )
    )
    markets = ["BTC", "ETH"].map {
      Crypto(market: "KRW-" + $0, koreanName: $0, englishName: $0, marketEvent: event)
    }
    let rows = """
    [{"market":"KRW-BTC","change":"EVEN","trade_price":100000000,"timestamp":1},
     {"market":"KRW-ETH","change":"RISE","trade_price":110000000,"timestamp":1}]
    """
    tickers = try JSONDecoder().decode(CryptoTickerListDTO.self, from: Data(rows.utf8)).toDomain()
    super.init(mainRepository: MainRepository())
  }

  override func loadCryptoList() -> Observable<CryptoList> { .just(markets) }
  override func loadCryptoTicker(markets: [String]) -> Observable<CryptoTickerList> { .just(tickers) }
  override func loadFearGreedIndex() -> Observable<FearGreedIndex> { .never() }
}

private final class FuturesMainFixtureSocket: TickerSocketServiceProtocol {
  var isConnected = false
  var stream: Observable<CryptoSocketTicker> { .never() }
  func connect() { isConnected = true }
  func disconnect(userInitiated: Bool) { isConnected = false }
  func reconnectIfNeeded() { connect() }
  func subscribe(markets: [String]) {}
}
