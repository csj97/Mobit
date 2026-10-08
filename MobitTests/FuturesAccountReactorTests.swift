import XCTest
import UIKit
import ReactorKit
import RxSwift
import SnapKit
import GoogleMobileAds
@testable import Mobit

final class FuturesAccountReactorTests: XCTestCase {
  @MainActor
  func testLiquidationNoticeWaitsForMainAppearanceAndStartsThreeSecondsOnDisplay() throws {
    // 메인 화면이 보이기 전에는 청산 안내의 타이머도 시작하지 않는다.
    var ready = false
    // 실제 창에서 인트로와 메인 화면 전환을 재현한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 청산 저장과 분리된 표시 순서만 검증한다.
    let presenter = FuturesLiquidationNoticePresenter(window: window, canShow: { ready })
    presenter.receive([try FuturesCalculator.open(domesticFuturesOrder())])
    waitForNoticeUpdates(3.1)
    XCTAssertNil(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" })
    // 화면 생성이나 로드 대신 실제 표시 완료에서 안내를 해제한다.
    let main = MobitTabBarViewController()
    // 재표시 때 완료 콜백을 중복 전달하지 않는지 확인한다.
    var appearanceCount = 0
    main.didAppearCallBack = {
      appearanceCount += 1
      ready = true
      presenter.showPendingNotices()
    }
    main.setViewControllers([UIViewController()])
    XCTAssertFalse(ready)
    window.rootViewController = main
    waitForNoticeUpdates(0.1)
    XCTAssertEqual(appearanceCount, 1)
    // 표시된 시점부터 유지해야 하는 안내다.
    let notice = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" })
    XCTAssertTrue(notice.isUserInteractionEnabled)
    main.viewDidAppear(false)
    XCTAssertEqual(appearanceCount, 1)
    waitForNoticeUpdates(2.7)
    XCTAssertTrue(notice.superview === window)
    XCTAssertEqual(notice.alpha, 1)
    waitForNoticeUpdates(0.6)
    XCTAssertNil(notice.superview)
  }

  @MainActor
  func testLiquidationNoticeTapAndUpSwipeDismissInOrderWithoutReplacingCurrentNotice() throws {
    // 연속 청산 안내를 실제 창에서 순서대로 표시한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 제스처와 자동 닫기가 공유하는 표시 수명이다.
    let presenter = FuturesLiquidationNoticePresenter(window: window, canShow: { true })
    // 서로 다른 청산 알림을 구분할 포지션이다.
    let firstPosition = try FuturesCalculator.open(domesticFuturesOrder())
    // 첫 안내가 표시되는 동안 도착하는 다음 포지션이다.
    let secondPosition = try FuturesCalculator.open(domesticFuturesOrder(side: .short))
    presenter.receive([firstPosition])
    // 다음 이벤트가 첫 안내를 덮어쓰면 안 된다.
    let first = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" } as? UILabel)
    presenter.receive([secondPosition])
    XCTAssertEqual(window.subviews.filter { $0.accessibilityIdentifier == "futuresLiquidationNotice" }.count, 1)
    XCTAssertTrue(window.subviews.contains(first))
    XCTAssertEqual(first.gestureRecognizers?.filter { $0 is UITapGestureRecognizer }.count, 1)
    // 위 방향만 닫기로 연결해야 한다.
    let swipe = try XCTUnwrap(first.gestureRecognizers?.compactMap { $0 as? UISwipeGestureRecognizer }.first)
    XCTAssertEqual(swipe.direction, .up)
    XCTAssertNotNil(first.accessibilityCustomActions?.first)
    presenter.perform(NSSelectorFromString("dismissNotice"))
    presenter.dismissNotice()
    XCTAssertLessThan(first.transform.ty, 0)
    XCTAssertEqual(first.alpha, 0)
    waitForNoticeUpdates(0.35)
    XCTAssertNil(first.superview)
    // 첫 안내를 닫은 뒤에만 다음 안내가 표시된다.
    let second = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" } as? UILabel)
    XCTAssertNotEqual(first.text, second.text)
    XCTAssertEqual(second.alpha, 1)
    presenter.perform(NSSelectorFromString("dismissNotice"))
    waitForNoticeUpdates(0.35)
    XCTAssertNil(second.superview)
    XCTAssertNil(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" })
  }

  @MainActor
  func testLiquidationNoticeSurvivesBackgroundDuringDismissalAndCancelsOldTimer() throws {
    // 비활성화 중 도착한 이벤트와 표시 중이던 안내를 모두 보관한다.
    var active = true
    // 화면 이동 없이 Scene 활성 상태만 바꿔 확인한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 비활성화 때 타이머와 애니메이션을 함께 중단한다.
    let presenter = FuturesLiquidationNoticePresenter(window: window, canShow: { active })
    presenter.receive([try FuturesCalculator.open(domesticFuturesOrder())])
    // 중단한 애니메이션이 대기 목록까지 지우면 안 된다.
    let first = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" } as? UILabel)
    presenter.dismissNotice()
    active = false
    presenter.suspend()
    presenter.receive([try FuturesCalculator.open(domesticFuturesOrder(side: .short))])
    waitForNoticeUpdates(2.8)
    XCTAssertNil(first.superview)
    XCTAssertNil(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" })
    active = true
    presenter.showPendingNotices()
    // 복귀 후 새 안내에는 기존 3초 타이머가 영향을 주면 안 된다.
    let resumed = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" } as? UILabel)
    XCTAssertEqual(resumed.text, first.text)
    waitForNoticeUpdates(0.5)
    XCTAssertTrue(resumed.superview === window)
    XCTAssertEqual(resumed.alpha, 1)
    presenter.dismissNotice()
    waitForNoticeUpdates(0.35)
    // 비활성화 중 들어온 다음 안내도 보존된다.
    let next = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" } as? UILabel)
    XCTAssertNotEqual(next.text, resumed.text)
    presenter.suspend()
  }

  @MainActor
  private func waitForNoticeUpdates(_ delay: TimeInterval) {
    // 실제 UIKit 애니메이션과 자동 닫기 작업까지 메인 큐에서 기다린다.
    let updated = expectation(description: "Liquidation notice updates")
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { updated.fulfill() }
    wait(for: [updated], timeout: delay + 1)
  }

  @MainActor
  func testFuturesDetailBlocksUnpreparedDataWithAlertAndNeverPushesStandaloneOrder() throws {
    // 다른 테스트의 거래소 선택을 복구한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    ExchangeSelectionStore.currentExchange = .upbit
    defer { ExchangeSelectionStore.currentExchange = previousExchange }
    for condition in ["loading", "failed", "missing", "invalidPrice"] {
      // 조회 상태별로 상세 진입을 검증할 마켓 상태다.
      let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
      market.isStubEnabled = true
      // 준비 중·실패·종목 누락·가격 없음 상태를 재현한다.
      var state = market.initialState
      if condition == "loading" { state.isLoading = true }
      if condition == "failed" { state.errorMessage = "Test load failed" }
      if condition == "invalidPrice" { state.totalCryptoList = [.init(cryptoName: "Bitcoin", market: "BTC/KRW", tradePrice: nil)] }
      market.stub.state.value = state
      // 저장된 포지션은 마켓 데이터보다 먼저 존재할 수 있다.
      let position = try FuturesCalculator.open(domesticFuturesOrder())
      // 실제 앱과 같은 상세 진입 검사다.
      let coordinator = FuturesCoordinator(reactor: reactor(), marketReactor: market)
      // 투자내역 위치를 대신하는 시작 화면이다.
      let root = UIViewController()
      // 준비 실패가 스택과 네비게이션 바를 변경하지 않아야 한다.
      let navigation = UINavigationController(rootViewController: root)
      navigation.setNavigationBarHidden(true, animated: false)
      // 안내 알럿을 실제 창에 표시한다.
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
      window.rootViewController = navigation
      window.makeKeyAndVisible()
      defer { window.isHidden = true; window.rootViewController = nil }
      coordinator.open(position: position, from: navigation)
      // 화면 이동 대신 나온 안내다.
      let alert = try XCTUnwrap(root.presentedViewController as? UIAlertController)
      // 조회 단계에 맞는 안내 문구다.
      let key = condition == "loading" ? "futures_trade_loading" : condition == "failed" ? "futures_trade_load_failed" : "futures_trade_unavailable"
      XCTAssertEqual(alert.message, FuturesText.text(key))
      XCTAssertNotEqual(alert.message, key)
      XCTAssertEqual(alert.actions.count, condition == "loading" ? 1 : 2)
      coordinator.open(position: position, from: navigation)
      coordinator.open(coin: .init(cryptoName: "Bitcoin", market: "BTC/KRW", tradePrice: 100), from: navigation)
      XCTAssertTrue(root.presentedViewController === alert)
      XCTAssertEqual(navigation.viewControllers.count, 1)
      XCTAssertTrue(navigation.isNavigationBarHidden)
      XCTAssertTrue(coordinator.childCoordinators.isEmpty)
    }
  }

  @MainActor
  func testFuturesMarketAndInvestmentOpenTheSameTradeVCAndIgnoreRepeatedEntry() throws {
    // 상세 진입 대상 계좌와 선택 거래소를 일치시킨다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    ExchangeSelectionStore.currentExchange = .upbit
    defer { ExchangeSelectionStore.currentExchange = previousExchange }
    // 현재가가 준비된 코인 정보다.
    let coin = CryptoCellInfo(cryptoName: "Bitcoin", market: "BTC/KRW", tradePrice: 100)
    // 조회를 완료한 마켓 상태다.
    let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
    market.isStubEnabled = true
    // 정상 조회 결과를 상세 진입의 기준으로 제공한다.
    var state = market.initialState
    state.totalCryptoList = [coin]
    market.stub.state.value = state
    // 두 진입 경로에서 동일하게 전달해야 하는 계좌 Reactor다.
    let accountReactor = reactor()
    // 마켓 목록과 투자내역의 공통 Coordinator다.
    let coordinator = FuturesCoordinator(reactor: accountReactor, marketReactor: market)
    // 투자내역을 통해 선택할 보유 포지션이다.
    let position = try FuturesCalculator.open(domesticFuturesOrder())
    for fromPosition in [true, false] {
      // 화면 로드 전에 목적지 타입과 전달 데이터를 검증해 외부 조회를 시작하지 않는다.
      let navigation = UINavigationController(rootViewController: UIViewController())
      if fromPosition { coordinator.open(position: position, from: navigation) }
      else { coordinator.open(coin: coin, from: navigation) }
      // 주문 화면 단독 진입 대신 생성된 정상 거래 상세다.
      let trade = try XCTUnwrap(navigation.topViewController as? TradeViewController)
      XCTAssertTrue(trade.futuresReactor === accountReactor)
      XCTAssertEqual(trade.reactor.selectCrypto, coin)
      XCTAssertEqual(navigation.viewControllers.count, 2)
      XCTAssertTrue(navigation.isNavigationBarHidden)
      coordinator.open(position: position, from: navigation)
      coordinator.open(coin: coin, from: navigation)
      XCTAssertEqual(navigation.viewControllers.count, 2)
    }
  }

  @MainActor
  func testTradeBannerKeepsSDKSizeAboveSafeAreaInSpotAndFutures() throws {
    // 현물·선물 상세 화면에서 사용할 동일한 종목이다.
    let coin = CryptoCellInfo(cryptoName: "Bitcoin", market: "BTC/KRW", tradePrice: 100)
    for futures in [false, true] {
      // 시세 조회 없이 실제 XIB와 광고 배치를 검증한다.
      let tradeReactor = TradeReactor(
        selectCrypto: coin,
        cmcInformation: nil,
        cryptoDetailUseCase: CryptoDetailUseCase(cryptoDetailRepository: CryptoDetailRepository()),
        mainUseCase: try FuturesMainFixtureUseCase(),
        tickerSocketService: FuturesMainFixtureSocket()
      )
      tradeReactor.isStubEnabled = true
      // 각 거래 모드의 실제 상세 화면을 생성한다.
      let controller = TradeViewController(reactor: tradeReactor)
      controller.futuresReactor = futures ? reactor() : nil
      // 화면 폭과 홈 인디케이터 여백을 바꿔 배너가 잘리지 않는지 확인한다.
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
      window.rootViewController = controller
      window.makeKeyAndVisible()
      defer { window.isHidden = true; window.rootViewController = nil }
      // 네트워크 응답과 무관하게 요청에 사용된 SDK 배너를 검사한다.
      let banner = try XCTUnwrap(controller.bannerContainerView.subviews.first as? BannerView)
      XCTAssertTrue(banner.delegate === controller)
      for width: CGFloat in [320, 393] {
        window.frame.size.width = width
        for bottomInset: CGFloat in [0, 34] {
          controller.additionalSafeAreaInsets.bottom = bottomInset
          controller.view.setNeedsLayout()
          window.layoutIfNeeded()
          controller.view.layoutIfNeeded()
          XCTAssertEqual(banner.bounds.width, AdSizeBanner.size.width, accuracy: 0.5)
          XCTAssertEqual(banner.bounds.height, AdSizeBanner.size.height, accuracy: 0.5)
          // 화면 좌표로 변환해 안전영역과 주문 패널의 경계를 확인한다.
          let bannerFrame = banner.convert(banner.bounds, to: controller.view)
          XCTAssertEqual(bannerFrame.maxY, controller.view.safeAreaLayoutGuide.layoutFrame.maxY, accuracy: 0.5)
          XCTAssertEqual(bannerFrame.midX, controller.view.bounds.midX, accuracy: 0.5)
          XCTAssertLessThanOrEqual(controller.segmentedContainerView.frame.maxY, bannerFrame.minY + 0.5)
          XCTAssertFalse(banner.hasAmbiguousLayout)
        }
      }
    }
  }

  @MainActor
  func testFuturesStartupLoadsMarketsOnceAndRetryClearsPreviousFailure() throws {
    // 초기 조회가 끝나지 않은 상황을 제어하는 응답이다.
    let response = PublishSubject<CryptoList>()
    // 외부 조회 없이 요청 횟수와 재시도 결과를 확인한다.
    let useCase = try FuturesMainFixtureUseCase()
    useCase.marketResponse = response.asObservable()
    // 실제 Reactor의 로딩·오류 순서를 검증한다.
    let market = MainReactor(mainUseCase: useCase, tickerSocketService: FuturesMainFixtureSocket())
    // 로딩 상태를 활성화하는 구독이다.
    let subscription = market.state.subscribe()
    defer { subscription.dispose() }
    // 초기 화면 구성 시 마켓 조회가 먼저 시작되어야 한다.
    let coordinator = FuturesCoordinator(reactor: reactor(), marketReactor: market)
    coordinator.start()
    XCTAssertTrue(market.currentState.isLoading)
    XCTAssertEqual(useCase.marketRequests, 1)
    market.action.onNext(.loadCryptoList)
    XCTAssertEqual(useCase.marketRequests, 1)
    response.onError(URLError(.notConnectedToInternet))
    XCTAssertFalse(market.currentState.isLoading)
    XCTAssertNotNil(market.currentState.errorMessage)
    useCase.marketResponse = nil
    market.action.onNext(.loadCryptoList)
    XCTAssertFalse(market.currentState.isLoading)
    XCTAssertNil(market.currentState.errorMessage)
    XCTAssertEqual(market.currentState.totalCryptoList.count, 2)
    XCTAssertEqual(useCase.marketRequests, 2)
  }

  @MainActor
  func testTradingAccessoryKeepsLocalConstraintsWhenOwnerDetaches() throws {
    let controller = MobitTabBarViewController()
    let owner = UIViewController()
    controller.setViewControllers([owner])
    controller.view.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
    let accessory = UIButton()
    owner.view.addSubview(accessory)
    accessory.snp.makeConstraints {
      $0.trailing.equalTo(owner.view.safeAreaLayoutGuide).offset(-16)
      $0.bottom.equalTo(owner.view.safeAreaLayoutGuide).offset(-81)
      $0.width.height.equalTo(56)
    }
    controller.view.layoutIfNeeded()
    controller.alignTradingAccessory(accessory)
    controller.view.layoutIfNeeded()
    let selector = try XCTUnwrap(descendants(controller.view).first {
      $0.accessibilityIdentifier == "tradingProductSelector"
    })
    XCTAssertEqual(accessory.convert(accessory.bounds, to: controller.view).midY, selector.frame.midY, accuracy: 1)
    owner.view.removeFromSuperview()
    XCTAssertTrue(owner.view.constraints.contains {
      ($0.firstItem as? UIView) === accessory && $0.firstAttribute == .bottom && $0.isActive
    })
    controller.switchToTab(index: 0)
    controller.view.layoutIfNeeded()
    XCTAssertFalse(accessory.hasAmbiguousLayout)
    XCTAssertGreaterThan(accessory.frame.minX, owner.view.bounds.midX)
    XCTAssertGreaterThan(accessory.frame.minY, owner.view.bounds.midY)
  }

  @MainActor
  func testMarginGroupingPreservesFractionsAndUpdatesEstimate() throws {
    let reactor = reactor()
    let controller = FuturesOrderViewController(
      reactor: reactor,
      instrument: .init(exchange: .upbit, product: .perpetual, rawSymbol: "KRW-BTC", settlementCurrency: .krw)
    )
    controller.loadViewIfNeeded()
    func descendants(_ view: UIView) -> [UIView] {
      [view] + view.subviews.flatMap(descendants)
    }
    let views = descendants(controller.view)
    let field = try XCTUnwrap(views.first { $0.accessibilityIdentifier == "futuresMargin" } as? UITextField)
    for (input, expected) in [
      ("1234567", "1,234,567"), ("1234.50", "1,234"), ("1234.", "1,234"),
      ("123.50", "123.50"), ("123.", "123."), ("999.999999999", "999.99999999"), ("", "")
    ] {
      field.text = input
      field.sendActions(for: .editingChanged)
      XCTAssertEqual(field.text, expected)
    }
    field.text = "1000"
    field.sendActions(for: .editingChanged)
    XCTAssertEqual(field.text, "1,000")
    XCTAssertTrue(views.compactMap { $0 as? UILabel }.contains { $0.text?.contains("10,000") == true })
  }

  @MainActor
  func testPercentageMarginUsesUnifiedPrecisionWithoutExceedingBalance() throws {
    let reactor = reactor()
    let controller = FuturesOrderViewController(
      reactor: reactor,
      instrument: .init(exchange: .upbit, product: .perpetual, rawSymbol: "KRW-BTC", settlementCurrency: .krw)
    )
    controller.loadViewIfNeeded()
    let views = descendants(controller.view)
    let field = try XCTUnwrap(views.first { $0.accessibilityIdentifier == "futuresMargin" } as? UITextField)
    let button = try XCTUnwrap(views.compactMap { $0 as? UIButton }.first { $0.title(for: .normal) == "25%" })
    for (cash, expected) in [
      ("403.99", "100.9975"), ("399.99", "99.9975"), ("3999.99", "999.9975"),
      ("4003.99", "1,000"), ("493827.99", "123,456")
    ] {
      let balance = try XCTUnwrap(Decimal(string: cash))
      let snapshot = FuturesAccountSnapshot(revision: 1, accounts: [.init(id: account, availableBalance: balance)])
      reactor.stub.state.value = reactor.reduce(state: reactor.initialState, mutation: .snapshot(snapshot, [:]))
      button.sendActions(for: .touchUpInside)
      XCTAssertEqual(field.text, expected)
    }
    let all = try XCTUnwrap(views.compactMap { $0 as? UIButton }.first { $0.title(for: .normal) == "100%" })
    all.sendActions(for: .touchUpInside)
    XCTAssertEqual(field.text, "493,827")
    XCTAssertTrue(reactor.stub.actions.isEmpty)
  }

  func testTradingValuesPreserveEightDecimalsBelowOneThousandAndTruncateAboveIt() throws {
    for (input, expected) in [
      ("100.123456789", "100.12345678"), ("999.999999999", "999.99999999"),
      ("1000.99999999", "1,000"), ("123456.99", "123,456"),
      ("-999.123456789", "-999.12345678"), ("-1000.99", "-1,000"),
      ("0.00000001", "0.00000001"), ("0.000000009", "0"), ("-0.000000009", "0")
    ] {
      let value = try XCTUnwrap(Decimal(string: input))
      XCTAssertEqual(FuturesText.number(value), expected)
      XCTAssertEqual(try XCTUnwrap(Double(input)).formatTradingValue(), expected)
    }
    XCTAssertEqual(FuturesText.number(nil), "—")
    XCTAssertEqual(FuturesText.number(.nan), "—")
    XCTAssertEqual(Double.infinity.formatTradingValue(), "—")
    XCTAssertEqual(Double.nan.formatTradingValue(), "—")
    XCTAssertEqual(FuturesText.number(Decimal(string: "1000.1234"), digits: 2), "1,000.12")
  }

  @MainActor
  func testInvestmentHistoryAndShareUseTheSameQuantityAndAmountPrecision() throws {
    for (input, expected) in [
      ("100.12345678", "100.12345678"), ("999.99999999", "999.99999999"), ("1000.99999999", "1,000")
    ] {
      let amount = try XCTUnwrap(Decimal(string: input))
      let position = try FuturesCalculator.open(domesticFuturesOrder(leverage: 1, margin: amount, price: 1))
      let investment = try XCTUnwrap(
        UINib(nibName: "InvestmentTableViewCell", bundle: .main).instantiate(withOwner: nil).first as? InvestmentTableViewCell
      )
      investment.configure(position: position, valuation: nil, isLast: true)
      XCTAssertEqual(investment.cryptoAmount.text, expected)
      XCTAssertEqual(investment.cryptoBuyPrice.text, expected + " 원")
      let record = FuturesTransactionRecord(
        eventID: UUID(),
        positionID: position.id,
        kind: .closing,
        instrument: position.order.instrument,
        side: .long,
        leverage: 1,
        quantity: position.quantity,
        intervalStart: 120_000,
        intervalEndExclusive: nil,
        recordedAt: Date(timeIntervalSince1970: 120),
        price: 1,
        realizedPnL: amount
      )
      let history = try XCTUnwrap(
        UINib(nibName: "PNLTableViewCell", bundle: .main).instantiate(withOwner: nil).first as? PNLTableViewCell
      )
      history.configure(record: record, position: position)
      XCTAssertEqual(history.quantityLabel.text, expected)
      XCTAssertEqual(history.pnlLabel.text, expected + " 원")
      let share = PNLShareView.instanceFromNib(pnlShareUnit: try FuturesText.shareUnit(record, position: position)) { _ in }
      XCTAssertEqual(share.quantityLabel.text, expected)
      XCTAssertEqual(share.pnlLabel.text, "+" + expected + " ₩")
      XCTAssertEqual(position.quantity, amount)
      XCTAssertEqual(try position.margin, amount)
    }
  }

  @MainActor
  func testPositionCardUpdatesProfitPricesAndClearsUnavailableValuation() throws {
    let reactor = reactor()
    let position = try FuturesCalculator.open(domesticFuturesOrder())
    let instrument = position.order.instrument
    let snapshot = FuturesAccountSnapshot(
      revision: 1,
      accounts: [.init(id: account, availableBalance: 900_000)],
      positions: [position],
      historyCheckStates: [try .initial(for: position)]
    )
    let timestamp = try FuturesHistoryCheckState.milliseconds(Date()) - 1000
    var state = reactor.reduce(
      state: reactor.initialState,
      mutation: .snapshot(snapshot, [instrument: .init(instrument: instrument, price: 110_000_000, timestamp: timestamp)])
    )
    reactor.stub.state.value = state
    let controller = FuturesOrderViewController(reactor: reactor, instrument: instrument)
    controller.loadViewIfNeeded()
    let card = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresPositionCard" })
    func label(_ key: String) throws -> UILabel {
      try XCTUnwrap(descendants(card).first { $0.accessibilityIdentifier == key } as? UILabel)
    }
    XCTAssertEqual(try label("futures_pnl").text, "+" + FuturesText.number(100_000))
    XCTAssertEqual(try label("futures_roe").text, "+100%")
    XCTAssertEqual(try label("futures_margin").text, FuturesText.number(100_000))
    XCTAssertEqual(try label("futures_position_size").text, FuturesText.number(1_100_000))
    XCTAssertEqual(try label("futures_entry").text, FuturesText.number(100_000_000))
    XCTAssertEqual(try label("futures_liquidation_price").text, FuturesText.number(90_000_000))
    state.quotes[instrument] = .init(instrument: instrument, price: 95_000_000, timestamp: timestamp + 1)
    reactor.stub.state.value = state
    XCTAssertEqual(try label("futures_pnl").text, FuturesText.number(-50_000))
    XCTAssertEqual(try label("futures_roe").text, "-50%")
    XCTAssertEqual(try label("futures_current").text, FuturesText.number(95_000_000))
    XCTAssertEqual(try label("futures_pnl").superview?.accessibilityValue, FuturesText.number(-50_000))
    state.quotes.removeAll()
    reactor.stub.state.value = state
    for key in ["futures_pnl", "futures_roe", "futures_current", "futures_position_size"] {
      XCTAssertEqual(try label(key).text, "—")
    }
    XCTAssertEqual(try label("futures_entry").text, FuturesText.number(100_000_000))
    state.snapshot = .init(revision: 2, accounts: [.init(id: account, availableBalance: 1_000_000)])
    reactor.stub.state.value = state
    XCTAssertTrue(card.isHidden)
  }

  @MainActor
  func testPositionCardFitsNarrowOrderPanelAndWideLayout() throws {
    let reactor = reactor()
    let position = try FuturesCalculator.open(
      domesticFuturesOrder(margin: try XCTUnwrap(Decimal(string: "100.12345678")), price: 1)
    )
    let instrument = position.order.instrument
    let snapshot = FuturesAccountSnapshot(
      revision: 1,
      accounts: [.init(id: account, availableBalance: 900_000)],
      positions: [position],
      historyCheckStates: [try .initial(for: position)]
    )
    let timestamp = try FuturesHistoryCheckState.milliseconds(Date()) - 1000
    reactor.stub.state.value = reactor.reduce(
      state: reactor.initialState,
      mutation: .snapshot(snapshot, [instrument: .init(instrument: instrument, price: 1.5, timestamp: timestamp)])
    )
    let controller = FuturesOrderViewController(reactor: reactor, instrument: instrument)
    controller.loadViewIfNeeded()
    // 주문 패널의 제목·금액 정렬과 테두리를 확인할 실제 라벨이다.
    let marketOrder = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresMarketOrder" } as? UILabel)
    // 소수 잔액을 포함한 금액의 표시 정밀도는 그대로 유지한다.
    let availableAmount = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresAvailableAmount" } as? UILabel)
    XCTAssertEqual(availableAmount.text, "900,000 원")
    XCTAssertTrue(descendants(controller.view).compactMap { $0 as? UILabel }.contains { $0.text == FuturesText.text("futures_held_position") })
    // 키보드 레이아웃 가이드와 스크롤 높이를 실제 창에서 계산한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 1200))
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    window.rootViewController?.view.addSubview(controller.view)
    defer { controller.view.removeFromSuperview(); window.isHidden = true; window.rootViewController = nil }
    for style in [UIUserInterfaceStyle.dark, .light] {
      controller.overrideUserInterfaceStyle = style
      for width: CGFloat in [203, 390] {
        controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 1200)
        controller.view.setNeedsLayout()
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        XCTAssertEqual(marketOrder.layer.borderWidth, 1)
        XCTAssertEqual(marketOrder.layer.borderColor, UIColor.mobitColors(.tradeSeparator).resolvedColor(with: controller.traitCollection).cgColor)
        // 실제 생성된 네 비율 버튼의 테두리를 확인한다.
        let percentageButtons = descendants(controller.view).compactMap({ $0 as? UIButton }).filter {
          $0.accessibilityIdentifier?.hasPrefix("futuresOrderPercent") == true
        }
        XCTAssertEqual(percentageButtons.count, 4)
        for button in percentageButtons {
          XCTAssertEqual(button.configuration?.background.strokeWidth, 1)
          XCTAssertEqual(button.configuration?.background.strokeColor?.resolvedColor(with: controller.traitCollection).cgColor, marketOrder.layer.borderColor)
          XCTAssertLessThanOrEqual((button.titleLabel?.intrinsicContentSize.width ?? 0) + 8, button.bounds.width)
        }
        XCTAssertFalse(availableAmount.hasAmbiguousLayout)
        XCTAssertEqual(availableAmount.textAlignment, .right)
        // 좁은 주문 패널에서도 금액 전체가 잘리지 않는지 확인한다.
        XCTAssertGreaterThanOrEqual(availableAmount.bounds.width, availableAmount.intrinsicContentSize.width - 1)
        // 테마별 주문 패널의 실제 배치를 남긴다.
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { controller.view.layer.render(in: $0.cgContext) }
        // 시각 확인에 사용할 주문 화면 자료다.
        let attachment = XCTAttachment(image: image)
        attachment.name = "FuturesOrder-\(style == .dark ? "Dark" : "Light")-\(Int(width))"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
    }
    let card = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresPositionCard" })
    card.removeFromSuperview()
    let container = UIView()
    container.addSubview(card)
    card.snp.makeConstraints { $0.top.leading.trailing.equalToSuperview() }
    card.overrideUserInterfaceStyle = .dark
    for width: CGFloat in [203, 390] {
      container.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
      container.setNeedsLayout()
      container.layoutIfNeeded()
      card.layoutIfNeeded()
      container.setNeedsLayout()
      container.layoutIfNeeded()
      XCTAssertEqual(card.bounds.width, width, accuracy: 1)
      for label in descendants(card).compactMap({ $0 as? UILabel }).filter({
        $0.accessibilityIdentifier?.hasPrefix("futures_") == true
      }) {
        XCTAssertFalse(label.hasAmbiguousLayout)
        XCTAssertGreaterThan(label.bounds.height, 0)
        let frame = label.convert(label.bounds, to: card)
        XCTAssertGreaterThanOrEqual(frame.minX, -1)
        XCTAssertLessThanOrEqual(frame.maxX, width + 1)
        XCTAssertLessThanOrEqual(frame.maxY, card.bounds.height + 1)
      }
      let image = UIGraphicsImageRenderer(bounds: card.bounds).image { card.layer.render(in: $0.cgContext) }
      let attachment = XCTAttachment(image: image)
      attachment.name = "FuturesPositionCard-\(Int(width))"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }

  @MainActor
  func testCloseSheetKeepsPrincipalAndQuantityWhileSocketUpdatesEstimatedReturn() throws {
    // 이미 포지션이 있는 화면의 테스트 상태다.
    let reactor = reactor()
    // 금액과 수량의 양방향 계산을 확인할 포지션이다.
    let position = try FuturesCalculator.open(domesticFuturesOrder(margin: 100, price: 100))
    // 최신 소켓 가격을 대신하는 테스트 값이다.
    var price: Decimal = 100
    // 주문 화면 소켓만 갱신되어도 종료 시트가 즉시 반응해야 한다.
    let priceUpdates = PublishSubject<Void>()
    // 시세 연결이 끊겨도 버튼은 유지하고 탭 시점에 제출을 막는다.
    var connected = true
    // 화면과 주문이 공유하는 현재 시각이다.
    let timestamp = try FuturesHistoryCheckState.milliseconds(Date()) - 1000
    reactor.stub.state.value = reactor.reduce(
      state: reactor.initialState,
      mutation: .snapshot(.init(revision: 1, accounts: [.init(id: account, availableBalance: 900)], positions: [position], historyCheckStates: [try .initial(for: position)]), [:])
    )
    // 부분 종료 입력과 시세 갱신을 확인할 시트다.
    let controller = FuturesCloseViewController(
      reactor: reactor,
      positionID: position.id,
      captureOrderPrice: {
        connected ? FuturesOrderPrice(quote: .init(instrument: position.order.instrument, price: price, timestamp: timestamp), requestedAt: timestamp) : nil
      },
      orderPriceUpdates: priceUpdates
    )
    // 실제 안전영역과 키보드 가이드가 적용된 종료 버튼의 위치를 확인한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 금액 직접 입력 필드다.
    let amount = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresCloseAmount" } as? UITextField)
    // 수량 직접 입력 필드다.
    let quantity = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresCloseQuantity" } as? UITextField)
    // 원금과 구분해 실시간 손익이 포함된 예상 반환금액을 확인한다.
    let summary = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresCloseSummary" } as? UILabel)
    // 시세·입력 변경으로 상태와 위치가 바뀌면 안 되는 하단 제출 버튼이다.
    let submit = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresCloseSubmit" } as? UIButton)
    window.layoutIfNeeded()
    controller.view.layoutIfNeeded()
    // 모든 시세 갱신에서 유지해야 하는 최초 버튼 위치와 크기다.
    let submitFrame = submit.frame
    // 연결 단절과 입력 오류도 버튼의 상태 전환을 발생시키지 않아야 한다.
    var enabledChanges: [Bool] = []
    // 실제 UIKit 버튼의 상태 변경을 감시한다.
    let observation = submit.observe(\.isEnabled, options: [.new]) { _, change in
      if let enabled = change.newValue { enabledChanges.append(enabled) }
    }
    // 비동기 시세 반영과 100ms 묶음 갱신이 끝난 시점을 기다린다.
    func flushPriceUpdates() {
      // 마지막 시세가 화면에 반영될 시간을 검증한다.
      let updated = expectation(description: "Close sheet price update")
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { updated.fulfill() }
      wait(for: [updated], timeout: 1)
      window.layoutIfNeeded()
      controller.view.layoutIfNeeded()
      XCTAssertEqual(submit.frame, submitFrame)
    }
    XCTAssertEqual(amount.text, "100")
    amount.text = "25"
    amount.sendActions(for: .editingChanged)
    XCTAssertEqual(quantity.text, FuturesText.number(Decimal(string: "2.5")))
    price = 125
    priceUpdates.onNext(())
    flushPriceUpdates()
    XCTAssertEqual(amount.text, "25")
    XCTAssertEqual(quantity.text, FuturesText.number(Decimal(string: "2.5")))
    XCTAssertTrue(summary.text?.contains(FuturesText.text("futures_close_return") + " " + FuturesText.number(Decimal(string: "87.5"))) == true)
    quantity.text = "3"
    quantity.sendActions(for: .editingChanged)
    price = 130
    priceUpdates.onNext(())
    flushPriceUpdates()
    XCTAssertEqual(quantity.text, "3")
    XCTAssertEqual(amount.text, "30")
    XCTAssertTrue(summary.text?.contains(FuturesText.text("futures_close_return") + " 120") == true)
    // 전량 버튼은 가격과 무관하게 원래 수량을 모두 선택한다.
    let all = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresClosePercent100" } as? UIButton)
    all.sendActions(for: .touchUpInside)
    XCTAssertEqual(quantity.text, "10")
    XCTAssertEqual(amount.text, "100")
    // 0%여도 버튼은 유지하고 종료 요청은 탭할 때 막는다.
    let zero = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresClosePercent0" } as? UIButton)
    zero.sendActions(for: .touchUpInside)
    XCTAssertTrue(submit.isEnabled)
    submit.sendActions(for: .touchUpInside)
    XCTAssertFalse(reactor.stub.actions.contains { if case .closeQuantity = $0 { return true }; return false })
    XCTAssertEqual((controller.presentedViewController as? UIAlertController)?.message, FuturesText.text("futures_close_invalid"))
    controller.dismiss(animated: false)
    amount.text = "12abc"
    amount.sendActions(for: .editingChanged)
    XCTAssertTrue(submit.isEnabled)
    quantity.text = ".5"
    quantity.sendActions(for: .editingChanged)
    XCTAssertEqual(amount.text, "5")
    XCTAssertTrue(submit.isEnabled)
    // 연결 단절 동안에도 마지막 평가값이 비워지지 않아야 한다.
    let lastSummary = summary.text
    connected = false
    priceUpdates.onNext(())
    flushPriceUpdates()
    XCTAssertTrue(submit.isEnabled)
    XCTAssertEqual(summary.text, lastSummary)
    submit.sendActions(for: .touchUpInside)
    XCTAssertFalse(reactor.stub.actions.contains { if case .closeQuantity = $0 { return true }; return false })
    XCTAssertEqual((controller.presentedViewController as? UIAlertController)?.message, FuturesText.text("futures_socket_wait"))
    controller.dismiss(animated: false)
    connected = true
    priceUpdates.onNext(())
    flushPriceUpdates()
    XCTAssertTrue(submit.isEnabled)
    // 반환할 증거금이 소진돼도 버튼은 유지하고 탭 시 검증 실패를 안내한다.
    price = 90
    priceUpdates.onNext(())
    flushPriceUpdates()
    XCTAssertTrue(submit.isEnabled)
    submit.sendActions(for: .touchUpInside)
    XCTAssertFalse(reactor.stub.actions.contains { if case .closeQuantity = $0 { return true }; return false })
    XCTAssertEqual((controller.presentedViewController as? UIAlertController)?.message, FuturesText.text("futures_retry_order"))
    controller.dismiss(animated: false)
    for nextPrice in [131, 132, 133, 130] {
      price = Decimal(nextPrice)
      priceUpdates.onNext(())
      flushPriceUpdates()
      XCTAssertEqual(quantity.text, ".5")
      XCTAssertTrue(submit.isEnabled)
    }
    // 같은 시세 묶음에서 잠깐 가격이 비어도 최종 유효 시세만 화면에 반영한다.
    connected = false
    priceUpdates.onNext(())
    connected = true
    for nextPrice in 131...150 {
      price = Decimal(nextPrice)
      priceUpdates.onNext(())
    }
    flushPriceUpdates()
    XCTAssertTrue(summary.text?.contains(FuturesText.text("futures_close_return") + " 30") == true)
    // 제출 시점에는 화면 갱신 주기와 무관하게 최신 체결 가격을 다시 읽는다.
    price = 130
    observation.invalidate()
    XCTAssertTrue(enabledChanges.isEmpty)
    XCTAssertEqual(amount.text, "5")
    submit.sendActions(for: .touchUpInside)
    submit.sendActions(for: .touchUpInside)
    // 연속 탭도 확인한 수량과 소켓 가격으로 한 번만 종료 요청을 보낸다.
    let closingActions = reactor.stub.actions.compactMap { action -> (UUID, Decimal, Decimal, FuturesOrderPrice)? in
      if case let .closeQuantity(id, quantity, expected, price) = action { return (id, quantity, expected, price) }
      return nil
    }
    XCTAssertEqual(closingActions.count, 1)
    XCTAssertEqual(closingActions.first?.0, position.id)
    XCTAssertEqual(closingActions.first?.1, Decimal(string: "0.5"))
    XCTAssertEqual(closingActions.first?.2, 10)
    XCTAssertEqual(closingActions.first?.3.quote.price, 130)
    // 실제 종료 요청 처리 중에도 하단 버튼의 모양과 배치를 유지한다.
    var submittingState = reactor.currentState
    submittingState.submitting = true
    reactor.stub.state.value = submittingState
    flushPriceUpdates()
    XCTAssertTrue(submit.isEnabled)
    submit.sendActions(for: .touchUpInside)
    XCTAssertEqual(reactor.stub.actions.filter { if case .closeQuantity = $0 { return true }; return false }.count, 1)
    // 주문 검증이 실패하면 알럿을 띄우고 입력을 유지한 채 재시도를 허용한다.
    var failedState = submittingState
    failedState.submitting = false
    failedState.message = FuturesText.text("futures_retry_order")
    reactor.stub.state.value = failedState
    XCTAssertEqual((controller.presentedViewController as? UIAlertController)?.message, FuturesText.text("futures_retry_order"))
    controller.dismiss(animated: false)
    submit.sendActions(for: .touchUpInside)
    XCTAssertEqual(reactor.stub.actions.filter { if case .closeQuantity = $0 { return true }; return false }.count, 2)
  }

  @MainActor
  func testCloseSheetDimFollowsThemeAndIsRemovedAfterDismissal() throws {
    // 실제 포지션을 보유한 주문 화면에서 시트를 표시한다.
    let accountReactor = reactor()
    // 원금·수량 표시를 확인할 모의 포지션이다.
    let position = try FuturesCalculator.open(domesticFuturesOrder(margin: 100, price: 100))
    accountReactor.stub.state.value = accountReactor.reduce(
      state: accountReactor.initialState,
      mutation: .snapshot(
        .init(revision: 1, accounts: [.init(id: account, availableBalance: 900)], positions: [position], historyCheckStates: [try .initial(for: position)]),
        [:]
      )
    )
    for style in [UIUserInterfaceStyle.dark, .light] {
      // 시트 뒤에서 종료 버튼의 테두리도 확인한다.
      let order = FuturesOrderViewController(reactor: accountReactor, instrument: position.order.instrument)
      // 실제 UIKit 시트의 dim 영역과 안전 영역을 제공한다.
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
      window.overrideUserInterfaceStyle = style
      window.rootViewController = order
      window.makeKeyAndVisible()
      defer { window.isHidden = true; window.rootViewController = nil }
      // 시트에 실시간 시세를 제공한다.
      let timestamp = try FuturesHistoryCheckState.milliseconds(Date()) - 1000
      // 기본 바텀 시트로 표시하고 닫았을 때 dim이 남지 않아야 한다.
      let sheet = FuturesCloseViewController(reactor: accountReactor, positionID: position.id) {
        .init(quote: .init(instrument: position.order.instrument, price: 105, timestamp: timestamp), requestedAt: timestamp)
      }
      sheet.modalPresentationStyle = .pageSheet
      sheet.sheetPresentationController?.detents = [.medium(), .large()]
      sheet.sheetPresentationController?.selectedDetentIdentifier = .medium
      sheet.sheetPresentationController?.prefersGrabberVisible = true
      // 표시 애니메이션이 끝난 뒤 실제 배경과 버튼을 검사한다.
      let presented = expectation(description: "Close sheet presented")
      order.present(sheet, animated: true) { presented.fulfill() }
      wait(for: [presented], timeout: 3)
      // 기본 dim 아래에 추가한 색상 영역이다.
      let dim = try XCTUnwrap(descendants(window).first { $0.accessibilityIdentifier == "futuresCloseDim" })
      XCTAssertFalse(dim.isUserInteractionEnabled)
      XCTAssertEqual(dim.backgroundColor?.resolvedColor(with: dim.traitCollection).cgColor.alpha, style == .dark ? 0.12 : 0)
      // 테마가 바뀌어도 비율 버튼 테두리는 현재 색상으로 갱신한다.
      sheet.overrideUserInterfaceStyle = style == .dark ? .light : .dark
      sheet.overrideUserInterfaceStyle = .unspecified
      for button in descendants(sheet.view).compactMap({ $0 as? UIButton }) {
        if button.accessibilityIdentifier?.hasPrefix("futuresClosePercent") == true {
          XCTAssertEqual(button.layer.borderWidth, 1)
          XCTAssertEqual(button.layer.borderColor, UIColor.mobitColors(.tradeSeparator).resolvedColor(with: button.traitCollection).cgColor)
        } else {
          XCTAssertEqual(button.configuration?.background.strokeWidth, 1)
        }
      }
      // 시트를 여는 기존 포지션 종료 버튼이다.
      let openButton = try XCTUnwrap(descendants(order.view).first { $0.accessibilityIdentifier == "futuresClose" } as? UIButton)
      XCTAssertEqual(openButton.configuration?.background.strokeWidth, 1)
      // 실제 dim과 시트 경계를 함께 남기는 모드별 확인 이미지다.
      window.layoutIfNeeded()
      let image = UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) }
      // Xcode 테스트 결과에 포함할 화면 자료다.
      let attachment = XCTAttachment(image: image)
      attachment.name = style == .dark ? "FuturesCloseSheet-Dark" : "FuturesCloseSheet-Light"
      attachment.lifetime = .keepAlways
      add(attachment)
      // 취소·제출과 같은 프로그램 방식의 닫기도 dim을 제거한다.
      let dismissed = expectation(description: "Close sheet dismissed")
      sheet.dismiss(animated: true) { dismissed.fulfill() }
      wait(for: [dismissed], timeout: 3)
      XCTAssertNil(dim.superview)
      XCTAssertNil(order.presentedViewController)
    }
  }

  @MainActor
  func testClosePercentSliderSupportsZeroAndCloseSheetFitsSmallScreen() throws {
    // 기존 주문과 같은 슬라이더가 종료 비율에서는 0%까지 지원한다.
    let control = FuturesLeverageControl()
    control.minimumValue = 0
    control.maximumValue = 100
    control.valueSuffix = "%"
    control.value = 0
    control.accessibilityIncrement()
    XCTAssertEqual(control.value, 1)
    control.accessibilityDecrement()
    XCTAssertEqual(control.value, 0)
    XCTAssertEqual(control.accessibilityValue, "0%")
    // 작은 화면에서도 입력창과 제출 버튼이 안전 영역 안에 놓인다.
    let reactor = reactor()
    // 테스트 화면의 포지션이다.
    let position = try FuturesCalculator.open(domesticFuturesOrder(margin: 100, price: 100))
    reactor.stub.state.value = reactor.reduce(state: reactor.initialState, mutation: .snapshot(.init(revision: 1, accounts: [.init(id: account, availableBalance: 900)], positions: [position], historyCheckStates: [try .initial(for: position)]), [:]))
    // 시트에 제공할 유효한 시세다.
    let time = try FuturesHistoryCheckState.milliseconds(Date()) - 1000
    // 실제 시트 레이아웃을 렌더링한다.
    let controller = FuturesCloseViewController(reactor: reactor, positionID: position.id) {
      .init(quote: .init(instrument: position.order.instrument, price: 105, timestamp: time), requestedAt: time)
    }
    // 키보드 안전 영역도 실제 창에 연결해 레이아웃을 검증한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    controller.overrideUserInterfaceStyle = .dark
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    window.layoutIfNeeded()
    controller.view.layoutIfNeeded()
    for key in ["futuresCloseAmount", "futuresCloseQuantity", "futuresCloseSubmit"] {
      // 크기가 확정된 각 입력·제출 컨트롤이다.
      let view = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == key })
      XCTAssertFalse(view.hasAmbiguousLayout, "Ambiguous close sheet control: \(key)")
      XCTAssertGreaterThan(view.bounds.height, 0)
      XCTAssertLessThanOrEqual(view.convert(view.bounds, to: controller.view).maxX, 320)
    }
    // 시트의 시각 검증에 사용하는 작은 화면 이미지다.
    let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { controller.view.layer.render(in: $0.cgContext) }
    // Xcode 결과에 남길 레이아웃 확인 자료다.
    let attachment = XCTAttachment(image: image)
    attachment.name = "FuturesPartialCloseSheet-320"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func testOrderCapturesDisplayedSocketPriceAndClearsItWhenPaused() throws {
    let previousExchange = ExchangeSelectionStore.currentExchange
    ExchangeSelectionStore.currentExchange = .upbit
    defer { ExchangeSelectionStore.currentExchange = previousExchange }
    let socket = FuturesMainFixtureSocket()
    socket.isConnected = true
    let reactor = TradeReactor(
      selectCrypto: .init(cryptoName: "Bitcoin", market: "BTC/KRW", tradePrice: 100),
      cmcInformation: nil,
      cryptoDetailUseCase: CryptoDetailUseCase(cryptoDetailRepository: CryptoDetailRepository()),
      mainUseCase: try FuturesMainFixtureUseCase(),
      tickerSocketService: socket
    )
    func emit(_ price: Double, timestamp: Int64 = 299_000) {
      socket.ticks.onNext(CryptoSocketTicker(
        type: "ticker",
        code: "KRW-BTC",
        openingPrice: price,
        highPrice: price,
        lowPrice: price,
        tradePrice: price,
        prevClosingPrice: price,
        change: "EVEN",
        changePrice: 0,
        signedChangePrice: 0,
        changeRate: 0,
        signedChangeRate: 0,
        tradeVolume: 1,
        accTradeVolume: 1,
        accTradeVolume24H: 1,
        accTradePrice: price,
        accTradePrice24H: price,
        tradeDate: "",
        tradeTime: "",
        tradeTimestamp: 299_000,
        askBid: "",
        accAskVolume: 0,
        accBidVolume: 0,
        highest52WeekPrice: 0,
        highest52WeekDate: "",
        lowest52WeekPrice: 0,
        lowest52WeekDate: "",
        marketState: "",
        delistingDate: nil,
        marketWarning: nil,
        timestamp: timestamp,
        streamType: "REALTIME"
      ))
    }
    func receive(_ price: Double) {
      let displayed = expectation(description: "Socket price reaches displayed state")
      let subscription = reactor.state.filter { $0.cryptoCellInfo?.tradePrice == price }.take(1)
        .subscribe(onNext: { _ in displayed.fulfill() })
      emit(price)
      wait(for: [displayed], timeout: 3)
      subscription.dispose()
    }
    let now = Date(timeIntervalSince1970: 300)
    XCTAssertNil(reactor.captureFuturesOrderPrice(now: now))
    receive(101)
    let captured = try XCTUnwrap(reactor.captureFuturesOrderPrice(now: now))
    receive(110)
    XCTAssertEqual(captured.quote.price, 101)
    XCTAssertEqual(reactor.captureFuturesOrderPrice(now: now)?.quote.price, 110)
    _ = reactor.mutate(action: .pauseSocket)
    XCTAssertNil(reactor.captureFuturesOrderPrice(now: now))
    socket.isConnected = true
    XCTAssertNil(reactor.captureFuturesOrderPrice(now: now))
    receive(120)
    XCTAssertEqual(reactor.captureFuturesOrderPrice(now: now)?.quote.price, 120)
    // 한 번에 밀려온 소켓 이벤트도 화면 시세와 주문 시세가 어긋나지 않아야 한다.
    let completed = expectation(description: "Burst prices reach displayed state")
    // 화면 상태를 구독하는 종료 시트에서 보게 되는 일시적인 시세 누락이다.
    var missingPrices = 0
    // 각 표시 가격과 같은 시점의 주문 가격을 확인한다.
    let observation = reactor.state.subscribe(onNext: { state in
      guard let price = state.cryptoCellInfo?.tradePrice, price >= 121 else { return }
      if reactor.captureFuturesOrderPrice(now: now) == nil { missingPrices += 1 }
      if price == 140 { completed.fulfill() }
    })
    for price in 121...140 { emit(Double(price)) }
    wait(for: [completed], timeout: 3)
    observation.dispose()
    XCTAssertEqual(missingPrices, 0)
    // 표시 가능한 가격이라도 미래 시각의 소켓을 주문에 사용해서는 안 된다.
    let futureDisplayed = expectation(description: "Future socket price is displayed but cannot be captured for order")
    // 거래 화면 표시와 주문의 시각 검증이 분리돼 있는지 확인한다.
    let futureSubscription = reactor.state.filter { $0.cryptoCellInfo?.tradePrice == 150 }.take(1)
      .subscribe(onNext: { _ in futureDisplayed.fulfill() })
    emit(150, timestamp: 300_001)
    wait(for: [futureDisplayed], timeout: 3)
    futureSubscription.dispose()
    XCTAssertNil(reactor.captureFuturesOrderPrice(now: now))
  }

  private let account = TradingAccountID(exchange: .upbit, product: .perpetual, currency: .krw)

  private func reactor() -> FuturesAccountReactor {
    let reactor = FuturesAccountReactor(account: account)
    reactor.isStubEnabled = true
    return reactor
  }

  @MainActor
  func testLoadingDismissalRemovesOriginalOverlayAfterPresenterDetaches() {
    let controller = MobitBaseViewController()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    controller.showLoadingIndicator()
    let displayed = expectation(description: "Original window has loading overlay")
    DispatchQueue.main.async {
      XCTAssertNotNil(window.viewWithTag(999_999))
      window.rootViewController = UIViewController()
      controller.hideLoadingIndicator()
      DispatchQueue.main.async {
        XCTAssertNil(window.viewWithTag(999_999))
        displayed.fulfill()
      }
    }
    wait(for: [displayed], timeout: 3)
  }

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
      historyCheckStates: [try .initial(for: position)]
    )
    let now = Date()
    let timestamp = try FuturesHistoryCheckState.milliseconds(now) - 60_000
    let quote = FuturesMarkQuote(instrument: position.order.instrument, price: 110_000_000, timestamp: timestamp)
    var state = reactor.reduce(state: reactor.initialState, mutation: .snapshot(snapshot, [:]))
    XCTAssertEqual(state.quotes[position.order.instrument]?.price, try position.averageEntryPrice)
    state = reactor.reduce(state: state, mutation: .snapshot(snapshot, [quote.instrument: quote]))
    state = reactor.reduce(state: state, mutation: .snapshot(snapshot, [:]))
    state = reactor.reduce(state: state, mutation: .loadFailed)
    reactor.stub.state.value = state
    XCTAssertFalse(reactor.canSubmit)
    XCTAssertEqual(state.quotes[quote.instrument], quote)
    XCTAssertEqual(try FuturesText.valuation(position, quotes: state.quotes)?.displayedEquity, 200_000)
    XCTAssertThrowsError(try snapshot.valuation(for: account, quotes: state.quotes, now: now))
    XCTAssertEqual(
      try snapshot.valuation(for: account, quotes: state.quotes, now: now, forDisplay: true).totalEquity,
      1_100_000
    )
    var verification = try FuturesHistoryCheckState.initial(for: position)
    verification.verifiedThrough = timestamp
    verification.lastVerifiedMark = quote.price
    let restoredSnapshot = FuturesAccountSnapshot(
      revision: 0,
      accounts: snapshot.accounts,
      positions: [position],
      historyCheckStates: [verification]
    )
    let restored = reactor.reduce(state: reactor.initialState, mutation: .snapshot(restoredSnapshot, [:]))
    XCTAssertEqual(restored.quotes[quote.instrument], quote)
    let replacement = FuturesMarkQuote(instrument: quote.instrument, price: 120_000_000, timestamp: timestamp + 1)
    state = reactor.reduce(state: state, mutation: .snapshot(snapshot, [quote.instrument: replacement]))
    XCTAssertEqual(try FuturesText.valuation(position, quotes: state.quotes)?.displayedEquity, 300_000)
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
      historyCheckStates: [try .initial(for: position)]
    )
    var state = reactor.reduce(state: reactor.initialState, mutation: .snapshot(snapshot, [:]))
    for status in [
      FuturesRefreshStatus.refreshing, .paused,
      .finished([
        FuturesRefreshResult(
          positionID: position.id,
          verifiedThrough: 120_000,
          liquidated: false,
          hold: .missingHistory
        )
      ])
    ] {
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
    let snapshot = FuturesAccountSnapshot(
      revision: 1,
      accounts: [.init(id: account, availableBalance: 1000)],
      positions: [position],
      historyCheckStates: [try .initial(for: position)]
    )
    var state = reactor.reduce(state: reactor.initialState, mutation: .snapshot(snapshot, [:]))
    for status in [
      FuturesRefreshStatus.refreshing, .paused, .storageFailed, .finished([]),
      .finished([.init(positionID: position.id, verifiedThrough: 120_000, liquidated: false, hold: .missingHistory)])
    ] {
      state = reactor.reduce(state: state, mutation: .status(status))
      reactor.stub.state.value = state
      XCTAssertFalse(reactor.canSubmit)
    }
    state = reactor.reduce(
      state: state,
      mutation: .status(
        .finished([
          .init(positionID: position.id, verifiedThrough: 120_000, liquidated: false, hold: nil)
        ])
      )
    )
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
    let snapshot = FuturesAccountSnapshot(
      revision: 1,
      accounts: [.init(id: account, availableBalance: 1000)],
      positions: [position],
      historyCheckStates: [try .initial(for: position)]
    )
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
    state = reactor.reduce(
      state: state,
      mutation: .status(
        .finished([
          .init(positionID: position.id, verifiedThrough: 120_000, liquidated: false, hold: .missingHistory)
        ])
      )
    )
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
    var closed = try FuturesHistoryCheckState.initial(for: first)
    closed.liquidation = .init(
      intervalStart: 60_000,
      intervalEndExclusive: 120_000,
      observedLiquidationPrice: 1,
      settledAt: Date()
    )
    let snapshot = FuturesAccountSnapshot(
      revision: 3,
      accounts: [.init(id: account, availableBalance: 1000)],
      positions: [first, other],
      historyCheckStates: [closed, try .initial(for: other)]
    )
    reactor.stub.state.value = reactor.reduce(state: reactor.initialState, mutation: .snapshot(snapshot, [:]))
    XCTAssertTrue(reactor.positions.isEmpty)
  }

  func testOrderBlocksOppositeDirectionAndLocksLeverageAndBlocksAfterLiquidation() throws {
    let reactor = reactor()
    let position = try FuturesCalculator.open(domesticFuturesOrder(side: .short, leverage: 50))
    // 테스트 포지션의 검증 시점과 청산 결과를 설정한다.
    let historyCheck = try FuturesHistoryCheckState.initial(for: position)
    let snapshot = FuturesAccountSnapshot(
      revision: 3,
      accounts: [.init(id: account, availableBalance: 1000)],
      positions: [position],
      historyCheckStates: [historyCheck]
    )
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
    var liquidated = historyCheck
    liquidated.liquidation = .init(
      intervalStart: 60_000,
      intervalEndExclusive: 120_000,
      observedLiquidationPrice: 200_000_000,
      settledAt: Date()
    )
    let after = FuturesAccountSnapshot(
      revision: 4,
      accounts: snapshot.accounts,
      positions: [position],
      historyCheckStates: [liquidated]
    )
    reactor.stub.state.value = reactor.reduce(state: state, mutation: .snapshot(after, [:]))
    XCTAssertFalse(submit.isEnabled)
  }

  func testNewOrderScreenDoesNotReopenAfterItsFirstPositionIsLiquidated() throws {
    let reactor = reactor()
    let position = try FuturesCalculator.open(domesticFuturesOrder())
    let cash = [FuturesCashAccount(id: account, availableBalance: 1_000_000)]
    var state = reactor.reduce(
      state: reactor.initialState,
      mutation: .snapshot(.init(revision: 1, accounts: cash), [:])
    )
    state.status = .finished([])
    reactor.stub.state.value = state
    let controller = FuturesOrderViewController(reactor: reactor, instrument: position.order.instrument)
    controller.loadViewIfNeeded()
    let submit = try XCTUnwrap(
      descendants(controller.view).first { $0.accessibilityIdentifier == "futuresSubmit" } as? UIButton
    )
    var verification = try FuturesHistoryCheckState.initial(for: position)
    let opened = FuturesAccountSnapshot(
      revision: 2,
      accounts: cash,
      positions: [position],
      historyCheckStates: [verification]
    )
    state = reactor.reduce(state: state, mutation: .snapshot(opened, [:]))
    reactor.stub.state.value = state
    verification.liquidation = .init(
      intervalStart: 60_000,
      intervalEndExclusive: 120_000,
      observedLiquidationPrice: 1,
      settledAt: Date()
    )
    let liquidated = FuturesAccountSnapshot(
      revision: 3,
      accounts: cash,
      positions: [position],
      historyCheckStates: [verification]
    )
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
    let trade = TradeReactor(
      selectCrypto: .init(cryptoName: "Bitcoin", market: "BTC/KRW", tradePrice: 100_000_000),
      cmcInformation: nil,
      cryptoDetailUseCase: CryptoDetailUseCase(cryptoDetailRepository: CryptoDetailRepository()),
      mainUseCase: MainUseCase(mainRepository: MainRepository())
    )
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
    XCTAssertEqual(
      orderView.segmentedControl.segments,
      ["futures_long", "futures_short", "futures_history"].map(FuturesText.text)
    )
    XCTAssertTrue(orderView.investLiveView.isHidden)
    XCTAssertNil(orderView.bidView)
    XCTAssertNil(orderView.askView)
    XCTAssertGreaterThan(controller.view.bounds.height, 300)
    XCTAssertGreaterThan(controller.view.bounds.width, 0)
    let submit = try XCTUnwrap(
      descendants(controller.view).first { $0.accessibilityIdentifier == "futuresSubmit" } as? UIButton
    )
    orderView.segmentedControl.onSegmentChanged?(1)
    XCTAssertEqual(submit.configuration?.title, FuturesText.text("futures_enter_short"))
    orderView.segmentedControl.onSegmentChanged?(2)
    XCTAssertTrue(
      descendants(controller.view).compactMap { $0 as? UILabel }.contains {
        $0.text == FuturesText.text("futures_empty_history")
      }
    )
    orderView.segmentedControl.onSegmentChanged?(0)
    window.layoutIfNeeded()
    orderView.layoutIfNeeded()
    controller.view.layoutIfNeeded()
    let scroll = try XCTUnwrap(controller.view.subviews.first as? UIScrollView)
    XCTAssertGreaterThan(scroll.bounds.height, 200)
    scroll.layoutIfNeeded()
    let image = UIGraphicsImageRenderer(bounds: orderView.bounds).image { context in
      orderView.layer.render(in: context.cgContext)
    }
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
    let service = FuturesHistoryCheckService(store: { store }, provider: { _ in provider })
    let useCase = FuturesTradingUseCase(store: { store }, historyCheck: service)
    let reactor = FuturesAccountReactor(account: account, useCase: useCase, historyCheck: service, provider: provider)
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

  @MainActor
  func testSocketQuotesUpdatePositionCardWhileRESTAndHistoricalVerificationArePending() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalFuturesAccountRepository(fileURL: directory.appendingPathComponent("accounts.json"))
    let order = domesticFuturesOrder(margin: 100, price: 100)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    let saved = try store.openTestPosition(order, expectedRevision: store.snapshot().revision)
    let provider = PendingFuturesQuoteProvider()
    let monitor = FuturesAccountMonitorFixture()
    let service = FuturesHistoryCheckService(store: { store }, provider: { _ in provider }, monitor: monitor)
    let useCase = FuturesTradingUseCase(store: { store }, historyCheck: service)
    let reactor = FuturesAccountReactor(account: account, useCase: useCase, historyCheck: service, provider: provider)
    let loaded = expectation(description: "Position loaded without waiting for REST")
    let bag = DisposeBag()
    reactor.state.filter { $0.snapshot == saved }.take(1).subscribe(onNext: { _ in loaded.fulfill() }).disposed(by: bag)
    wait(for: [loaded], timeout: 3)
    let controller = FuturesOrderViewController(reactor: reactor, instrument: order.instrument)
    controller.loadViewIfNeeded()
    func label(_ key: String) throws -> UILabel {
      try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == key } as? UILabel)
    }
    monitor.subject.onNext(.connection(.upbit, true))
    let timestamp = try FuturesHistoryCheckState.milliseconds(Date()) - 1000
    for (price, profit, rate) in [(Decimal(110), "+100", "+100%"), (Decimal(105), "+50", "+50%")] {
      let updated = expectation(description: "Socket price immediately updates card")
      reactor.state.filter { $0.quotes[order.instrument]?.price == price }.take(1)
        .subscribe(onNext: { _ in DispatchQueue.main.async { updated.fulfill() } }).disposed(by: bag)
      monitor.subject.onNext(.quote(.init(instrument: order.instrument, price: price, timestamp: timestamp)))
      wait(for: [updated], timeout: 3)
      XCTAssertEqual(try label("futures_pnl").text, profit)
      XCTAssertEqual(try label("futures_roe").text, rate)
      XCTAssertEqual(try label("futures_current").text, FuturesText.number(price))
      if case .refreshing = reactor.currentState.status {} else { XCTFail("History should still be pending") }
      XCTAssertEqual(try store.snapshot(), saved)
    }
    provider.quotes.onError(FuturesMarketDataError.invalidResponse)
    service.suspend()
  }

  @MainActor
  func testSocketPriceWithClockDifferenceUpdatesValuationWithoutEnablingSettlement() throws {
    // 운영 계좌와 분리된 저장소로 표시만 갱신되고 정산은 차단되는지 확인한다.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    // 소켓 표시가 저장된 자산을 변경해서는 안 된다.
    let store = LocalFuturesAccountRepository(fileURL: directory.appendingPathComponent("accounts.json"))
    // 작은 숫자로 손익과 총평가의 계산 결과를 명확히 확인한다.
    let order = domesticFuturesOrder(margin: 100, price: 100)
    try store.applyAdvertisementReward(AdRewardClaim(account: order.account))
    // 평가 갱신 전후 비교할 원본 포지션과 잔고다.
    let saved = try store.openTestPosition(order, expectedRevision: store.snapshot().revision)
    // REST와 과거 검증을 기다리는 중에도 실시간 평가는 가능해야 한다.
    let provider = PendingFuturesQuoteProvider()
    // 거래소 소켓과 같은 가격·체결 시각·ticker 시각을 전달한다.
    let monitor = FuturesAccountMonitorFixture()
    // 기기보다 거래소 시각이 앞서는 상황을 고정한다.
    let now = Date()
    // 표시 시세와 정산 검증의 경계를 확인할 서비스다.
    let service = FuturesHistoryCheckService(store: { store }, provider: { _ in provider }, now: { now }, monitor: monitor)
    defer { service.suspend() }
    // 검증 서비스와 같은 계좌 저장소를 사용한다.
    let useCase = FuturesTradingUseCase(store: { store }, historyCheck: service)
    // 주문 카드와 투자내역이 공유하는 시세 상태다.
    let reactor = FuturesAccountReactor(account: account, useCase: useCase, historyCheck: service, provider: provider)
    // 포지션 조회 후 소켓 이벤트를 전달한다.
    let loaded = expectation(description: "Saved position loaded")
    // 테스트가 끝나면 시세와 계좌 구독을 함께 정리한다.
    let disposeBag = DisposeBag()
    reactor.state.filter { $0.snapshot == saved }.take(1).subscribe(onNext: { _ in loaded.fulfill() }).disposed(by: disposeBag)
    wait(for: [loaded], timeout: 3)
    // 실제 카드 라벨이 — 대신 현재가와 손익을 표시하는지 확인한다.
    let controller = FuturesOrderViewController(reactor: reactor, instrument: order.instrument)
    controller.loadViewIfNeeded()
    monitor.subject.onNext(.connection(.upbit, true))
    // 거래소에서 보내온 ticker 시각은 기기보다 1초 앞선 것으로 재현한다.
    let timestamp = try FuturesHistoryCheckState.milliseconds(now) + 1000
    for (price, tradeTimestamp) in [(Decimal(105), timestamp), (Decimal(110), Int64(0))] {
      // 같은 체결 시각의 ticker 갱신도 최신 가격으로 반영한다.
      let updated = expectation(description: "Socket price reaches position valuation")
      reactor.state.filter { $0.quotes[order.instrument]?.price == price }.take(1)
        .subscribe(onNext: { _ in DispatchQueue.main.async { updated.fulfill() } }).disposed(by: disposeBag)
      if tradeTimestamp == 0 {
        service.observe(
          .init(instrument: order.instrument, price: price, timestamp: tradeTimestamp),
          displayTimestamp: timestamp
        )
      } else {
        monitor.subject.onNext(
          .quote(
            .init(instrument: order.instrument, price: price, timestamp: tradeTimestamp),
            displayTimestamp: timestamp
          )
        )
      }
      wait(for: [updated], timeout: 3)
      // 카드와 총평가는 같은 표시 시세를 사용한다.
      let quotes = reactor.currentState.quotes
      XCTAssertEqual(quotes[order.instrument]?.timestamp, timestamp)
      XCTAssertEqual(try FuturesText.valuation(saved.positions[0], quotes: quotes)?.displayedPnL, (price - 100) * 10)
      XCTAssertEqual(
        try saved.valuation(for: account, quotes: quotes, now: now, forDisplay: true).positionsEquity,
        100 + (price - 100) * 10
      )
      XCTAssertThrowsError(try saved.valuation(for: account, quotes: quotes, now: now))
      XCTAssertEqual(
        (descendants(controller.view).first { $0.accessibilityIdentifier == "futures_current" } as? UILabel)?.text,
        FuturesText.number(price)
      )
      XCTAssertEqual(
        (descendants(controller.view).first { $0.accessibilityIdentifier == "futures_pnl" } as? UILabel)?.text,
        "+" + FuturesText.number((price - 100) * 10)
      )
      XCTAssertThrowsError(
        try store.liquidateObservedQuote(
          .init(instrument: order.instrument, price: 1, timestamp: tradeTimestamp),
          settledAt: now
        )
      )
      XCTAssertEqual(try store.snapshot(), saved)
    }
    provider.quotes.onError(FuturesMarketDataError.invalidResponse)
  }

  func testLiveQuoteMergeKeepsNewerSocketPriceAndIgnoresOtherAccountsAndClosedPositions() throws {
    let reactor = reactor()
    let position = try FuturesCalculator.open(domesticFuturesOrder())
    let other = try FuturesCalculator.open(domesticFuturesOrder(exchange: .bithumb))
    let snapshot = FuturesAccountSnapshot(
      revision: 1,
      accounts: [.init(id: account, availableBalance: 900_000)],
      positions: [position, other],
      historyCheckStates: [try .initial(for: position), try .initial(for: other)]
    )
    let instrument = position.order.instrument
    let quote = FuturesMarkQuote(instrument: instrument, price: 110_000_000, timestamp: 120_000)
    var state = reactor.reduce(state: reactor.initialState, mutation: .snapshot(snapshot, nil))
    state = reactor.reduce(state: state, mutation: .quote(quote))
    for invalid in [
      FuturesMarkQuote(instrument: instrument, price: 100_000_000, timestamp: 119_999),
      .init(instrument: instrument, price: .nan, timestamp: 120_001),
      .init(instrument: instrument, price: 0, timestamp: 120_001),
      .init(instrument: other.order.instrument, price: 120_000_000, timestamp: 120_001)
    ] {
      state = reactor.reduce(state: state, mutation: .quote(invalid))
      XCTAssertEqual(state.quotes, [instrument: quote])
    }
    for timestamp in [Int64(119_999), 120_000] {
      state = reactor.reduce(
        state: state,
        mutation: .snapshot(snapshot, [instrument: .init(instrument: instrument, price: 100_000_000, timestamp: timestamp)])
      )
      XCTAssertEqual(state.quotes, [instrument: quote])
    }
    XCTAssertEqual(state.snapshot, snapshot)
    let closed = FuturesAccountSnapshot(revision: 2, accounts: snapshot.accounts)
    state = reactor.reduce(state: state, mutation: .snapshot(closed, nil))
    state = reactor.reduce(state: state, mutation: .quote(quote))
    XCTAssertTrue(state.quotes.isEmpty)
    XCTAssertEqual(state.snapshot, closed)
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
      accounts: [
        .init(id: account, availableBalance: 900_000), .init(id: other.order.account, availableBalance: 50_000_000)
      ],
      positions: [position, other],
      historyCheckStates: [try .initial(for: position), try .initial(for: other)]
    )
    let time = try FuturesHistoryCheckState.milliseconds(Date())
    let quotes = [
      position.order.instrument: FuturesMarkQuote(
        instrument: position.order.instrument,
        price: 110_000_000,
        timestamp: time
      )
    ]
    futures.stub.state.value = futures.reduce(state: futures.initialState, mutation: .snapshot(snapshot, quotes))
    let spotHolding = CryptoTransactionDataModel(
      staticData: .init(
        exchange: .upbit,
        marketName: "BTC/KRW",
        cryptoName: "Bitcoin",
        holdingQuantity: 5,
        averageBuyPrice: 1,
        buyAmount: 5
      ),
      dynamicData: .init(
        exchange: .upbit,
        marketName: "BTC/KRW",
        profitRate: 0,
        evaluationProfitLoss: 0,
        evaluationPrice: 500_000_000
      )
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
      let label = try XCTUnwrap(
        descendants(controller.view).first { $0.accessibilityIdentifier == identifier } as? UILabel
      )
      return label.attributedText?.string ?? label.text ?? ""
    }
    XCTAssertTrue(descendants(controller.view).contains { ($0 as? UILabel)?.text == FuturesText.text("futures_total_evaluation") })
    XCTAssertTrue(try summary("futures.main.margin").contains("100,000"))
    XCTAssertTrue(try summary("futures.main.equity").contains("200,000"))
    XCTAssertTrue(try summary("futures.main.pnl").contains("100,000"))
    XCTAssertTrue(try summary("futures.main.roe").contains("100"))
    let stale = [
      position.order.instrument: FuturesMarkQuote(
        instrument: position.order.instrument,
        price: 110_000_000,
        timestamp: time - 31_000
      )
    ]
    futures.stub.state.value = futures.reduce(state: futures.currentState, mutation: .snapshot(snapshot, stale))
    XCTAssertEqual(controller.selectedTab, .hold)
    XCTAssertEqual(market.currentState.totalCryptoList.count, 2)
    XCTAssertEqual(futures.currentState.quotes[position.order.instrument]?.timestamp, time)
    futures.stub.state.value = futures.reduce(state: futures.currentState, mutation: .snapshot(snapshot, [:]))
    futures.stub.state.value = futures.reduce(state: futures.currentState, mutation: .status(.refreshing))
    flushDisplay()
    XCTAssertEqual(controller.dataSource?.snapshot().itemIdentifiers.first?.evaluationPrice, 200_000)
    XCTAssertTrue(try summary("futures.main.equity").contains("200,000"))
    // 손실이 나도 총평가는 현금을 제외한 증거금과 평가손익의 합이어야 한다.
    let lossQuote = FuturesMarkQuote(
      instrument: position.order.instrument,
      price: 95_000_000,
      timestamp: try FuturesHistoryCheckState.milliseconds(Date())
    )
    futures.stub.state.value = futures.reduce(state: futures.currentState, mutation: .quote(lossQuote))
    flushDisplay()
    XCTAssertEqual(try summary("futures.main.equity"), "50,000 원")
    XCTAssertTrue(try summary("futures.main.pnl").contains("-50,000"))
    let cashOnly = FuturesAccountSnapshot(revision: 2, accounts: [.init(id: account, availableBalance: 10_000_000)])
    futures.stub.state.value = futures.reduce(state: futures.currentState, mutation: .snapshot(cashOnly, [:]))
    flushDisplay()
    XCTAssertTrue(controller.tableView.isHidden)
    XCTAssertEqual(try summary("futures.main.equity"), "0 원")
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
    let snapshot = FuturesAccountSnapshot(
      revision: 1,
      accounts: [
        .init(id: account, availableBalance: 900_000),
        .init(id: other.order.account, availableBalance: 50_000_000)
      ],
      positions: [position, other],
      historyCheckStates: [try .initial(for: position), try .initial(for: other)]
    )
    let timestamp = try FuturesHistoryCheckState.milliseconds(Date())
    let quotes = [
      position.order.instrument: FuturesMarkQuote(
        instrument: position.order.instrument,
        price: 110_000_000,
        timestamp: timestamp
      )
    ]
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
    XCTAssertEqual(controller.totalEvaluationTitle.text, FuturesText.text("futures_total_evaluation"))
    XCTAssertNotEqual(controller.totalEvaluationTitle.text, "futures_total_evaluation")
    flushDisplay()
    XCTAssertEqual(controller.totalUserBalance.text, "200,000 원")
    XCTAssertEqual(controller.availableUserBalance.text, "900,000 원")
    XCTAssertEqual(controller.totalBuyPrice.text, "100,000 원")
    XCTAssertEqual(controller.totalEvalProfitLoss.text, "100,000 원")
    XCTAssertEqual(controller.totalProfitRate.text, "100 %")
    XCTAssertTrue(controller.noResultView.isHidden)
    XCTAssertEqual(controller.transactionTableview.numberOfRows(inSection: 0), 1)
    let cell = try XCTUnwrap(
      controller.transactionTableview.dataSource?.tableView(
        controller.transactionTableview,
        cellForRowAt: IndexPath(row: 0, section: 0)
      ) as? InvestmentTableViewCell
    )
    XCTAssertTrue(cell.cryptoName.text?.contains(FuturesText.text("futures_long")) == true)
    XCTAssertEqual(cell.cryptoBuyPrice.text, "100,000 원")
    XCTAssertEqual(cell.cryptoEvalPrice.text, "200,000 원")
    XCTAssertEqual(cell.cryptoProfitRate.text, "100 %")
    XCTAssertEqual(cell.averagePriceTitle.text, FuturesText.text("futures_entry") + " : ")
    for style in [UIUserInterfaceStyle.dark, .light] {
      controller.overrideUserInterfaceStyle = style
      // 작은 기기와 일반 기기의 요약 행 너비를 각각 검증한다.
      for width in [320.0, 375.0] {
        window.frame.size.width = width
        controller.view.layoutIfNeeded()
        controller.chargeButton.layoutIfNeeded()
        XCTAssertGreaterThanOrEqual(controller.chargeButton.bounds.height, 44)
        XCTAssertGreaterThanOrEqual(
          controller.chargeButton.bounds.width,
          controller.chargeButton.intrinsicContentSize.width - 0.5
        )
        XCTAssertEqual(controller.chargeButton.configuration?.title, FuturesText.text("investment_recharge"))
        XCTAssertEqual(controller.chargeButton.accessibilityLabel, FuturesText.text("futures_charge"))
        // 작은 화면에서도 충전 버튼과 평가 금액이 겹치지 않는지 시각적으로 확인한다.
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image {
          controller.view.layer.render(in: $0.cgContext)
        }
        // 현물과 공유하는 레이아웃의 다크·라이트 모드 검증 결과를 보관한다.
        let attachment = XCTAttachment(image: image)
        attachment.name = "Futures investment \(style == .dark ? "dark" : "light") \(Int(width))"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
    }
    let stale = [
      position.order.instrument: FuturesMarkQuote(
        instrument: position.order.instrument,
        price: 110_000_000,
        timestamp: timestamp - 31_000
      )
    ]
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .snapshot(snapshot, stale))
    flushDisplay()
    XCTAssertEqual(controller.totalUserBalance.text, "200,000 원")
    XCTAssertEqual(controller.totalProfitRate.text, "100 %")
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .snapshot(snapshot, [:]))
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .status(.refreshing))
    flushDisplay()
    XCTAssertEqual(controller.totalUserBalance.text, "200,000 원")
    XCTAssertEqual(controller.totalEvalProfitLoss.text, "100,000 원")
    XCTAssertEqual(controller.totalBuyPrice.text, "100,000 원")
    XCTAssertEqual(controller.availableUserBalance.text, "900,000 원")
    // 투자내역의 총평가도 현재 보유 포지션의 손실만 반영한다.
    let lossQuote = FuturesMarkQuote(
      instrument: position.order.instrument,
      price: 95_000_000,
      timestamp: try FuturesHistoryCheckState.milliseconds(Date())
    )
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .quote(lossQuote))
    flushDisplay()
    XCTAssertEqual(controller.totalUserBalance.text, "50,000 원")
    XCTAssertEqual(controller.totalEvalProfitLoss.text, "-50,000 원")
    XCTAssertEqual(controller.availableUserBalance.text, "900,000 원")
    let empty = FuturesAccountSnapshot(revision: 2, accounts: [.init(id: account, availableBalance: 1_000_000)])
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .snapshot(empty, [:]))
    flushDisplay()
    XCTAssertEqual(controller.totalUserBalance.text, "0 원")
    XCTAssertEqual(controller.availableUserBalance.text, "1,000,000 원")
    XCTAssertEqual(controller.totalBuyPrice.text, "0 원")
    XCTAssertEqual(controller.totalProfitRate.text, "0 %")
    XCTAssertFalse(controller.noResultView.isHidden)
    XCTAssertEqual(controller.emptyLabel.text, FuturesText.text("futures_no_position"))
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .loadFailed)
    flushDisplay()
    XCTAssertEqual(controller.emptyLabel.text, FuturesText.text("futures_storage_error"))
  }

  @MainActor
  func testFuturesRealizedHistoryAndShareShowLiquidationOccurrenceOnlyToTheMinute() throws {
    let reactor = reactor()
    let position = try FuturesCalculator.open(domesticFuturesOrder(side: .short))
    // 테스트 포지션의 검증 시점과 청산 결과를 설정한다.
    var historyCheck = try FuturesHistoryCheckState.initial(for: position)
    historyCheck.verifiedThrough = 120_000
    historyCheck.lastVerifiedMark = 120_000_000
    historyCheck.liquidation = .init(
      intervalStart: 60_000,
      intervalEndExclusive: 120_000,
      observedLiquidationPrice: 120_000_000,
      settledAt: Date(timeIntervalSince1970: 300)
    )
    let snapshot = FuturesAccountSnapshot(
      revision: 1,
      accounts: [.init(id: account, availableBalance: 900_000)],
      positions: [position],
      historyCheckStates: [historyCheck]
    )
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
    let cell = try XCTUnwrap(
      controller.tableView(controller.pnlTableView, cellForRowAt: IndexPath(row: 0, section: 0)) as? PNLTableViewCell
    )
    XCTAssertEqual(cell.pnlLabel.text, "-100,000 원")
    XCTAssertTrue(cell.marketNameLabel.text?.contains(FuturesText.text("futures_short")) == true)
    XCTAssertTrue(cell.marketNameLabel.text?.contains(FuturesText.text("futures_liquidation")) == true)
    XCTAssertEqual(cell.exitTitle.text, FuturesText.text("futures_liquidation_exit_price") + " :")
    XCTAssertEqual(cell.entryTitle.text, FuturesText.text("futures_entry_price") + " :")
    XCTAssertEqual(cell.dateTitle.text, FuturesText.text("investment_execution_time") + " :")
    XCTAssertEqual(cell.transactionDateLabel.numberOfLines, 1)
    XCTAssertEqual((cell.transactionDateLabel.superview as? UIStackView)?.axis, .horizontal)
    XCTAssertEqual(cell.metricsStackView.arrangedSubviews.count, 2)
    XCTAssertEqual(cell.transactionDateLabel.text, String(FuturesText.date(Date(timeIntervalSince1970: 60)).dropLast(3)))
    XCTAssertFalse(cell.transactionDateLabel.text?.contains("~") == true)
    XCTAssertFalse(cell.transactionDateLabel.text?.contains(FuturesText.text("futures_settled")) == true)
    XCTAssertNotNil(cell.shareCallBack)
    let record = try XCTUnwrap(snapshot.transactionHistory(for: account).last)
    XCTAssertEqual(record.occurredMinute, 60_000)
    let unit = try FuturesText.shareUnit(record, position: position)
    XCTAssertEqual(unit.transactionDate, cell.transactionDateLabel.text)
    XCTAssertEqual(unit.roi, -100)
    XCTAssertEqual(unit.product, .perpetual)
    let share = PNLShareView.instanceFromNib(pnlShareUnit: unit) { _ in }
    XCTAssertEqual(share.entryTitle.text, FuturesText.text("futures_entry"))
    let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image {
      controller.view.layer.render(in: $0.cgContext)
    }
    let attachment = XCTAttachment(image: image)
    attachment.name = "Futures realized liquidation history"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func testShortRealizedShareUsesMarginReturnRatherThanSpotPriceChange() throws {
    let position = try FuturesCalculator.open(domesticFuturesOrder(side: .short, leverage: 10))
    let record = FuturesTransactionRecord(
      eventID: UUID(),
      positionID: position.id,
      kind: .closing,
      instrument: position.order.instrument,
      side: .short,
      leverage: 10,
      quantity: position.quantity,
      intervalStart: 120_000,
      intervalEndExclusive: nil,
      recordedAt: Date(timeIntervalSince1970: 300),
      price: 90_000_000,
      realizedPnL: 100_000
    )
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
    XCTAssertEqual(controller.totalEvaluationTitle.text, "총 보유자산")
    XCTAssertEqual(controller.emptyLabel.text, "보유중인 코인이 없습니다.")
    let cell = try XCTUnwrap(
      UINib(nibName: "InvestmentTableViewCell", bundle: nil).instantiate(withOwner: nil).first
        as? InvestmentTableViewCell
    )
    XCTAssertEqual(cell.buyPriceTitle.text, "매수금액 : ")
    // 화면 진입 부수 효과 없이 XIB 레이아웃을 실제 윈도우에서 검증한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 812))
    window.rootViewController = UIViewController()
    window.rootViewController?.view.addSubview(controller.view)
    window.makeKeyAndVisible()
    controller.view.frame = window.bounds
    defer { window.isHidden = true }
    XCTAssertEqual(controller.view.bounds.width, 320)
    for style in [UIUserInterfaceStyle.dark, .light] {
      controller.overrideUserInterfaceStyle = style
      controller.view.layoutIfNeeded()
      controller.chargeButton.layoutIfNeeded()
      XCTAssertGreaterThanOrEqual(controller.chargeButton.bounds.height, 44)
      XCTAssertGreaterThanOrEqual(
        controller.chargeButton.bounds.width,
        controller.chargeButton.intrinsicContentSize.width - 0.5
      )
      XCTAssertEqual(controller.chargeButton.configuration?.title, FuturesText.text("investment_recharge"))
      // 현물 화면도 동일한 캡슐 버튼을 사용하는지 검증할 이미지를 만든다.
      let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image {
        controller.view.layer.render(in: $0.cgContext)
      }
      // 작은 화면의 두 테마를 테스트 결과에서 바로 비교한다.
      let attachment = XCTAttachment(image: image)
      attachment.name = "Spot investment \(style == .dark ? "dark" : "light") 320"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
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

  @MainActor
  func testFuturesPNLRestoresTradingControlsWhenDisappearanceBegins() throws {
    // 외부 네트워크 없이 선물 Coordinator의 PNL 진입 경로를 사용한다.
    let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
    market.isStubEnabled = true
    // PNL 화면의 복원 요청을 전달할 선물 Coordinator다.
    let coordinator = FuturesCoordinator(reactor: reactor(), marketReactor: market)
    coordinator.investmentNavigationController.viewControllers = [UIViewController()]
    // 현물·선물 스위치와 하단 탭바가 들어 있는 실제 컨테이너다.
    let container = MobitTabBarViewController()
    container.setViewControllers([UIViewController(), coordinator.investmentNavigationController], selectedIndex: 1)
    container.setProduct(.perpetual)
    // 앱과 동일하게 Coordinator의 표시 요청을 컨테이너에 전달한다.
    let delegate = FuturesTradingControlsDelegateFixture(container: container)
    coordinator.delegate = delegate
    coordinator.openPNL()
    // 복귀 시 viewWillDisappear를 전달할 실제 PNL 화면이다.
    let pnl = try XCTUnwrap(coordinator.investmentNavigationController.topViewController as? PNLViewController)
    pnl.beginAppearanceTransition(true, animated: false)
    pnl.endAppearanceTransition()
    // 표시 상태를 함께 확인할 현물·선물 스위치다.
    let selector = try XCTUnwrap(descendants(container.view).first { $0.accessibilityIdentifier == "tradingProductSelector" })
    XCTAssertTrue(container.mobitTabBar.isHidden)
    XCTAssertTrue(selector.isHidden)
    // disappearance 완료나 navigation didShow를 호출하기 전에 복원이 끝나야 한다.
    pnl.beginAppearanceTransition(false, animated: true)
    XCTAssertFalse(container.mobitTabBar.isHidden)
    XCTAssertFalse(selector.isHidden)
    XCTAssertEqual(coordinator.investmentNavigationController.additionalSafeAreaInsets.bottom, 76)
    pnl.endAppearanceTransition()
    XCTAssertFalse(container.mobitTabBar.isHidden)
  }

}

private final class FuturesTradingControlsDelegateFixture: MainCoordinatorDelegate {
  // 실제 탭바·스위치 표시 상태를 갱신할 컨테이너다.
  private let container: MobitTabBarViewController

  init(container: MobitTabBarViewController) { self.container = container }

  func mainCoordinatorDidRequestHideTabBar() { container.setTradingChromeHidden(true) }
  func mainCoordinatorDidRequestShowTabBar() { container.setTradingChromeHidden(false) }
}

private final class PendingFuturesQuoteProvider: FuturesMarketDataProviding {
  let quotes = PublishSubject<FuturesMarkQuote>()
  func markQuote(_ instrument: TradingInstrumentID) -> Single<FuturesMarkQuote> { quotes.take(1).asSingle() }
  func contract(_ instrument: TradingInstrumentID) -> Single<FuturesMarketContract> {
    .error(FuturesMarketDataError.unsupportedInstrument)
  }
  func markCandles(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<
    FuturesHistoryPage<FuturesMarkCandle>
  > {
    .error(FuturesMarketDataError.unsupportedInstrument)
  }
  func funding(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<
    FuturesHistoryPage<FuturesFundingEvent>
  > {
    .error(FuturesMarketDataError.unsupportedInstrument)
  }
}

private final class FuturesAccountMonitorFixture: FuturesPositionMonitoring {
  let subject = PublishSubject<FuturesMonitorEvent>()
  var events: Observable<FuturesMonitorEvent> { subject.asObservable() }
  func watch(_ instruments: [TradingInstrumentID]) {}
  func suspend() {}
}

private final class FuturesMainFixtureUseCase: MainUseCase {
  private let markets: CryptoList
  private let tickers: CryptoTickerList
  // 지연·실패 응답으로 초기 준비와 재시도 순서를 검증한다.
  var marketResponse: Observable<CryptoList>?
  // 로딩 중 중복 조회가 시작되지 않는지 확인한다.
  private(set) var marketRequests = 0

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

  // 네트워크 대신 테스트용 마켓 목록을 반환한다.
  override func fetchCryptoList() -> Observable<CryptoList> {
    marketRequests += 1
    return marketResponse ?? .just(markets)
  }
  // 네트워크 대신 테스트용 시세 목록을 반환한다.
  override func fetchCryptoTicker(markets: [String]) -> Observable<CryptoTickerList> { .just(tickers) }
  // 이 테스트에서는 공포·탐욕 지수 이벤트를 발생시키지 않는다.
  override func fetchFearGreedIndex() -> Observable<FearGreedIndex> { .never() }
}

private final class FuturesMainFixtureSocket: TickerSocketServiceProtocol {
  var isConnected = false
  let ticks = PublishSubject<CryptoSocketTicker>()
  var stream: Observable<CryptoSocketTicker> { ticks.asObservable() }
  func connect() { isConnected = true }
  func disconnect(userInitiated: Bool) { isConnected = false }
  func reconnectIfNeeded() { connect() }
  func subscribe(markets: [String]) {}
}
