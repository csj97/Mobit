import XCTest
import UIKit
import ReactorKit
import RxSwift
import SnapKit
import GoogleMobileAds
import SkeletonView
@testable import Mobit

final class FuturesAccountReactorTests: XCTestCase {
  @MainActor
  func testSpotInvestmentForegroundResumesMainSocketButDetailUsesOnlyItsOwnSocket() {
    // 다른 테스트의 상품 선택을 복구한다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    ExchangeSelectionStore.currentProduct = .spot
    defer { ExchangeSelectionStore.currentProduct = previousProduct }
    // 현물 평가를 갱신하는 메인 소켓 제어 대상이다.
    let main = LifecycleSocketViewControllerFixture()
    // 투자내역처럼 별도 소켓이 없는 탭이다.
    let investment = UIViewController()
    // 실제 앱과 같은 탭·내비게이션 계층에서 제어 대상을 찾는다.
    let tabs = MobitTabBarViewController()
    tabs.setViewControllers([
      UINavigationController(rootViewController: main),
      UINavigationController(rootViewController: investment)
    ], selectedIndex: 1)
    tabs.controlSocket(appState: .background)
    tabs.controlSocket(appState: .foreground)
    XCTAssertEqual(main.pauses, 1)
    XCTAssertEqual(main.resumes, 1)
    // 거래 상세에서는 메인 소켓을 다시 연결하면 중복 구독이 된다.
    let detail = LifecycleSocketViewControllerFixture()
    tabs.setViewControllers([
      UINavigationController(rootViewController: main),
      UINavigationController(rootViewController: detail)
    ], selectedIndex: 1)
    tabs.controlSocket(appState: .background)
    tabs.controlSocket(appState: .foreground)
    XCTAssertEqual(main.pauses, 1)
    XCTAssertEqual(main.resumes, 1)
    XCTAssertEqual(detail.pauses, 1)
    XCTAssertEqual(detail.resumes, 1)
  }

  @MainActor
  func testExchangeSwitchKeepsSpotInvestmentSelectedAndPreparesMainPriceBinding() throws {
    // 테스트가 바꾼 거래소와 상품 선택을 종료 시 복구한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    // 계좌 전환 경로는 현물 투자내역을 기준으로 검사한다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    ExchangeSelectionStore.currentExchange = .upbit
    ExchangeSelectionStore.currentProduct = .spot
    // 실제 상위 Coordinator를 통해 탭 재구성 경로를 실행한다.
    let navigation = UINavigationController()
    // 투자내역을 유지하면서 메인 시세 바인딩을 준비하는 대상이다.
    let coordinator = AppTabBarCoordinator(navigationController: navigation)
    // 거래소 버튼이 실제 시스템 시트를 표시할 수 있는 화면 계층이다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
    window.rootViewController = navigation
    window.makeKeyAndVisible()
    defer {
      window.isHidden = true
      window.rootViewController = nil
      coordinator.childCoordinators.compactMap { $0 as? MainCoordinator }.forEach { $0.disconnectSocket() }
      ExchangeSelectionStore.currentExchange = previousExchange
      ExchangeSelectionStore.currentProduct = previousProduct
      UserDataManager.publishCurrentExchangeBalance()
    }
    coordinator.start()
    // 투자내역에서 거래소를 고른 상황을 재현한다.
    let tabs = try XCTUnwrap(navigation.viewControllers.first as? MobitTabBarViewController)
    tabs.switchToTab(index: 1)
    func checkSelectedExchange(_ exchange: Exchange) throws {
      // 전환 때마다 새로 구성된 투자내역 화면의 버튼을 검사한다.
      let controller = try XCTUnwrap(
        coordinator.childCoordinators.compactMap { $0 as? InvestmentCoordinator }.first?
          .navigationController.viewControllers.first as? InvestmentViewController
      )
      try assertInvestmentExchangeButton(in: controller, exchange: exchange)
    }
    func confirmExchange(_ exchange: Exchange) throws {
      // 현재 투자내역의 버튼을 통해 선택부터 확인까지 실제 경로를 검사한다.
      let controller = try XCTUnwrap(
        coordinator.childCoordinators.compactMap { $0 as? InvestmentCoordinator }.first?
          .navigationController.viewControllers.first as? InvestmentViewController
      )
      // 확인 전에는 기존 계좌가 유지돼야 한다.
      let previous = ExchangeSelectionStore.currentExchange
      // 현재 화면의 바텀시트 진입 버튼이다.
      let button = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIButton }.first {
        $0.accessibilityIdentifier == "investment.exchange"
      })
      button.sendActions(for: .touchUpInside)
      button.sendActions(for: .touchUpInside)
      // 중복 탭에도 시스템 시트 하나만 표시한다.
      let sheet = try XCTUnwrap(
        (controller.presentedViewController ?? navigation.presentedViewController) as? ExchangeSelectionSheetViewController
      )
      // 기기별 애니메이션 길이 대신 시트 표시 완료를 기다린다.
      let presented = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in !sheet.isBeingPresented && sheet.view.window != nil },
        object: nil
      )
      wait(for: [presented], timeout: 3)
      // 카드 선택은 계좌를 전환하는 확인 동작과 분리된다.
      let option = try XCTUnwrap(descendants(sheet.view).compactMap { $0 as? UIControl }.first {
        $0.accessibilityIdentifier == "investment.exchangeOption.\(exchange.rawValue)"
      })
      option.sendActions(for: .touchUpInside)
      XCTAssertEqual(ExchangeSelectionStore.currentExchange, previous)
      // dismiss 완료 뒤 기존 Coordinator가 탭과 시세를 함께 전환한다.
      let confirm = try XCTUnwrap(descendants(sheet.view).compactMap { $0 as? UIButton }.first {
        $0.accessibilityIdentifier == "investment.exchangeConfirm"
      })
      confirm.sendActions(for: .touchUpInside)
      // 모달 종료와 계좌 전환이 모두 반영되는 시점까지 기다린다.
      let switched = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          ExchangeSelectionStore.currentExchange == exchange && navigation.presentedViewController == nil
        },
        object: nil
      )
      wait(for: [switched], timeout: 3)
    }
    try checkSelectedExchange(.upbit)
    // 이전 거래소의 화면을 재사용하지 않는지도 함께 검사한다.
    let previousMain = try XCTUnwrap(
      coordinator.childCoordinators.compactMap { $0 as? MainCoordinator }.first?
        .navigationController.viewControllers.first as? MainViewController
    )
    try confirmExchange(.bithumb)
    // 새 거래소의 숨겨진 메인도 투자내역 시세를 반영할 바인딩이 준비돼야 한다.
    let main = try XCTUnwrap(
      coordinator.childCoordinators.compactMap { $0 as? MainCoordinator }.first?
        .navigationController.viewControllers.first as? MainViewController
    )
    XCTAssertEqual(tabs.selectedIndex, 1)
    XCTAssertEqual(ExchangeSelectionStore.currentExchange, .bithumb)
    XCTAssertEqual(ExchangeSelectionStore.currentProduct, .spot)
    XCTAssertFalse(main === previousMain)
    XCTAssertTrue(main.isViewLoaded)
    try checkSelectedExchange(.bithumb)
    try confirmExchange(.upbit)
    XCTAssertEqual(tabs.selectedIndex, 1)
    XCTAssertEqual(ExchangeSelectionStore.currentExchange, .upbit)
    try checkSelectedExchange(.upbit)
  }

  #if DEBUG
  @MainActor
  func testLiquidationNoticeAnalyticsRecordsOnlyVisibleOriginalAccountOnce() throws {
    // 기존 분석 수집 경로를 테스트 종료 시 복구한다.
    let previousEventCallBack = MobitAnalyticsUtil.eventCallBack
    // 안내의 원본 계좌와 전역 선택을 다르게 두고 기존 선택은 복구한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    // 현물 선택 중에도 표시 이벤트가 원본 선물 계좌를 사용해야 한다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    defer {
      MobitAnalyticsUtil.eventCallBack = previousEventCallBack
      ExchangeSelectionStore.currentExchange = previousExchange
      ExchangeSelectionStore.currentProduct = previousProduct
    }
    ExchangeSelectionStore.currentExchange = .upbit
    ExchangeSelectionStore.currentProduct = .spot
    // 실제 분석 전송 경계에서 안내 노출 이벤트만 수집한다.
    var events: [(name: String, parameters: [String: Any])] = []
    MobitAnalyticsUtil.eventCallBack = { name, parameters in
      if parameters["Step_depth_02"] as? String == "선물_청산안내_노출" {
        events.append((name, parameters))
      }
    }
    // 최초에는 화면·계좌 표시 조건이 아직 준비되지 않은 상태다.
    var ready = false
    // 실제 창에 안내가 추가되는 순간과 대기 상태를 구분한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 전역 선택 대신 서비스에서 전달한 청산 포지션의 원본 계좌다.
    let position = try FuturesCalculator.open(domesticFuturesOrder(exchange: .bithumb))
    // 기존 표시 조건과 배너 중복 방지 경계를 그대로 사용한다.
    let presenter = FuturesLiquidationNoticePresenter(window: window, canShow: { _ in ready })
    defer { presenter.suspend() }
    presenter.receive([position])
    presenter.showPendingNotices()
    XCTAssertTrue(events.isEmpty)
    XCTAssertNil(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" })

    ready = true
    presenter.showPendingNotices()
    XCTAssertNotNil(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" })
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events.first?.name, "mobit_screen_event")
    XCTAssertEqual(events.first?.parameters["exchange"] as? String, position.order.account.exchange.rawValue)
    XCTAssertEqual(events.first?.parameters["product"] as? String, position.order.account.product.rawValue)
    XCTAssertEqual(events.first?.parameters["account_name"] as? String, "빗썸_선물")
    // 노출 이벤트에는 계좌 구분과 행동 경로 외의 거래 데이터가 없어야 한다.
    let allowedKeys: Set<String> = [
      "location", "Step_depth_01", "Step_depth_02", "exchange", "exchange_name",
      "product", "product_name", "account_name", "currency"
    ]
    XCTAssertEqual(Set(events.first?.parameters.keys.map { $0 } ?? []), allowedKeys)

    presenter.receive([position])
    presenter.showPendingNotices()
    XCTAssertEqual(events.count, 1)
    // 같은 청산이 발생했다는 통계와 달리 다시 보이는 안내는 별도 노출로 기록한다.
    presenter.suspend()
    presenter.showPendingNotices()
    XCTAssertEqual(events.count, 2)
  }
  #endif

  @MainActor
  func testLiquidationNoticeWaitsForMainAppearanceAndStartsFourSecondsOnDisplay() throws {
    // 메인 화면이 보이기 전에는 청산 안내의 타이머도 시작하지 않는다.
    var ready = false
    // 실제 창에서 인트로와 메인 화면 전환을 재현한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 청산 저장과 분리된 표시 순서만 검증한다.
    let presenter = FuturesLiquidationNoticePresenter(window: window, canShow: { _ in ready })
    presenter.receive([try FuturesCalculator.open(domesticFuturesOrder())])
    waitForNoticeUpdates(4.1)
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
    waitForNoticeUpdates(3.7)
    XCTAssertTrue(notice.superview === window)
    XCTAssertEqual(notice.alpha, 1)
    waitForNoticeUpdates(0.6)
    XCTAssertNil(notice.superview)
  }

  @MainActor
  func testLiquidationNoticeWaitsForAllLoadingOwnersAndThenDisplaysForFourSeconds() throws {
    // 같은 창의 최초 조회와 복귀 검증이 겹치는 상황이다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
    // 먼저 완료되는 조회 화면이다.
    let firstOwner = MobitBaseViewController()
    // 늦게 완료되는 검증 화면이다.
    let secondOwner = MobitBaseViewController()
    window.rootViewController = firstOwner
    firstOwner.addChild(secondOwner)
    firstOwner.view.addSubview(secondOwner.view)
    secondOwner.didMove(toParent: firstOwner)
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 청산 이벤트 수신부터가 아닌 실제 노출부터 시간을 잰다.
    let presenter = FuturesLiquidationNoticePresenter(window: window, canShow: { _ in true })
    firstOwner.showLoadingIndicator()
    secondOwner.showLoadingIndicator()
    waitForNoticeUpdates(0.05)
    presenter.receive([try FuturesCalculator.open(domesticFuturesOrder())])
    waitForNoticeUpdates(4.1)
    XCTAssertTrue(MobitBaseViewController.isLoadingIndicatorVisible(in: window))
    XCTAssertNil(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" })
    firstOwner.hideLoadingIndicator()
    waitForNoticeUpdates(0.05)
    XCTAssertTrue(MobitBaseViewController.isLoadingIndicatorVisible(in: window))
    XCTAssertNil(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" })
    secondOwner.hideLoadingIndicator()
    waitForNoticeUpdates(0.05)
    XCTAssertFalse(MobitBaseViewController.isLoadingIndicatorVisible(in: window))
    // 마지막 인디케이터 요청이 종료되면 별도 재호출 없이 안내가 나타난다.
    let notice = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" })
    firstOwner.hideLoadingIndicator()
    presenter.showPendingNotices()
    waitForNoticeUpdates(3.7)
    XCTAssertEqual(window.subviews.filter { $0.accessibilityIdentifier == "futuresLiquidationNotice" }.count, 1)
    XCTAssertTrue(notice.superview === window)
    XCTAssertEqual(notice.alpha, 1)
    waitForNoticeUpdates(0.6)
    XCTAssertNil(notice.superview)
  }

  @MainActor
  func testLoadingSuspendsVisibleLiquidationNoticeAndPreservesQueuedNotices() throws {
    // 안내를 표시한 뒤 인디케이터가 추가되는 역순도 확인한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
    // 실제 공통 인디케이터를 표시·종료하는 화면이다.
    let owner = MobitBaseViewController()
    window.rootViewController = owner
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 비활성 상태에서 인디케이터가 종료돼도 안내는 보류한다.
    var active = true
    // 순서와 이전 자동 종료 작업의 영향을 확인한다.
    let presenter = FuturesLiquidationNoticePresenter(window: window, canShow: { _ in active })
    presenter.receive([try FuturesCalculator.open(domesticFuturesOrder())])
    // 재개된 안내가 같은 청산인지 비교할 원본이다.
    let original = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" } as? UILabel)
    owner.showLoadingIndicator()
    waitForNoticeUpdates(0.05)
    XCTAssertNil(original.superview)
    presenter.receive([try FuturesCalculator.open(domesticFuturesOrder(side: .short))])
    XCTAssertNil(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" })
    waitForNoticeUpdates(3.7)
    active = false
    owner.hideLoadingIndicator()
    waitForNoticeUpdates(0.05)
    XCTAssertFalse(MobitBaseViewController.isLoadingIndicatorVisible(in: window))
    XCTAssertNil(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" })
    active = true
    presenter.showPendingNotices()
    // 재개 직후 원래 안내의 4초 기한을 지나도 새 안내는 유지한다.
    let resumed = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" } as? UILabel)
    XCTAssertEqual(resumed.text, original.text)
    waitForNoticeUpdates(0.5)
    XCTAssertTrue(resumed.superview === window)
    XCTAssertEqual(resumed.alpha, 1)
    presenter.dismissNotice()
    waitForNoticeUpdates(0.35)
    // 대기 중 도착한 다음 청산 안내도 유실되지 않는다.
    let next = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" } as? UILabel)
    XCTAssertNotEqual(next.text, resumed.text)
    presenter.suspend()
  }

  @MainActor
  func testLoadingInAnotherWindowDoesNotSuspendLiquidationNotice() throws {
    // 청산 안내와 무관한 창의 인디케이터를 구분한다.
    let noticeWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
    noticeWindow.rootViewController = UIViewController()
    noticeWindow.makeKeyAndVisible()
    // 다른 Scene에 해당하는 별도 창이다.
    let loadingWindow = UIWindow(frame: noticeWindow.frame)
    // 인디케이터가 자신의 화면이 속한 창에만 표시되도록 한다.
    let owner = MobitBaseViewController()
    loadingWindow.rootViewController = owner
    loadingWindow.isHidden = false
    defer {
      noticeWindow.isHidden = true
      noticeWindow.rootViewController = nil
      loadingWindow.isHidden = true
      loadingWindow.rootViewController = nil
    }
    // 다른 창의 표시·종료 이벤트에 현재 안내를 재생성하면 안 된다.
    let presenter = FuturesLiquidationNoticePresenter(window: noticeWindow, canShow: { _ in true })
    presenter.receive([try FuturesCalculator.open(domesticFuturesOrder())])
    // 다른 창의 이벤트 전후 동일한 안내 객체를 유지한다.
    let notice = try XCTUnwrap(noticeWindow.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" })
    owner.showLoadingIndicator()
    waitForNoticeUpdates(0.05)
    XCTAssertTrue(MobitBaseViewController.isLoadingIndicatorVisible(in: loadingWindow))
    XCTAssertTrue(notice.superview === noticeWindow)
    owner.hideLoadingIndicator()
    waitForNoticeUpdates(0.05)
    XCTAssertFalse(MobitBaseViewController.isLoadingIndicatorVisible(in: loadingWindow))
    XCTAssertTrue(notice.superview === noticeWindow)
    presenter.suspend()
  }

  @MainActor
  func testLiquidationNoticeUpdatesThemeAndFitsSmallScreensWithoutClipping() throws {
    // 실제 거래소 요약 위에서 안내의 대비와 크기를 확인한다.
    let futures = reactor()
    // 화면과 안내에 동일한 국내 선물 포지션을 사용한다.
    let position = try FuturesCalculator.open(domesticFuturesOrder(margin: 100, price: 100))
    futures.stub.state.value = futures.reduce(
      state: futures.initialState,
      mutation: .snapshot(.init(revision: 1, accounts: [.init(id: account, availableBalance: 900)], positions: [position]), [:])
    )
    // 외부 네트워크 없이 거래소 목록을 준비한다.
    let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
    // 사용자가 보는 실제 배경과 요약이다.
    let main = MainViewController(reactor: market, futuresReactor: futures, networkAvailability: .empty())
    // 한 안내를 유지한 채 창의 테마와 너비를 바꾼다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
    window.rootViewController = main
    window.isHidden = false
    defer { main.viewWillDisappear(false); window.isHidden = true; window.rootViewController = nil }
    market.action.onNext(.loadCryptoList)
    waitForNoticeUpdates(0.1)
    // 자동 닫기 시간은 별도 테스트에서 확인하고 여기서는 같은 뷰의 외관을 검사한다.
    let presenter = FuturesLiquidationNoticePresenter(window: window, canShow: { _ in true })
    presenter.receive([position])
    defer { presenter.suspend() }
    // 기존 접근성 식별자와 제스처를 유지하는 안내다.
    let notice = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" } as? UILabel)
    for style in [UIUserInterfaceStyle.light, .dark, .light] {
      window.overrideUserInterfaceStyle = style
      for width in [320.0, 393.0] {
        window.frame.size.width = width
        window.layoutIfNeeded()
        XCTAssertEqual(notice.traitCollection.userInterfaceStyle, style)
        XCTAssertEqual(notice.layer.backgroundColor, UIColor.mobitColors(.surfaceElevated).resolvedColor(with: notice.traitCollection).cgColor)
        XCTAssertEqual(notice.layer.borderColor, UIColor.mobitColors(.accentPrimary).withAlphaComponent(0.65).resolvedColor(with: notice.traitCollection).cgColor)
        XCTAssertEqual(notice.textColor.resolvedColor(with: notice.traitCollection), UIColor.mobitColors(.textPrimary).resolvedColor(with: notice.traitCollection))
        XCTAssertEqual(notice.layer.borderWidth, 1)
        XCTAssertGreaterThan(notice.layer.shadowOpacity, 0)
        XCTAssertNotNil(notice.layer.shadowPath)
        XCTAssertFalse(notice.clipsToBounds)
        XCTAssertGreaterThanOrEqual(notice.frame.minX, 16)
        XCTAssertLessThanOrEqual(notice.frame.maxX, window.bounds.width - 16)
        XCTAssertLessThanOrEqual(notice.sizeThatFits(CGSize(width: notice.bounds.width, height: .greatestFiniteMagnitude)).height, notice.bounds.height + 1)
        // 실제 안내와 주변 요약을 같은 이미지로 남긴다.
        let capture = UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) }
        // 라이트·다크의 카드 경계와 내부 여백을 시각적으로 확인한다.
        let attachment = XCTAttachment(image: capture)
        attachment.name = "Liquidation-notice-\(style == .dark ? "dark" : "light")-\(Int(width))"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
    }
    // 긴 복수 안내와 접근성 글자 크기에서도 높이를 고정하지 않는다.
    notice.text = Array(repeating: try XCTUnwrap(notice.text), count: 3).joined(separator: "\n")
    notice.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
      for: .systemFont(ofSize: 15),
      compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
    )
    window.frame.size.width = 320
    window.layoutIfNeeded()
    XCTAssertGreaterThan(notice.bounds.height, 64)
    XCTAssertLessThanOrEqual(notice.sizeThatFits(CGSize(width: notice.bounds.width, height: .greatestFiniteMagnitude)).height, notice.bounds.height + 1)
  }

  @MainActor
  func testReadinessIndicatorNetworkNoticeErrorAndIntroFollowLightAndDarkThemes() throws {
    // 동일 창에서 테마를 바꿔도 기존 표시 객체가 현재 색상을 사용해야 한다.
    let controller = MobitBaseViewController()
    // 실제 전체 화면 인디케이터를 올릴 독립 창이다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    window.rootViewController = controller
    window.isHidden = false
    defer { controller.hideLoadingIndicator(); window.isHidden = true; window.rootViewController = nil }
    controller.view.backgroundColor = .mobitColors(.backgroundPrimary)
    controller.showLoadingIndicator()
    waitForNoticeUpdates(0.05)
    // 새 배경을 그리지 않고 원래 Lottie가 테마 색상을 받는지 확인한다.
    let indicator = try XCTUnwrap(window.viewWithTag(999_999) as? MobitLottieView)
    // 기존 네트워크 유실 화면도 같은 색상 기준을 따라야 한다.
    let network = NetworkLostView()
    network.configure()
    network.frame = window.bounds
    controller.view.addSubview(network)
    // 주문·투자내역이 공유하는 실제 실패/재시도 안내다.
    let error = FuturesDataStatusView(retry: {})
    error.render(message: FuturesText.text("futures_data_held"), retry: true)
    error.frame = CGRect(x: 16, y: 480, width: 288, height: 90)
    controller.view.addSubview(error)
    // 인트로의 기존 XIB 색상도 함께 검사한다.
    let intro = MobitLaunchScreen()
    intro.loadViewIfNeeded()
    for style in [UIUserInterfaceStyle.light, .dark, .light] {
      window.overrideUserInterfaceStyle = style
      intro.overrideUserInterfaceStyle = style
      window.layoutIfNeeded()
      // 현재 모드의 실제 렌더링 색상을 비교한다.
      let traits = indicator.traitCollection
      XCTAssertEqual(indicator.backgroundColor?.resolvedColor(with: traits), UIColor.mobitColors(.backgroundPrimary).withAlphaComponent(0.6).resolvedColor(with: traits))
      XCTAssertEqual(network.view.backgroundColor?.resolvedColor(with: traits), UIColor.mobitColors(.backgroundPrimary).resolvedColor(with: traits))
      XCTAssertEqual(network.label.textColor.resolvedColor(with: traits), UIColor.mobitColors(.textSecondary).resolvedColor(with: traits))
      XCTAssertEqual(network.imageView.tintColor.resolvedColor(with: traits), UIColor.mobitColors(.textSecondary).resolvedColor(with: traits))
      XCTAssertEqual(intro.view.backgroundColor?.resolvedColor(with: intro.traitCollection), UIColor.mobitColors(.backgroundPrimary).resolvedColor(with: intro.traitCollection))
      // 실제 오류 문구와 재시도 버튼이 두 모드 모두 숨겨지지 않는다.
      let label = try XCTUnwrap(descendants(error).first { $0.accessibilityIdentifier == "futures.data.status" } as? UILabel)
      // 기본 UIKit 버튼 색상도 현재 모드에서 해석할 수 있어야 한다.
      let retry = try XCTUnwrap(descendants(error).first { $0.accessibilityIdentifier == "futures.data.retry" } as? UIButton)
      XCTAssertEqual(label.textColor.resolvedColor(with: traits), UIColor.mobitColors(.textSecondary).resolvedColor(with: traits))
      XCTAssertFalse(error.isHidden)
      XCTAssertFalse(retry.isHidden)
      XCTAssertTrue(indicator.isPlaying)
      // 실제 정책처럼 오류·네트워크 안내 위에 인디케이터가 겹치지 않게 각각 확인한다.
      for component in ["indicator", "network", "error"] {
        indicator.isHidden = component != "indicator"
        network.isHidden = component != "network"
        error.isHidden = component != "error"
        // 각 안내의 실제 가독성을 다른 오버레이의 dim 없이 기록한다.
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) })
        attachment.name = "Readiness-\(component)-\(style == .dark ? "dark" : "light")"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
      indicator.isHidden = false
      network.isHidden = false
      error.isHidden = false
    }
  }

  @MainActor
  func testLiquidationNoticeTapAndUpSwipeDismissInOrderWithoutReplacingCurrentNotice() throws {
    // 연속 청산 안내를 실제 창에서 순서대로 표시한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 제스처와 자동 닫기가 공유하는 표시 수명이다.
    let presenter = FuturesLiquidationNoticePresenter(window: window, canShow: { _ in true })
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
    let presenter = FuturesLiquidationNoticePresenter(window: window, canShow: { _ in active })
    presenter.receive([try FuturesCalculator.open(domesticFuturesOrder())])
    // 중단한 애니메이션이 대기 목록까지 지우면 안 된다.
    let first = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" } as? UILabel)
    presenter.dismissNotice()
    active = false
    presenter.suspend()
    presenter.receive([try FuturesCalculator.open(domesticFuturesOrder(side: .short))])
    waitForNoticeUpdates(3.8)
    XCTAssertNil(first.superview)
    XCTAssertNil(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" })
    active = true
    presenter.showPendingNotices()
    // 복귀 후 새 안내에는 기존 4초 타이머가 영향을 주면 안 된다.
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
  func testLiquidationNoticesMatchExchangeAndFuturesModeWithoutLosingOtherAccounts() throws {
    // 현물에서는 두 거래소의 선물 청산 안내를 모두 보류한다.
    var selected = TradingAccountID(exchange: .upbit, product: .spot, currency: .krw)
    // 계좌별 안내가 실제 창에 표시되는지 확인한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 거래소·모드 선택만 바꿔 동일 안내 대기열을 재사용한다.
    let presenter = FuturesLiquidationNoticePresenter(window: window, canShow: { $0 == selected })
    // 대기열 앞의 빗썸 안내가 업비트 안내를 막으면 안 된다.
    let bithumb = try FuturesCalculator.open(domesticFuturesOrder(exchange: .bithumb))
    // 하나의 검증 완료 이벤트에 다른 거래소 청산도 함께 포함된다.
    let upbit = try FuturesCalculator.open(domesticFuturesOrder())
    presenter.receive([bithumb, upbit])
    XCTAssertNil(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" })
    selected = upbit.order.account
    presenter.showPendingNotices()
    // 현재 거래소의 청산만 포함된 안내다.
    let upbitNotice = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" } as? UILabel)
    XCTAssertTrue(upbitNotice.text?.contains(FuturesText.text("futures_upbit")) == true)
    XCTAssertFalse(upbitNotice.text?.contains(FuturesText.text("futures_bithumb")) == true)
    presenter.dismissNotice()
    waitForNoticeUpdates(0.35)
    XCTAssertNil(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" })
    selected = TradingAccountID(exchange: .bithumb, product: .spot, currency: .krw)
    presenter.showPendingNotices()
    XCTAssertNil(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" })
    selected = bithumb.order.account
    presenter.showPendingNotices()
    // 앞에서 건너뛴 빗썸 안내는 빗썸 선물 진입 때 표시된다.
    let bithumbNotice = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" } as? UILabel)
    XCTAssertTrue(bithumbNotice.text?.contains(FuturesText.text("futures_bithumb")) == true)
    XCTAssertFalse(bithumbNotice.text?.contains(FuturesText.text("futures_upbit")) == true)
    presenter.dismissNotice()
    waitForNoticeUpdates(0.35)
    selected = upbit.order.account
    presenter.showPendingNotices()
    XCTAssertNil(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" })
  }

  @MainActor
  func testSelectionChangeHidesCurrentNoticeAndPreservesItDuringDismissal() throws {
    // 화면 전환은 표시 중이던 다른 계좌의 안내를 즉시 숨긴다.
    var selected = account
    // 타이머와 애니메이션이 계좌 전환 이후 안내를 지우지 않는지 확인한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 현재 선택한 계좌만 안내를 허용한다.
    let presenter = FuturesLiquidationNoticePresenter(window: window, canShow: { $0 == selected })
    // 업비트로 돌아왔을 때 다시 확인할 안내다.
    let upbit = try FuturesCalculator.open(domesticFuturesOrder())
    // 전환 직후 표시할 빗썸 안내다.
    let bithumb = try FuturesCalculator.open(domesticFuturesOrder(exchange: .bithumb))
    presenter.receive([upbit, bithumb])
    // 닫기 도중 전환되어도 업비트 안내를 소비한 것으로 처리하지 않는다.
    let original = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" } as? UILabel)
    presenter.dismissNotice()
    selected = bithumb.order.account
    presenter.showPendingNotices()
    waitForNoticeUpdates(0.35)
    XCTAssertNil(original.superview)
    // 빗썸 화면에는 빗썸 안내만 남는다.
    let current = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" } as? UILabel)
    XCTAssertTrue(current.text?.contains(FuturesText.text("futures_bithumb")) == true)
    selected = TradingAccountID(exchange: .bithumb, product: .spot, currency: .krw)
    presenter.showPendingNotices()
    XCTAssertNil(current.superview)
    XCTAssertNil(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" })
    selected = upbit.order.account
    presenter.showPendingNotices()
    // 원래 안내가 아직 소비되지 않아 다시 표시된다.
    let resumed = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "futuresLiquidationNotice" } as? UILabel)
    XCTAssertEqual(resumed.text, original.text)
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
  func testProductSwitchFitsLocalizedTitlesAndAccessoryAcrossScreensAndThemes() throws {
    // 화면 초기화가 재저장하는 상품 선택과 현물 보유 데이터를 복원한다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    // 레이아웃 검사로 기존 현물 저장값이 바뀌지 않게 원본을 보존한다.
    let previousHoldingsData = UserDefaults.standard.object(forKey: UserDataManager.Keys.userCryptoList)
    // 화면 구독자에게 돌려줄 기존 보유 내역이다.
    let previousHoldings = UserDataManager.userCryptoList
    defer {
      ExchangeSelectionStore.currentProduct = previousProduct
      UserDataManager.userCryptoList = previousHoldings ?? []
      UserDefaults.standard.set(previousHoldingsData, forKey: UserDataManager.Keys.userCryptoList)
    }
    for product in [TradingProduct.spot, .perpetual] {
      ExchangeSelectionStore.currentProduct = product
      for width: CGFloat in [320, 375, 393] {
        // 실제 화면을 외부 시세·광고 조회 없이 배치한다.
        let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
        market.isStubEnabled = true
        // 자산 검증 이벤트 없이 두 상품의 투자내역을 구성한다.
        let futures = reactor()
        // 공포·탐욕 버튼을 포함한 실제 거래소 화면이다.
        let main = MainViewController(reactor: market, futuresReactor: product == .perpetual ? futures : nil, networkAvailability: .empty())
        // 현재 상품에 맞는 실제 투자내역 XIB를 사용한다.
        let investment: UIViewController
        if product == .perpetual {
          investment = FuturesInvestmentViewController(reactor: futures, marketReactor: market)
        } else {
          // 현물 화면 역시 테스트 중 네트워크를 호출하지 않는다.
          let spot = InvestReactor(mainUseCase: try FuturesMainFixtureUseCase())
          spot.isStubEnabled = true
          investment = InvestmentViewController(reactor: spot)
        }
        // 앱과 같은 내비게이션 계층에서 스위치·부속 버튼의 위치를 검사한다.
        let tabs = MobitTabBarViewController()
        tabs.setViewControllers([main, investment].map {
          // 상단 내비게이션 바는 실제 메인·투자내역과 같이 숨긴다.
          let navigation = UINavigationController(rootViewController: $0)
          navigation.setNavigationBarHidden(true, animated: false)
          return navigation
        })
        tabs.setProduct(product)
        // viewDidAppear의 광고 요청 없이 실제 화면 레이아웃과 테마만 렌더링한다.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: width == 320 ? 568 : 852))
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(tabs.view)
        tabs.view.frame = window.bounds
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        // 언어별 자연 너비를 확인할 실제 공통 스위치다.
        let selector = try XCTUnwrap(descendants(tabs.view).first { $0.accessibilityIdentifier == "tradingProductSelector" })
        // UIKit 버튼 내부의 글자 여백과 터치 크기를 확인한다.
        let buttons = descendants(selector).compactMap { $0 as? UIButton }
        XCTAssertEqual(buttons.count, 2)
        for style in [UIUserInterfaceStyle.light, .dark] {
          tabs.overrideUserInterfaceStyle = style
          if #available(iOS 17.0, *) { tabs.updateTraitsIfNeeded() }
          for tab in [0, 1] {
            tabs.switchToTab(index: tab)
            waitForNoticeUpdates(0.05)
            window.layoutIfNeeded()
            tabs.view.layoutIfNeeded()
            main.view.layoutIfNeeded()
            tabs.view.layoutIfNeeded()
            XCTAssertFalse(selector.isHidden)
            XCTAssertFalse(selector.hasAmbiguousLayout)
            XCTAssertEqual(selector.frame.midX, tabs.view.bounds.midX, accuracy: 0.5)
            XCTAssertLessThanOrEqual(selector.bounds.width, width - (tab == 0 ? 192 : 32) + 0.5)
            XCTAssertGreaterThanOrEqual(selector.frame.minX, tabs.view.safeAreaLayoutGuide.layoutFrame.minX + 16 - 0.5)
            for button in buttons {
              // 최대 너비에서도 정해진 축소 범위 안에 한·영 문구가 들어가는지 확인한다.
              let label = try XCTUnwrap(button.titleLabel)
              XCTAssertGreaterThanOrEqual(button.bounds.width, 44)
              XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
              // 기본 32pt 여백은 최대 너비에서 글자 공간이 부족할 때만 줄어든다.
              let insets = try XCTUnwrap(button.configuration?.contentInsets)
              XCTAssertEqual(insets.leading, insets.trailing)
              XCTAssertGreaterThanOrEqual(insets.leading, 12)
              XCTAssertLessThanOrEqual(insets.leading, 32)
              if tab == 1 { XCTAssertEqual(insets.leading, 32) }
              // 좌우 여백의 정수 반올림으로 생기는 최대 1pt 차이는 제외한다.
              if label.bounds.width + 1 < label.intrinsicContentSize.width {
                XCTAssertEqual(insets.leading, 12, "글자를 축소하기 전에 여백부터 줄여야 한다.")
              }
              XCTAssertGreaterThanOrEqual(label.bounds.width + 0.5, label.intrinsicContentSize.width * label.minimumScaleFactor)
              XCTAssertTrue(button.bounds.insetBy(dx: insets.leading - 0.5, dy: 0).contains(label.convert(label.bounds, to: button)))
              XCTAssertEqual(
                button.backgroundColor?.resolvedColor(with: button.traitCollection),
                (button.accessibilityTraits.contains(.selected) ? UIColor.mobitColors(.accountAction) : .clear).resolvedColor(with: button.traitCollection)
              )
              XCTAssertEqual(
                button.configuration?.baseForegroundColor?.resolvedColor(with: button.traitCollection),
                (button.accessibilityTraits.contains(.selected) ? UIColor.white : .mobitColors(.textPrimary)).resolvedColor(with: button.traitCollection)
              )
            }
            if tab == 0 {
              // 실제 공포·탐욕 버튼의 좌표로 최소 24pt 간격을 검증한다.
              let accessory = try XCTUnwrap(descendants(main.view).first { $0.accessibilityIdentifier == "fearGreedFloatingButton" })
              // 서로 다른 화면 계층의 좌표를 공통 탭 컨테이너로 변환한다.
              let frame = accessory.convert(accessory.bounds, to: tabs.view)
              XCTAssertGreaterThanOrEqual(frame.minX - selector.frame.maxX, 24 - 0.5)
              XCTAssertEqual(frame.midY, selector.frame.midY, accuracy: 0.5)
            } else {
              XCTAssertEqual(selector.frame.midX, tabs.view.safeAreaLayoutGuide.layoutFrame.midX, accuracy: 0.5)
            }
            // 실제 작은 화면의 두 테마를 결과 파일에서 비교할 수 있게 남긴다.
            let capture = XCTAttachment(image: UIGraphicsImageRenderer(bounds: tabs.view.bounds).image { tabs.view.layer.render(in: $0.cgContext) })
            capture.name = "Product-switch-\(product.rawValue)-\(tab == 0 ? "exchange" : "investment")-\(Int(width))-\(style == .dark ? "dark" : "light")"
            capture.lifetime = .keepAlways
            add(capture)
          }
        }
      }
    }
  }

  @MainActor
  func testProductSwitchKeepsBothTitlesVisibleAfterRepeatedTaps() throws {
    // 실제 버튼 탭으로 선택 상태만 바꾸고 다른 화면 이벤트로 색을 보정하지 않는다.
    let tabs = MobitTabBarViewController()
    tabs.setViewControllers([UIViewController(), UIViewController()])
    // 작은 화면에서 공통 스위치의 두 테마를 렌더링한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = tabs
    window.isHidden = false
    defer { window.isHidden = true; window.rootViewController = nil }
    // 거래소와 투자내역에서 공유하는 실제 스위치다.
    let selector = try XCTUnwrap(descendants(tabs.view).first { $0.accessibilityIdentifier == "tradingProductSelector" })
    // 각 항목의 최종 글자색을 검사할 버튼이다.
    let buttons = descendants(selector).compactMap { $0 as? UIButton }
    XCTAssertEqual(buttons.count, 2)
    for style in [UIUserInterfaceStyle.light, .dark] {
      tabs.overrideUserInterfaceStyle = style
      for tab in [0, 1] {
        tabs.switchToTab(index: tab)
        for selectedIndex in [1, 0, 1, 0] {
          buttons[selectedIndex].sendActions(for: .touchUpInside)
          waitForNoticeUpdates(0.01)
          tabs.view.layoutIfNeeded()
          for (index, button) in buttons.enumerated() {
            // baseForegroundColor가 아닌 UILabel에 실제 적용된 색을 비교한다.
            let label = try XCTUnwrap(button.titleLabel)
            // 비선택 글자가 이전 선택 상태의 흰색으로 남지 않아야 한다.
            let expected = index == selectedIndex ? UIColor.white : .mobitColors(.textPrimary)
            // UIKit이 최종 제목에 적용한 글자색이다.
            let actual = (label.attributedText?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor) ?? label.textColor
            XCTAssertEqual(actual?.resolvedColor(with: button.traitCollection), expected.resolvedColor(with: button.traitCollection))
            XCTAssertFalse(label.isHidden)
            XCTAssertGreaterThan(label.bounds.width, 0)
          }
        }
      }
    }
  }

  @MainActor
  func testProductSwitchKeepsColorsWhileExchangeActionSheetIsPresented() throws {
    // 거래소 선택창과 같은 UIKit 액션시트를 실제 화면 위에 표시한다.
    let tabs = MobitTabBarViewController()
    tabs.setViewControllers([UIViewController(), UIViewController()])
    // 실제 시스템의 tint dimming을 받는 창을 사용한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
    window.rootViewController = tabs
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 공통 스위치에서 UIKit이 최종 렌더링할 글자 색을 검사한다.
    let selector = try XCTUnwrap(descendants(tabs.view).first { $0.accessibilityIdentifier == "tradingProductSelector" })
    // 배경색과 글자색이 서로 다른 보정을 받지 않아야 한다.
    let buttons = descendants(selector).compactMap { $0 as? UIButton }
    for style in [UIUserInterfaceStyle.light, .dark] {
      tabs.overrideUserInterfaceStyle = style
      for product in [TradingProduct.spot, .perpetual] {
        tabs.setProduct(product)
        // MainViewController의 거래소 선택과 같은 프레젠테이션 종류다.
        let sheet = UIAlertController(title: "Exchange", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        // 프레젠테이션이 완료된 뒤 실제 시스템 보정 색을 검사한다.
        let shown = expectation(description: "Exchange sheet presented")
        tabs.present(sheet, animated: false) { shown.fulfill() }
        wait(for: [shown], timeout: 2)
        for presented in [true, false] {
          if !presented {
            // 닫힘 완료를 기다려 다음 상품의 액션시트와 겹치지 않게 한다.
            let dismissed = expectation(description: "Exchange sheet dismissed")
            tabs.dismiss(animated: false) { dismissed.fulfill() }
            wait(for: [dismissed], timeout: 2)
          }
          XCTAssertEqual(tabs.presentedViewController != nil, presented)
          tabs.view.layoutIfNeeded()
          for button in buttons {
            // baseForegroundColor가 아닌 실제 attributedTitle 색상을 비교한다.
            let label = try XCTUnwrap(button.titleLabel)
            // 선택된 모드의 흰 글자와 비선택 모드의 테마 색을 유지한다.
            let expected = button.accessibilityTraits.contains(.selected) ? UIColor.white : .mobitColors(.textPrimary)
            // UIButton.Configuration이 최종 글자에 적용한 색이다.
            let actual = (label.attributedText?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor) ?? label.textColor
            XCTAssertEqual(actual?.resolvedColor(with: button.traitCollection), expected.resolvedColor(with: button.traitCollection))
          }
        }
      }
    }
  }

  @MainActor
  func testProductSwitchCapsLongTitlesAndKeepsSelectionAfterResize() throws {
    // 긴 번역과 큰 글씨에서도 스위치가 화면 밖으로 나가지 않아야 한다.
    let tabs = MobitTabBarViewController()
    tabs.setViewControllers([UIViewController(), UIViewController()])
    // 최소 화면 폭에서 글자가 부족한 상황을 만든다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = tabs
    window.isHidden = false
    defer { window.isHidden = true; window.rootViewController = nil }
    // 길어진 제목은 기존 버튼에 전달해 새 구현을 별도로 복제하지 않는다.
    let selector = try XCTUnwrap(descendants(tabs.view).first { $0.accessibilityIdentifier == "tradingProductSelector" })
    // 새 화면이나 버튼을 생성하지 않고 제목 변화에 따른 너비 갱신을 검사한다.
    let buttons = descendants(selector).compactMap { $0 as? UIButton }
    // 크기 변경 뒤에도 정상 모드 전환이 한 번만 전달되는지 기록한다.
    var selected: [TradingProduct] = []
    tabs.onProductSelected = { selected.append($0) }
    for tab in [0, 1] {
      tabs.switchToTab(index: tab)
      for button in buttons { button.configuration?.title = "A" }
      tabs.view.layoutIfNeeded()
      // 짧은 문구에서 불필요한 고정 너비를 남기지 않아야 한다.
      let compactWidth = selector.bounds.width
      XCTAssertLessThan(compactWidth, 170)
      XCTAssertEqual(selector.frame.midX, tabs.view.bounds.midX, accuracy: 0.5)
      for button in buttons { button.configuration?.title = String(repeating: "Extended translated product ", count: 4) }
      tabs.view.layoutIfNeeded()
      if tab == 0 { XCTAssertEqual(selector.bounds.width, 128, accuracy: 0.5) }
      else { XCTAssertGreaterThan(selector.bounds.width, compactWidth) }
      XCTAssertEqual(selector.frame.midX, tabs.view.bounds.midX, accuracy: 0.5)
      XCTAssertLessThanOrEqual(selector.frame.maxX, 320 - (tab == 0 ? 96 : 16) + 0.5)
      XCTAssertGreaterThanOrEqual(selector.frame.minX, 16 - 0.5)
      for button in buttons {
        XCTAssertGreaterThanOrEqual(button.bounds.width, 44)
        XCTAssertTrue(button.titleLabel?.adjustsFontSizeToFitWidth == true)
        XCTAssertEqual(button.titleLabel?.minimumScaleFactor ?? 0, 0.55, accuracy: 0.001)
        XCTAssertEqual(button.titleLabel?.lineBreakMode, .byTruncatingTail)
        XCTAssertFalse(button.hasAmbiguousLayout)
      }
      if #available(iOS 17.0, *) {
        tabs.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        tabs.updateTraitsIfNeeded()
        waitForNoticeUpdates(0.05)
        tabs.view.layoutIfNeeded()
        XCTAssertEqual(selector.frame.midX, tabs.view.bounds.midX, accuracy: 0.5)
        XCTAssertLessThanOrEqual(selector.frame.maxX, 320 - (tab == 0 ? 96 : 16) + 0.5)
        tabs.traitOverrides.preferredContentSizeCategory = .large
      }
      // 제목이 다시 짧아져도 늘어났던 너비가 고정되지 않는다.
      for button in buttons { button.configuration?.title = "A" }
      waitForNoticeUpdates(0.05)
      tabs.view.layoutIfNeeded()
      XCTAssertEqual(selector.bounds.width, compactWidth, accuracy: 0.5)
      for button in buttons { button.sendActions(for: .touchUpInside) }
    }
    XCTAssertEqual(selected, [.spot, .perpetual, .spot, .perpetual])
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
      XCTAssertEqual(investment.cryptoBuyPrice.text, expected)
      investment.prepareForReuse()
      XCTAssertNil(investment.sideBadgeLabel.text)
      XCTAssertNil(investment.leverageBadgeLabel.text)
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
      XCTAssertEqual(history.marketNameLabel.text, FuturesText.symbol(record.instrument))
      XCTAssertEqual(history.positionBadgeLabel.text, "\(FuturesText.side(record.side)) 1×")
      XCTAssertEqual(history.statusLabel.text, FuturesText.text("futures_pnl_closed"))
      XCTAssertEqual(history.quantityLabel.text, expected + " BTC")
      XCTAssertEqual(history.pnlLabel.text, "+" + expected + " " + FuturesText.text("currency_krw_unit"))
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
    // 카드의 실시간 평가값은 보유 포지션 검증을 마친 상태에서만 표시한다.
    state = reactor.reduce(
      state: state,
      mutation: .status(.finished([
        .init(positionID: position.id, verifiedThrough: timestamp, liquidated: false, hold: nil, lastVerifiedMark: 110_000_000)
      ]))
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
  func testFuturesButtonsExplainInvalidInputAndReadinessOnTapWithoutSubmitting() throws {
    for closing in [false, true] {
      // 화면은 탭할 수 있어도 실제 주문은 계좌·가격·입력 검증을 통과해야 한다.
      let futures = reactor()
      // 추가 진입과 부분 종료를 모두 검사하는 같은 보유 포지션이다.
      let position = try FuturesCalculator.open(domesticFuturesOrder(margin: 100, price: 100))
      // 정상 검증 완료 상태를 오류별로 변경한다.
      var state = futures.reduce(state: futures.initialState, mutation: .snapshot(.init(revision: 1, accounts: [.init(id: account, availableBalance: 900)], positions: [position]), [:]))
      state = futures.reduce(state: state, mutation: .status(.finished([.init(positionID: position.id, verifiedThrough: 1, liquidated: false, hold: nil)])))
      futures.stub.state.value = state
      // 연결 중단은 상태 변경과 별개로 캡처 가격이 없어지는 상황이다.
      var priceAvailable = true
      // 두 화면에서 동일한 최신 표시 가격을 캡처한다.
      let capture: () -> FuturesOrderPrice? = {
        guard priceAvailable else { return nil }
        // 요청 순간의 가격 유효기간을 만족한다.
        let timestamp = (try? FuturesHistoryCheckState.milliseconds(Date())) ?? 0
        return .init(quote: .init(instrument: position.order.instrument, price: 105, timestamp: timestamp), requestedAt: timestamp)
      }
      // 같은 제출 정책을 실제 두 종류의 UIKit 화면에서 확인한다.
      let controller: UIViewController
      if closing {
        controller = FuturesCloseViewController(reactor: futures, positionID: position.id, captureOrderPrice: capture)
      } else {
        // 진입 폼은 동일한 가격 제공자를 사용한다.
        let order = FuturesOrderViewController(reactor: futures, instrument: position.order.instrument)
        order.captureOrderPrice = capture
        controller = order
      }
      // 처음 시세가 없는 종료 시트도 값을 비워 두지 않고 미확인으로 표시한다.
      if closing { priceAvailable = false }
      // 알럿 표시와 입력 보존까지 확인할 작은 창이다.
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 667))
      window.rootViewController = controller
      window.makeKeyAndVisible()
      defer { controller.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil }
      waitForNoticeUpdates(0.05)
      if closing {
        XCTAssertEqual((descendants(controller.view).first { $0.accessibilityIdentifier == "futuresCloseEstimatedPnL" } as? UILabel)?.text, "—")
        XCTAssertEqual((descendants(controller.view).first { $0.accessibilityIdentifier == "futuresCloseReceivedAmount" } as? UILabel)?.text, "—")
        priceAvailable = true
      }
      // 입력값 자체가 잘못돼도 버튼은 활성 상태를 유지한다.
      let input = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == (closing ? "futuresCloseQuantity" : "futuresMargin") } as? UITextField)
      // 현재 주문의 마지막 제출 버튼이다.
      let submit = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == (closing ? "futuresCloseSubmit" : "futuresSubmit") } as? UIButton)
      func checkAlert(_ key: String) {
        XCTAssertTrue(submit.isEnabled)
        submit.sendActions(for: .touchUpInside)
        waitForNoticeUpdates(0.35)
        XCTAssertEqual((controller.presentedViewController as? UIAlertController)?.message, FuturesText.text(key))
        XCTAssertFalse(descendants(controller.view).compactMap { $0 as? UILabel }.contains { $0.text == FuturesText.text(key) })
        XCTAssertFalse(futures.stub.actions.contains { if case .open = $0 { return true }; if case .closeQuantity = $0 { return true }; return false })
        controller.dismiss(animated: false)
        waitForNoticeUpdates(0.05)
        XCTAssertFalse(descendants(controller.view).compactMap { $0 as? UILabel }.contains { $0.text == FuturesText.text(key) })
      }
      input.text = "0"
      input.sendActions(for: .editingChanged)
      checkAlert(closing ? "futures_close_invalid" : "futures_input_error")
      input.text = "1000"
      input.sendActions(for: .editingChanged)
      checkAlert(closing ? "futures_close_invalid" : "futures_margin_exceeds_balance")
      input.text = "1"
      input.sendActions(for: .editingChanged)
      state = futures.reduce(state: state, mutation: .status(.paused))
      state = futures.reduce(state: state, mutation: .status(.refreshing))
      futures.stub.state.value = state
      checkAlert("futures_order_not_ready")
      state = futures.reduce(state: state, mutation: .network(false))
      futures.stub.state.value = state
      checkAlert("network_lost")
      state = futures.reduce(state: state, mutation: .network(true))
      state = futures.reduce(state: state, mutation: .status(.finished([.init(positionID: position.id, verifiedThrough: 1, liquidated: false, hold: nil)])))
      futures.stub.state.value = state
      priceAvailable = false
      checkAlert("futures_socket_wait")
      priceAvailable = true
      if let order = controller as? FuturesOrderViewController {
        order.selectTab(1)
        checkAlert("futures_same_conditions")
        order.selectTab(0)
      }
      // 열린 폼의 포지션이 이미 종료되면 탭해도 새 거래를 만들지 않는다.
      let closedState = futures.reduce(state: state, mutation: .snapshot(.init(revision: 2, accounts: state.snapshot?.accounts ?? []), [:]))
      futures.stub.state.value = closedState
      checkAlert("futures_position_closed")
      futures.stub.state.value = state
      submit.sendActions(for: .touchUpInside)
      submit.sendActions(for: .touchUpInside)
      XCTAssertEqual(futures.stub.actions.filter { if case .open = $0 { return true }; if case .closeQuantity = $0 { return true }; return false }.count, 1)
      state = futures.reduce(state: state, mutation: .submitting(true))
      futures.stub.state.value = state
      waitForNoticeUpdates(0.05)
      XCTAssertFalse(submit.isEnabled)
      // 서버/저장 검증 실패도 단순 상태 문구 대신 알럿으로 전달된다.
      state = futures.reduce(state: state, mutation: .message(FuturesText.text("futures_retry_order")))
      state = futures.reduce(state: state, mutation: .submitting(false))
      futures.stub.state.value = state
      waitForNoticeUpdates(0.35)
      XCTAssertTrue(submit.isEnabled)
      XCTAssertEqual((controller.presentedViewController as? UIAlertController)?.message, FuturesText.text("futures_retry_order"))
      XCTAssertFalse(descendants(controller.view).compactMap { $0 as? UILabel }.contains { $0.text == FuturesText.text("futures_retry_order") })
      controller.dismiss(animated: false)
      // 같은 실패 상태를 다시 받아도 폼에 오류를 재출력하거나 알럿을 반복하지 않는다.
      futures.stub.state.value = state
      waitForNoticeUpdates(0.05)
      XCTAssertNil(controller.presentedViewController)
      XCTAssertFalse(descendants(controller.view).compactMap { $0 as? UILabel }.contains { $0.text == FuturesText.text("futures_retry_order") })
      XCTAssertEqual(input.text, "1")
    }
  }

  @MainActor
  func testCloseSummaryUsesEstimatedPnLAndReceivedAmountAcrossSizesAndThemes() throws {
    for width in [320, 393] {
      for style in [UIUserInterfaceStyle.light, .dark] {
        // 체결 전 예상 손익과 실제 수령액을 구분할 보유 포지션이다.
        let position = try FuturesCalculator.open(domesticFuturesOrder(margin: 10_000_000, price: 100))
        // 하단 미리보기는 거래 준비 여부와 별도로 입력·시세를 반영한다.
        let futures = reactor()
        futures.stub.state.value = futures.reduce(state: futures.initialState, mutation: .snapshot(.init(revision: 1, accounts: [.init(id: account, availableBalance: 900)], positions: [position]), [:]))
        // 손실 미리보기로 전환해 색상뿐 아니라 음수 부호를 확인한다.
        var price: Decimal = 110
        // 작은 화면과 테마별 종료 시트다.
        let controller = FuturesCloseViewController(reactor: futures, positionID: position.id) {
          // 표시 가격과 캡처 시각을 매번 함께 갱신한다.
          let timestamp = (try? FuturesHistoryCheckState.milliseconds(Date())) ?? 0
          return .init(quote: .init(instrument: position.order.instrument, price: price, timestamp: timestamp), requestedAt: timestamp)
        }
        controller.overrideUserInterfaceStyle = style
        // 최소 폭에서는 큰 글씨와 여러 줄 배치까지 검사한다.
        if #available(iOS 17.0, *), width == 320 { controller.traitOverrides.preferredContentSizeCategory = .extraExtraLarge }
        // 하단 버튼과 스크롤 가능한 요약의 위치를 확인한다.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: width == 320 ? 568 : 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        // 요약 영역은 확정 실현손익·잔여 수량을 표시하지 않는다.
        let summary = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresCloseSummary" } as? UIStackView)
        // 사용자에게 전달하는 두 금액을 각각 검증한다.
        let pnl = try XCTUnwrap(descendants(summary).first { $0.accessibilityIdentifier == "futuresCloseEstimatedPnL" } as? UILabel)
        // 증거금과 손익 합계는 손익과 구분되어야 한다.
        let received = try XCTUnwrap(descendants(summary).first { $0.accessibilityIdentifier == "futuresCloseReceivedAmount" } as? UILabel)
        XCTAssertEqual(pnl.text, "+10,000,000 " + FuturesText.text("currency_krw_unit"))
        XCTAssertEqual(received.text, "20,000,000 " + FuturesText.text("currency_krw_unit"))
        XCTAssertFalse(descendants(summary).compactMap { ($0 as? UILabel)?.text }.contains(FuturesText.text("futures_realized")))
        // 부분 종료의 손익만 보여주고 전체 포지션 손익과 혼동하지 않게 한다.
        let partial = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresClosePercent25" } as? UIButton)
        partial.sendActions(for: .touchUpInside)
        XCTAssertEqual(pnl.text, "+2,500,000 " + FuturesText.text("currency_krw_unit"))
        XCTAssertEqual(received.text, "5,000,000 " + FuturesText.text("currency_krw_unit"))
        price = 95
        partial.sendActions(for: .touchUpInside)
        XCTAssertEqual(pnl.text, "-1,250,000 " + FuturesText.text("currency_krw_unit"))
        XCTAssertEqual(received.text, "1,250,000 " + FuturesText.text("currency_krw_unit"))
        XCTAssertEqual(pnl.textColor.resolvedColor(with: controller.traitCollection), MarketColorPalette.fallColor.resolvedColor(with: controller.traitCollection))
        controller.view.layoutIfNeeded()
        // 좁은 화면은 요약까지 스크롤하면 모든 라벨을 읽을 수 있어야 한다.
        let scroll = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIScrollView }.first)
        scroll.scrollRectToVisible(summary.convert(summary.bounds, to: scroll), animated: false)
        controller.view.layoutIfNeeded()
        for label in descendants(summary).compactMap({ $0 as? UILabel }) {
          XCTAssertFalse(label.hasAmbiguousLayout)
          XCTAssertGreaterThan(label.bounds.width, 0)
          XCTAssertGreaterThanOrEqual(label.bounds.height + 1, label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height)
        }
        // 긴 수령액 제목은 큰 글씨에서도 한 글자씩 쪼개지 않고 금액과 분리한다.
        if width == 320 {
          XCTAssertEqual((summary.arrangedSubviews.last as? UIStackView)?.axis, .vertical)
        }
        XCTAssertEqual(summary.backgroundColor?.resolvedColor(with: controller.traitCollection), UIColor.mobitColors(.tradeControlSurface).resolvedColor(with: controller.traitCollection))
        // 실제 라이트/다크 및 작은 화면 결과를 시각 검토할 수 있도록 저장한다.
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image { controller.view.layer.render(in: $0.cgContext) })
        attachment.name = "Close-summary-\(width)-\(style == .dark ? "dark" : "light")"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
    }
  }

  @MainActor
  func testCloseCardPresetsUnitsAndLayoutAcrossSizesAndThemes() throws {
    for width in [320, 393] {
      for style in [UIUserInterfaceStyle.light, .dark] {
        // 첨부 예시와 같은 큰 수량의 숏 포지션을 표시한다.
        let position = try FuturesCalculator.open(domesticFuturesOrder(symbol: "KRW-ICX", side: .short, leverage: 20, margin: 10_000_000, price: 17))
        // 실제 거래 상태 대신 표시·입력 경계만 제어한다.
        let futures = reactor()
        futures.stub.state.value = futures.reduce(state: futures.initialState, mutation: .snapshot(.init(revision: 1, accounts: [.init(id: account, availableBalance: 900)], positions: [position]), [:]))
        // 카드와 입력·예상 금액을 모두 실제 UIKit으로 구성한다.
        let controller = FuturesCloseViewController(reactor: futures, positionID: position.id) {
          // 계산 기준만 고정하고 시세 시각은 매번 최신으로 제공한다.
          let timestamp = (try? FuturesHistoryCheckState.milliseconds(Date())) ?? 0
          return .init(quote: .init(instrument: position.order.instrument, price: Decimal(string: "15.4") ?? 0, timestamp: timestamp), requestedAt: timestamp)
        }
        // 작은 화면도 스크롤로 마지막 정보에 접근해야 한다.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: width == 320 ? 568 : 852))
        window.overrideUserInterfaceStyle = style
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        if #available(iOS 17.0, *) { window.updateTraitsIfNeeded() }
        controller.view.layoutIfNeeded()
        // 위·아래가 고정된 콘텐츠 스크롤이다.
        let scroll = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresCloseScroll" } as? UIScrollView)
        // 카드가 실제 포지션의 종목을 표시해야 한다.
        let market = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresCloseMarket" } as? UILabel)
        XCTAssertEqual(market.text, "ICX / KRW")
        // 단위는 입력 숫자와 별도 라벨로 유지한다.
        let units = descendants(scroll).compactMap { ($0 as? UILabel)?.text }
        XCTAssertTrue(units.contains("KRW"))
        XCTAssertTrue(units.contains("ICX"))
        // 원금 입력과 빠른 선택 버튼을 서로 동기화한다.
        let amount = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresCloseAmount" } as? UITextField)
        // 기본 선택 100%는 테두리와 접근성 선택 상태로 구분된다.
        let all = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresClosePercent100" } as? UIButton)
        // 직접 입력으로도 25%가 선택되어야 한다.
        let quarter = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresClosePercent25" } as? UIButton)
        XCTAssertTrue(all.isSelected)
        amount.text = "2500000"
        amount.sendActions(for: .editingChanged)
        XCTAssertTrue(quarter.isSelected)
        XCTAssertTrue(quarter.accessibilityTraits.contains(.selected))
        XCTAssertFalse(all.isSelected)
        amount.text = "wrong"
        amount.sendActions(for: .editingChanged)
        XCTAssertFalse(quarter.isSelected)
        all.sendActions(for: .touchUpInside)
        XCTAssertEqual(amount.text, "10,000,000")
        controller.view.layoutIfNeeded()
        // 카드 첫 화면과 하단 정산 정보를 따로 남긴다.
        for bottom in [false, true] {
          scroll.setContentOffset(CGPoint(x: 0, y: bottom ? max(0, scroll.contentSize.height - scroll.bounds.height) : 0), animated: false)
          controller.view.layoutIfNeeded()
          // 모든 텍스트는 단위·문구 길이에 따라 높이를 확보한다.
          for label in descendants(scroll).compactMap({ $0 as? UILabel }).filter({ $0.numberOfLines == 0 }) {
            XCTAssertFalse(label.hasAmbiguousLayout)
            XCTAssertGreaterThan(label.bounds.width, 0)
            XCTAssertGreaterThanOrEqual(label.bounds.height + 1, label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height)
          }
          // 실제 렌더링의 여백·강조·테마를 검토할 이미지다.
          let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image { controller.view.layer.render(in: $0.cgContext) })
          attachment.name = "Close-card-\(width)-\(style == .dark ? "dark" : "light")-\(bottom ? "bottom" : "top")"
          attachment.lifetime = .keepAlways
          add(attachment)
        }
        // 키보드가 점유하는 하단 공간을 동일한 안전 영역 경계로 재현한다.
        controller.additionalSafeAreaInsets.bottom = 250
        controller.view.layoutIfNeeded()
        // 버튼과 입력 영역은 줄어든 가용 높이에서도 겹치지 않는다.
        let submit = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresCloseSubmit" } as? UIButton)
        XCTAssertLessThanOrEqual(submit.frame.maxY, controller.view.keyboardLayoutGuide.layoutFrame.minY)
        XCTAssertLessThanOrEqual(scroll.frame.maxY, submit.frame.minY)
        for field in descendants(scroll).compactMap({ $0 as? UITextField }) {
          scroll.scrollRectToVisible(field.convert(field.bounds, to: scroll), animated: false)
          XCTAssertTrue(scroll.bounds.insetBy(dx: -1, dy: -1).contains(field.convert(field.bounds, to: scroll)))
        }
      }
    }
  }

  @MainActor
  func testCloseCardFieldsRemainReachableWithRealKeyboard() throws {
    // 실제 시스템 키보드와 안전 영역을 제공하는 앱 Scene이다.
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    // 검증이 끝나면 기존 창의 입력 상태로 복구한다.
    let previousWindow = scene.windows.first { $0.isKeyWindow }
    // 외부 통신 없이 종료 시트에 표시할 포지션이다.
    let position = try FuturesCalculator.open(domesticFuturesOrder(margin: 10_000_000, price: 100))
    // 입력과 UI 갱신에는 실제 Reactor 상태를 사용한다.
    let futures = reactor()
    futures.stub.state.value = futures.reduce(state: futures.initialState, mutation: .snapshot(.init(revision: 1, accounts: [.init(id: account, availableBalance: 900)], positions: [position]), [:]))
    // 작은 Simulator의 실제 화면과 키보드 높이로 표시한다.
    let controller = FuturesCloseViewController(reactor: futures, positionID: position.id) {
      // 미리보기 가격은 입력 중에도 유효한 시각을 사용한다.
      let timestamp = (try? FuturesHistoryCheckState.milliseconds(Date())) ?? 0
      return .init(quote: .init(instrument: position.order.instrument, price: 105, timestamp: timestamp), requestedAt: timestamp)
    }
    // 키보드는 Scene에 연결된 창에서만 실제로 표시된다.
    let window = UIWindow(windowScene: scene)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer {
      window.endEditing(true)
      window.isHidden = true
      window.rootViewController = nil
      previousWindow?.makeKeyAndVisible()
    }
    waitForNoticeUpdates(0.3)
    // 실제 스크롤 영역과 하단 고정 제출 버튼이다.
    let scroll = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresCloseScroll" } as? UIScrollView)
    // 버튼은 키보드와 입력 영역 사이에 고정된다.
    let submit = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresCloseSubmit" } as? UIButton)
    for style in [UIUserInterfaceStyle.light, .dark] {
      window.overrideUserInterfaceStyle = style
      for field in descendants(scroll).compactMap({ $0 as? UITextField }) {
        XCTAssertTrue(field.becomeFirstResponder())
        // 하드웨어 키보드만 연결된 실행을 실제 소프트웨어 키보드 검증으로 오인하지 않는다.
        let shown = XCTNSPredicateExpectation(
          predicate: NSPredicate { _, _ in
            controller.view.bounds.maxY - controller.view.keyboardLayoutGuide.layoutFrame.minY > 150
          },
          object: nil
        )
        wait(for: [shown], timeout: 5)
        waitForNoticeUpdates(0.4)
        controller.view.layoutIfNeeded()
        XCTAssertLessThanOrEqual(submit.frame.maxY, controller.view.keyboardLayoutGuide.layoutFrame.minY)
        XCTAssertLessThan(scroll.frame.maxY, submit.frame.minY)
        XCTAssertTrue(scroll.bounds.insetBy(dx: -1, dy: -1).contains(field.convert(field.bounds, to: scroll)))
        // 입력을 유지하면서 요약까지 스크롤할 수 있어야 한다.
        let received = try XCTUnwrap(descendants(scroll).first { $0.accessibilityIdentifier == "futuresCloseReceivedAmount" })
        scroll.scrollRectToVisible(received.convert(received.bounds, to: scroll), animated: false)
        XCTAssertTrue(scroll.bounds.insetBy(dx: -1, dy: -1).contains(received.convert(received.bounds, to: scroll)))
        XCTAssertTrue(field.isFirstResponder)
        // 실제 키보드 경계에 맞춰 줄어든 주문 영역을 보관한다.
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image { controller.view.layer.render(in: $0.cgContext) })
        attachment.name = "Close-card-keyboard-\(style == .dark ? "dark" : "light")-\(field.accessibilityIdentifier ?? "input")"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.endEditing(true)
        waitForNoticeUpdates(0.2)
      }
    }
  }

  @MainActor
  func testSpotButtonsStayEnabledForInvalidInputsAndAlertsDoNotChangeAssets() throws {
    try withSpotCompletionStorage {
      // 매수와 매도를 같은 실제 보유 상태에서 검사한다.
      _ = try TradeOrderService.executeBid(marketName: "BTC/KRW", cryptoName: "Bitcoin", currentPrice: 1_000, quantity: 2).get()
      // 실패 전후 거래 내역과 잔고를 비교한다.
      let transactions = UserDataManager.userTransactionList
      // 실제 폼부터 상위 알럿까지 연결한다.
      let host = try makeSpotCompletionController()
      // 소형 화면에서 양쪽 폼을 번갈아 검사한다.
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 667))
      window.rootViewController = host
      window.makeKeyAndVisible()
      defer { host.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil }
      // 각 폼에 실제 잘못된 수량·잔액 조건을 전달한다.
      let bid = try XCTUnwrap(host.orderView?.bidView)
      // 보유분보다 큰 수량과 최소 미달 수량을 검사한다.
      let ask = try XCTUnwrap(host.orderView?.askView)
      for selling in [false, true] {
        host.orderView?.segmentedControl.onSegmentChanged?(selling ? 1 : 0)
        for (amount, error) in [
          (0.0, TradeOrderValidator.ValidationError.invalidQuantity),
          (0.001, .belowMinimumOrderAmount(minimum: SettlementCurrency.krw.minimumOrderAmount, currency: .krw)),
          (20.0, selling ? .insufficientHolding : .insufficientBalance(currency: .krw))
        ] {
          // 가격이나 입력이 유효하지 않아도 탭해서 이유를 확인할 수 있다.
          let button = try XCTUnwrap(selling ? ask.orderButton : bid.orderButton)
          if selling { ask.inputAmount = amount; ask.refreshMarketColors() }
          else { bid.inputAmount = amount; bid.refreshMarketColors() }
          XCTAssertTrue(button.isEnabled)
          button.sendActions(for: .touchUpInside)
          waitForNoticeUpdates(0.35)
          XCTAssertTrue(button.isEnabled)
          XCTAssertEqual((host.presentedViewController as? UIAlertController)?.message, error.message)
          // 같은 알럿이 표시된 상태에서 반복 탭해도 안내 창을 추가하지 않는다.
          let alert = host.presentedViewController
          button.sendActions(for: .touchUpInside)
          XCTAssertTrue(host.presentedViewController === alert)
          host.dismiss(animated: false)
          waitForNoticeUpdates(0.05)
        }
      }
      XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 8_000)
      XCTAssertEqual(UserDataManager.userCryptoList?.first?.staticData.holdingQuantity, 2)
      XCTAssertEqual(UserDataManager.userTransactionList, transactions)
      XCTAssertFalse(host.view.subviews.contains { $0.accessibilityIdentifier == "mobitToast" })
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
    reactor.stub.state.value = reactor.reduce(
      state: reactor.currentState,
      mutation: .status(.finished([.init(positionID: position.id, verifiedThrough: timestamp, liquidated: false, hold: nil)]))
    )
    // 부분 종료 입력과 시세 갱신을 확인할 시트다.
    let controller = FuturesCloseViewController(
      reactor: reactor,
      positionID: position.id,
      captureOrderPrice: {
        connected ? FuturesOrderPrice(quote: .init(instrument: position.order.instrument, price: price, timestamp: timestamp), requestedAt: (try? FuturesHistoryCheckState.milliseconds(Date())) ?? timestamp) : nil
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
    let summary = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresCloseReceivedAmount" } as? UILabel)
    // 시세·입력 변경으로 상태와 위치가 바뀌면 안 되는 하단 제출 버튼이다.
    let submit = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresCloseSubmit" } as? UIButton)
    window.layoutIfNeeded()
    controller.view.layoutIfNeeded()
    // 모든 시세 갱신에서 유지해야 하는 최초 버튼 위치와 크기다.
    let submitFrame = submit.frame
    // 실제 연결 준비 변경 외에는 버튼 상태가 반복해서 바뀌지 않아야 한다.
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
    func dismissAlert() {
      // 표시 애니메이션 중 닫기와 다음 탭을 겹치지 않게 실제 알럿 종료를 기다린다.
      waitForNoticeUpdates(0.35)
      // UIKit의 닫기 완료 이후에만 다시 제출할 수 있다.
      let dismissed = expectation(description: "Close error alert dismissed")
      controller.dismiss(animated: false) { dismissed.fulfill() }
      wait(for: [dismissed], timeout: 2)
    }
    flushPriceUpdates()
    XCTAssertEqual(amount.text, "100")
    amount.text = "25"
    amount.sendActions(for: .editingChanged)
    XCTAssertEqual(quantity.text, FuturesText.number(Decimal(string: "2.5")))
    price = 125
    priceUpdates.onNext(())
    flushPriceUpdates()
    XCTAssertEqual(amount.text, "25")
    XCTAssertEqual(quantity.text, FuturesText.number(Decimal(string: "2.5")))
    XCTAssertTrue(summary.text?.contains(FuturesText.number(Decimal(string: "87.5"))) == true)
    quantity.text = "3"
    quantity.sendActions(for: .editingChanged)
    price = 130
    priceUpdates.onNext(())
    flushPriceUpdates()
    XCTAssertEqual(quantity.text, "3")
    XCTAssertEqual(amount.text, "30")
    XCTAssertTrue(summary.text?.contains("120") == true)
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
    dismissAlert()
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
    dismissAlert()
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
    dismissAlert()
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
    XCTAssertTrue(summary.text?.contains("30") == true)
    // 제출 시점에는 화면 갱신 주기와 무관하게 최신 체결 가격을 다시 읽는다.
    price = 130
    observation.invalidate()
    XCTAssertFalse(enabledChanges.contains(false))
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
    XCTAssertFalse(submit.isEnabled)
    submit.sendActions(for: .touchUpInside)
    XCTAssertEqual(reactor.stub.actions.filter { if case .closeQuantity = $0 { return true }; return false }.count, 1)
    // 주문 검증이 실패하면 알럿을 띄우고 입력을 유지한 채 재시도를 허용한다.
    var failedState = submittingState
    failedState.submitting = false
    failedState.message = FuturesText.text("futures_retry_order")
    reactor.stub.state.value = failedState
    XCTAssertEqual((controller.presentedViewController as? UIAlertController)?.message, FuturesText.text("futures_retry_order"))
    dismissAlert()
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
          XCTAssertEqual(button.layer.borderWidth, button.isSelected ? 2 : 1)
          XCTAssertEqual(button.layer.borderColor, UIColor.mobitColors(button.isSelected ? .accentPrimary : .tradeSeparator).resolvedColor(with: button.traitCollection).cgColor)
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

  @MainActor
  func testConcurrentLoadingOwnersKeepOneOverlayUntilBothFinishAndCleanUpOnRelease() throws {
    // 같은 창에서 최초 조회와 복귀 검증의 표시 요청이 겹치는 상황이다.
    let first = MobitBaseViewController()
    // 표시를 요청하지 않은 화면의 종료 호출은 영향을 주면 안 된다.
    let unrelated = MobitBaseViewController()
    // 실제 창에 오버레이를 추가해 개수와 제거 시점을 확인한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
    window.rootViewController = first
    window.isHidden = false
    defer { window.isHidden = true; window.rootViewController = nil }
    // 해제 대상 화면을 강하게 캡처하지 않고 생존 여부만 관찰한다.
    let remainingOwners = NSHashTable<MobitBaseViewController>.weakObjects()
    func flush() {
      // 메인 큐의 표시·종료 처리를 기다린다.
      let rendered = expectation(description: "Concurrent loading rendered")
      DispatchQueue.main.async { rendered.fulfill() }
      wait(for: [rendered], timeout: 2)
    }
    // UIKit의 임시 참조 수명을 테스트 전체가 아니라 이 화면의 수명에 맞춘다.
    try autoreleasepool {
      // 먼저 표시한 화면이 끝나도 두 번째 작업의 표시가 유지돼야 한다.
      let second = MobitBaseViewController()
      first.addChild(second)
      first.view.addSubview(second.view)
      second.didMove(toParent: first)
      first.showLoadingIndicator()
      second.showLoadingIndicator()
      second.showLoadingIndicator()
      flush()
      // 중복 호출도 같은 Lottie 하나를 공유해야 한다.
      let overlay = try XCTUnwrap(window.viewWithTag(999_999))
      XCTAssertEqual(window.subviews.filter { $0.tag == 999_999 }.count, 1)
      unrelated.hideLoadingIndicator()
      first.hideLoadingIndicator()
      flush()
      XCTAssertTrue(window.viewWithTag(999_999) === overlay)
      second.hideLoadingIndicator()
      flush()
      XCTAssertNil(window.viewWithTag(999_999))
      second.showLoadingIndicator()
      flush()
      XCTAssertNotNil(window.viewWithTag(999_999))
      remainingOwners.add(second)
      second.willMove(toParent: nil)
      second.view.removeFromSuperview()
      second.removeFromParent()
    }
    // 실제 화면 해제 이후 메인 큐의 정리까지 완료돼야 한다.
    let released = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in remainingOwners.allObjects.isEmpty && window.viewWithTag(999_999) == nil },
      object: nil
    )
    wait(for: [released], timeout: 3)
    XCTAssertTrue(remainingOwners.allObjects.isEmpty)
    XCTAssertNil(window.viewWithTag(999_999))
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

  func testNormalVerificationIsSilentAndActualFailuresKeepLastValuation() throws {
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
      XCTAssertEqual(!FuturesText.status(reactor).isEmpty, reactor.needsDataRetry)
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

  func testHeldVerificationDisplaysSavedValuationWithoutUsingUnverifiedProfit() throws {
    // 보류 중 표시와 주문 허용 조건을 독립적으로 확인한다.
    let reactor = reactor()
    // 이미 확인한 가격이 있는 정상 보유 포지션이다.
    let position = try FuturesCalculator.open(domesticFuturesOrder())
    // 검증 완료된 과거 가격만 표시용 대체값으로 사용할 수 있다.
    var verification = try FuturesHistoryCheckState.initial(for: position)
    verification.verifiedThrough = 120_000
    verification.lastVerifiedMark = 110_000_000
    // 미검증 가격이 먼저 도착해도 저장된 평가값이 유지돼야 한다.
    let snapshot = FuturesAccountSnapshot(
      revision: 1,
      accounts: [.init(id: account, availableBalance: 900_000)],
      positions: [position],
      historyCheckStates: [verification]
    )
    // 과거 청산 확인 전에는 큰 이익으로 표시하면 안 되는 현재가다.
    let quote = FuturesMarkQuote(instrument: position.order.instrument, price: 150_000_000, timestamp: 125_000)
    // REST·소켓 표시 가격 자체는 손실 없이 유지한다.
    var state = reactor.reduce(state: reactor.initialState, mutation: .snapshot(snapshot, [quote.instrument: quote]))
    for status in [
      FuturesRefreshStatus.refreshing,
      .finished([.init(positionID: position.id, verifiedThrough: 120_000, liquidated: false, hold: .missingHistory)]),
      .refreshing
    ] {
      state = reactor.reduce(state: state, mutation: .status(status))
      reactor.stub.state.value = state
      XCTAssertTrue(reactor.canDisplayValuation)
      XCTAssertFalse(reactor.canSubmit)
      XCTAssertEqual(reactor.currentState.quotes[quote.instrument], quote)
      XCTAssertEqual(reactor.valuationQuotes[quote.instrument]?.price, 110_000_000)
      XCTAssertEqual(try FuturesText.valuation(position, quotes: reactor.valuationQuotes)?.displayedEquity, 200_000)
      XCTAssertEqual(try FuturesText.valuation(position, quotes: reactor.valuationQuotes)?.displayedPnL, 100_000)
      XCTAssertEqual(try FuturesText.valuation(position, quotes: reactor.valuationQuotes)?.displayedROEPercent, 100)
    }
    reactor.stub.state.value = reactor.reduce(
      state: state,
      mutation: .status(.finished([.init(positionID: position.id, verifiedThrough: 125_000, liquidated: false, hold: nil)]))
    )
    XCTAssertEqual(reactor.valuationQuotes[quote.instrument], quote)
    XCTAssertEqual(try FuturesText.valuation(position, quotes: reactor.valuationQuotes)?.displayedEquity, 600_000)
  }

  func testPeriodicRefreshRetainsLiveValuationAndPauseFreezesLastConfirmedQuote() throws {
    // 화면이 바뀌어도 현재가와 검증 가격을 별도로 관리한다.
    let reactor = reactor()
    // 저장된 경계 이후에도 완료한 검증 가격이 존재하는 포지션이다.
    let position = try FuturesCalculator.open(domesticFuturesOrder(margin: 100, price: 100))
    // 파일에 저장된 가격은 마지막 완료 결과보다 이전일 수 있다.
    var verification = try FuturesHistoryCheckState.initial(for: position)
    verification.lastVerifiedMark = 102
    // 저장 가격과 화면 현재가의 우선순위를 확인한다.
    let snapshot = FuturesAccountSnapshot(
      revision: 1,
      accounts: [.init(id: account, availableBalance: 900)],
      positions: [position],
      historyCheckStates: [verification]
    )
    // 검증 전 표시하면 손익을 크게 오인할 수 있는 현재가다.
    let quote = FuturesMarkQuote(instrument: position.order.instrument, price: 134, timestamp: 125_000)
    reactor.stub.state.value = reactor.reduce(
      state: reactor.initialState,
      mutation: .snapshot(snapshot, [quote.instrument: quote])
    )
    XCTAssertEqual(reactor.valuationQuotes[quote.instrument]?.price, 102)
    // 파일 저장 간격과 무관하게 완료 시 확인한 가격을 재사용한다.
    let finished = FuturesRefreshResult(
      positionID: position.id,
      verifiedThrough: 124_000,
      liquidated: false,
      hold: nil,
      lastVerifiedMark: 105
    )
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .status(.finished([finished])))
    XCTAssertEqual(reactor.valuationQuotes[quote.instrument]?.price, 134)
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .status(.refreshing))
    XCTAssertEqual(reactor.valuationQuotes[quote.instrument]?.price, 134)
    XCTAssertEqual(try FuturesText.valuation(position, quotes: reactor.valuationQuotes)?.displayedPnL, 340)
    XCTAssertEqual(reactor.currentState.quotes[quote.instrument]?.price, 134)
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .status(.finished([finished])))
    XCTAssertEqual(reactor.valuationQuotes[quote.instrument]?.price, 134)
    XCTAssertEqual(try FuturesText.valuation(position, quotes: reactor.valuationQuotes)?.displayedPnL, 340)
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
    controller.captureOrderPrice = {
      // 실제 주문 화면처럼 연결된 소켓의 가격과 요청 시각을 제공한다.
      let timestamp = (try? FuturesHistoryCheckState.milliseconds(Date())) ?? 0
      return FuturesOrderPrice(quote: .init(instrument: position.order.instrument, price: 100_000_000, timestamp: timestamp), requestedAt: timestamp)
    }
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
    XCTAssertTrue(reactor.hasVerificationFailure)
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
    controller.captureOrderPrice = {
      // 버튼 허용 판정에 필요한 해당 종목 소켓 가격을 제공한다.
      let timestamp = (try? FuturesHistoryCheckState.milliseconds(Date())) ?? 0
      return FuturesOrderPrice(quote: .init(instrument: position.order.instrument, price: 100_000_000, timestamp: timestamp), requestedAt: timestamp)
    }
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
    XCTAssertTrue(submit.isEnabled)
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
    XCTAssertTrue(submit.isEnabled)
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
    XCTAssertTrue(submit.isEnabled)
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
  func testSocketQuotesRemainSeparateFromPositionValuationUntilHistoryCompletes() throws {
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
    // 현재가는 계속 수신하되 검증 중 카드의 평가값은 진입 가격으로 유지한다.
    for price in [Decimal(110), Decimal(105)] {
      let updated = expectation(description: "Socket price immediately updates card")
      reactor.state.filter { $0.quotes[order.instrument]?.price == price }.take(1)
        .subscribe(onNext: { _ in DispatchQueue.main.async { updated.fulfill() } }).disposed(by: bag)
      monitor.subject.onNext(.quote(.init(instrument: order.instrument, price: price, timestamp: timestamp)))
      wait(for: [updated], timeout: 3)
      XCTAssertEqual(try label("futures_pnl").text, FuturesText.number(0))
      XCTAssertEqual(try label("futures_roe").text, "0%")
      XCTAssertEqual(try label("futures_current").text, FuturesText.number(100))
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
    // REST와 과거 검증 중에도 원본 소켓 가격은 별도로 수신해야 한다.
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
        FuturesText.number(100)
      )
      XCTAssertEqual(
        (descendants(controller.view).first { $0.accessibilityIdentifier == "futures_pnl" } as? UILabel)?.text,
        FuturesText.number(0)
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
  func testInvestmentRefreshHasNoStatusRowAndUpdatesValuationAfterVerification() throws {
    // 검증 전후 투자내역의 표시값을 비교할 포지션이다.
    let position = try FuturesCalculator.open(domesticFuturesOrder(leverage: 1, margin: 100, price: 100))
    // 화면과 공유하는 계좌 상태다.
    let futures = reactor()
    // 진입가로 시작한 저장 계좌다.
    let snapshot = FuturesAccountSnapshot(revision: 1, accounts: [.init(id: account, availableBalance: 900)], positions: [position], historyCheckStates: [try .initial(for: position)])
    // 직전 확인 가격은 수익 10을 표시한다.
    let quote = FuturesMarkQuote(instrument: position.order.instrument, price: 110, timestamp: 100_000)
    // 검증 이후 캐시를 실제 복귀 상태로 전환한다.
    var state = futures.reduce(state: futures.initialState, mutation: .snapshot(snapshot, [quote.instrument: quote]))
    state = futures.reduce(state: state, mutation: .status(.finished([.init(positionID: position.id, verifiedThrough: 100_000, liquidated: false, hold: nil)])))
    futures.stub.state.value = state
    // 정상 목록 상태로 화면 생성만 지원한다.
    let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
    market.isStubEnabled = true
    // 원래 XIB의 목록 위치를 비교할 기존 현물 화면이다.
    let spot = InvestReactor(mainUseCase: try FuturesMainFixtureUseCase())
    spot.isStubEnabled = true
    // 현물과 선물이 공유하는 XIB의 원래 목록 위치다.
    let original = InvestmentViewController(reactor: spot)
    original.loadViewIfNeeded()
    original.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
    original.view.layoutIfNeeded()
    // 추가 상태 행이 없어야 하는 선물 투자내역이다.
    let controller = FuturesInvestmentViewController(reactor: futures, marketReactor: market)
    controller.loadViewIfNeeded()
    controller.view.frame = original.view.frame
    func send(_ mutation: FuturesAccountReactor.Mutation) {
      state = futures.reduce(state: state, mutation: mutation)
      futures.stub.state.value = state
      // diffable 목록과 UI 바인딩을 반영한다.
      let rendered = expectation(description: "Investment refresh rendered")
      DispatchQueue.main.async { DispatchQueue.main.async { rendered.fulfill() } }
      wait(for: [rendered], timeout: 2)
      controller.view.layoutIfNeeded()
      XCTAssertNil(controller.tableView(controller.transactionTableview, viewForFooterInSection: 0))
      XCTAssertFalse(descendants(controller.view).contains { $0 is FuturesDataStatusView })
      XCTAssertFalse(descendants(controller.view).contains { ($0 as? UIActivityIndicatorView)?.isAnimating == true })
      // 목록은 원래 XIB와 같은 위치에서 시작해야 한다.
      XCTAssertEqual(controller.transactionTableview.convert(controller.transactionTableview.bounds, to: controller.view).minY, original.transactionTableview.convert(original.transactionTableview.bounds, to: original.view).minY, accuracy: 0.5)
    }
    send(.status(.refreshing))
    XCTAssertEqual(controller.totalEvalProfitLoss.text, "+10")
    send(.status(.paused))
    send(.status(.refreshing))
    for hold in [FuturesHistoryCheckHold.workLimit, .currentInterval, .revisionChanged] {
      send(.status(.finished([.init(positionID: position.id, verifiedThrough: 100_000, liquidated: false, hold: hold)])))
      XCTAssertFalse(futures.canSubmit)
      send(.status(.refreshing))
    }
    send(.quote(.init(instrument: quote.instrument, price: 120, timestamp: 110_000)))
    XCTAssertEqual(controller.totalEvalProfitLoss.text, "+10")
    send(.status(.finished([.init(positionID: position.id, verifiedThrough: 110_000, liquidated: false, hold: nil)])))
    XCTAssertEqual(controller.totalEvalProfitLoss.text, "+20")
    XCTAssertEqual(controller.transactionTableview.numberOfRows(inSection: 0), 1)
    // 갱신 문구 없이 정상 목록이 표시되는 화면 검토 자료다.
    let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image { controller.view.layer.render(in: $0.cgContext) })
    attachment.name = "Investment without refresh row"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func testInvestmentErrorAndRetryRemainVisibleInOriginalListFooter() throws {
    // 빈 계좌에서는 오류를 빈 보유 내역으로 잘못 표시하면 안 된다.
    let futures = reactor()
    // 빈 계좌가 먼저 정상 표시된 뒤 오류·복구 전이를 검사한다.
    let snapshot = FuturesAccountSnapshot(revision: 1, accounts: [.init(id: account, availableBalance: 1000)])
    // 정상 계좌는 오류 footer 없이 빈 결과를 표시한다.
    var state = futures.reduce(state: futures.initialState, mutation: .snapshot(snapshot, [:]))
    state = futures.reduce(state: state, mutation: .status(.finished([])))
    futures.stub.state.value = state
    // 화면 레이아웃에 영향을 주지 않는 고정 목록 상태다.
    let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
    market.isStubEnabled = true
    // 기존 목록 배치에서 빈 결과 뷰가 오류 footer를 가리지 않아야 한다.
    let controller = FuturesInvestmentViewController(reactor: futures, marketReactor: market)
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
    controller.view.layoutIfNeeded()
    // 메인 스레드 바인딩 뒤에 오류 UI를 검사한다.
    let rendered = expectation(description: "Investment error rendered")
    DispatchQueue.main.async { DispatchQueue.main.async { rendered.fulfill() } }
    wait(for: [rendered], timeout: 2)
    controller.view.layoutIfNeeded()
    XCTAssertFalse(controller.noResultView.isHidden)
    XCTAssertLessThan(controller.transactionTableview.rectForFooter(inSection: 0).height, 1)
    state = futures.reduce(state: state, mutation: .loadFailed)
    futures.stub.state.value = state
    // 빈 목록의 동일한 diffable section에도 오류 footer가 실제로 생성돼야 한다.
    let failed = expectation(description: "Investment error footer rendered")
    DispatchQueue.main.async { DispatchQueue.main.async { failed.fulfill() } }
    wait(for: [failed], timeout: 2)
    controller.view.layoutIfNeeded()
    // 상태 영역을 포함하는 재시도 버튼이다.
    let retry = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futures.data.retry" } as? UIButton)
    // 실제 오류일 때만 생성하는 목록 footer의 상태 뷰다.
    let status = try XCTUnwrap(retry.superview as? FuturesDataStatusView)
    XCTAssertFalse(status.isHidden)
    XCTAssertFalse(retry.isHidden)
    XCTAssertTrue(controller.noResultView.isHidden)
    XCTAssertFalse(descendants(status).contains { ($0 as? UIActivityIndicatorView)?.isAnimating == true })
    XCTAssertEqual((descendants(status).first { $0.accessibilityIdentifier == "futures.data.status" } as? UILabel)?.text, FuturesText.text("futures_storage_error"))
    // 빈 결과 뷰가 오류·재시도 영역을 가리지 않아야 한다.
    let statusFrame = status.convert(status.bounds, to: controller.view)
    // 오류 안내도 기존 목록 영역 안에 배치한다.
    let tableFrame = controller.transactionTableview.convert(controller.transactionTableview.bounds, to: controller.view)
    XCTAssertGreaterThanOrEqual(statusFrame.minY, tableFrame.minY)
    XCTAssertLessThanOrEqual(statusFrame.maxY, tableFrame.maxY)
    XCTAssertGreaterThan(statusFrame.height, 20)
    XCTAssertLessThanOrEqual(statusFrame.maxX, controller.view.bounds.maxX)
    retry.sendActions(for: .touchUpInside)
    XCTAssertTrue(futures.stub.actions.contains { if case .reload = $0 { return true }; return false })
    // 오류와 재시도 배치를 작은 화면에서 시각적으로 확인한다.
    let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { controller.view.layer.render(in: $0.cgContext) }
    // 빈 계좌 오류 화면의 시각 검증 자료다.
    let attachment = XCTAttachment(image: image)
    attachment.name = "Readiness investment error 320"
    attachment.lifetime = .keepAlways
    add(attachment)
    state = futures.reduce(state: state, mutation: .snapshot(snapshot, [:]))
    state = futures.reduce(state: state, mutation: .status(.finished([])))
    futures.stub.state.value = state
    // 복구 후에도 오류 footer의 공간이 남지 않아야 한다.
    let recovered = expectation(description: "Investment recovered footer removed")
    DispatchQueue.main.async { DispatchQueue.main.async { recovered.fulfill() } }
    wait(for: [recovered], timeout: 2)
    controller.view.layoutIfNeeded()
    XCTAssertFalse(controller.noResultView.isHidden)
    XCTAssertLessThan(controller.transactionTableview.rectForFooter(inSection: 0).height, 1)
    XCTAssertNil(controller.tableView(controller.transactionTableview, viewForFooterInSection: 0))
  }

  @MainActor
  func testMainRequestTimeoutShowsErrorAndRetryRecoversWithoutResettingSelection() throws {
    // 앱에서 사용하는 20초 경계를 가상 시계로 검증한다.
    let scheduler = HistoricalScheduler(initialClock: Date(timeIntervalSince1970: 0))
    // 응답이 영원히 오지 않는 최초 목록 요청이다.
    let useCase = try FuturesMainFixtureUseCase()
    useCase.marketResponse = .never()
    // 실제 Reactor·화면 바인딩과 제어 가능한 시간 축이다.
    let market = MainReactor(mainUseCase: useCase, tickerSocketService: FuturesMainFixtureSocket(), requestScheduler: scheduler)
    // 네트워크 안내와 요청 자체의 실패를 구분한다.
    let main = MainViewController(reactor: market, networkAvailability: .empty())
    main.loadViewIfNeeded()
    market.action.onNext(.setSelectedTab(tab: .favorite))
    market.action.onNext(.loadCryptoList)
    XCTAssertTrue(market.currentState.isLoading)
    market.action.onNext(.loadCryptoList)
    XCTAssertEqual(useCase.marketRequests, 1)
    scheduler.advanceTo(Date(timeIntervalSince1970: 19.999))
    XCTAssertTrue(market.currentState.isLoading)
    XCTAssertNil(market.currentState.errorMessage)
    scheduler.advanceTo(Date(timeIntervalSince1970: 20))
    XCTAssertFalse(market.currentState.isLoading)
    XCTAssertNotNil(market.currentState.errorMessage)
    XCTAssertEqual(market.currentState.selectedTab, .favorite)
    XCTAssertNil(main.presentedViewController)
    // 오류 안내의 재시도와 동일한 진입점으로 선택 탭을 유지하며 복구한다.
    useCase.marketResponse = nil
    main.retryMainData()
    XCTAssertEqual(useCase.marketRequests, 2)
    XCTAssertFalse(market.currentState.isLoading)
    XCTAssertNil(market.currentState.errorMessage)
    XCTAssertEqual(market.currentState.totalCryptoList.count, 2)
    XCTAssertEqual(market.currentState.selectedTab, .favorite)
    XCTAssertFalse(descendants(main.view).contains { $0.accessibilityIdentifier == "market.dataStatus" })
  }

  @MainActor
  func testPersistentDataAlertClosesOnRecoveryAndDoesNotRepeatAfterRetryOrModeReentry() throws {
    // UIKit 알럿 표시·종료는 실제 Scene 창에서 확인한다.
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    // 호스트 앱의 key window를 테스트 종료 때 복원한다.
    let previousWindow = scene.windows.first { $0.isKeyWindow }
    // 서비스의 표시 이력을 공유하는 계좌 화면이다.
    let service = FuturesHistoryCheckService(
      store: { throw LocalFuturesAccountRepository.StoreError.invalidStoredData },
      provider: { _ in nil }
    )
    // 표시 상태만 제어하고 실제 계좌·호스트 서비스에는 영향을 주지 않는다.
    let futures = FuturesAccountReactor(account: account, historyCheck: service)
    futures.isStubEnabled = true
    // 보유 포지션이 있을 때 미검증 거래 제한도 함께 확인한다.
    let position = try FuturesCalculator.open(domesticFuturesOrder())
    // 화면 표시와 실제 거래 준비를 서로 다른 상태로 제어한다.
    var state = futures.reduce(
      state: futures.initialState,
      mutation: .snapshot(.init(revision: 1, accounts: [.init(id: account, availableBalance: 100)], positions: [position]), [:])
    )
    // 전체 화면 로딩과 자산 실패를 분리하는 정상 시세 목록이다.
    let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
    // 같은 검증 결과를 표시하는 첫 메인 화면이다.
    let main = MainViewController(reactor: market, futuresReactor: futures, networkAvailability: .just(true))
    // 테스트가 소유한 창에서만 알럿을 표시한다.
    let window = UIWindow(windowScene: scene)
    window.rootViewController = main
    window.makeKeyAndVisible()
    defer {
      window.rootViewController?.dismiss(animated: false)
      window.isHidden = true
      window.rootViewController = nil
      previousWindow?.makeKeyAndVisible()
    }
    func render(_ mutation: FuturesAccountReactor.Mutation) {
      state = futures.reduce(state: state, mutation: mutation)
      futures.stub.state.value = state
      waitForNoticeUpdates(0.1)
    }
    market.action.onNext(.loadCryptoList)
    waitForNoticeUpdates(0.3)
    // 한두 번의 실패는 오류 문구 없이 거래만 제한한다.
    let failureID = UUID()
    render(.status(.finished([.init(positionID: position.id, verifiedThrough: nil, liquidated: false, hold: .requestFailed)])))
    render(.dataFailure(.init(id: failureID, account: account, attempts: 2, hold: .requestFailed)))
    XCTAssertNil(main.presentedViewController)
    XCTAssertFalse(futures.canSubmit)
    // 같은 오류가 지속되었을 때에만 최초 알럿을 표시한다.
    render(.dataFailure(.init(id: failureID, account: account, attempts: 3, hold: .requestFailed)))
    XCTAssertEqual((main.presentedViewController as? UIAlertController)?.message, FuturesText.text("futures_data_held"))
    // 알럿을 확인하지 않아도 실제 복구가 먼저 끝나면 자동으로 닫는다.
    render(.dataFailure(nil))
    XCTAssertFalse(futures.needsDataRetry)
    render(.status(.finished([.init(positionID: position.id, verifiedThrough: 100_000, liquidated: false, hold: nil)])))
    // 표시 애니메이션 도중 복구돼도 표시 완료 후 자동 종료되어야 한다.
    let recoveredAlert = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      main.presentedViewController == nil
    }, object: nil)
    wait(for: [recoveredAlert], timeout: 2)
    XCTAssertNil(main.presentedViewController)
    XCTAssertTrue(futures.canSubmit)
    // 복구 뒤 새 실패 구간은 다시 한 번 알릴 수 있다.
    let nextFailureID = UUID()
    render(.status(.finished([.init(positionID: position.id, verifiedThrough: nil, liquidated: false, hold: .missingHistory)])))
    render(.dataFailure(.init(id: nextFailureID, account: account, attempts: 3, hold: .missingHistory)))
    waitForNoticeUpdates(0.4)
    XCTAssertNotNil(main.presentedViewController)
    // 확인/재시도 버튼처럼 UIKit의 실제 닫기 완료 이후 재조회한다.
    let dismissed = expectation(description: "Retry alert dismissed")
    main.dismiss(animated: false) { dismissed.fulfill() }
    wait(for: [dismissed], timeout: 2)
    main.retryMainData()
    render(.status(.refreshing))
    XCTAssertNil(main.presentedViewController)
    XCTAssertFalse(futures.canSubmit)
    // 실제 상품 변경처럼 메인과 Reactor를 새로 만들어도 오류를 재노출하지 않는다.
    let nextReactor = FuturesAccountReactor(account: account, historyCheck: service)
    nextReactor.isStubEnabled = true
    nextReactor.stub.state.value = state
    // 오류 표시 이력은 개별 ViewController에 종속되지 않는다.
    let nextMain = MainViewController(reactor: market, futuresReactor: nextReactor, networkAvailability: .just(true))
    window.rootViewController = nextMain
    waitForNoticeUpdates(0.4)
    XCTAssertNil(nextMain.presentedViewController)
    XCTAssertNil(window.viewWithTag(999999))
    XCTAssertFalse(nextReactor.canSubmit)
  }

  @MainActor
  func testAutomaticVerificationIsSilentAcrossScreensAndOnlyFailuresOfferRetry() throws {
    // 화면 전체가 같은 검증 결과를 구독하는 실제 계좌 상태다.
    let futures = reactor()
    // 입력값과 마지막 평가를 보존할 보유 포지션이다.
    let position = try FuturesCalculator.open(domesticFuturesOrder(leverage: 1, margin: 100, price: 100))
    // 로컬 읽기를 마친 뒤 외부 검증만 대기하는 계좌다.
    var state = futures.reduce(
      state: futures.initialState,
      mutation: .snapshot(.init(revision: 1, accounts: [.init(id: account, availableBalance: 900)], positions: [position]), [:])
    )
    futures.stub.state.value = state
    // 정상 시세 목록을 제공하되 자산 검증과 독립적으로 갱신한다.
    let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
    // 실제 오류 알럿의 노출과 중복 여부를 확인할 메인이다.
    let main = MainViewController(reactor: market, futuresReactor: futures, networkAvailability: .empty())
    // 테스트 소유 창만 사용해 다른 화면의 key window를 바꾸지 않는다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    window.rootViewController = main
    window.isHidden = false
    main.viewWillAppear(false)
    defer {
      main.dismiss(animated: false)
      main.viewWillDisappear(false)
      window.isHidden = true
      window.rootViewController = nil
    }
    // 소켓 준비 자체도 자동 갱신 안내 없이 기다려야 한다.
    var priceAvailable = false
    // 주문·종료에 동일한 최신 표시 가격을 전달한다.
    let capture: () -> FuturesOrderPrice? = {
      guard priceAvailable else { return nil }
      // 최종 제출 시점의 신선도 조건을 만족하는 가격이다.
      let timestamp = (try? FuturesHistoryCheckState.milliseconds(Date())) ?? 0
      return .init(quote: .init(instrument: position.order.instrument, price: 110, timestamp: timestamp), requestedAt: timestamp)
    }
    // 주문 폼은 검증 중에도 입력할 수 있어야 한다.
    let order = FuturesOrderViewController(reactor: futures, instrument: position.order.instrument)
    order.captureOrderPrice = capture
    order.loadViewIfNeeded()
    // 이미 열린 종료 시트에서도 복귀 검증은 조용히 반영되어야 한다.
    let close = FuturesCloseViewController(reactor: futures, positionID: position.id, captureOrderPrice: capture, orderPriceUpdates: .empty())
    close.loadViewIfNeeded()
    // 오류가 없을 때 접혀 있어야 할 주문 안내 영역이다.
    let status = try XCTUnwrap(descendants(order.view).first { $0 is FuturesDataStatusView })
    // 종료 화면의 사용자 안내를 직접 검사한다.
    let closeStatus = try XCTUnwrap(descendants(close.view).first { $0.accessibilityIdentifier == "futuresCloseStatus" } as? UILabel)
    // 검증 전에는 실제 제출만 막는다.
    let submit = try XCTUnwrap(descendants(order.view).first { $0.accessibilityIdentifier == "futuresSubmit" } as? UIButton)
    // 종료 역시 같은 거래 허용 조건을 적용한다.
    let closeSubmit = try XCTUnwrap(descendants(close.view).first { $0.accessibilityIdentifier == "futuresCloseSubmit" } as? UIButton)
    // 자동 검증 이벤트가 입력을 지우거나 막지 않는지 확인한다.
    let input = try XCTUnwrap(descendants(order.view).first { $0.accessibilityIdentifier == "futuresMargin" } as? UITextField)
    input.text = "25"
    func flush() {
      // 메인과 주문·종료의 비동기 바인딩을 모두 처리한다.
      let rendered = expectation(description: "Quiet verification rendered")
      DispatchQueue.main.async { DispatchQueue.main.async { rendered.fulfill() } }
      wait(for: [rendered], timeout: 2)
    }
    func send(_ status: FuturesRefreshStatus) {
      state = futures.reduce(state: state, mutation: .status(status))
      futures.stub.state.value = state
      flush()
    }
    market.action.onNext(.loadCryptoList)
    flush()
    XCTAssertFalse(market.currentState.totalCryptoList.isEmpty)
    for hold in [FuturesHistoryCheckHold.workLimit, .currentInterval, .revisionChanged] {
      send(.finished([.init(positionID: position.id, verifiedThrough: 100_000, liquidated: false, hold: hold)]))
      send(.refreshing)
      XCTAssertFalse(futures.needsDataRetry)
      XCTAssertTrue(status.isHidden)
      XCTAssertEqual(closeStatus.text, "")
      XCTAssertTrue(submit.isEnabled)
      XCTAssertTrue(closeSubmit.isEnabled)
      XCTAssertTrue(input.isEnabled)
      XCTAssertEqual(input.text, "25")
      main.viewWillDisappear(false)
      main.viewWillAppear(false)
      flush()
      XCTAssertNil(window.viewWithTag(999999))
      XCTAssertNil(main.presentedViewController)
    }
    // 캐시 목록이 있는 재조회도 전체 화면을 잠그지 않는다.
    // 실제 읽은 목록을 유지한 채 지연된 갱신을 재현한다.
    var marketState = market.currentState
    market.isStubEnabled = true
    marketState.isLoading = true
    market.stub.state.value = marketState
    flush()
    XCTAssertNil(window.viewWithTag(999999))
    marketState.isLoading = false
    market.stub.state.value = marketState
    priceAvailable = true
    // 실제 서비스에서 세 번 실패한 뒤 전달하는 공통 오류 구간이다.
    let failureID = UUID()
    for hold in [FuturesHistoryCheckHold.missingHistory, .requestFailed, .staleQuote, .storageFailed, .unsupportedInstrument, .ambiguousEntryCandle, .ambiguousFundingOrder] {
      state = futures.reduce(state: state, mutation: .dataFailure(.init(id: failureID, account: account, attempts: 3, hold: hold)))
      send(.finished([.init(positionID: position.id, verifiedThrough: 100_000, liquidated: false, hold: hold)]))
      XCTAssertTrue(futures.needsDataRetry)
      XCTAssertFalse(status.isHidden)
      XCTAssertEqual(closeStatus.text, FuturesText.text(hold == .storageFailed ? "futures_storage_error" : "futures_data_held"))
      XCTAssertTrue(submit.isEnabled)
      XCTAssertTrue(closeSubmit.isEnabled)
      if hold == .missingHistory {
        XCTAssertEqual((main.presentedViewController as? UIAlertController)?.message, FuturesText.text("futures_data_held"))
        // UIKit의 실제 닫기 완료를 기다려 표시 전환 중인 알럿을 중복으로 오인하지 않는다.
        let dismissed = expectation(description: "Data error dismissed")
        main.dismiss(animated: false) { dismissed.fulfill() }
        wait(for: [dismissed], timeout: 2)
        flush()
      } else {
        XCTAssertNil(main.presentedViewController)
      }
      send(.refreshing)
      XCTAssertFalse(status.isHidden)
      XCTAssertNil(window.viewWithTag(999999))
      XCTAssertNil(main.presentedViewController)
    }
    // 사용자 재시도는 기존 서비스 경로로 전달한다.
    let retry = try XCTUnwrap(descendants(status).first { $0.accessibilityIdentifier == "futures.data.retry" } as? UIButton)
    retry.sendActions(for: .touchUpInside)
    XCTAssertTrue(futures.stub.actions.contains { if case .reload = $0 { return true }; return false })
    state = futures.reduce(state: state, mutation: .dataFailure(nil))
    send(.finished([.init(positionID: position.id, verifiedThrough: 100_000, liquidated: false, hold: nil)]))
    XCTAssertTrue(status.isHidden)
    XCTAssertEqual(closeStatus.text, "")
    XCTAssertTrue(submit.isEnabled)
    XCTAssertTrue(closeSubmit.isEnabled)
    XCTAssertEqual(input.text, "25")
    send(.paused)
    send(.refreshing)
    XCTAssertTrue(status.isHidden)
    XCTAssertEqual(closeStatus.text, "")
    XCTAssertTrue(submit.isEnabled)
    XCTAssertTrue(closeSubmit.isEnabled)
    XCTAssertNil(window.viewWithTag(999999))
  }

  @MainActor
  func testInitialListWaitIsBoundedAndAssetVerificationNeverLocksNavigation() throws {
    // 네트워크와 계좌 이벤트를 명시적으로 제어할 화면 상태다.
    let futures = reactor()
    // 이전 성공 시세와 복귀 중 수신 시세가 달라도 확인값을 유지해야 한다.
    let position = try FuturesCalculator.open(domesticFuturesOrder(margin: 100, price: 100))
    // 계좌 준비와 거래 준비를 구분하는 로컬 원본이다.
    let snapshot = FuturesAccountSnapshot(revision: 1, accounts: [.init(id: account, availableBalance: 900)], positions: [position], historyCheckStates: [try .initial(for: position)])
    // 실제 버튼 신선도 조건에 사용할 요청 시각이다.
    let timestamp = try FuturesHistoryCheckState.milliseconds(Date())
    // 복귀 전 확인한 표시 가격이다.
    let previous = FuturesMarkQuote(instrument: position.order.instrument, price: 110, timestamp: timestamp - 1_000)
    // 검증 완료 결과가 없는 초기 조회 상태다.
    var state = futures.reduce(state: futures.initialState, mutation: .snapshot(snapshot, [previous.instrument: previous]))
    futures.stub.state.value = state
    // 화면 진입이 실제 네트워크나 저장소를 수정하지 않도록 목록을 고정한다.
    let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
    market.isStubEnabled = true
    // 첫 목록은 셀 자리만 표시하고 자산 검증과 탐색을 분리한다.
    var marketState = market.initialState
    marketState.isLoading = true
    market.stub.state.value = marketState
    // 실제 Scene의 창에 올려 전역 오버레이 여부를 확인한다.
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    // 앱의 원래 key window를 변경하지 않는다.
    let window = UIWindow(windowScene: scene)
    // 목록 자리 표시의 연속 대기 상한을 가상 시계로 확인한다.
    let scheduler = HistoricalScheduler(initialClock: Date(timeIntervalSince1970: 0))
    // 경로 이벤트와 목록 대기 시간을 직접 주입한다.
    let main = MainViewController(
      reactor: market,
      futuresReactor: futures,
      networkAvailability: .empty(),
      loadingIndicatorScheduler: scheduler
    )
    main.loadViewIfNeeded()
    window.addSubview(main.view)
    main.view.frame = window.bounds
    window.isHidden = false
    main.view.layoutIfNeeded()
    main.viewWillAppear(false)
    defer { main.viewWillDisappear(false); main.view.removeFromSuperview(); window.isHidden = true }
    // 입력 상태와 최종 제출 버튼을 함께 확인한다.
    let order = FuturesOrderViewController(reactor: futures, instrument: position.order.instrument)
    order.captureOrderPrice = {
      // 연결된 표시 소켓에서 캡처한 해당 종목 가격이다.
      let now = (try? FuturesHistoryCheckState.milliseconds(Date())) ?? 0
      return FuturesOrderPrice(quote: .init(instrument: position.order.instrument, price: 110, timestamp: now), requestedAt: now)
    }
    order.loadViewIfNeeded()
    // 최종 제출과 입력 필드를 각각 점검한다.
    let submit = try XCTUnwrap(descendants(order.view).first { $0.accessibilityIdentifier == "futuresSubmit" } as? UIButton)
    // 준비 중에도 사용자의 입력은 허용한다.
    let input = try XCTUnwrap(descendants(order.view).first { $0.accessibilityIdentifier == "futuresMargin" } as? UITextField)
    func flush() {
      // Reactor 바인딩과 창 추가가 완료된 메인 루프를 기다린다.
      let rendered = expectation(description: "Readiness views rendered")
      DispatchQueue.main.async { DispatchQueue.main.async { rendered.fulfill() } }
      wait(for: [rendered], timeout: 2)
    }
    func send(_ mutation: FuturesAccountReactor.Mutation) {
      state = futures.reduce(state: state, mutation: mutation)
      futures.stub.state.value = state
      flush()
    }
    flush()
    // 생성 시 예약된 실제 계좌 이벤트를 처리한 뒤 테스트용 목록 조회 상태를 주입한다.
    market.stub.state.value = marketState
    flush()
    XCTAssertTrue(market.currentState.isLoading)
    XCTAssertTrue(submit.isEnabled)
    XCTAssertTrue(input.isEnabled)
    XCTAssertTrue(main.searchBar.isUserInteractionEnabled)
    XCTAssertTrue(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    XCTAssertFalse(descendants(main.view).contains { $0.accessibilityIdentifier == "futures.main.dataStatus" || $0.accessibilityIdentifier == "market.dataStatus" })
    // 자산 확인이 끝나도 아직 남은 첫 목록의 자리 표시는 유지한다.
    let verified = FuturesRefreshResult(positionID: position.id, verifiedThrough: timestamp - 1_000, liquidated: false, hold: nil)
    send(.status(.finished([verified])))
    XCTAssertTrue(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    send(.status(.paused))
    send(.status(.refreshing))
    XCTAssertTrue(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    // 셀 자리 표시와 검색·탐색 영역을 함께 검토할 자료다.
    let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) })
    attachment.name = "Main coin list skeleton"
    attachment.lifetime = .keepAlways
    add(attachment)
    XCTAssertFalse(descendants(window).contains { $0.accessibilityIdentifier == "loading.dismiss" })
    // 시세 이벤트가 발생해도 20초 대기 상한이 뒤로 밀리지 않아야 한다.
    scheduler.advanceTo(Date(timeIntervalSince1970: 10))
    send(.quote(previous))
    scheduler.advanceTo(Date(timeIntervalSince1970: 19.999))
    flush()
    XCTAssertTrue(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    scheduler.advanceTo(Date(timeIntervalSince1970: 20))
    flush()
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    XCTAssertTrue(submit.isEnabled)
    XCTAssertFalse(futures.canSubmit)
    XCTAssertTrue(FuturesText.status(futures).isEmpty)
    XCTAssertEqual(futures.valuationQuotes[previous.instrument], previous)
    // 타임아웃 후 늦은 시세를 받아도 같은 검증은 다시 화면을 잠그지 않는다.
    send(.quote(previous))
    scheduler.advanceTo(Date(timeIntervalSince1970: 60))
    flush()
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    XCTAssertTrue(FuturesText.status(futures).isEmpty)
    // 목록 완료 후 같은 검증이 남아 있어도 재진입·복귀가 화면을 다시 잠그지 않는다.
    marketState.isLoading = false
    market.stub.state.value = marketState
    main.viewWillDisappear(false)
    main.viewWillAppear(false)
    NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    flush()
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    XCTAssertTrue(submit.isEnabled)
    XCTAssertTrue(input.isEnabled)
    // 실제 검증 완료 뒤에만 실행을 허용한다.
    send(.status(.finished([verified])))
    XCTAssertTrue(submit.isEnabled)
    marketState.isLoading = false
    market.stub.state.value = marketState
    flush()
    main.viewWillDisappear(false)
    main.viewWillAppear(false)
    flush()
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    send(.status(.refreshing))
    XCTAssertTrue(submit.isEnabled)
    XCTAssertEqual(futures.valuationQuotes[previous.instrument], previous)
    // 백그라운드 복귀에서는 완료 전 새 이익을 반영하거나 거래를 허용하지 않는다.
    send(.status(.paused))
    send(.status(.refreshing))
    send(.quote(.init(instrument: previous.instrument, price: 120, timestamp: timestamp)))
    XCTAssertTrue(submit.isEnabled)
    XCTAssertTrue(input.isEnabled)
    XCTAssertEqual(futures.valuationQuotes[previous.instrument], previous)
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    // 지속 실패로 승격된 오류만 사용자 재시도를 제공한다.
    send(.dataFailure(.init(id: UUID(), account: account, attempts: 3, hold: .missingHistory)))
    send(.status(.finished([.init(positionID: position.id, verifiedThrough: timestamp, liquidated: false, hold: .missingHistory)])))
    XCTAssertTrue(futures.needsDataRetry)
    XCTAssertFalse(FuturesText.status(futures).isEmpty)
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    // 같은 보류의 자동 재시도는 화면을 반복해서 잠그지 않는다.
    send(.status(.refreshing))
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    send(.status(.finished([.init(positionID: position.id, verifiedThrough: timestamp, liquidated: false, hold: .missingHistory)])))
    // 요약 아래 상태 행 없이 오류 재시도의 데이터 경로를 확인한다.
    main.retryMainData()
    XCTAssertEqual(futures.stub.actions.filter { if case .reload = $0 { return true }; return false }.count, 1)
    send(.status(.refreshing))
    XCTAssertTrue(submit.isEnabled)
    send(.dataFailure(nil))
    send(.status(.finished([verified])))
    XCTAssertTrue(submit.isEnabled)
    XCTAssertEqual(futures.valuationQuotes[previous.instrument]?.price, 120)
    send(.network(false))
    XCTAssertTrue(submit.isEnabled)
    XCTAssertTrue(FuturesText.status(futures).contains(FuturesText.text("futures_data_offline")))
    // 단절 전에 시작한 REST가 늦게 끝나도 재연결 검증을 완료한 것으로 처리하지 않는다.
    send(.status(.finished([verified])))
    send(.network(true))
    XCTAssertTrue(submit.isEnabled)
    send(.status(.finished([verified])))
    XCTAssertTrue(submit.isEnabled)
    send(.loadFailed)
    XCTAssertTrue(submit.isEnabled)
    XCTAssertTrue(futures.canDisplayValuation)
    XCTAssertEqual(futures.currentState.snapshot, snapshot)
    XCTAssertEqual(futures.valuationQuotes[previous.instrument]?.price, 120)
    XCTAssertTrue(futures.needsDataRetry)
    // 목록 실패에서도 전체 화면 잠금을 제거하고 동일 요청 경로로 재시도한다.
    marketState.isLoading = false
    marketState.errorMessage = "fixture"
    market.stub.state.value = marketState
    flush()
    main.retryMainData()
    XCTAssertTrue(market.stub.actions.contains { if case .loadCryptoList = $0 { return true }; return false })
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    // 숨겨진 메인의 늦은 갱신은 다른 탭을 덮지 않아야 한다.
    main.viewWillDisappear(false)
    marketState.isLoading = true
    market.stub.state.value = marketState
    flush()
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
  }

  @MainActor
  func testMainCoinListSkeletonOnlyUsesMarketTabsAndEndsWhenRequestCompletes() throws {
    // BTC 탭이 제공되는 현물 화면을 확인한 뒤 기존 상품 선택을 복구한다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    ExchangeSelectionStore.currentProduct = .spot
    defer { ExchangeSelectionStore.currentProduct = previousProduct }
    // 빈 기본 목록과 사용자별 빈 목록을 같은 요청 상태에서 비교한다.
    let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
    market.isStubEnabled = true
    // 탭 전환만으로 조회 완료 상태가 바뀌지 않도록 유지한다.
    var state = market.initialState
    state.isLoading = true
    market.stub.state.value = state
    // 실제 테이블의 자리 표시와 탐색 영역을 함께 확인한다.
    let main = MainViewController(reactor: market, networkAvailability: .empty())
    main.loadViewIfNeeded()
    // 다른 테스트의 key window와 데이터 소스에는 영향을 주지 않는다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    window.addSubview(main.view)
    main.view.frame = window.bounds
    window.isHidden = false
    main.view.layoutIfNeeded()
    main.viewWillAppear(false)
    defer { main.viewWillDisappear(false); main.view.removeFromSuperview(); window.isHidden = true }
    func flush() {
      // 탭·로딩 상태의 비동기 구독이 반영된 뒤 표시를 검사한다.
      let rendered = expectation(description: "Coin list skeleton rendered")
      DispatchQueue.main.async { DispatchQueue.main.async { rendered.fulfill() } }
      wait(for: [rendered], timeout: 2)
    }
    flush()
    // 실제 탭 입력으로 빈 안내 화면과 목록의 표시 상태를 함께 전환한다.
    for (tab, button) in [(SelectedTab.krw, main.krwButton), (.favorite, main.favoriteButton), (.btc, main.btcButton), (.hold, main.holdButton)] {
      button.sendActions(for: .touchUpInside)
      state.selectedTab = tab
      market.stub.state.value = state
      flush()
      XCTAssertEqual(main.tableView.sk.isSkeletonActive, tab == .krw || tab == .btc)
      XCTAssertEqual(main.tableView.isHidden, tab == .favorite || tab == .hold)
      XCTAssertEqual(main.noHoldView.isHidden, tab != .hold)
      XCTAssertEqual(main.noFavoriteView.isHidden, tab != .favorite)
      XCTAssertTrue(main.searchBar.isUserInteractionEnabled)
      XCTAssertNil(window.viewWithTag(999999))
    }
    main.krwButton.sendActions(for: .touchUpInside)
    state.selectedTab = .krw
    market.stub.state.value = state
    flush()
    XCTAssertTrue(main.tableView.sk.isSkeletonActive)
    state.isLoading = false
    market.stub.state.value = state
    flush()
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
  }

  @MainActor
  func testForegroundVerificationIndicatorEndsOnceAndOnlyNewBackgroundRearmsIt() throws {
    // 완료·오류·연결 유실과 검증 이벤트를 직접 제어한다.
    let futures = reactor()
    // 복귀 중에도 표시할 마지막 자산이 있는 계좌다.
    let position = try FuturesCalculator.open(domesticFuturesOrder(leverage: 1, margin: 100, price: 100))
    // 검증 UI 종료가 계좌 준비 완료를 위조하지 않는지 확인할 저장 상태다.
    let snapshot = FuturesAccountSnapshot(revision: 1, accounts: [.init(id: account, availableBalance: 900)], positions: [position])
    // 준비 완료와 미검증 상태 전환을 구분한다.
    let verified = FuturesRefreshResult(positionID: position.id, verifiedThrough: 100_000, liquidated: false, hold: nil)
    // 시세 목록은 별도로 준비해 자산 검증만 화면을 잠그는지 확인한다.
    let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
    // 동일 복귀에서 상한을 연장하지 않고 측정할 가상 시계다.
    let scheduler = HistoricalScheduler(initialClock: Date(timeIntervalSince1970: 0))
    // 기존 네트워크 유실 화면의 우선순위를 함께 확인한다.
    let availability = PublishSubject<Bool>()
    // 사용자가 보는 실제 메인 화면이다.
    let main = MainViewController(reactor: market, futuresReactor: futures, networkAvailability: availability, loadingIndicatorScheduler: scheduler)
    // 알럿의 표시와 닫기까지 확인하는 테스트 소유 창이다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    // 화면마다 복귀 상태를 만들지 않고 상위 컨테이너 하나를 사용한다.
    let tabs = MobitTabBarViewController()
    tabs.setViewControllers([main, UIViewController()])
    tabs.bindForegroundVerification(futures, scheduler: scheduler)
    window.rootViewController = tabs
    window.isHidden = false
    main.viewWillAppear(false)
    defer {
      main.dismiss(animated: false)
      main.viewWillDisappear(false)
      tabs.bindForegroundVerification(nil)
      window.isHidden = true
      window.rootViewController = nil
    }
    func flush() {
      // 생명주기 알림과 Reactor의 비동기 화면 반영을 모두 기다린다.
      let rendered = expectation(description: "Foreground indicator rendered")
      DispatchQueue.main.async { DispatchQueue.main.async { rendered.fulfill() } }
      wait(for: [rendered], timeout: 2)
    }
    func send(_ mutation: FuturesAccountReactor.Mutation) {
      futures.stub.state.value = futures.reduce(state: futures.currentState, mutation: mutation)
      flush()
    }
    func activate() {
      NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
      flush()
    }
    func enterBackground() {
      NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
      send(.status(.paused))
      NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
      flush()
      XCTAssertNil(window.viewWithTag(999999))
    }
    market.action.onNext(.loadCryptoList)
    flush()
    XCTAssertFalse(market.currentState.totalCryptoList.isEmpty)
    // 알럿·네트워크 알림이 실제 요청을 발생시키지 않도록 준비된 목록을 고정한다.
    let marketState = market.currentState
    market.isStubEnabled = true
    market.stub.state.value = marketState
    for ending in ["completed", "failed", "storage", "offline", "timeout", "left", "interrupted"] {
      send(.dataFailure(nil))
      send(.snapshot(snapshot, [:]))
      send(.status(.finished([verified])))
      send(.network(true))
      availability.onNext(true)
      main.viewWillAppear(false)
      enterBackground()
      activate()
      // 서비스가 아직 paused여도 복귀 요청 시작까지 같은 상한으로 기다린다.
      XCTAssertNotNil(window.viewWithTag(999999), ending)
      send(.status(.refreshing))
      XCTAssertNotNil(window.viewWithTag(999999), ending)
      XCTAssertFalse(futures.canSubmit)
      switch ending {
      case "completed":
        send(.status(.finished([verified])))
        XCTAssertTrue(futures.canSubmit)
      case "failed":
        send(.status(.finished([.init(positionID: position.id, verifiedThrough: 100_000, liquidated: false, hold: .requestFailed)])))
      case "storage":
        send(.dataFailure(.init(id: UUID(), account: nil, attempts: 1, hold: .storageFailed)))
        send(.loadFailed)
      case "offline":
        availability.onNext(false)
        send(.network(false))
        XCTAssertNotNil(main.networkLostView)
        XCTAssertNil(window.viewWithTag(999999))
        availability.onNext(true)
        send(.network(true))
        XCTAssertNil(main.networkLostView)
      case "timeout":
        // 중복 활성 알림과 자동 이어받기가 대기 상한을 뒤로 밀면 안 된다.
        let started = scheduler.now
        scheduler.advanceTo(started.addingTimeInterval(10))
        activate()
        for hold in [FuturesHistoryCheckHold.workLimit, .currentInterval, .revisionChanged] {
          send(.status(.finished([.init(positionID: position.id, verifiedThrough: 100_000, liquidated: false, hold: hold)])))
          send(.status(.refreshing))
          XCTAssertNotNil(window.viewWithTag(999999))
        }
        scheduler.advanceTo(started.addingTimeInterval(19.999))
        flush()
        XCTAssertNotNil(window.viewWithTag(999999))
        scheduler.advanceTo(started.addingTimeInterval(20))
        flush()
      case "left":
        tabs.switchToTab(index: 1)
        tabs.switchToTab(index: 0)
        flush()
      default:
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        activate()
      }
      XCTAssertNil(window.viewWithTag(999999), ending)
      if ending != "completed" { XCTAssertFalse(futures.canSubmit, ending) }
      if ending == "failed" { XCTAssertNil(main.presentedViewController) }
      if ending == "storage" {
        XCTAssertNotNil(main.presentedViewController as? UIAlertController)
        // 실제 알럿 전환이 완료된 뒤 재시도·탭 이동을 재현한다.
        let dismissed = expectation(description: "Foreground error dismissed")
        main.dismiss(animated: false) { dismissed.fulfill() }
        wait(for: [dismissed], timeout: 2)
      }
      send(.status(.refreshing))
      tabs.switchToTab(index: 1)
      tabs.switchToTab(index: 0)
      activate()
      XCTAssertNil(window.viewWithTag(999999), ending)
      if ending == "failed" {
        // 직전 오류 알럿 이력이 있어도 새 실제 복귀의 정상 이어받기는 표시한다.
        send(.status(.finished([.init(positionID: position.id, verifiedThrough: 100_000, liquidated: false, hold: .workLimit)])))
        enterBackground()
        activate()
        XCTAssertNotNil(window.viewWithTag(999999))
        tabs.switchToTab(index: 1)
        tabs.switchToTab(index: 0)
        flush()
        XCTAssertNil(window.viewWithTag(999999))
      }
      // 늦은 완료 후에도 정상 주기 갱신은 조용히 처리한다.
      send(.dataFailure(nil))
      send(.snapshot(snapshot, [:]))
      send(.status(.finished([verified])))
      send(.status(.refreshing))
      XCTAssertTrue(futures.canSubmit)
      XCTAssertNil(window.viewWithTag(999999))
    }
    // 다른 탭도 같은 복귀 정책으로 표시하며 탭 이동 후 재등장하지 않는다.
    tabs.switchToTab(index: 1)
    enterBackground()
    activate()
    XCTAssertNotNil(window.viewWithTag(999999))
    tabs.switchToTab(index: 0)
    send(.status(.refreshing))
    XCTAssertNil(window.viewWithTag(999999))
    // 복귀 전에 이미 완료된 빠른 검증은 불필요하게 깜빡이지 않는다.
    enterBackground()
    send(.status(.finished([verified])))
    activate()
    XCTAssertNil(window.viewWithTag(999999))
    // 직전 상한을 사용한 타이머가 다음 실제 복귀의 대기를 조기 종료하지 않는다.
    enterBackground()
    activate()
    XCTAssertNotNil(window.viewWithTag(999999))
    scheduler.advanceTo(scheduler.now.addingTimeInterval(20))
    flush()
    XCTAssertNil(window.viewWithTag(999999))
    XCTAssertFalse(futures.canSubmit)
  }

  @MainActor
  func testInvestmentOrderAndCloseUseOneForegroundIndicatorAndDeadline() throws {
    // 투자내역·주문·종료가 실제로 공유하는 계좌다.
    let futures = reactor()
    // 검증이 필요한 보유 포지션이다.
    let position = try FuturesCalculator.open(domesticFuturesOrder(leverage: 1, margin: 100, price: 100))
    // 표시할 계좌를 유지한 채 검증 상태만 변경한다.
    let snapshot = FuturesAccountSnapshot(revision: 1, accounts: [.init(id: account, availableBalance: 900)], positions: [position])
    // 정상 완료 뒤에만 거래가 가능해져야 한다.
    let verified = FuturesRefreshResult(positionID: position.id, verifiedThrough: 100_000, liquidated: false, hold: nil)
    // 외부 시세 조회 없이 실제 투자내역 레이아웃을 구성한다.
    let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
    market.isStubEnabled = true
    // 숨겨진 메인의 종료 호출이 공통 표시를 지우면 안 된다.
    let main = MainViewController(reactor: market, futuresReactor: futures, networkAvailability: .empty())
    // 실제 투자내역 화면이다.
    let investment = FuturesInvestmentViewController(reactor: futures, marketReactor: market)
    // 실제 주문 화면과 하위 폼을 사용한다.
    let order = FuturesOrderViewController(reactor: futures, instrument: position.order.instrument)
    order.captureOrderPrice = {
      // UI 제출 가능 조건에 사용할 현재 소켓 가격이다.
      let timestamp = (try? FuturesHistoryCheckState.milliseconds(Date())) ?? 0
      return .init(quote: .init(instrument: position.order.instrument, price: 110, timestamp: timestamp), requestedAt: timestamp)
    }
    // 주문 화면이 담기는 실제 내비게이션 계층이다.
    let navigation = UINavigationController(rootViewController: investment)
    // 모든 화면에 같은 대기 상한을 적용하는 가상 시계다.
    let scheduler = HistoricalScheduler(initialClock: Date(timeIntervalSince1970: 0))
    // 앱과 같은 공통 부모에 계좌를 한 번 연결한다.
    let tabs = MobitTabBarViewController()
    tabs.setViewControllers([main, navigation], selectedIndex: 1)
    tabs.bindForegroundVerification(futures, scheduler: scheduler)
    // 종료 시트 위까지 덮는 실제 창이다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = tabs
    window.isHidden = false
    defer {
      order.dismiss(animated: false)
      tabs.bindForegroundVerification(nil)
      window.isHidden = true
      window.rootViewController = nil
    }
    func flush() {
      // 공통 부모와 각 화면의 비동기 바인딩이 반영될 때까지 기다린다.
      let rendered = expectation(description: "Shared foreground indicator rendered")
      DispatchQueue.main.async { DispatchQueue.main.async { rendered.fulfill() } }
      wait(for: [rendered], timeout: 2)
    }
    func send(_ mutation: FuturesAccountReactor.Mutation) {
      futures.stub.state.value = futures.reduce(state: futures.currentState, mutation: mutation)
      flush()
    }
    func resume() {
      NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
      send(.status(.paused))
      NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
      NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
      flush()
      send(.status(.refreshing))
    }
    for screen in ["investment", "order", "close"] {
      send(.snapshot(snapshot, [:]))
      send(.status(.finished([verified])))
      if screen == "order" { navigation.pushViewController(order, animated: false) }
      if screen == "close" {
        // 사용자 주문 화면에서 열리는 실제 종료 바텀 시트다.
        let close = FuturesCloseViewController(reactor: futures, positionID: position.id, captureOrderPrice: { order.captureOrderPrice?() })
        close.modalPresentationStyle = .pageSheet
        close.sheetPresentationController?.detents = [.medium(), .large()]
        // 시트 표시가 끝나야 복귀 후 창 전체 가림 여부를 확인할 수 있다.
        let presented = expectation(description: "Close sheet presented")
        order.present(close, animated: false) { presented.fulfill() }
        wait(for: [presented], timeout: 2)
      }
      for ending in ["completed", "failed", "offline", "timeout"] {
        send(.network(true))
        send(.status(.finished([verified])))
        resume()
        // 화면 종류와 무관하게 창 전체에 인디케이터 하나만 생성한다.
        let overlay = try XCTUnwrap(window.viewWithTag(999999), screen)
        XCTAssertEqual(overlay.frame, window.bounds)
        XCTAssertEqual(descendants(window).filter { $0.tag == 999999 }.count, 1)
        XCTAssertFalse(futures.canSubmit)
        main.hideLoadingIndicator()
        order.hideLoadingIndicator()
        flush()
        XCTAssertTrue(window.viewWithTag(999999) === overlay)
        switch ending {
        case "completed": send(.status(.finished([verified])))
        case "failed": send(.status(.finished([.init(positionID: position.id, verifiedThrough: 100_000, liquidated: false, hold: .requestFailed)])))
        case "offline": send(.network(false))
        default:
          // 자동 이어받기와 중복 활성 알림에서도 같은 인디케이터·상한을 유지한다.
          let started = scheduler.now
          scheduler.advanceTo(started.addingTimeInterval(10))
          send(.status(.finished([.init(positionID: position.id, verifiedThrough: 100_000, liquidated: false, hold: .workLimit)])))
          send(.status(.refreshing))
          NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
          flush()
          XCTAssertTrue(window.viewWithTag(999999) === overlay)
          scheduler.advanceTo(started.addingTimeInterval(19.999))
          flush()
          XCTAssertNotNil(window.viewWithTag(999999))
          scheduler.advanceTo(started.addingTimeInterval(20))
          flush()
        }
        XCTAssertNil(window.viewWithTag(999999), screen + ending)
        XCTAssertEqual(futures.canSubmit, ending == "completed")
        send(.network(true))
        send(.status(.refreshing))
        XCTAssertNil(window.viewWithTag(999999))
      }
    }
    // 타임아웃 후 다른 탭으로 이동해도 같은 검증의 표시를 새로 만들지 않는다.
    let dismissed = expectation(description: "Close sheet dismissed")
    order.dismiss(animated: false) { dismissed.fulfill() }
    wait(for: [dismissed], timeout: 2)
    tabs.switchToTab(index: 0)
    tabs.switchToTab(index: 1)
    flush()
    XCTAssertNil(window.viewWithTag(999999))
    resume()
    XCTAssertNotNil(window.viewWithTag(999999))
    // 현물 또는 다른 계좌로 전환하면 이전 구독·인디케이터를 폐기한다.
    tabs.bindForegroundVerification(nil)
    flush()
    XCTAssertNil(window.viewWithTag(999999))
    resume()
    XCTAssertNil(window.viewWithTag(999999))
    scheduler.advanceTo(scheduler.now.addingTimeInterval(20))
    flush()
    XCTAssertNil(window.viewWithTag(999999))
  }

  @MainActor
  func testMainLoadingDeadlineIsCanceledAcrossBackgroundNetworkLossAndScreenExit() throws {
    // 이전 목록 대기의 타이머가 복귀 후 새 대기를 조기에 종료하지 않아야 한다.
    let scheduler = HistoricalScheduler(initialClock: Date(timeIntervalSince1970: 0))
    // 오래 진행되는 목록 요청과 연결 상태를 직접 제어한다.
    let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
    market.isStubEnabled = true
    // 중복 연결 이벤트도 대기 상한을 다시 시작하지 않도록 한다.
    let availability = PublishSubject<Bool>()
    // 네트워크·생명주기 이벤트를 받는 실제 메인이다.
    let main = MainViewController(
      reactor: market,
      networkAvailability: availability,
      loadingIndicatorScheduler: scheduler
    )
    main.loadViewIfNeeded()
    // 다른 테스트의 key window를 변경하지 않는다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    window.addSubview(main.view)
    main.view.frame = window.bounds
    window.isHidden = false
    main.view.layoutIfNeeded()
    main.viewWillAppear(false)
    defer { main.viewWillDisappear(false); main.view.removeFromSuperview(); window.isHidden = true }
    func flush() {
      // 목록 자리 표시의 시작·종료까지 처리한 뒤 확인한다.
      let rendered = expectation(description: "Loading deadline rendered")
      DispatchQueue.main.async { DispatchQueue.main.async { rendered.fulfill() } }
      wait(for: [rendered], timeout: 2)
    }
    flush()
    // 생성 시 예약된 이벤트를 처리한 뒤 지연 요청을 주입한다.
    var state = market.currentState
    state.isLoading = true
    state.selectedTab = .krw
    market.stub.state.value = state
    flush()
    XCTAssertTrue(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    scheduler.advanceTo(Date(timeIntervalSince1970: 10))
    NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
    // 시스템 active 값이 바뀌기 전 늦은 화면 상태가 도착해도 다시 표시하지 않는다.
    market.stub.state.value = state
    flush()
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    flush()
    XCTAssertTrue(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    scheduler.advanceTo(Date(timeIntervalSince1970: 20))
    flush()
    XCTAssertTrue(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    scheduler.advanceTo(Date(timeIntervalSince1970: 25))
    availability.onNext(false)
    flush()
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    XCTAssertNotNil(main.networkLostView)
    availability.onNext(true)
    flush()
    XCTAssertTrue(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    XCTAssertNil(main.networkLostView)
    scheduler.advanceTo(Date(timeIntervalSince1970: 30))
    availability.onNext(true)
    flush()
    XCTAssertTrue(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    scheduler.advanceTo(Date(timeIntervalSince1970: 45))
    flush()
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    XCTAssertEqual(market.currentState.selectedTab, .krw)
    // 화면 재진입은 새 상한을 적용하되 이탈 뒤 이전 타이머는 취소한다.
    main.viewWillDisappear(false)
    main.viewWillAppear(false)
    flush()
    XCTAssertTrue(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    scheduler.advanceTo(Date(timeIntervalSince1970: 50))
    main.viewWillDisappear(false)
    flush()
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    scheduler.advanceTo(Date(timeIntervalSince1970: 60))
    main.viewWillAppear(false)
    flush()
    scheduler.advanceTo(Date(timeIntervalSince1970: 65))
    flush()
    XCTAssertTrue(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    scheduler.advanceTo(Date(timeIntervalSince1970: 80))
    flush()
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
  }

  @MainActor
  func testMainFailureClosesOverlayAndOffersRetryWhileAssetVerificationContinues() throws {
    // 검증은 아직 준비되지 않은 상태로 유지한다.
    let futures = reactor()
    // 실제 요청 경로에 실패를 주입해 상태 캐시를 덮어쓰는 테스트 간섭을 피한다.
    let response = PublishSubject<CryptoList>()
    // 읽기·실패·재시도를 요청 횟수와 함께 검증한다.
    let useCase = try FuturesMainFixtureUseCase()
    useCase.marketResponse = response.asObservable()
    // 실제 Reactor의 오류 mutation과 화면 바인딩을 함께 검사한다.
    let market = MainReactor(mainUseCase: useCase, tickerSocketService: FuturesMainFixtureSocket())
    // 실제 알럿을 표시할 메인 화면과 독립된 창이다.
    let main = MainViewController(reactor: market, futuresReactor: futures, networkAvailability: .empty())
    // 원래 key window는 유지하며 표시 가능 여부만 검증한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    // 최초 목록 요청과 공통 복귀 검증이 동시에 진행되는 실제 계층이다.
    let tabs = MobitTabBarViewController()
    // 중간 컨테이너가 있어도 부모 탐색 없이 종료 요청을 전달한다.
    let wrapper = UIViewController()
    wrapper.addChild(main)
    wrapper.view.addSubview(main.view)
    main.view.frame = window.bounds
    main.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    main.didMove(toParent: wrapper)
    // 실제 MainCoordinator의 delegate 경로를 통과시킨다.
    let coordinator = MainCoordinator(navigationController: UINavigationController(), dataManager: .shared)
    // 요청 횟수를 확인하면서 공통 인디케이터도 실제로 종료한다.
    let delegate = MainIndicatorDelegateSpy()
    delegate.tabs = tabs
    coordinator.delegate = delegate
    main.coordinator = coordinator
    tabs.setViewControllers([wrapper])
    tabs.bindForegroundVerification(futures)
    window.rootViewController = tabs
    window.isHidden = false
    main.viewWillAppear(false)
    defer {
      tabs.bindForegroundVerification(nil)
      main.dismiss(animated: false)
      main.viewWillDisappear(false)
      window.isHidden = true
      window.rootViewController = nil
    }
    func flush() {
      // 비동기 로딩 표시와 오류 표시를 모두 처리한다.
      let rendered = expectation(description: "Main error rendered")
      DispatchQueue.main.async { DispatchQueue.main.async { rendered.fulfill() } }
      wait(for: [rendered], timeout: 2)
    }
    flush()
    // 실제 표시 크기를 확정한 뒤 첫 목록의 skeleton 행을 계산한다.
    window.setNeedsLayout()
    window.layoutIfNeeded()
    main.view.setNeedsLayout()
    main.view.layoutIfNeeded()
    market.action.onNext(.loadCryptoList)
    flush()
    XCTAssertTrue(market.currentState.isLoading)
    XCTAssertTrue(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
    NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    flush()
    XCTAssertNotNil(window.viewWithTag(999999))
    // 한 요청이 실패하면 다른 검증이 남아 있어도 잠금을 해제해야 한다.
    response.onError(NSError(domain: "MainLoadFixture", code: -1))
    flush()
    XCTAssertFalse(market.currentState.isLoading)
    XCTAssertNotNil(market.currentState.errorMessage)
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    XCTAssertFalse(futures.canSubmit)
    XCTAssertGreaterThan(delegate.finishCount, 0)
    XCTAssertTrue(main.coordinator === coordinator)
    // 실패를 숨기지 않고 기존 입력·탐색으로 돌아가거나 재시도할 수 있다.
    let alert = try XCTUnwrap(main.presentedViewController as? UIAlertController)
    XCTAssertEqual(alert.message, FuturesText.text("market_data_error"))
    XCTAssertEqual(alert.actions.map(\.title), [FuturesText.text("common_confirm"), FuturesText.text("data_retry")])
    // 알럿이 실제로 닫힌 뒤 중복 표시 여부를 확인한다.
    let dismissed = expectation(description: "Main error dismissed")
    main.dismiss(animated: false) { dismissed.fulfill() }
    wait(for: [dismissed], timeout: 2)
    flush()
    market.action.onNext(.loadUserCryptos)
    flush()
    XCTAssertNil(main.presentedViewController)
    useCase.marketResponse = .never()
    main.retryMainData()
    flush()
    XCTAssertEqual(useCase.marketRequests, 2)
    XCTAssertTrue(market.currentState.isLoading)
    XCTAssertNil(market.currentState.errorMessage)
    XCTAssertTrue(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
  }

  @MainActor
  func testExistingNetworkLossNoticeHandlesInitiallyOfflineDuplicatesAndRecovery() throws {
    // 실제 기존 Notification 이름과 payload를 사용한다.
    let availability = NotificationCenter.default.rx.notification(.networkStatusChanged)
      .compactMap { $0.userInfo?["isConnected"] as? Bool }.startWith(false).distinctUntilChanged()
    // 목록의 동작은 네트워크 안내 검증과 분리한다.
    let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
    market.isStubEnabled = true
    // 이미 오프라인인 상태에서 늦게 열린 메인 화면이다.
    let main = MainViewController(reactor: market, networkAvailability: availability)
    main.loadViewIfNeeded()
    func flush() {
      // Notification의 UI 바인딩이 메인 루프에서 반영된 뒤 검사한다.
      let rendered = expectation(description: "Network notice rendered")
      DispatchQueue.main.async { DispatchQueue.main.async { rendered.fulfill() } }
      wait(for: [rendered], timeout: 2)
    }
    flush()
    // 재연결 때 목록 요청이 실제 화면에 연결되는지 확인한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    window.addSubview(main.view)
    main.view.frame = window.bounds
    main.view.layoutIfNeeded()
    main.viewWillAppear(false)
    defer { main.viewWillDisappear(false); main.view.removeFromSuperview() }
    flush()
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    XCTAssertEqual(descendants(main.view).filter { $0 is NetworkLostView }.count, 1)
    XCTAssertEqual(main.networkLostView?.label.text, FuturesText.text("network_lost"))
    XCTAssertFalse(main.networkLostView?.label.isHidden ?? true)
    XCTAssertTrue(main.view.subviews.last === main.networkLostView)
    // 기존 유실 안내가 실제 화면 안에서 표시되는지 기록한다.
    let image = UIGraphicsImageRenderer(bounds: main.view.bounds).image { main.view.layer.render(in: $0.cgContext) }
    // 작은 화면의 오프라인 안내 시각 검증 자료다.
    let attachment = XCTAttachment(image: image)
    attachment.name = "Readiness network loss 320"
    attachment.lifetime = .keepAlways
    add(attachment)
    NotificationCenter.default.post(name: .networkStatusChanged, object: nil, userInfo: ["isConnected": false])
    flush()
    XCTAssertEqual(descendants(main.view).filter { $0 is NetworkLostView }.count, 1)
    NotificationCenter.default.post(name: .networkStatusChanged, object: nil, userInfo: ["isConnected": true])
    flush()
    XCTAssertNil(main.networkLostView)
    XCTAssertEqual(descendants(main.view).filter { $0 is NetworkLostView }.count, 0)
    XCTAssertTrue(market.stub.actions.contains { if case .loadCryptoList = $0 { return true }; return false })
    // 복구 후 진행 중인 첫 조회는 목록에만 자리 표시를 적용한다.
    var loading = market.currentState
    loading.isLoading = true
    market.stub.state.value = loading
    flush()
    XCTAssertTrue(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    NotificationCenter.default.post(name: .networkStatusChanged, object: nil, userInfo: ["isConnected": false])
    flush()
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    XCTAssertEqual(descendants(main.view).filter { $0 is NetworkLostView }.count, 1)
    // 안내는 작은 화면에서도 화면 안에 배치된다.
    main.view.layoutIfNeeded()
    // 마지막 오프라인 반복이 실제 루프에서도 복구되는지 확인한다.
    NotificationCenter.default.post(name: .networkStatusChanged, object: nil, userInfo: ["isConnected": true])
    flush()
    XCTAssertNil(main.networkLostView)
  }

  @MainActor
  func testPriceReadinessUpdatesKeepValidationInAlertWithoutInlineMessage() throws {
    // 입력 검증이 가능한 정상 빈 계좌다.
    let futures = reactor()
    // 계좌 준비와 별개인 폼 검증 오류를 확인한다.
    var state = futures.reduce(state: futures.initialState, mutation: .snapshot(.init(revision: 1, accounts: [.init(id: account, availableBalance: 1000)]), [:]))
    state = futures.reduce(state: state, mutation: .status(.finished([])))
    futures.stub.state.value = state
    // 가격 준비 이벤트를 수동으로 전달한다.
    let updates = PublishSubject<Void>()
    // 신규 진입할 종목이다.
    let instrument = domesticFuturesOrder().instrument
    // 가격은 준비됐으나 증거금 입력이 비어 있는 주문 화면이다.
    let controller = FuturesOrderViewController(reactor: futures, instrument: instrument)
    controller.captureOrderPrice = {
      // 실제 표시 소켓과 같은 요청 시각을 사용한다.
      let timestamp = (try? FuturesHistoryCheckState.milliseconds(Date())) ?? 0
      return .init(quote: .init(instrument: instrument, price: 100, timestamp: timestamp), requestedAt: timestamp)
    }
    controller.orderPriceUpdates = updates
    // 실제 알럿 표시·해제를 검사할 화면 소유 창이다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 667))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { controller.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil }
    // 최초 바인딩과 이후 가격 준비 이벤트의 반영을 기다린다.
    func flush() {
      // 폼 검증을 메인 UI 바인딩과 구분한다.
      let rendered = expectation(description: "Order readiness rendered")
      DispatchQueue.main.async { DispatchQueue.main.async { rendered.fulfill() } }
      wait(for: [rendered], timeout: 2)
    }
    flush()
    // 최종 진입 버튼으로 실제 입력 검증을 실행한다.
    let submit = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "futuresSubmit" } as? UIButton)
    submit.sendActions(for: .touchUpInside)
    waitForNoticeUpdates(0.35)
    // 시세 갱신은 사용자가 읽고 있는 알럿을 지우거나 폼에 같은 오류를 추가하지 않는다.
    let alert = try XCTUnwrap(controller.presentedViewController as? UIAlertController)
    updates.onNext(())
    flush()
    XCTAssertTrue(controller.presentedViewController === alert)
    XCTAssertEqual(alert.message, FuturesText.text("futures_input_error"))
    XCTAssertFalse(descendants(controller.view).compactMap { $0 as? UILabel }.contains { $0.text == alert.message })
    // UIKit의 알럿 해제 완료 이후 도착하는 시세 이벤트를 재현한다.
    let dismissed = expectation(description: "Validation alert dismissed")
    controller.dismiss(animated: false) { dismissed.fulfill() }
    wait(for: [dismissed], timeout: 2)
    updates.onNext(())
    flush()
    XCTAssertNil(controller.presentedViewController)
    XCTAssertFalse(descendants(controller.view).compactMap { $0 as? UILabel }.contains { $0.text == alert.message })
    XCTAssertFalse(futures.stub.actions.contains { if case .open = $0 { return true }; return false })
  }

  func testOrderReadinessRejectsMissingWrongAccountFutureAndExpiredCapturedPrices() throws {
    // 포지션이 없어도 표시 소켓 가격과 계좌 조건은 필요하다.
    let futures = reactor()
    // 정상 로컬 계좌와 검증 완료 상태다.
    var state = futures.reduce(state: futures.initialState, mutation: .snapshot(.init(revision: 1, accounts: [.init(id: account, availableBalance: 1000)]), [:]))
    state = futures.reduce(state: state, mutation: .status(.finished([])))
    futures.stub.state.value = state
    // 테스트의 현재 시각을 고정한다.
    let now = Date(timeIntervalSince1970: 100)
    // 같은 계좌에 속한 거래 종목이다.
    let instrument = domesticFuturesOrder().instrument
    XCTAssertFalse(futures.canExecuteOrder(price: nil, now: now))
    for age in [0, 5_000] {
      // 기존 5초 가격 유효기간의 양 경계는 포함된다.
      let price = FuturesOrderPrice(quote: .init(instrument: instrument, price: 100, timestamp: 90_000), requestedAt: 100_000 - Int64(age))
      XCTAssertTrue(futures.canExecuteOrder(price: price, now: now))
    }
    for requestedAt in [94_999, 100_001] {
      // 지난 요청이나 미래 시각을 화면에서도 실행 가능으로 표시하지 않는다.
      let price = FuturesOrderPrice(quote: .init(instrument: instrument, price: 100, timestamp: 90_000), requestedAt: Int64(requestedAt))
      XCTAssertFalse(futures.canExecuteOrder(price: price, now: now))
    }
    XCTAssertFalse(futures.canExecuteOrder(price: .init(quote: .init(instrument: domesticFuturesOrder(exchange: .bithumb).instrument, price: 100, timestamp: 99_000), requestedAt: 100_000), now: now))
  }

  @MainActor
  func testFuturesFavoriteSummaryUpdatesAfterHistoryCompletesWithoutChangingTabs() throws {
    // 화면 생성에 필요한 거래소 설정을 테스트 종료 후 복원한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    // 선물 화면 설정이 다른 테스트로 이어지지 않게 복원한다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    // 화면 초기화가 재저장하는 현물 보유 데이터를 원래 형태로 복원한다.
    let previousHoldingsData = UserDefaults.standard.object(forKey: UserDataManager.Keys.userCryptoList)
    // 보유 데이터 구독자에게도 테스트 전 값을 복원한다.
    let previousHoldings = UserDataManager.userCryptoList
    defer {
      UserDataManager.userCryptoList = previousHoldings ?? []
      UserDefaults.standard.set(previousHoldingsData, forKey: UserDataManager.Keys.userCryptoList)
      ExchangeSelectionStore.currentExchange = previousExchange
      ExchangeSelectionStore.currentProduct = previousProduct
    }
    ExchangeSelectionStore.currentExchange = .upbit
    ExchangeSelectionStore.currentProduct = .perpetual
    // 검증 완료 여부와 시세 수신 순서를 독립적으로 전달한다.
    let futures = reactor()
    // 10배 롱에서 관찰된 두 수익률을 정확한 Decimal 가격으로 만든다.
    let position = try FuturesCalculator.open(domesticFuturesOrder(symbol: "KRW-ETH", margin: 100, price: 100))
    // 화면 표시 시세의 최신 순서를 구분한다.
    let time = try FuturesHistoryCheckState.milliseconds(Date())
    // 복귀 전 검증 가격은 +135.78%에 해당한다.
    let previousPrice = try XCTUnwrap(Decimal(string: "113.578"))
    // 복귀 후 현재가는 +123%에 해당한다.
    let currentPrice = try XCTUnwrap(Decimal(string: "112.3"))
    // 저장된 경계도 복귀 전 검증 가격과 함께 유지한다.
    var verification = try FuturesHistoryCheckState.initial(for: position)
    verification.lastVerifiedMark = previousPrice
    verification.verifiedThrough = time - 60_000
    // 계좌 현금은 포지션 수익률 계산에 포함되지 않아야 한다.
    let snapshot = FuturesAccountSnapshot(
      revision: 1,
      accounts: [.init(id: account, availableBalance: 900)],
      positions: [position],
      historyCheckStates: [verification]
    )
    // 백그라운드 진입 전에 표시되던 가격이다.
    let previousQuote = FuturesMarkQuote(instrument: position.order.instrument, price: previousPrice, timestamp: time - 60_000)
    futures.stub.state.value = futures.reduce(
      state: futures.initialState,
      mutation: .snapshot(snapshot, [position.order.instrument: previousQuote])
    )
    futures.stub.state.value = futures.reduce(
      state: futures.currentState,
      mutation: .status(.finished([
        .init(positionID: position.id, verifiedThrough: time - 60_000, liquidated: false, hold: nil, lastVerifiedMark: previousPrice)
      ]))
    )
    // 목록 소켓 이벤트 없이 선물 상태만으로 summary가 갱신되는지 확인한다.
    let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
    market.isStubEnabled = true
    // 관찰 당시처럼 즐겨찾기 탭을 유지하며 화면을 이동하지 않는다.
    let controller = MainViewController(reactor: market, futuresReactor: futures)
    controller.selectedTab = .favorite
    controller.loadViewIfNeeded()
    func flush() {
      // 계좌 상태가 메인 summary 바인딩에 전달된 다음 검사한다.
      let rendered = expectation(description: "Favorite summary rendered")
      DispatchQueue.main.async { DispatchQueue.main.async { rendered.fulfill() } }
      wait(for: [rendered], timeout: 2)
    }
    flush()
    // 실제 상단 summary의 수익률 라벨을 검사한다.
    let returnLabel = try XCTUnwrap(
      descendants(controller.view).first { $0.accessibilityIdentifier == "futures.main.roe" } as? UILabel
    )
    XCTAssertEqual(returnLabel.text, "+135.78 %")
    futures.stub.state.value = futures.reduce(state: futures.currentState, mutation: .status(.paused))
    futures.stub.state.value = futures.reduce(state: futures.currentState, mutation: .status(.refreshing))
    futures.stub.state.value = futures.reduce(
      state: futures.currentState,
      mutation: .quote(.init(instrument: position.order.instrument, price: currentPrice, timestamp: time))
    )
    XCTAssertEqual(futures.currentState.quotes[position.order.instrument]?.price, currentPrice)
    flush()
    XCTAssertEqual(returnLabel.text, "+135.78 %")
    // 현물 목록의 스크롤 잠금도 선물 summary 구독을 막지 않아야 한다.
    controller.isSocketUpdating = true
    futures.stub.state.value = futures.reduce(
      state: futures.currentState,
      mutation: .status(.finished([
        .init(positionID: position.id, verifiedThrough: time, liquidated: false, hold: nil, lastVerifiedMark: currentPrice)
      ]))
    )
    flush()
    XCTAssertEqual(returnLabel.text, "+123 %")
    XCTAssertEqual(controller.selectedTab, .favorite)
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
    XCTAssertEqual(items.first?.evaluationPrice, 100_000)
    XCTAssertEqual(items.first?.evaluationProfitLoss, 0)
    XCTAssertEqual(items.first?.profitRate, 0)
    func summary(_ identifier: String) throws -> String {
      let label = try XCTUnwrap(
        descendants(controller.view).first { $0.accessibilityIdentifier == identifier } as? UILabel
      )
      return label.attributedText?.string ?? label.text ?? ""
    }
    XCTAssertTrue(descendants(controller.view).contains { ($0 as? UILabel)?.text == FuturesText.text("futures_total_evaluation") })
    XCTAssertTrue(try summary("futures.main.margin").contains("100,000"))
    XCTAssertTrue(try summary("futures.main.roe").contains("0"))
    XCTAssertTrue(try summary("futures.main.equity").contains("100,000"))
    // 미검증 현재가가 먼저 도착해도 이력 확인을 마친 뒤에만 손익을 표시한다.
    let verified = FuturesRefreshResult(
      positionID: position.id,
      verifiedThrough: time,
      liquidated: false,
      hold: nil,
      lastVerifiedMark: 110_000_000
    )
    futures.stub.state.value = futures.reduce(
      state: futures.currentState,
      mutation: .status(.finished([verified]))
    )
    flushDisplay()
    XCTAssertEqual(controller.dataSource?.snapshot().itemIdentifiers.first?.evaluationPrice, 200_000)
    XCTAssertEqual(controller.dataSource?.snapshot().itemIdentifiers.first?.evaluationProfitLoss, 100_000)
    XCTAssertEqual(controller.dataSource?.snapshot().itemIdentifiers.first?.profitRate, 100)
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
    // 전환 후 검증이 완료되면 다음 사용자 동작 없이 수신한 현재가를 반영한다.
    futures.stub.state.value = futures.reduce(
      state: futures.currentState,
      mutation: .status(.finished([verified]))
    )
    flushDisplay()
    XCTAssertEqual(try summary("futures.main.equity"), "50,000 원")
    XCTAssertTrue(try summary("futures.main.pnl").contains("-50,000"))
    // 과거 청산은 저장된 포지션이 갱신되기 전에도 미정산 이익 표시를 차단한다.
    let liquidated = FuturesRefreshResult(positionID: position.id, verifiedThrough: time, liquidated: true, hold: nil)
    futures.stub.state.value = futures.reduce(
      state: futures.currentState,
      mutation: .status(.finished([liquidated]))
    )
    flushDisplay()
    XCTAssertEqual(try summary("futures.main.roe"), "-")
    XCTAssertNil(controller.dataSource?.snapshot().itemIdentifiers.first?.evaluationProfitLoss)
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
  func testFuturesInvestmentExchangeTitleUsesItsAccountInsteadOfGlobalSelection() throws {
    // 전역 현물 선택과 선물 화면 계좌가 다를 때도 표시할 계좌가 우선한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    ExchangeSelectionStore.currentExchange = .upbit
    defer { ExchangeSelectionStore.currentExchange = previousExchange }
    // 공유 XIB의 업비트 초기값을 덮어써야 하는 빗썸 선물 계좌다.
    let account = TradingAccountID(exchange: .bithumb, product: .perpetual, currency: .krw)
    // 실제 계좌 조회 없이 화면에 전달되는 계좌 이름을 검증한다.
    let reactor = FuturesAccountReactor(account: account)
    reactor.isStubEnabled = true
    // 시세 조회를 시작하지 않고 투자내역 화면을 생성한다.
    let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
    market.isStubEnabled = true
    // 현물과 공유하는 XIB에도 빗썸 계좌명이 표시돼야 한다.
    let controller = FuturesInvestmentViewController(reactor: reactor, marketReactor: market)
    try assertInvestmentExchangeButton(in: controller, exchange: .bithumb)
    // 선물 버튼도 동일한 바텀시트를 현재 선물 계좌로 열어야 한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 기본 거래소가 전역 현물 선택으로 덮어써지지 않는지 확인한다.
    let button = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIButton }.first {
      $0.accessibilityIdentifier == "investment.exchange"
    })
    button.sendActions(for: .touchUpInside)
    // 계좌별 초기 선택을 표시하는 실제 시스템 시트다.
    let sheet = try XCTUnwrap(controller.presentedViewController as? ExchangeSelectionSheetViewController)
    // 빗썸 카드만 선택 표시를 유지해야 한다.
    let option = try XCTUnwrap(descendants(sheet.view).compactMap { $0 as? UIButton }.first {
      $0.accessibilityIdentifier == "investment.exchangeOption.bithumb"
    })
    XCTAssertTrue(option.isSelected)
    XCTAssertEqual(ExchangeSelectionStore.currentExchange, .upbit)
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
    try assertInvestmentExchangeButton(in: controller, exchange: account.exchange)
    XCTAssertEqual(controller.totalBuyTitle.text, FuturesText.text("futures_total_margin"))
    XCTAssertEqual(controller.totalEvaluationTitle.text, FuturesText.text("investment_total_assets"))
    XCTAssertNotEqual(controller.totalEvaluationTitle.text, "investment_total_assets")
    flushDisplay()
    XCTAssertEqual(controller.totalUserBalance.text, "1,000,000")
    XCTAssertEqual(controller.totalEvaluationAmount.text, "100,000")
    XCTAssertEqual(controller.totalEvalProfitLoss.text, "0")
    // 화면을 재생성하지 않고 완료 이벤트만으로 현재가 평가를 표시한다.
    let verified = FuturesRefreshResult(
      positionID: position.id,
      verifiedThrough: timestamp,
      liquidated: false,
      hold: nil,
      lastVerifiedMark: 110_000_000
    )
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .status(.finished([verified])))
    flushDisplay()
    XCTAssertEqual(controller.totalUserBalance.text, "1,100,000")
    XCTAssertEqual(controller.totalEvaluationAmount.text, "200,000")
    XCTAssertEqual(controller.availableUserBalance.text, "900,000")
    XCTAssertEqual(controller.totalBuyPrice.text, "100,000")
    XCTAssertEqual(controller.totalEvalProfitLoss.text, "+100,000")
    XCTAssertEqual(controller.totalProfitRate.text, "+100%")
    XCTAssertTrue(controller.noResultView.isHidden)
    XCTAssertEqual(controller.transactionTableview.numberOfRows(inSection: 0), 1)
    let cell = try XCTUnwrap(
      controller.transactionTableview.dataSource?.tableView(
        controller.transactionTableview,
        cellForRowAt: IndexPath(row: 0, section: 0)
      ) as? InvestmentTableViewCell
    )
    XCTAssertEqual(cell.cryptoName.text, "BTC")
    XCTAssertEqual(cell.marketSymbolLabel.text, "BTC/KRW")
    XCTAssertEqual(cell.sideBadgeLabel.text, FuturesText.text("futures_long"))
    XCTAssertEqual(cell.leverageBadgeLabel.text, "10×")
    XCTAssertEqual(cell.cryptoBuyPrice.text, "100,000")
    XCTAssertEqual(cell.cryptoEvalPrice.text, "200,000")
    XCTAssertEqual(cell.cryptoProfitRate.text, "+100%")
    XCTAssertEqual(cell.averagePriceTitle.text, FuturesText.text("futures_entry"))
    // 투자 전용 버튼은 XIB에서 지정한 글꼴 크기를 확대 설정과 무관하게 유지한다.
    let chargeFontSize = try XCTUnwrap(controller.chargeButton.titleLabel).font.pointSize
    for style in [UIUserInterfaceStyle.light, .dark, .light] {
      controller.overrideUserInterfaceStyle = style
      // iOS 17 이후 지연되는 trait 전파를 완료한 뒤 실제 테마를 검사한다.
      if #available(iOS 17.0, *) { controller.updateTraitsIfNeeded() }
      waitForNoticeUpdates(0.05)
      XCTAssertEqual(controller.view.traitCollection.userInterfaceStyle, style)
      XCTAssertEqual(
        controller.transactionTableview.superview?.backgroundColor?.resolvedColor(with: controller.traitCollection),
        UIColor.mobitColors(.investmentBackground).resolvedColor(with: controller.traitCollection)
      )
      // 작은 기기와 일반 기기의 요약 행 너비를 각각 검증한다.
      for width in [320.0, 375.0] {
        window.frame.size.width = width
        for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge, .large] {
          if #available(iOS 17.0, *) {
            controller.traitOverrides.preferredContentSizeCategory = category
            controller.updateTraitsIfNeeded()
          }
          waitForNoticeUpdates(0.05)
          if #available(iOS 17.0, *) {
            XCTAssertEqual(controller.view.traitCollection.preferredContentSizeCategory, category)
          }
          controller.view.setNeedsLayout()
          controller.view.layoutIfNeeded()
          controller.chargeButton.layoutIfNeeded()
          try assertInvestmentHeaderLayout(in: controller)
          try assertCompactInvestmentChargeButton(controller.chargeButton, fontSize: chargeFontSize)
          XCTAssertEqual(controller.chargeButton.accessibilityLabel, FuturesText.text("futures_charge"))
          // 작은 화면에서도 충전 버튼과 평가 금액이 겹치지 않는지 시각적으로 확인한다.
          let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image {
            controller.view.layer.render(in: $0.cgContext)
          }
          // 현물과 공유하는 레이아웃의 테마·글자 크기 검증 결과를 보관한다.
          let attachment = XCTAttachment(image: image)
          attachment.name = "Futures investment \(style == .dark ? "dark" : "light") \(Int(width)) \(category.rawValue)"
          attachment.lifetime = .keepAlways
          add(attachment)
        }
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
    XCTAssertEqual(controller.totalUserBalance.text, "1,100,000")
    XCTAssertEqual(controller.totalEvaluationAmount.text, "200,000")
    XCTAssertEqual(controller.totalProfitRate.text, "+100%")
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .snapshot(snapshot, [:]))
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .status(.refreshing))
    flushDisplay()
    XCTAssertEqual(controller.totalUserBalance.text, "1,100,000")
    XCTAssertEqual(controller.totalEvaluationAmount.text, "200,000")
    XCTAssertEqual(controller.totalEvalProfitLoss.text, "+100,000")
    XCTAssertEqual(controller.totalBuyPrice.text, "100,000")
    XCTAssertEqual(controller.availableUserBalance.text, "900,000")
    // 총 보유자산은 현재 계좌의 현금과 포지션 평가금액을 합산한다.
    let lossQuote = FuturesMarkQuote(
      instrument: position.order.instrument,
      price: 95_000_000,
      timestamp: try FuturesHistoryCheckState.milliseconds(Date())
    )
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .quote(lossQuote))
    flushDisplay()
    XCTAssertEqual(controller.totalUserBalance.text, "950,000")
    XCTAssertEqual(controller.totalEvaluationAmount.text, "50,000")
    // 검증 중에는 마지막 확인 가격을 유지하고 완료 후 손실 시세를 표시한다.
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .status(.finished([verified])))
    flushDisplay()
    XCTAssertEqual(controller.totalUserBalance.text, "950,000")
    XCTAssertEqual(controller.totalEvaluationAmount.text, "50,000")
    XCTAssertEqual(controller.totalEvalProfitLoss.text, "-50,000")
    XCTAssertEqual(controller.availableUserBalance.text, "900,000")
    let empty = FuturesAccountSnapshot(revision: 2, accounts: [.init(id: account, availableBalance: 1_000_000)])
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .snapshot(empty, [:]))
    flushDisplay()
    XCTAssertEqual(controller.totalUserBalance.text, "1,000,000")
    XCTAssertEqual(controller.totalEvaluationAmount.text, "0")
    XCTAssertEqual(controller.availableUserBalance.text, "1,000,000")
    XCTAssertEqual(controller.totalBuyPrice.text, "0")
    XCTAssertEqual(controller.totalProfitRate.text, "0%")
    XCTAssertFalse(controller.noResultView.isHidden)
    XCTAssertEqual(controller.emptyLabel.text, FuturesText.text("futures_no_position"))
    reactor.stub.state.value = reactor.reduce(state: reactor.currentState, mutation: .loadFailed)
    flushDisplay()
    XCTAssertEqual(controller.emptyLabel.text, FuturesText.text("futures_storage_error"))
  }

  @MainActor
  func testInvestmentPositionBadgesAndROEStayCompactAcrossLayoutQuoteUpdatesAndReuse() throws {
    // 작은 화면과 일반 화면에서 같은 셀을 재사용하며 최초 배치까지 확인한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
    // 저장 데이터와 네트워크 없이 실제 nib의 제약만 검증한다.
    let host = UIViewController()
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    if #available(iOS 17.0, *) {
      host.traitOverrides.preferredContentSizeCategory = .large
      host.updateTraitsIfNeeded()
    }
    // 셀 배경까지 포함한 자연 폭과 ROE의 실제 텍스트 간격을 검사한다.
    func assertCompactLayout(_ cell: InvestmentTableViewCell) throws {
      for label in [cell.sideBadgeLabel, cell.leverageBadgeLabel].compactMap({ $0 }) {
        // 텍스트뿐 아니라 배경 뷰까지 자연 폭을 유지해야 한다.
        let badge = try XCTUnwrap(label.superview)
        // XIB의 좌우 8pt 여백을 제외한 배지 폭은 글자 폭과 같아야 한다.
        let naturalWidth = label.sizeThatFits(
          CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        ).width
        XCTAssertEqual(badge.bounds.width, naturalWidth + 16, accuracy: 0.5, label.text ?? "")
        XCTAssertFalse(badge.hasAmbiguousLayout)
      }
      // 값 라벨이 남는 폭을 차지하면 오른쪽 정렬된 글자까지의 간격이 벌어진다.
      let titleFrame = cell.profitRateTitle.convert(cell.profitRateTitle.bounds, to: cell.contentView)
      // 숫자 프레임도 같은 좌표계에서 비교한다.
      let rateFrame = cell.cryptoProfitRate.convert(cell.cryptoProfitRate.bounds, to: cell.contentView)
      // 손익 크기가 바뀌어도 ROE 한 묶음은 셀의 우측 여백에 붙는다.
      let rateWidth = cell.cryptoProfitRate.sizeThatFits(
        CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
      ).width
      XCTAssertEqual(rateFrame.minX - titleFrame.maxX, 4, accuracy: 0.5)
      XCTAssertEqual(rateFrame.maxX, cell.contentView.bounds.width - 16, accuracy: 0.5)
      XCTAssertEqual(rateFrame.width, rateWidth, accuracy: 0.5)
      XCTAssertGreaterThanOrEqual(rateFrame.minX, 16 - 0.5)
      XCTAssertLessThanOrEqual(rateFrame.maxX, cell.contentView.bounds.width - 16 + 0.5)
    }
    for width: CGFloat in [320, 393] {
      // 각 폭의 첫 layout pass도 이전 폭의 결과에 의존하지 않아야 한다.
      let cell = try XCTUnwrap(
        UINib(nibName: "InvestmentTableViewCell", bundle: .main)
          .instantiate(withOwner: nil).first as? InvestmentTableViewCell
      )
      host.view.addSubview(cell)
      defer { cell.removeFromSuperview() }
      cell.frame = CGRect(x: 0, y: 0, width: width, height: 260)
      for side in [FuturesSide.long, .short] {
        for (symbol, leverage) in [("KRW-GTC", 20), ("KRW-BTC", 1), ("KRW-BTC", 100)] {
          cell.prepareForReuse()
          // 사용자 화면의 GTC 20배를 포함해 배지 문자열 길이를 바꾼다.
          let position = try FuturesCalculator.open(
            domesticFuturesOrder(
              symbol: symbol,
              side: side,
              leverage: leverage,
              margin: 2_500_000,
              price: 404
            )
          )
          for price: Decimal in [404, 405, 4_040, 404] {
            // 0%와 작은 변동, 큰 손익 뒤 0%로 복귀하는 실시간 갱신이다.
            let valuation = try FuturesCalculator.evaluate(position, markPrice: price)
            cell.configure(position: position, valuation: valuation, isLast: false)
            cell.setNeedsLayout()
            cell.layoutIfNeeded()
            try assertCompactLayout(cell)
            // 테이블의 self-sizing 이후에도 첫 배치와 같은 배지 폭을 유지한다.
            let fittedHeight = cell.systemLayoutSizeFitting(
              CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
              withHorizontalFittingPriority: .required,
              verticalFittingPriority: .fittingSizeLevel
            ).height
            cell.frame.size.height = ceil(fittedHeight)
            for _ in 0..<2 {
              cell.setNeedsLayout()
              cell.layoutIfNeeded()
              try assertCompactLayout(cell)
              // 중첩 지표 행까지 검사해 배지가 정상이어도 남을 수 있는 크기 모호성을 잡는다.
              for view in descendants(cell.contentView) where !sequence(first: view, next: { $0.superview })
                .contains(where: { $0.isHidden }) {
                XCTAssertFalse(
                  view.hasAmbiguousLayout,
                  "\(view), labels: \(descendants(view).compactMap { ($0 as? UILabel)?.text })"
                )
              }
              // 옆 지표가 두 줄이어도 한 줄 숫자가 세로로 늘어나 단위와 어긋나면 안 된다.
              for label in [cell.cryptoAmount, cell.cryptoAveragePrice, cell.cryptoEvalPrice, cell.cryptoBuyPrice]
                .compactMap({ $0 }) {
                XCTAssertEqual(label.bounds.height, label.intrinsicContentSize.height, accuracy: 0.5)
              }
            }
            XCTAssertEqual(cell.sideBadgeLabel.text, FuturesText.side(side))
            XCTAssertEqual(cell.leverageBadgeLabel.text, "\(leverage)×")
            if price == 404 {
              XCTAssertEqual(cell.cryptoProfitRate.text, "0%")
              XCTAssertEqual(cell.cryptoEvalLoss.text, "0")
            }
          }
          if symbol == "KRW-GTC", side == .long {
            // 제보된 20배·0% 상태의 실제 배지 폭과 수익률 간격을 보관한다.
            let capture = XCTAttachment(image: UIGraphicsImageRenderer(bounds: cell.bounds).image {
              cell.layer.render(in: $0.cgContext)
            })
            capture.name = "FuturesCell-GTC20-\(Int(width))"
            capture.lifetime = .keepAlways
            add(capture)
            if #available(iOS 17.0, *) {
              for category in [UIContentSizeCategory.accessibilityExtraExtraExtraLarge, .large] {
                cell.traitOverrides.preferredContentSizeCategory = category
                cell.updateTraitsIfNeeded()
                // 글자 확대와 복귀에서도 배지·수익률의 자연 크기를 다시 반영한다.
                let height = cell.systemLayoutSizeFitting(
                  CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                  withHorizontalFittingPriority: .required,
                  verticalFittingPriority: .fittingSizeLevel
                ).height
                cell.frame.size.height = ceil(height)
                cell.setNeedsLayout()
                cell.layoutIfNeeded()
                try assertCompactLayout(cell)
              }
            }
          }
          cell.prepareForReuse()
          cell.configure(crypto: spotOrderLayoutHolding(), isLast: false)
          cell.setNeedsLayout()
          cell.layoutIfNeeded()
          XCTAssertNil(cell.sideBadgeLabel.text)
          XCTAssertNil(cell.leverageBadgeLabel.text)
          XCTAssertTrue(cell.sideBadgeLabel.superview?.superview?.isHidden == true)
        }
      }
    }
  }

  @MainActor
  func testInvestmentSpotIdentityKeepsSingleLineAcrossReconfigurationAndReuse() throws {
    // 실제 테이블의 self-sizing과 재사용 경로에서 제보된 현물 종목을 표시한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
    // 화면 바인딩과 네트워크 없이 셀의 제약만 검증한다.
    let host = UIViewController()
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 행 높이를 고정하지 않고 XIB의 콘텐츠로 계산한다.
    let table = UITableView(frame: host.view.bounds, style: .plain)
    table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    table.rowHeight = UITableView.automaticDimension
    table.estimatedRowHeight = 174
    table.register(UINib(nibName: "InvestmentTableViewCell", bundle: .main), forCellReuseIdentifier: "InvestmentTableViewCell")
    host.view.addSubview(table)
    // 이름과 마켓 모두 실제 제보 문자열을 사용한다.
    let holding = CryptoTransactionDataModel(
      staticData: .init(
        exchange: .upbit,
        marketName: "CARV/KRW",
        cryptoName: "카브",
        holdingQuantity: 21_551,
        averageBuyPrice: 46.4,
        buyAmount: 1_000_000
      ),
      dynamicData: .init(
        exchange: .upbit,
        marketName: "CARV/KRW",
        profitRate: 0,
        evaluationProfitLoss: 0,
        evaluationPrice: 1_000_000
      )
    )
    // 화면 밖 행까지 만들어 재구성과 실제 셀 재사용을 함께 검사한다.
    let dataSource = UITableViewDiffableDataSource<Int, Int>(tableView: table) { table, path, _ in
      guard let cell = table.dequeueReusableCell(withIdentifier: "InvestmentTableViewCell", for: path) as? InvestmentTableViewCell else {
        return UITableViewCell()
      }
      cell.configure(crypto: holding, isLast: path.row == 39)
      return cell
    }
    // 시세 갱신과 같은 식별자 재구성을 반복할 기준 목록이다.
    var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
    snapshot.appendSections([0])
    snapshot.appendItems(Array(0..<40))
    dataSource.apply(snapshot, animatingDifferences: false)
    // 최초 배치와 너비 변경 후에도 짧은 종목명이 줄바꿈되지 않아야 한다.
    for width: CGFloat in [375, 393, 320, 375] {
      window.frame.size.width = width
      window.layoutIfNeeded()
      table.frame = host.view.bounds
      for iteration in 0..<3 {
        snapshot.reconfigureItems([0])
        dataSource.apply(snapshot, animatingDifferences: false)
        table.layoutIfNeeded()
        table.scrollToRow(at: IndexPath(row: 39, section: 0), at: .bottom, animated: false)
        table.layoutIfNeeded()
        table.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
        table.layoutIfNeeded()
        // 화면으로 복귀한 셀의 실제 라벨 프레임을 비교한다.
        let cell = try XCTUnwrap(table.cellForRow(at: IndexPath(row: 0, section: 0)) as? InvestmentTableViewCell)
        // 스택 폭과 라벨 폭을 함께 기록해 축소된 라벨만 남는 경우를 확인한다.
        let diagnostic = "width=\(width), iteration=\(iteration), cell=\(cell.bounds), identity=\(String(describing: cell.cryptoName.superview?.bounds)), name=\(cell.cryptoName.bounds), market=\(cell.marketSymbolLabel.bounds), namePreferredWidth=\(cell.cryptoName.preferredMaxLayoutWidth), marketPreferredWidth=\(cell.marketSymbolLabel.preferredMaxLayoutWidth)"
        XCTAssertEqual(cell.cryptoName.text, "카브")
        XCTAssertEqual(cell.marketSymbolLabel.text, "CARV/KRW")
        // 각 라벨이 종목 영역의 전체 폭을 받아 이전 측정 폭에 고착되지 않아야 한다.
        let identity = try XCTUnwrap(cell.cryptoName.superview)
        for label in [cell.cryptoName, cell.marketSymbolLabel].compactMap({ $0 }) {
          XCTAssertEqual(label.bounds.width, identity.bounds.width, accuracy: 0.5, diagnostic)
          XCTAssertLessThanOrEqual(label.bounds.height, ceil(label.font.lineHeight) + 1, diagnostic)
        }
        if iteration == 0 {
          // 프레임과 렌더 결과를 실패 시 원인 비교 자료로 보관한다.
          let frames = XCTAttachment(string: diagnostic)
          frames.name = "SpotIdentityFrames-\(Int(width))"
          frames.lifetime = .keepAlways
          add(frames)
          // 한 줄 여부를 실제 셀 이미지에서도 확인한다.
          let capture = XCTAttachment(image: UIGraphicsImageRenderer(bounds: cell.bounds).image {
            cell.layer.render(in: $0.cgContext)
          })
          capture.name = "SpotIdentity-CARV-\(Int(width))"
          capture.lifetime = .keepAlways
          add(capture)
        }
      }
    }
    withExtendedLifetime(dataSource) {}
  }

  @MainActor
  func testInvestmentLongQuantityKeepsXIBLayoutAcrossReuseAndTextSizeChanges() throws {
    // 실제 nib을 화면 계층에 올려 기기 너비별 제약을 검증한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
    // 네트워크와 투자내역 화면의 구독 없이 셀만 배치한다.
    let host = UIViewController()
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    if #available(iOS 17.0, *) {
      host.traitOverrides.preferredContentSizeCategory = .large
      host.updateTraitsIfNeeded()
    }
    // 제보된 WAXP 수량 15,527,950를 만드는 실제 진입 가격이다.
    let executionPrice = try XCTUnwrap(Decimal(string: "6.44"))
    // 긴 수량과 네 글자 심볼이 같은 열에서 공간을 나누게 한다.
    let position = try FuturesCalculator.open(
      domesticFuturesOrder(symbol: "KRW-WAXP", leverage: 20, margin: 5_000_000, price: executionPrice)
    )
    // 평가값을 채워 실제 셀과 같은 헤더 및 지표를 배치한다.
    let valuation = try FuturesCalculator.evaluate(position, markPrice: executionPrice)
    // 작은 기기부터 일반 기기까지 가로 공간이 달라지는 경우를 확인한다.
    for width: CGFloat in [320, 375, 393] {
      // 각 너비에서 최초 로드부터 XIB 설정이 유지되는지 확인한다.
      let cell = try XCTUnwrap(
        UINib(nibName: "InvestmentTableViewCell", bundle: .main)
          .instantiate(withOwner: nil).first as? InvestmentTableViewCell
      )
      host.view.addSubview(cell)
      defer { cell.removeFromSuperview() }
      cell.frame = CGRect(x: 0, y: 0, width: width, height: 260)
      // 제목과 숫자 아웃렛이 실제 nib에 연결되어 있어야 한다.
      let titleLabel = try XCTUnwrap(cell.amountTitle)
      // 수량 숫자의 XIB 속성과 축소할 수 있는 폭을 검사한다.
      let amountLabel = try XCTUnwrap(cell.cryptoAmount)
      // 수량 숫자와 심볼을 포함하는 실제 중첩 스택이다.
      let valuesStack = try XCTUnwrap(amountLabel.superview as? UIStackView)
      // 숫자 오른쪽에서 자연 폭을 유지해야 하는 종목 심볼이다.
      let unitLabel = try XCTUnwrap(valuesStack.arrangedSubviews.last as? UILabel)
      // 제목과 수량 묶음의 가로 배치를 검증한다.
      let quantityStack = try XCTUnwrap(valuesStack.superview as? UIStackView)
      // 수량과 평균 진입가가 나란히 배치되는 지표 행이다.
      let rowStack = try XCTUnwrap(quantityStack.superview as? UIStackView)
      // 구성과 재사용 이후에도 원본 속성을 비교할 라벨들이다.
      let quantityLabels = [titleLabel, amountLabel, unitLabel]
      // XIB에서 지정한 글꼴을 trait 변경 이후와 비교한다.
      let nibFonts = quantityLabels.map { $0.font }
      // 남는 폭을 배분하는 XIB의 우선순위를 보존한다.
      let nibHugging = quantityLabels.map { $0.contentHuggingPriority(for: .horizontal) }
      // 숫자보다 제목과 심볼을 우선하는 XIB의 압축 순서다.
      let nibCompression = quantityLabels.map { $0.contentCompressionResistancePriority(for: .horizontal) }
      // XIB의 줄바꿈 방식이 구성 코드에서 바뀌지 않아야 한다.
      let nibLineBreakModes = quantityLabels.map { $0.lineBreakMode }
      // 확대 설정을 바꿔도 XIB가 지정한 가로 배치와 글꼴을 유지한다.
      for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge, .large] {
        cell.prepareForReuse()
        cell.configure(position: position, valuation: valuation, isLast: false)
        if #available(iOS 17.0, *) {
          cell.traitOverrides.preferredContentSizeCategory = category
          cell.updateTraitsIfNeeded()
        }
        // 테이블과 같은 self-sizing 이후의 최종 프레임을 검사한다.
        let fittedHeight = cell.systemLayoutSizeFitting(
          CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
          withHorizontalFittingPriority: .required,
          verticalFittingPriority: .fittingSizeLevel
        ).height
        cell.frame.size.height = ceil(fittedHeight)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        XCTAssertEqual(cell.cryptoAmount.text, "15,527,950")
        XCTAssertEqual(unitLabel.text, "WAXP")
        XCTAssertEqual(rowStack.axis, .horizontal)
        XCTAssertEqual(quantityStack.axis, .horizontal)
        XCTAssertEqual(valuesStack.axis, .horizontal)
        XCTAssertEqual(quantityLabels.map { $0.font }, nibFonts)
        XCTAssertEqual(quantityLabels.map { $0.contentHuggingPriority(for: .horizontal) }, nibHugging)
        XCTAssertEqual(quantityLabels.map { $0.contentCompressionResistancePriority(for: .horizontal) }, nibCompression)
        XCTAssertEqual(quantityLabels.map { $0.lineBreakMode }, nibLineBreakModes)
        XCTAssertEqual(cell.cryptoAmount.numberOfLines, 1)
        XCTAssertEqual(cell.cryptoAmount.lineBreakMode, .byClipping)
        XCTAssertTrue(cell.cryptoAmount.adjustsFontSizeToFitWidth)
        XCTAssertEqual(cell.cryptoAmount.minimumScaleFactor, 0.5, accuracy: 0.001)
        XCTAssertEqual(cell.cryptoAmount.contentCompressionResistancePriority(for: .horizontal).rawValue, 749)
        XCTAssertEqual(cell.amountTitle.bounds.width, cell.amountTitle.intrinsicContentSize.width, accuracy: 0.5)
        XCTAssertEqual(unitLabel.bounds.width, unitLabel.intrinsicContentSize.width, accuracy: 0.5)
        // 실제 글자의 좌우 순서로 제목 아래로 수량이 내려가는 회귀를 잡는다.
        let titleFrame = cell.amountTitle.convert(cell.amountTitle.bounds, to: cell.contentView)
        // 숫자가 축소되더라도 제목 오른쪽에서 같은 행을 유지해야 한다.
        let amountFrame = cell.cryptoAmount.convert(cell.cryptoAmount.bounds, to: cell.contentView)
        // 심볼도 숫자 오른쪽에서 원래 폭을 유지해야 한다.
        let unitFrame = unitLabel.convert(unitLabel.bounds, to: cell.contentView)
        XCTAssertEqual(amountFrame.minX - titleFrame.maxX, quantityStack.spacing, accuracy: 0.5)
        XCTAssertEqual(unitFrame.minX - amountFrame.maxX, valuesStack.spacing, accuracy: 0.5)
        XCTAssertGreaterThan(min(titleFrame.maxY, amountFrame.maxY) - max(titleFrame.minY, amountFrame.minY), 0)
        XCTAssertGreaterThan(min(unitFrame.maxY, amountFrame.maxY) - max(unitFrame.minY, amountFrame.minY), 0)
        XCTAssertLessThan(cell.cryptoAmount.bounds.width, cell.cryptoAmount.intrinsicContentSize.width)
        if width >= 375 {
          XCTAssertGreaterThanOrEqual(
            cell.cryptoAmount.bounds.width + 0.5,
            cell.cryptoAmount.intrinsicContentSize.width * cell.cryptoAmount.minimumScaleFactor
          )
        }
      }
      // 제보된 너비에서 한 줄로 축소된 실제 렌더링을 보관한다.
      let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: cell.bounds).image {
        cell.layer.render(in: $0.cgContext)
      })
      attachment.name = "FuturesCell-WAXP-Quantity-\(Int(width))"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
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
    // 단독 실행에서도 메인 큐의 Reactor 바인딩이 반영된 뒤 셀을 확인한다.
    waitForNoticeUpdates(0.05)
    controller.view.layoutIfNeeded()
    XCTAssertEqual(controller.tableView(controller.pnlTableView, numberOfRowsInSection: 0), 1)
    let cell = try XCTUnwrap(
      controller.tableView(controller.pnlTableView, cellForRowAt: IndexPath(row: 0, section: 0)) as? PNLTableViewCell
    )
    XCTAssertEqual(cell.pnlLabel.text, "-100,000 " + FuturesText.text("currency_krw_unit"))
    XCTAssertEqual(cell.marketNameLabel.text, FuturesText.symbol(position.order.instrument))
    XCTAssertEqual(cell.positionBadgeLabel.text, "\(FuturesText.text("futures_short")) \(position.order.leverage)×")
    XCTAssertEqual(cell.statusLabel.text, FuturesText.text("futures_pnl_liquidated"))
    XCTAssertEqual(cell.exitTitle.text, FuturesText.text("futures_liquidation_exit_price"))
    XCTAssertEqual(cell.entryTitle.text, FuturesText.text("futures_entry_price"))
    XCTAssertEqual(cell.transactionDateLabel.numberOfLines, 1)
    XCTAssertEqual((cell.transactionDateLabel.superview as? UIStackView)?.axis, .horizontal)
    XCTAssertEqual(cell.metricsStackView.arrangedSubviews.count, 2)
    XCTAssertEqual(cell.transactionDateLabel.text, String(FuturesText.date(Date(timeIntervalSince1970: 60)).dropLast(3)))
    XCTAssertEqual(cell.transactionDateLabel.accessibilityValue, cell.transactionDateLabel.text)
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
    for style in [UIUserInterfaceStyle.light, .dark] {
      controller.overrideUserInterfaceStyle = style
      waitForNoticeUpdates(0.05)
      controller.view.layoutIfNeeded()
      XCTAssertEqual(
        controller.view.backgroundColor?.resolvedColor(with: controller.traitCollection),
        UIColor.mobitColors(.backgroundPrimary).resolvedColor(with: controller.traitCollection)
      )
      // 헤더의 기본 배경과 구분해 목록·빈 화면의 표면색을 검사한다.
      let backgroundViews: [UIView] = [controller.pnlTableView, controller.noResultView]
      for backgroundView in backgroundViews {
        XCTAssertEqual(
          backgroundView.backgroundColor?.resolvedColor(with: controller.traitCollection),
          UIColor.mobitColors(.investmentSurface).resolvedColor(with: controller.traitCollection)
        )
      }
      // 화면에 실제 배치된 셀의 문구와 동적 색상을 확인한다.
      let visibleCell = try XCTUnwrap(controller.pnlTableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? PNLTableViewCell)
      XCTAssertEqual(visibleCell.statusLabel.text, FuturesText.text("futures_pnl_liquidated"))
      XCTAssertEqual(
        visibleCell.marketNameLabel.textColor.resolvedColor(with: visibleCell.traitCollection),
        UIColor.mobitColors(.textPrimary).resolvedColor(with: visibleCell.traitCollection)
      )
      XCTAssertEqual(
        visibleCell.cardView.backgroundColor?.resolvedColor(with: visibleCell.traitCollection),
        UIColor.mobitColors(.backgroundPrimary).resolvedColor(with: visibleCell.traitCollection)
      )
      // 테마별 실제 셀 배치와 손익 색상을 렌더링해 확인한다.
      let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image {
        controller.view.layer.render(in: $0.cgContext)
      }
      // 실행 결과에서 두 테마의 화면을 비교할 수 있도록 보관한다.
      let attachment = XCTAttachment(image: image)
      attachment.name = "Futures realized liquidation history \(style == .dark ? "dark" : "light")"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
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
    XCTAssertEqual(controller.totalBuyTitle.text, FuturesText.text("investment_total_buy"))
    XCTAssertEqual(controller.totalEvaluationTitle.text, FuturesText.text("investment_total_assets"))
    XCTAssertEqual(controller.emptyLabel.text, FuturesText.text("trade_no_coins"))
    let cell = try XCTUnwrap(
      UINib(nibName: "InvestmentTableViewCell", bundle: nil).instantiate(withOwner: nil).first
        as? InvestmentTableViewCell
    )
    XCTAssertEqual(cell.buyPriceTitle.text, "매수금액")
    // 화면 진입 부수 효과 없이 XIB 레이아웃을 실제 윈도우에서 검증한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 812))
    window.rootViewController = UIViewController()
    window.rootViewController?.view.addSubview(controller.view)
    window.makeKeyAndVisible()
    controller.view.frame = window.bounds
    defer { window.isHidden = true }
    XCTAssertEqual(controller.view.bounds.width, 320)
    controller.view.layoutIfNeeded()
    controller.chargeButton.layoutIfNeeded()
    // 고정 크기의 투자 전용 버튼에서 XIB 글꼴 설정을 보존한다.
    let chargeFontSize = try XCTUnwrap(controller.chargeButton.titleLabel).font.pointSize
    for style in [UIUserInterfaceStyle.light, .dark, .light] {
      controller.overrideUserInterfaceStyle = style
      // iOS 17 이후 지연되는 trait 전파를 완료한 뒤 실제 테마를 검사한다.
      if #available(iOS 17.0, *) { controller.updateTraitsIfNeeded() }
      waitForNoticeUpdates(0.05)
      XCTAssertEqual(controller.view.traitCollection.userInterfaceStyle, style)
      XCTAssertEqual(
        controller.transactionTableview.superview?.backgroundColor?.resolvedColor(with: controller.traitCollection),
        UIColor.mobitColors(.investmentBackground).resolvedColor(with: controller.traitCollection)
      )
      for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge, .large] {
        if #available(iOS 17.0, *) {
          controller.traitOverrides.preferredContentSizeCategory = category
          controller.updateTraitsIfNeeded()
        }
        waitForNoticeUpdates(0.05)
        if #available(iOS 17.0, *) {
          XCTAssertEqual(controller.view.traitCollection.preferredContentSizeCategory, category)
        }
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        controller.chargeButton.layoutIfNeeded()
        try assertInvestmentHeaderLayout(in: controller)
        try assertCompactInvestmentChargeButton(controller.chargeButton, fontSize: chargeFontSize)
        // 현물 화면도 같은 크기와 XIB 글꼴을 유지하는지 시각적으로 확인한다.
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image {
          controller.view.layer.render(in: $0.cgContext)
        }
        // 작은 화면의 테마·글자 크기를 테스트 결과에서 바로 비교한다.
        let attachment = XCTAttachment(image: image)
        attachment.name = "Spot investment \(style == .dark ? "dark" : "light") 320 \(category.rawValue)"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
    }
  }

  @MainActor
  func testInvestmentXIBContainsItsSummaryAndLaysOutBeforeControllerConfiguration() throws {
    // 화면 설정 코드가 실행되기 전에도 XIB 자체의 계층과 배치가 완성돼야 한다.
    let spot = InvestReactor(mainUseCase: MainUseCase(mainRepository: MainRepository()))
    spot.isStubEnabled = true
    // File's Owner 연결만 제공하고 viewDidLoad를 호출하지 않는다.
    let owner = InvestmentViewController(reactor: spot)
    // 분리된 최상위 요약 뷰가 없어야 편집기에서도 한 화면으로 표시된다.
    let roots = UINib(nibName: "InvestmentViewController", bundle: nil).instantiate(withOwner: owner)
    XCTAssertEqual(roots.count, 1)
    // nib에서 직접 로드한 실제 편집 대상 화면이다.
    let root = try XCTUnwrap(roots.first as? UIView)
    root.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
    // 원래 테이블 헤더로 연결된 상태를 검사한다.
    let header = try XCTUnwrap(owner.transactionTableview.tableHeaderView as? InvestmentSummaryView)
    XCTAssertTrue(header === owner.summaryHeaderView)
    XCTAssertTrue(header.isDescendant(of: root))
    root.layoutIfNeeded()
    header.updateLayout(in: owner.transactionTableview)
    root.layoutIfNeeded()
    header.layoutIfNeeded()
    XCTAssertGreaterThan(owner.transactionTableview.bounds.height, 400)
    // 상단 안전 영역과 무관하게 내비게이션 콘텐츠 높이만 검사한다.
    XCTAssertLessThan(owner.transactionTableview.frame.minY - root.safeAreaLayoutGuide.layoutFrame.minY, 100)
    XCTAssertLessThan(header.bounds.height, 450)
    XCTAssertGreaterThan(header.bounds.height, 250)
    XCTAssertFalse(root.hasAmbiguousLayout)
    XCTAssertFalse(header.hasAmbiguousLayout)
    // 편집기에 저장할 프레임도 코드 설정 전의 배치와 비교할 수 있게 남긴다.
    func frames(_ view: UIView) -> [String: Any] {
      if !sequence(first: view, next: { $0.superview }).contains(where: { $0.isHidden }) {
        XCTAssertFalse(view.hasAmbiguousLayout, String(describing: type(of: view)))
      }
      // UIKit 내부 장식 대신 XIB에서 편집하는 자식 뷰만 수집한다.
      let children: [UIView]
      if let table = view as? UITableView {
        children = table.tableHeaderView.map { [$0] } ?? []
      } else if view is UIButton {
        children = view.subviews.filter { $0.accessibilityIdentifier == "investment.exchange.chevron" }
      } else if view is UILabel {
        children = []
      } else if let stack = view as? UIStackView {
        children = stack.arrangedSubviews
      } else {
        children = view.subviews
      }
      return [
        "class": String(describing: type(of: view)),
        "frame": [view.frame.minX, view.frame.minY, view.frame.width, view.frame.height],
        "children": children.map(frames)
      ]
    }
    // XIB 미리보기의 저장 프레임과 실제 Auto Layout 결과를 비교한다.
    let data = try JSONSerialization.data(withJSONObject: frames(root), options: [.prettyPrinted, .sortedKeys])
    // 실행 코드로 보정하기 전의 배치를 테스트 결과에 보관한다.
    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
    attachment.name = "Investment-XIB-default-frames"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func testInvestmentHeaderFitsBothAccountsAndLargeLocalizedTitles() throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Trait overrides require iOS 17") }
    // 현물 버튼의 현재 거래소 선택은 테스트 후 복구한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    defer { ExchangeSelectionStore.currentExchange = previousExchange }
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      // 현물 데이터 조회 없이 공유 헤더를 검사한다.
      let spot = InvestReactor(mainUseCase: MainUseCase(mainRepository: MainRepository()))
      spot.isStubEnabled = true
      // 선물 헤더도 전역 선택과 무관하게 계좌를 표시한다.
      let futures = FuturesAccountReactor(account: .init(exchange: exchange, product: .perpetual, currency: .krw))
      futures.isStubEnabled = true
      // 실제 소켓 연결 없이 선물 화면의 기존 주입 경로를 사용한다.
      let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
      market.isStubEnabled = true
      // 같은 XIB를 사용하는 두 상품의 화면을 동일한 조건에서 검사한다.
      let controllers: [UIViewController] = [
        InvestmentViewController(reactor: spot),
        FuturesInvestmentViewController(reactor: futures, marketReactor: market)
      ]
      for controller in controllers {
        // 좁은 화면에서도 제목과 양쪽 버튼이 겹치지 않아야 한다.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 812))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
          controller.traitOverrides.preferredContentSizeCategory = category
          controller.updateTraitsIfNeeded()
          controller.view.layoutIfNeeded()
          try assertInvestmentHeaderLayout(in: controller)
        }
      }
    }
  }

  @MainActor
  private func assertCompactInvestmentChargeButton(_ button: UIButton, fontSize: CGFloat) throws {
    XCTAssertTrue(button is InvestmentChargeButton)
    XCTAssertFalse(button is MobitChargeButton)
    XCTAssertEqual(button.bounds.width, 80, accuracy: 0.5)
    XCTAssertEqual(button.bounds.height, 32, accuracy: 0.5)
    XCTAssertEqual(button.configuration?.title, FuturesText.text("investment_recharge"))
    XCTAssertFalse(button.hasAmbiguousLayout)
    // 고정 크기 안에서 원래 XIB 글꼴과 한 줄 제목을 모두 보존해야 한다.
    let title = try XCTUnwrap(button.titleLabel)
    XCTAssertEqual(title.numberOfLines, 1)
    XCTAssertFalse(title.adjustsFontForContentSizeCategory)
    XCTAssertEqual(title.font.pointSize, fontSize, accuracy: 0.001)
    // 줄바꿈이나 숨은 압축으로 통과하지 않도록 전체 제목의 자연 폭을 검사한다.
    let titleWidth = ((title.text ?? "") as NSString).size(withAttributes: [.font: title.font as Any]).width
    XCTAssertGreaterThanOrEqual(title.bounds.width + 0.5, titleWidth)
    XCTAssertGreaterThanOrEqual(title.bounds.height + 0.5, title.font.lineHeight)
    // 버튼 설정의 실제 내부 여백 안에 심볼과 제목이 모두 들어가야 한다.
    let insets = button.configuration?.contentInsets ?? .zero
    // 배경이나 그림자 크기 대신 콘텐츠가 사용할 수 있는 영역만 비교한다.
    let contentBounds = CGRect(
      x: button.bounds.minX + insets.leading,
      y: button.bounds.minY + insets.top,
      width: button.bounds.width - insets.leading - insets.trailing,
      height: button.bounds.height - insets.top - insets.bottom
    )
    // plus가 사라지거나 버튼 밖에서 잘리는 상태도 검출한다.
    let image = try XCTUnwrap(button.imageView)
    XCTAssertGreaterThan(image.bounds.width, 0)
    XCTAssertGreaterThan(image.bounds.height, 0)
    // UIKit 내부 컨테이너와 무관하게 버튼 좌표계에서 경계를 확인한다.
    let contentViews: [UIView] = [title, image]
    for view in contentViews {
      // 각각의 실제 렌더링 영역을 설정된 내부 여백과 비교한다.
      let frame = view.convert(view.bounds, to: button)
      XCTAssertGreaterThanOrEqual(frame.minX + 0.5, contentBounds.minX)
      XCTAssertGreaterThanOrEqual(frame.minY + 0.5, contentBounds.minY)
      XCTAssertLessThanOrEqual(frame.maxX - 0.5, contentBounds.maxX)
      XCTAssertLessThanOrEqual(frame.maxY - 0.5, contentBounds.maxY)
    }
  }

  @MainActor
  private func assertInvestmentHeaderLayout(in controller: UIViewController) throws {
    // 거래소와 내역 버튼은 제목을 사이에 두고 한 줄의 헤더를 구성한다.
    let exchange = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIButton }.first {
      $0.accessibilityIdentifier == "investment.exchange"
    })
    // 내역 버튼은 확대된 글씨에서도 요청한 24pt 정사각형을 유지한다.
    let history = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIButton }.first {
      $0.accessibilityIdentifier == "investment.history"
    })
    // 제목은 양쪽 버튼 사이의 가용 폭에서 자연스럽게 줄바꿈한다.
    let title = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UILabel }.first {
      $0.text == FuturesText.text("investment_history")
    })
    XCTAssertTrue(exchange.superview === title.superview)
    XCTAssertTrue(history.superview === title.superview)
    XCTAssertEqual(history.bounds.size.width, 24, accuracy: 0.5)
    XCTAssertEqual(history.bounds.size.height, 24, accuracy: 0.5)
    XCTAssertGreaterThan(history.currentImage?.size.height ?? 0, 0)
    XCTAssertGreaterThan(history.imageView?.bounds.height ?? 0, 0)
    // 버튼 밖으로 원본 심볼이 그려져 잘리는 상태도 크기 검증에 포함한다.
    let historyImage = try XCTUnwrap(history.imageView)
    // 이미지가 별도 컨테이너를 갖더라도 버튼의 좌표계에서 범위를 비교한다.
    let imageFrame = historyImage.convert(historyImage.bounds, to: history)
    // 실패 시 버튼 크기와 실제 심볼 렌더링 크기를 함께 확인한다.
    let imageDescription = "button=\(history.bounds), image=\(String(describing: history.currentImage?.size)), imageFrame=\(imageFrame)"
    XCTAssertGreaterThanOrEqual(imageFrame.minX, -0.5, imageDescription)
    XCTAssertGreaterThanOrEqual(imageFrame.minY, -0.5, imageDescription)
    XCTAssertLessThanOrEqual(imageFrame.maxX, history.bounds.width + 0.5, imageDescription)
    XCTAssertLessThanOrEqual(imageFrame.maxY, history.bounds.height + 0.5, imageDescription)
    XCTAssertTrue(history.actions(forTarget: controller, forControlEvent: .touchUpInside)?.contains("tapOnPnlButton:") == true)
    XCTAssertLessThanOrEqual(exchange.frame.maxX + 12, title.frame.minX + 0.5)
    XCTAssertLessThanOrEqual(title.frame.maxX + 12, history.frame.minX + 0.5)
    XCTAssertEqual(exchange.frame.midY, title.frame.midY, accuracy: 0.5)
    XCTAssertEqual(history.frame.midY, title.frame.midY, accuracy: 0.5)
    XCTAssertFalse(title.hasAmbiguousLayout)
    XCTAssertGreaterThanOrEqual(
      title.bounds.height + 1,
      title.sizeThatFits(CGSize(width: title.bounds.width, height: .greatestFiniteMagnitude)).height
    )
    // 확대된 충전 안내도 고정 높이로 잘리지 않아야 한다.
    let note = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UILabel }.first {
      $0.accessibilityIdentifier == "investment.chargeNote"
    })
    XCTAssertGreaterThanOrEqual(
      note.bounds.height + 1,
      note.sizeThatFits(CGSize(width: note.bounds.width, height: .greatestFiniteMagnitude)).height
    )
  }

  @MainActor
  private func assertInvestmentExchangeButton(
    in controller: UIViewController,
    exchange: Exchange,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    controller.loadViewIfNeeded()
    controller.view.layoutIfNeeded()
    // XIB의 기본 제목과 설정 기반 제목이 서로 덮어쓰지 않아야 한다.
    let button = try XCTUnwrap(
      descendants(controller.view).compactMap { $0 as? UIButton }.first {
        $0.accessibilityIdentifier == "investment.exchange"
      },
      file: file,
      line: line
    )
    // 실제 선택 계좌에서 생성한 다국어 거래소 이름이다.
    let expectedTitle = FuturesText.text(exchange == .upbit ? "futures_upbit" : "futures_bithumb")
    XCTAssertEqual(button.configuration?.title, expectedTitle, file: file, line: line)
    XCTAssertEqual(button.title(for: .normal), expectedTitle, file: file, line: line)
    XCTAssertEqual(button.currentTitle, expectedTitle, file: file, line: line)
    // 기존 거래소 로고도 실제 선택 계좌에 맞춰 함께 바뀌어야 한다.
    let assetImage = try XCTUnwrap(
      UIImage(named: exchange == .upbit ? "upbit_logo" : "bithumb_logo"),
      file: file,
      line: line
    )
    // 기존 거래소 로고가 버튼용 크기로 표시되는지 확인한다.
    let imageSize = CGSize(width: 18, height: 18)
    // 원본 자산과 같은 로고가 작은 버튼에도 유지되어야 한다.
    let expectedImage = UIGraphicsImageRenderer(size: imageSize).image { _ in
      assetImage.draw(in: CGRect(origin: .zero, size: imageSize))
    }
    XCTAssertEqual(button.currentImage?.size, imageSize, file: file, line: line)
    XCTAssertEqual(button.currentImage?.pngData(), expectedImage.pngData(), file: file, line: line)
    XCTAssertEqual(button.image(for: .normal)?.pngData(), expectedImage.pngData(), file: file, line: line)
    XCTAssertNil(button.menu, file: file, line: line)
    XCTAssertFalse(button.showsMenuAsPrimaryAction, file: file, line: line)
  }

  private func descendants(_ view: UIView) -> [UIView] {
    view.subviews.flatMap { [$0] + descendants($0) }
  }

  @MainActor
  func testFloatingSwitchHidesOnOtherTabsAndDetail() throws {
    // 실제 컨트롤 위치를 계산할 수 있는 탭 컨테이너다.
    let controller = MobitTabBarViewController()
    controller.setViewControllers([UIViewController(), UIViewController(), UIViewController()])
    controller.setProduct(.perpetual)
    // 안전 영역이 있는 윈도우에서 실제 스위치 높이를 반영한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    XCTAssertGreaterThan(try assertProductSelectorSafeArea(in: controller), 0)
    controller.switchToTab(index: 2)
    XCTAssertEqual(try assertProductSelectorSafeArea(in: controller), 0)
    controller.switchToTab(index: 1)
    XCTAssertGreaterThan(try assertProductSelectorSafeArea(in: controller), 0)
    controller.setTradingChromeHidden(true)
    XCTAssertEqual(try assertProductSelectorSafeArea(in: controller), 0)
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
    // 복귀 순간에도 실측 높이를 계산할 수 있도록 실제 창에 붙인다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
    window.rootViewController = container
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    _ = try assertProductSelectorSafeArea(in: container)
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
    XCTAssertGreaterThan(try assertProductSelectorSafeArea(in: container), 0)
    pnl.endAppearanceTransition()
    XCTAssertFalse(container.mobitTabBar.isHidden)
  }

  @MainActor
  func testInvestmentLastHoldingScrollsAboveProductSelectorAcrossStylesAndTextSizes() throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Trait overrides require iOS 17") }
    for style in [MobitTabBarViewController.Style.standard, .floating] {
      for width: CGFloat in [320, 393] {
        for product in [TradingProduct.spot, .perpetual] {
          // 두 상품에서 이미 사용하는 실제 요약과 목록 XIB를 로드한다.
          let spot = InvestReactor(mainUseCase: try FuturesMainFixtureUseCase())
          spot.isStubEnabled = true
          // 계좌 조회와 시세 연결 없이 선물 화면의 기존 바인딩을 유지한다.
          let futures = FuturesAccountReactor(account: account)
          futures.isStubEnabled = true
          // 외부 통신을 시작하지 않는 메인 시세 Reactor다.
          let market = MainReactor(mainUseCase: try FuturesMainFixtureUseCase(), tickerSocketService: FuturesMainFixtureSocket())
          market.isStubEnabled = true
          // 목록을 직접 스크롤할 실제 투자내역 화면이다.
          let investment: UIViewController = product == .spot
            ? InvestmentViewController(reactor: spot)
            : FuturesInvestmentViewController(reactor: futures, marketReactor: market)
          // 앱과 같은 내비게이션 계층에 추가 안전 영역이 전달돼야 한다.
          let navigation = UINavigationController(rootViewController: investment)
          navigation.setNavigationBarHidden(true, animated: false)
          // 스타일별 탭바와 상품 스위치의 실제 위치를 측정한다.
          let container = MobitTabBarViewController()
          container.style = style
          container.setViewControllers([UIViewController(), navigation, UIViewController()], selectedIndex: 1)
          container.setProduct(product)
          // 기기별 안전 영역을 가진 실제 윈도우에서 Auto Layout을 수행한다.
          let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 852))
          window.rootViewController = container
          window.makeKeyAndVisible()
          defer { window.isHidden = true; window.rootViewController = nil }
          investment.loadViewIfNeeded()
          window.layoutIfNeeded()
          _ = try assertProductSelectorSafeArea(in: container)
          XCTAssertTrue(investment.view.isDescendant(of: container.view))
          // 화면별 원래 테이블과 공유 헤더를 유지하고 행 데이터만 통제한다.
          let table: UITableView
          if let controller = investment as? InvestmentViewController {
            table = try XCTUnwrap(controller.transactionTableview)
            controller.noResultView.isHidden = true
            controller.summaryHeaderView.updateCount(12)
          } else {
            // 분기별 화면 타입은 위에서 정한 상품과 일치해야 한다.
            let controller = try XCTUnwrap(investment as? FuturesInvestmentViewController)
            table = try XCTUnwrap(controller.transactionTableview)
            controller.noResultView.isHidden = true
            controller.summaryHeaderView.updateCount(12)
          }
          // 마지막 셀이 화면 밖으로 충분히 내려가는 실제 보유자산 데이터다.
          let holding = spotOrderLayoutHolding()
          // 지연된 화면 바인딩도 원래 데이터 소스로 돌아가 갱신할 수 있게 복구한다.
          let originalDataSource = table.dataSource
          defer { table.dataSource = originalDataSource }
          // 선물도 현물과 같은 셀을 사용하면서 방향 배지와 ROE를 표시한다.
          let position = try FuturesCalculator.open(domesticFuturesOrder(leverage: 20))
          // 서버나 사용자 저장소를 바꾸지 않고 12개 셀의 자체 높이를 계산한다.
          let dataSource = UITableViewDiffableDataSource<Int, Int>(tableView: table) { table, path, _ in
            guard let cell = table.dequeueReusableCell(withIdentifier: "InvestmentTableViewCell", for: path) as? InvestmentTableViewCell else {
              return UITableViewCell()
            }
            if product == .spot { cell.configure(crypto: holding, isLast: path.row == 11) }
            else { cell.configure(position: position, valuation: nil, isLast: path.row == 11) }
            return cell
          }
          // 글씨 크기가 바뀐 뒤에도 같은 식별자를 재사용한다.
          var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
          snapshot.appendSections([0])
          snapshot.appendItems(Array(0..<12))
          dataSource.apply(snapshot, animatingDifferences: false)
          // 확대 후 기본 글씨로 돌아올 때 여백이 누적되지 않아야 한다.
          var normalInset: CGFloat?
          for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge, .large] {
            container.traitOverrides.preferredContentSizeCategory = category
            container.updateTraitsIfNeeded()
            // 화면을 반복해서 숨기고 복원해도 매번 같은 실측값을 적용한다.
            for _ in 0..<2 {
              container.setTradingChromeHidden(true)
              XCTAssertEqual(try assertProductSelectorSafeArea(in: container), 0)
              container.setTradingChromeHidden(false)
            }
            // 현재 글씨 크기의 실제 상품 스위치 높이에 맞춘 여백이다.
            let inset = try assertProductSelectorSafeArea(in: container)
            XCTAssertGreaterThan(inset, 0)
            if category == .large {
              if let normalInset { XCTAssertEqual(inset, normalInset, accuracy: 0.5) }
              else { normalInset = inset }
            }
            table.reloadData()
            table.layoutIfNeeded()
            // 목록 영역은 스위치 뒤까지 유지하고 스크롤 콘텐츠에만 하단 여백을 준다.
            XCTAssertEqual(table.frame.maxY, investment.view.bounds.maxY, accuracy: 0.5)
            // 마지막 행의 추정 높이를 실제 셀 높이로 확정한다.
            let lastPath = IndexPath(row: 11, section: 0)
            table.scrollToRow(at: lastPath, at: .bottom, animated: false)
            table.layoutIfNeeded()
            // 사용자가 끝까지 스크롤할 수 있는 실제 최대 오프셋이다.
            let maximumOffset = max(-table.adjustedContentInset.top, table.contentSize.height - table.bounds.height + table.adjustedContentInset.bottom)
            table.setContentOffset(CGPoint(x: 0, y: maximumOffset), animated: false)
            table.layoutIfNeeded()
            // 셀과 스위치를 컨테이너 좌표계에서 비교해야 내비게이션 여백도 포함된다.
            let lastFrame = table.convert(table.rectForRow(at: lastPath), to: container.view)
            // 스위치의 상단보다 셀 하단이 위로 올라가야 모든 지표가 보인다.
            let selector = try XCTUnwrap(descendants(container.view).first { $0.accessibilityIdentifier == "tradingProductSelector" })
            // 실제 선택 컨트롤의 표시 범위다.
            let selectorFrame = selector.convert(selector.bounds, to: container.view)
            XCTAssertLessThanOrEqual(lastFrame.maxY, selectorFrame.minY + 0.5, "\(product) \(style) \(width) \(category)")
            XCTAssertNotNil(table.cellForRow(at: lastPath))
            if style == .standard, width == 393, category == .large {
              // 스크롤 끝에서 마지막 셀과 하단 스위치의 실제 간격을 보관한다.
              let capture = XCTAttachment(image: UIGraphicsImageRenderer(bounds: container.view.bounds).image {
                container.view.layer.render(in: $0.cgContext)
              })
              capture.name = "InvestmentLastRow-\(product.rawValue)"
              capture.lifetime = .keepAlways
              add(capture)
            }
          }
          withExtendedLifetime(dataSource) {}
        }
      }
    }
  }

  @MainActor
  @discardableResult
  private func assertProductSelectorSafeArea(in container: MobitTabBarViewController) throws -> CGFloat {
    container.view.setNeedsLayout()
    container.view.layoutIfNeeded()
    // 안전 영역 변경을 받은 현재 탭의 실제 루트 화면이다.
    let content = try XCTUnwrap(container.children.first)
    content.view.layoutIfNeeded()
    // 표시 상태와 높이를 같은 레이아웃 패스에서 측정한다.
    let selector = try XCTUnwrap(descendants(container.view).first { $0.accessibilityIdentifier == "tradingProductSelector" })
    // 거래소는 기존 여백을 유지하고 투자내역만 실제 컨트롤 높이를 따른다.
    let expected: CGFloat
    if selector.isHidden {
      expected = 0
    } else if container.selectedIndex == 0 {
      expected = 76
    } else {
      expected = max(
        0,
        container.view.safeAreaLayoutGuide.layoutFrame.maxY - selector.convert(selector.bounds, to: container.view).minY
      )
    }
    XCTAssertEqual(content.additionalSafeAreaInsets.bottom, expected, accuracy: 0.5)
    return expected
  }

}

private final class SpotCompletionTradeViewControllerFixture: TradeViewController {
  override func loadView() {
    // 실제 화면의 outlet·제약은 유지하고 테스트 subclass 이름으로 nib을 찾지 않는다.
    Bundle.main.loadNibNamed("TradeViewController", owner: self)
  }

  override func setUI() {
    super.setUI()
    // 생성된 비동기 차트 작업이 외부 웹 페이지를 요청하기 전에 중단한다.
    chartView?.symbol = nil
    chartView?.webView.stopLoading()
  }

  override func loadBannerADView() {
    // 광고 영역의 실제 XIB 배치는 유지하고 SDK 네트워크 요청만 생략한다.
  }

  override func setChartData() {
    // 주문 복구 테스트가 외부 차트 조회를 시작하지 않도록 한다.
  }
}

extension FuturesAccountReactorTests {
  @MainActor
  private func withSpotCompletionStorage(_ run: () throws -> Void) throws {
    // 전체 설정을 지우지 않고 이 거래 경로에서 접근하는 저장 키만 복구한다.
    let keys = [
      UserDataManager.Keys.isFirstLaunch, UserDataManager.Keys.userCryptoList,
      UserDataManager.Keys.userTransactionList, UserDataManager.Keys.userValidTransactionList,
      UserDataManager.Keys.userPNLHistory, UserDataManager.Keys.userInformation,
      UserDataManager.Keys.userInformationByExchange, UserDataManager.Keys.pendingInvestmentState,
      UserDataManager.Keys.userFavoriteList, UserDataManager.Keys.tradingViewChartSettings,
      "selected-exchange", "selected-trading-product"
    ]
    // 원본 바이트·잘못된 형식·키 부재까지 그대로 되돌리기 위한 스냅샷이다.
    let savedValues = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
    // 보유자산 Observable의 직전 발행값도 테스트 값으로 남기지 않는다.
    var savedHoldings: [CryptoTransactionDataModel]?
    UserDataManager.userCryptoListObservable.take(1).subscribe(onNext: { savedHoldings = $0 }).dispose()
    // 현재 선택 계좌와 무관하게 직전 잔고 발행값을 복구한다.
    let savedBalance = try UserDataManager.userAvailableBalanceSubject.value()
    defer {
      // setter의 비동기 발행으로 캐시를 먼저 복구한 뒤 저장 원문을 되돌린다.
      UserDefaults.standard.removeObject(forKey: UserDataManager.Keys.pendingInvestmentState)
      UserDataManager.userCryptoList = []
      if let encoded = try? JSONEncoder().encode(savedHoldings) {
        UserDefaults.standard.set(encoded, forKey: UserDataManager.Keys.userCryptoList)
      }
      waitForNoticeUpdates(0.05)
      for (key, value) in savedValues {
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
      }
      UserDataManager.userAvailableBalanceSubject.onNext(savedBalance)
    }
    ExchangeSelectionStore.currentExchange = .upbit
    ExchangeSelectionStore.currentProduct = .spot
    UserDefaults.standard.removeObject(forKey: UserDataManager.Keys.pendingInvestmentState)
    UserDefaults.standard.set(false, forKey: UserDataManager.Keys.isFirstLaunch)
    UserDefaults.standard.set(
      try JSONEncoder().encode([Exchange.upbit.rawValue: MobitUserInformation(userAvailableBalance: 10_000)]),
      forKey: UserDataManager.Keys.userInformationByExchange
    )
    UserDataManager.userCryptoList = []
    UserDataManager.userTransactionList = []
    UserDataManager.userValidTransactionList = []
    UserDataManager.userPNLHistory = []
    waitForNoticeUpdates(0.05)
    try run()
  }

  @MainActor
  private func makeSpotCompletionController(price: Double = 1_000) throws -> SpotCompletionTradeViewControllerFixture {
    // 기존 주문 화면 fixture의 메모리 시세·stub Reactor를 재사용한다.
    let fixture = try makeSpotOrderLayoutController()
    // 주문·콜백·저장은 실제 구현을 사용하고 외부 광고·차트 요청만 막는다.
    let controller = SpotCompletionTradeViewControllerFixture(reactor: fixture.reactor)
    // 시세 응답 없이 즉시 체결 가능한 화면 상태를 주입한다.
    var state = controller.reactor.initialState
    state.cryptoCellInfo = CryptoCellInfo(
      cryptoName: "Bitcoin",
      market: "BTC/KRW",
      tradePrice: price,
      changePrice: 0,
      signedChangeRate: 0,
      change: "EVEN"
    )
    state.cryptoTransactionDatas = UserDataManager.userCryptoList ?? []
    controller.reactor.stub.state.value = state
    return controller
  }

  @MainActor
  func testSpotFormsRecoverAfterAlertPriceAndStorageFailuresWithoutDuplicateTrades() throws {
    for selling in [false, true] {
      try withSpotCompletionStorage {
        // 양쪽 폼을 같은 초기 잔고와 보유 수량에서 검사한다.
        _ = try TradeOrderService.executeBid(marketName: "BTC/KRW", cryptoName: "Bitcoin", currentPrice: 1_000, quantity: 2).get()
        // 저장 실패를 되돌린 뒤 같은 화면에서 재주문한다.
        let savedHistory = UserDefaults.standard.data(forKey: UserDataManager.Keys.userPNLHistory)
        // 실제 주문 콜백과 원자 저장을 사용하는 화면이다.
        let host = try makeSpotCompletionController()
        // 실패 알럿의 표시·해제까지 확인한다.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 667))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { host.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil }
        host.orderView?.segmentedControl.onSegmentChanged?(selling ? 1 : 0)
        // 실제 XIB 버튼과 입력을 그대로 사용한다.
        let bid = try XCTUnwrap(host.orderView?.bidView)
        // 매도에서도 입력 수정 후 재주문이 가능해야 한다.
        let ask = try XCTUnwrap(host.orderView?.askView)
        // 이번 시나리오의 제출 버튼이다.
        let button = try XCTUnwrap(selling ? ask.orderButton : bid.orderButton)
        @MainActor func enter(_ quantity: Double) {
          if selling { ask.inputAmount = quantity; ask.inputTradeAmount.text = String(quantity); ask.refreshMarketColors() }
          else { bid.inputAmount = quantity; bid.inputTradeAmount.text = String(quantity); bid.refreshMarketColors() }
        }
        @MainActor func dismissAlert(_ error: TradeOrderValidator.ValidationError) {
          waitForNoticeUpdates(0.4)
          XCTAssertEqual((host.presentedViewController as? UIAlertController)?.message, error.message)
          host.dismiss(animated: false)
          waitForNoticeUpdates(0.05)
          XCTAssertNil(host.presentedViewController)
        }
        enter(20)
        button.sendActions(for: .touchUpInside)
        dismissAlert(selling ? .insufficientHolding : .insufficientBalance(currency: .krw))
        XCTAssertTrue(button.isEnabled)
        enter(1)
        // 통신 실패로 사용할 가격이 없다가 새 가격이 도착하는 흐름이다.
        var state = host.reactor.stub.state.value
        state.cryptoCellInfo?.tradePrice = nil
        host.reactor.stub.state.value = state
        waitForNoticeUpdates(0.05)
        button.sendActions(for: .touchUpInside)
        dismissAlert(.missingPrice)
        XCTAssertTrue(button.isEnabled)
        state.cryptoCellInfo?.tradePrice = 1_500
        host.reactor.stub.state.value = state
        waitForNoticeUpdates(0.05)
        XCTAssertEqual(UserDataManager.userTransactionList?.count, 1)
        // 입력 검증을 통과한 뒤 실제 저장 단계에서 실패시킨다.
        UserDefaults.standard.set(Data("broken-history".utf8), forKey: UserDataManager.Keys.userPNLHistory)
        button.sendActions(for: .touchUpInside)
        XCTAssertFalse(button.isEnabled)
        for _ in 0..<10 { button.sendActions(for: .touchUpInside) }
        dismissAlert(.invalidStoredData)
        UserDefaults.standard.set(savedHistory, forKey: UserDataManager.Keys.userPNLHistory)
        waitForNoticeUpdates(0.2)
        XCTAssertTrue(button.isEnabled)
        XCTAssertEqual(selling ? ask.inputAmount : bid.inputAmount, 1)
        XCTAssertEqual(UserDataManager.userTransactionList?.count, 1)
        XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 8_000)
        // 실패와 동일한 입력으로 다시 탭해도 하나의 거래만 저장된다.
        button.sendActions(for: .touchUpInside)
        for _ in 0..<10 { button.sendActions(for: .touchUpInside) }
        XCTAssertEqual(UserDataManager.userTransactionList?.count, 2)
        XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, selling ? 9_500 : 6_500)
        XCTAssertEqual(UserDataManager.userCryptoList?.first?.staticData.holdingQuantity, selling ? 1 : 3)
        XCTAssertEqual(selling ? ask.inputAmount : bid.inputAmount, 0)
        waitForNoticeUpdates(0.55)
        XCTAssertTrue(button.isEnabled)
        // 성공 후 새 입력으로 정상적인 다음 주문도 가능해야 한다.
        enter(0.5)
        button.sendActions(for: .touchUpInside)
        for _ in 0..<10 { button.sendActions(for: .touchUpInside) }
        XCTAssertEqual(UserDataManager.userTransactionList?.count, 3)
        XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, selling ? 10_250 : 5_750)
        XCTAssertEqual(UserDataManager.userCryptoList?.first?.staticData.holdingQuantity, selling ? 0.5 : 3.5)
        waitForNoticeUpdates(0.55)
        XCTAssertTrue(button.isEnabled)
      }
    }
  }

  @MainActor
  func testSpotBTCFormsRetryRateAfterAlertAndTradeOnceAfterNetworkRecovery() throws {
    // 다른 화면 테스트의 마지막 BTC 환산 시세를 복구한다.
    let previousRate = AppDataManager.shared.lastBTCKRWPrice(for: .bithumb)
    // 복원 시 원래의 거래 사용 가능 여부도 보존한다.
    let wasFresh = AppDataManager.shared.freshBTCKRWPrice(for: .bithumb) != nil
    defer {
      if let previousRate { AppDataManager.shared.updateBTCKRWPrice(previousRate, for: .bithumb, updatedAt: wasFresh ? Date() : .distantPast) }
      else { AppDataManager.shared.invalidateBTCKRWPrice(for: .bithumb) }
    }
    for selling in [false, true] {
      try withSpotCompletionStorage {
        // 앱 시작 화면의 업비트 실시간 시세와 분리된 계좌로 네트워크 복구를 검증한다.
        ExchangeSelectionStore.currentExchange = .bithumb
        UserDataManager.updateUserInformation(MobitUserInformation(userAvailableBalance: 10_000), for: .bithumb)
        // BTC 마켓 매수와 매도에 필요한 실제 보유분이다.
        _ = try TradeOrderService.executeBid(marketName: "BTC/KRW", cryptoName: "Bitcoin", currentPrice: 1_000, quantity: 2).get()
        _ = try TradeOrderService.executeBid(marketName: "ETH/BTC", cryptoName: "Ethereum", currentPrice: 0.05, quantity: 2, btcKRWPrice: 1_000).get()
        AppDataManager.shared.invalidateBTCKRWPrice(for: .bithumb)
        // 최초 조회와 확인 버튼의 재조회가 같은 네트워크 오류를 받는다.
        let useCase = try FuturesMainFixtureUseCase()
        useCase.tickerResponse = .error(URLError(.notConnectedToInternet))
        // 선택 종목 가격과 결제 자산의 환산 가격은 서로 구분한다.
        let quote = CryptoCellInfo(cryptoName: "Ethereum", market: "ETH/BTC", tradePrice: 0.05)
        // 환산 재시도는 stub action 대신 실제 Reactor 경로로 실행한다.
        let trade = TradeReactor(
          selectCrypto: quote,
          cmcInformation: nil,
          cryptoDetailUseCase: CryptoDetailUseCase(cryptoDetailRepository: CryptoDetailRepository()),
          mainUseCase: useCase,
          tickerSocketService: FuturesMainFixtureSocket(),
          orderBookSocketService: SpotRecoveryOrderBookFixture()
        )
        // 주문·알럿의 확인 콜백·저장은 실제 화면 구현을 사용한다.
        let host = SpotCompletionTradeViewControllerFixture(reactor: trade)
        // 확인 알럿을 실제로 닫을 표시 창이다.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 667))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { trade.action.onNext(.pauseSocket); host.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil }
        waitForNoticeUpdates(0.1)
        host.orderView?.segmentedControl.onSegmentChanged?(selling ? 1 : 0)
        // 거래 종목의 시세가 있어도 BTC 환산 시세가 없으면 거래하지 않는다.
        let bid = try XCTUnwrap(host.orderView?.bidView)
        // 보유 수량을 읽는 실제 매도 폼이다.
        let ask = try XCTUnwrap(host.orderView?.askView)
        bid.cryptoInfo = quote
        ask.cryptoInfo = quote
        bid.inputAmount = 1
        ask.inputAmount = 1
        // 이번 시나리오에서 반복 탭할 버튼이다.
        let button = try XCTUnwrap(selling ? ask.orderButton : bid.orderButton)
        AppDataManager.shared.invalidateBTCKRWPrice(for: .bithumb)
        XCTAssertEqual(trade.settlementCurrency, .btc)
        XCTAssertNil(AppDataManager.shared.freshBTCKRWPrice(for: .bithumb))
        button.sendActions(for: .touchUpInside)
        for _ in 0..<10 { button.sendActions(for: .touchUpInside) }
        waitForNoticeUpdates(0.4)
        // 첫 확인의 재조회도 실패하며 거래와 입력은 그대로 남아야 한다.
        let firstAlert = try XCTUnwrap(
          host.presentedViewController as? MobitAlertViewController,
          "Unexpected alert: \((host.presentedViewController as? UIAlertController)?.message ?? String(describing: host.presentedViewController))"
        )
        firstAlert.confirmButton.sendActions(for: .touchUpInside)
        waitForNoticeUpdates(0.6)
        XCTAssertNil(host.presentedViewController)
        XCTAssertNil(AppDataManager.shared.freshBTCKRWPrice(for: .bithumb))
        XCTAssertTrue(button.isEnabled)
        XCTAssertEqual(selling ? ask.inputAmount : bid.inputAmount, 1)
        XCTAssertEqual(UserDataManager.userTransactionList?.count, 2)
        button.sendActions(for: .touchUpInside)
        waitForNoticeUpdates(0.4)
        // 네트워크가 복구되면 같은 확인 동작이 정상 REST 응답을 반영한다.
        let response = Data("[{\"market\":\"KRW-BTC\",\"change\":\"EVEN\",\"trade_price\":1000,\"timestamp\":1}]".utf8)
        useCase.tickerResponse = .just(try JSONDecoder().decode(CryptoTickerListDTO.self, from: response).toDomain())
        // 실제 알럿 버튼을 통해 재조회 콜백을 실행한다.
        let retryAlert = try XCTUnwrap(host.presentedViewController as? MobitAlertViewController)
        retryAlert.confirmButton.sendActions(for: .touchUpInside)
        waitForNoticeUpdates(0.6)
        XCTAssertNil(host.presentedViewController)
        XCTAssertEqual(AppDataManager.shared.freshBTCKRWPrice(for: .bithumb), 1_000)
        XCTAssertTrue(button.isEnabled)
        XCTAssertEqual(UserDataManager.userTransactionList?.count, 2)
        button.sendActions(for: .touchUpInside)
        for _ in 0..<10 { button.sendActions(for: .touchUpInside) }
        XCTAssertEqual(UserDataManager.userTransactionList?.count, 3)
        XCTAssertEqual(UserDataManager.userCryptoList?.first { $0.staticData.marketName == "ETH/BTC" }?.staticData.holdingQuantity, selling ? 1 : 3)
        XCTAssertEqual(UserDataManager.userCryptoList?.first { $0.staticData.marketName == "BTC/KRW" }?.staticData.holdingQuantity ?? 0, selling ? 1.95 : 1.85, accuracy: 0.00000001)
        waitForNoticeUpdates(0.55)
        XCTAssertTrue(button.isEnabled)
      }
    }
  }

  @MainActor
  func testSpotBidAndAskCompletionPersistOnceAndReuseOneToastAcrossThemes() throws {
    for style in [UIUserInterfaceStyle.light, .dark] {
      try withSpotCompletionStorage {
        // 작은 화면에서도 실제 매수·매도 버튼의 완료가 화면 공통 토스트로 연결된다.
        let host = try makeSpotCompletionController()
        // 테마별 XIB 배치와 하단 광고 경계를 유지한다.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 667))
        window.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        if #available(iOS 17.0, *) { window.updateTraitsIfNeeded() }
        // 실제 XIB의 양쪽 주문 폼과 연결된 버튼이다.
        let order = try XCTUnwrap(host.orderView)
        // 매수 입력 후 실제 버튼 액션을 두 번 빠르게 보낸다.
        let bid = try XCTUnwrap(order.bidView)
        bid.inputAmount = 2
        bid.inputTradeAmount.text = "2"
        bid.refreshMarketColors()
        XCTAssertTrue(bid.orderButton.isEnabled)
        bid.orderButton.sendActions(for: .touchUpInside)
        // 첫 완료 안내를 두 번째 탭이 교체하거나 시간을 다시 시작하면 안 된다.
        let buyToast = try XCTUnwrap(host.view.subviews.first { $0.accessibilityIdentifier == "mobitToast" })
        bid.orderButton.sendActions(for: .touchUpInside)
        XCTAssertTrue(host.view.subviews.first { $0.accessibilityIdentifier == "mobitToast" } === buyToast)
        XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 8_000)
        XCTAssertEqual(UserDataManager.userCryptoList?.first?.staticData.holdingQuantity, 2)
        XCTAssertEqual(UserDataManager.userCryptoList?.first?.staticData.buyAmount, 2_000)
        XCTAssertEqual(UserDataManager.userTransactionList?.count, 1)
        XCTAssertEqual(UserDataManager.userTransactionList?.last?.orderType, .bid)
        XCTAssertEqual(UserDataManager.userValidTransactionList?.count, 1)
        XCTAssertEqual(bid.inputAmount, 0)
        XCTAssertFalse(descendants(host.view).contains { $0 is MobitLottieView })
        // 매수 저장 결과와 상승한 현재가를 매도 폼에 반영한다.
        var state = host.reactor.currentState
        state.cryptoCellInfo?.tradePrice = 1_500
        state.cryptoTransactionDatas = UserDataManager.userCryptoList ?? []
        host.reactor.stub.state.value = state
        waitForNoticeUpdates(0.4)
        order.segmentedControl.selectedIndex = 1
        order.segmentedControl.onSegmentChanged?(1)
        // 매도도 같은 저장·성공 콜백 경로를 통과해야 한다.
        let ask = try XCTUnwrap(order.askView)
        ask.inputAmount = 1
        ask.inputTradeAmount.text = "1"
        ask.refreshMarketColors()
        XCTAssertTrue(ask.orderButton.isEnabled)
        ask.orderButton.sendActions(for: .touchUpInside)
        // 새 실제 체결은 토스트 한 개를 교체하고 중복 탭은 그대로 유지한다.
        let sellToast = try XCTUnwrap(host.view.subviews.first { $0.accessibilityIdentifier == "mobitToast" })
        XCTAssertFalse(sellToast === buyToast)
        XCTAssertNil(buyToast.superview)
        ask.orderButton.sendActions(for: .touchUpInside)
        XCTAssertTrue(host.view.subviews.first { $0.accessibilityIdentifier == "mobitToast" } === sellToast)
        XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 9_500)
        XCTAssertEqual(UserDataManager.userCryptoList?.first?.staticData.holdingQuantity, 1)
        XCTAssertEqual(UserDataManager.userCryptoList?.first?.staticData.buyAmount, 1_000)
        XCTAssertEqual(UserDataManager.userTransactionList?.count, 2)
        XCTAssertEqual(UserDataManager.userTransactionList?.last?.orderType, .ask)
        XCTAssertEqual(UserDataManager.userPNLHistory?.count, 1)
        XCTAssertEqual(UserDataManager.userPNLHistory?.first?.pnl, 500)
        XCTAssertEqual(ask.inputAmount, 0)
        for tab in [0, 2, 1, 0, 1] {
          state.cryptoCellInfo?.tradePrice = Double(1_500 + tab)
          state.cryptoTransactionDatas = UserDataManager.userCryptoList ?? []
          host.reactor.stub.state.value = state
          order.segmentedControl.selectedIndex = tab
          order.segmentedControl.onSegmentChanged?(tab)
          XCTAssertTrue(host.view.subviews.first { $0.accessibilityIdentifier == "mobitToast" } === sellToast)
        }
        waitForNoticeUpdates(0.25)
        window.layoutIfNeeded()
        XCTAssertEqual(sellToast.accessibilityLabel, FuturesText.text("futures_order_done"))
        XCTAssertEqual(sellToast.traitCollection.userInterfaceStyle, style)
        XCTAssertEqual(sellToast.frame.midX, host.view.bounds.midX, accuracy: 0.5)
        XCTAssertLessThanOrEqual(sellToast.frame.maxY, host.bannerContainerView.frame.minY - 19.5)
        XCTAssertEqual(host.view.subviews.filter { $0.accessibilityIdentifier == "mobitToast" }.count, 1)
        // 두 테마에서 실제 현물 체결 후 결과 안내를 첨부한다.
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) })
        attachment.name = "Spot-trade-completion-320-\(style == .dark ? "dark" : "light")"
        attachment.lifetime = .keepAlways
        add(attachment)
        if style == .light {
          waitForNoticeUpdates(3.4)
          XCTAssertNil(sellToast.superview)
          host.reactor.stub.state.value = state
          order.segmentedControl.onSegmentChanged?(0)
          order.segmentedControl.onSegmentChanged?(1)
          XCTAssertFalse(host.view.subviews.contains { $0.accessibilityIdentifier == "mobitToast" })
          XCTAssertEqual(UserDataManager.userTransactionList?.count, 2)
        }
      }
    }
  }

  @MainActor
  func testSpotOrderFailureKeepsAssetsAndShowsNoCompletionToast() throws {
    try withSpotCompletionStorage {
      // 매도 수량 초과 오류를 검증할 정상 보유분만 준비한다.
      _ = try TradeOrderService.executeBid(marketName: "BTC/KRW", cryptoName: "Bitcoin", currentPrice: 1_000, quantity: 2).get()
      // 실패로 바뀌면 안 되는 보유 수량과 매입 원가를 비교한다.
      let holding = try XCTUnwrap(UserDataManager.userCryptoList?.first)
      // 실제 저장된 매수 내역이 오류 후에도 같아야 한다.
      let transactions = UserDataManager.userTransactionList
      // 실패도 실제 폼→주문뷰→상위 Alert 경로로 전달한다.
      let host = try makeSpotCompletionController()
      // 기존 오류 안내가 표시될 UIKit 창이다.
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
      window.rootViewController = host
      window.makeKeyAndVisible()
      defer { host.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil }
      // 잔고보다 큰 금액을 검증 단계에서 거절한다.
      let bid = try XCTUnwrap(host.orderView?.bidView)
      bid.inputAmount = 20
      bid.tapOnBidButton(bid.orderButton)
      waitForNoticeUpdates(0.35)
      XCTAssertEqual((host.presentedViewController as? UIAlertController)?.message, TradeOrderValidator.ValidationError.insufficientBalance(currency: .krw).message)
      XCTAssertFalse(host.view.subviews.contains { $0.accessibilityIdentifier == "mobitToast" })
      host.dismiss(animated: false)
      waitForNoticeUpdates(0.05)
      host.orderView?.segmentedControl.selectedIndex = 1
      host.orderView?.segmentedControl.onSegmentChanged?(1)
      // 보유 수량보다 큰 매도도 완료 안내를 내보내면 안 된다.
      let ask = try XCTUnwrap(host.orderView?.askView)
      ask.inputAmount = 3
      ask.tapOnAskButton(ask.orderButton)
      waitForNoticeUpdates(0.35)
      XCTAssertEqual((host.presentedViewController as? UIAlertController)?.message, TradeOrderValidator.ValidationError.insufficientHolding.message)
      XCTAssertFalse(host.view.subviews.contains { $0.accessibilityIdentifier == "mobitToast" })
      XCTAssertFalse(descendants(host.view).contains { $0 is MobitLottieView })
      XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 8_000)
      // 시세 평가값과 디코딩마다 생성되는 내부 UUID는 거래 저장 결과와 구분한다.
      let currentHolding = try XCTUnwrap(UserDataManager.userCryptoList?.first)
      XCTAssertEqual(UserDataManager.userCryptoList?.count, 1)
      XCTAssertEqual(currentHolding.identifier, holding.identifier)
      XCTAssertEqual(currentHolding.staticData.exchangePairID, holding.staticData.exchangePairID)
      XCTAssertEqual(currentHolding.staticData.holdingQuantity, holding.staticData.holdingQuantity)
      XCTAssertEqual(currentHolding.staticData.averageBuyPrice, holding.staticData.averageBuyPrice)
      XCTAssertEqual(currentHolding.staticData.buyAmount, holding.staticData.buyAmount)
      XCTAssertEqual(currentHolding.staticData.costBasisKRW, holding.staticData.costBasisKRW)
      XCTAssertEqual(UserDataManager.userTransactionList, transactions)
      XCTAssertEqual(UserDataManager.userPNLHistory?.count, 0)
    }
  }

  @MainActor
  func testSpotCompletionToastClearsOnNavigationAndIgnoresOffscreenCompletion() throws {
    try withSpotCompletionStorage {
      // 실제 내비게이션 이동으로 화면 이탈 정리와 표시 가드를 확인한다.
      let navigation = UINavigationController(rootViewController: UIViewController())
      navigation.setNavigationBarHidden(true, animated: false)
      // Scene에 연결해야 내비게이션이 실제 화면 표시·이탈 생명주기를 전달한다.
      let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
      // 테스트가 끝나면 앱의 원래 표시 창을 복구한다.
      let previousWindow = scene.windows.first { $0.isKeyWindow }
      // 거래 상세 앞뒤의 실제 UIKit 생명주기를 실행한다.
      let window = UIWindow(windowScene: scene)
      window.rootViewController = navigation
      window.makeKeyAndVisible()
      defer {
        window.isHidden = true
        window.rootViewController = nil
        previousWindow?.makeKeyAndVisible()
      }
      window.layoutIfNeeded()
      waitForNoticeUpdates(0.1)
      // 외부 시세 요청 없이 매수 성공을 만드는 실제 주문 화면이다.
      let host = try makeSpotCompletionController()
      navigation.pushViewController(host, animated: false)
      host.loadViewIfNeeded()
      window.layoutIfNeeded()
      waitForNoticeUpdates(0.1)
      XCTAssertTrue(host.view.window === window)
      // 화면에 연결된 실제 매수 폼이다.
      let bid = try XCTUnwrap(host.orderView?.bidView)
      bid.inputAmount = 1
      bid.refreshMarketColors()
      bid.orderButton.sendActions(for: .touchUpInside)
      // 화면이 가려지면 자동 닫기 시간을 기다리지 않고 제거돼야 한다.
      let toast = try XCTUnwrap(host.view.subviews.first { $0.accessibilityIdentifier == "mobitToast" })
      navigation.pushViewController(UIViewController(), animated: false)
      window.layoutIfNeeded()
      waitForNoticeUpdates(0.1)
      XCTAssertNil(host.view.window)
      XCTAssertNil(toast.superview)
      host.orderView?.callBack?(.tradeCompleted)
      XCTAssertFalse(host.view.subviews.contains { $0.accessibilityIdentifier == "mobitToast" })
      navigation.popViewController(animated: false)
      window.layoutIfNeeded()
      waitForNoticeUpdates(0.1)
      XCTAssertTrue(navigation.topViewController === host)
      XCTAssertFalse(host.view.subviews.contains { $0.accessibilityIdentifier == "mobitToast" })
      navigation.popViewController(animated: false)
      window.layoutIfNeeded()
      waitForNoticeUpdates(0.1)
      host.orderView?.callBack?(.tradeCompleted)
      XCTAssertFalse(host.view.subviews.contains { $0.accessibilityIdentifier == "mobitToast" })
      XCTAssertEqual(UserDataManager.userTransactionList?.count, 1)
      XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, 9_000)
    }
  }
}

private final class LifecycleSocketViewControllerFixture: UIViewController, SocketControllable {
  // 백그라운드에서 선택된 소켓이 중단되는 횟수다.
  var pauses = 0
  // 포그라운드에서 선택된 소켓이 재개되는 횟수다.
  var resumes = 0
  func pauseSocket() { pauses += 1 }
  func resumeSocket() { resumes += 1 }
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
  // BTC 환산 시세의 네트워크 실패와 확인 후 재조회를 제어한다.
  var tickerResponse: Observable<CryptoTickerList>?
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
  override func fetchCryptoTicker(markets: [String]) -> Observable<CryptoTickerList> { tickerResponse ?? .just(tickers) }
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

extension FuturesAccountReactorTests {
  @MainActor
  private func makeSpotOrderLayoutController() throws -> TradeViewController {
    // 외부 시세 대신 실제 주문 XIB에 전달할 고정 시세다.
    let trade = TradeReactor(
      selectCrypto: .init(cryptoName: "Bitcoin", market: "BTC/KRW", tradePrice: 110_000_000),
      cmcInformation: nil,
      cryptoDetailUseCase: CryptoDetailUseCase(cryptoDetailRepository: CryptoDetailRepository()),
      mainUseCase: try FuturesMainFixtureUseCase(),
      tickerSocketService: FuturesMainFixtureSocket()
    )
    trade.isStubEnabled = true
    return TradeViewController(reactor: trade)
  }

  private func spotOrderLayoutHolding() -> CryptoTransactionDataModel {
    CryptoTransactionDataModel(
      staticData: .init(
        exchange: .upbit,
        marketName: "BTC/KRW",
        cryptoName: "Bitcoin",
        holdingQuantity: 0.01,
        averageBuyPrice: 100_000_000,
        buyAmount: 1_000_000
      ),
      dynamicData: .init(
        exchange: .upbit,
        marketName: "BTC/KRW",
        profitRate: 10,
        evaluationProfitLoss: 100_000,
        evaluationPrice: 1_100_000
      )
    )
  }

  private func spotOrderLayoutOrderbook() -> Orderbook {
    Orderbook(
      type: "orderbook",
      code: "KRW-BTC",
      timestamp: 1,
      totalAskSize: 10,
      totalBidSize: 10,
      orderbookUnits: (1...10).map { index in
        .init(
          askPrice: 110_000_000 + Double(index) * 10_000,
          bidPrice: 110_000_000 - Double(index) * 10_000,
          askSize: Double(index) / 10,
          bidSize: Double(11 - index) / 10
        )
      },
      streamType: "SNAPSHOT",
      level: 0
    )
  }

  @MainActor
  func testSpotOrderScrollPreservesFormAndHoldingRowsAcrossSmallScreens() throws {
    // 업비트 보유 fixture와 거래 화면의 계좌를 맞추고 원래 선택을 복구한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    ExchangeSelectionStore.currentExchange = .upbit
    defer { ExchangeSelectionStore.currentExchange = previousExchange }
    // 기기별 논리 크기와 안전영역을 맞춰 높이 압축을 재현한다.
    let sizes: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
      (320, 568, 20, 0), (375, 667, 20, 0), (375, 812, 44, 34), (393, 852, 59, 34), (430, 932, 59, 34)
    ]
    for style in [UIUserInterfaceStyle.light, .dark] {
      for (width, height, topInset, bottomInset) in sizes {
        // 실제 상세 화면의 상단 정보와 하단 광고 영역을 포함한다.
        let controller = try makeSpotOrderLayoutController()
        // 다양한 크기를 실제 Auto Layout에 전달한다.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.additionalSafeAreaInsets = UIEdgeInsets(
          top: topInset - controller.view.safeAreaInsets.top,
          left: 0,
          bottom: bottomInset - controller.view.safeAreaInsets.bottom,
          right: 0
        )
        window.overrideUserInterfaceStyle = style
        if #available(iOS 17.0, *) { window.updateTraitsIfNeeded() }
        waitForNoticeUpdates(0.1)
        XCTAssertEqual(controller.view.traitCollection.userInterfaceStyle, style)
        // 두 폼과 자산 현황이 공유하는 스크롤이다.
        let order = try XCTUnwrap(controller.orderView)
        // 호가 테이블을 실수로 감싼 스크롤과 구분한다.
        let scroll = try XCTUnwrap(descendants(order).first { $0.accessibilityIdentifier == "spotOrderScroll" } as? UIScrollView)
        XCTAssertFalse(order.orderbookTableView.isDescendant(of: scroll))
        XCTAssertEqual(order.orderbookTableView.bounds.width, 150, accuracy: 0.5)
        XCTAssertTrue(order.investLiveView.isDescendant(of: scroll))
        for hasHolding in [false, true] {
          // 보유 여부가 바뀔 때도 스크롤 높이가 콘텐츠에 맞춰 갱신된다.
          var state = controller.reactor.initialState
          state.cryptoTransactionDatas = hasHolding ? [spotOrderLayoutHolding()] : []
          state.obTicker = spotOrderLayoutOrderbook()
          controller.reactor.stub.state.value = state
          waitForNoticeUpdates(0.4)
          for tab in [0, 1] {
            order.segmentedControl.selectedIndex = tab
            order.segmentedControl.onSegmentChanged?(tab)
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            // 스크롤 동작 전후 호가 영역 크기는 같아야 한다.
            let bookFrame = order.orderbookTableView.convert(order.orderbookTableView.bounds, to: controller.view)
            // 오른쪽 스크롤이 호가 목록의 스크롤 위치를 바꾸면 안 된다.
            let bookOffset = order.orderbookTableView.contentOffset
            XCTAssertEqual(order.orderbookTableView.numberOfRows(inSection: 0), 20)
            XCTAssertTrue(try XCTUnwrap(tab == 0 ? order.bidView as UIView? : order.askView as UIView?).isDescendant(of: scroll))
            // 매수·매도 모두 같은 접근성 검사를 적용한다.
            let button = try XCTUnwrap(tab == 0 ? order.bidView?.orderButton : order.askView?.orderButton)
            // 보유 영역이 추가돼도 시장가 안내문 높이가 압축되면 안 된다.
            let notice = try XCTUnwrap(tab == 0 ? order.bidView?.orderNoticeLabel : order.askView?.orderNoticeLabel)
            XCTAssertEqual(order.investLiveView.isHidden, !hasHolding)
            XCTAssertFalse(scroll.hasAmbiguousLayout)
            XCTAssertEqual(scroll.contentSize.width, scroll.bounds.width, accuracy: 0.5)
            XCTAssertEqual(button.bounds.height, 48, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(
              notice.bounds.height + 0.5,
              notice.sizeThatFits(CGSize(width: notice.bounds.width, height: .greatestFiniteMagnitude)).height
            )
            scroll.scrollRectToVisible(button.convert(button.bounds, to: scroll), animated: false)
            XCTAssertTrue(scroll.bounds.insetBy(dx: -0.5, dy: -0.5).contains(button.convert(button.bounds, to: scroll)))
            if hasHolding {
              for label in [order.cryptoAveragePrice, order.cryptoHoldingQuantity, order.cryptoEvalPrice, order.cryptoEvalLoss, order.cryptoProfitRate].compactMap({ $0 }) {
                XCTAssertGreaterThanOrEqual(label.bounds.height + 0.5, label.font.lineHeight)
              }
              scroll.scrollRectToVisible(order.investLiveView.convert(order.investLiveView.bounds, to: scroll), animated: false)
              XCTAssertTrue(scroll.bounds.insetBy(dx: -0.5, dy: -0.5).contains(order.investLiveView.convert(order.investLiveView.bounds, to: scroll)))
            }
            XCTAssertEqual(order.orderbookTableView.convert(order.orderbookTableView.bounds, to: controller.view), bookFrame)
            XCTAssertEqual(order.orderbookTableView.contentOffset, bookOffset)
            if hasHolding && height <= 667 {
              // 압축되던 작은 화면의 스크롤 후 전체 자산 현황을 보관한다.
              let capture = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { controller.view.layer.render(in: $0.cgContext) }
              // 두 테마와 매수·매도를 결과에서 구분한다.
              let attachment = XCTAttachment(image: capture)
              attachment.name = "SpotScroll-\(style == .dark ? "dark" : "light")-\(Int(width))x\(Int(height))-tab-\(tab)"
              attachment.lifetime = .keepAlways
              add(attachment)
            }
          }
        }
        order.segmentedControl.selectedIndex = 2
        order.segmentedControl.onSegmentChanged?(2)
        window.layoutIfNeeded()
        XCTAssertTrue(order.investLiveView.isHidden)
        XCTAssertFalse(try XCTUnwrap(order.historyView).isHidden)
        XCTAssertGreaterThan(try XCTUnwrap(order.historyView).bounds.height, 0)
        order.segmentedControl.selectedIndex = 0
        order.segmentedControl.onSegmentChanged?(0)
        XCTAssertEqual(scroll.contentOffset.y, 0, accuracy: 0.5)
      }
    }
  }

  @MainActor
  func testSpotOrderScrollKeepsInputsAndActionsReachableWithRealKeyboard() throws {
    // 업비트 보유 fixture와 거래 화면의 계좌를 맞추고 원래 선택을 복구한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    ExchangeSelectionStore.currentExchange = .upbit
    defer { ExchangeSelectionStore.currentExchange = previousExchange }
    // 실제 Scene의 소프트웨어 키보드와 layout guide를 사용한다.
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    // 테스트가 끝나면 원래 앱 창의 입력 상태로 돌아간다.
    let previousWindow = scene.windows.first { $0.isKeyWindow }
    // 실행 대상 Simulator의 실제 화면 크기를 따른다.
    let window = UIWindow(windowScene: scene)
    // 검증 중 실제 주문은 제출하지 않는다.
    let controller = try makeSpotOrderLayoutController()
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer {
      window.endEditing(true)
      window.isHidden = true
      window.rootViewController = nil
      previousWindow?.makeKeyAndVisible()
    }
    // 키보드와 함께 접근할 보유자산 데이터를 주입한다.
    var state = controller.reactor.initialState
    state.cryptoTransactionDatas = [spotOrderLayoutHolding()]
    state.obTicker = spotOrderLayoutOrderbook()
    controller.reactor.stub.state.value = state
    waitForNoticeUpdates(0.5)
    // 화면 전환과 키보드 회피가 호가에 영향을 주는지 비교한다.
    let order = try XCTUnwrap(controller.orderView)
    // 실제 키보드 경계까지 줄어드는 오른쪽 영역이다.
    let scroll = try XCTUnwrap(descendants(order).first { $0.accessibilityIdentifier == "spotOrderScroll" } as? UIScrollView)
    // 최초 호가 영역은 키보드가 떠도 이동하거나 줄어들지 않는다.
    let bookFrame = order.orderbookTableView.convert(order.orderbookTableView.bounds, to: controller.view)
    XCTAssertFalse(order.investLiveView.isHidden)
    XCTAssertTrue(order.investLiveView.isDescendant(of: scroll))
    XCTAssertFalse(order.orderbookTableView.isDescendant(of: scroll))
    XCTAssertEqual(order.orderbookTableView.numberOfRows(inSection: 0), 20)
    for style in [UIUserInterfaceStyle.light, .dark] {
      window.endEditing(true)
      window.overrideUserInterfaceStyle = style
      if #available(iOS 17.0, *) { window.updateTraitsIfNeeded() }
      XCTAssertEqual(order.traitCollection.userInterfaceStyle, style)
      XCTAssertEqual(
        order.backgroundColor?.resolvedColor(with: order.traitCollection),
        UIColor.mobitColors(.tradeBackground).resolvedColor(with: order.traitCollection)
      )
      XCTAssertEqual(
        order.cryptoAveragePrice.textColor.resolvedColor(with: order.traitCollection),
        UIColor.mobitColors(.tradeTextPrimary).resolvedColor(with: order.traitCollection)
      )
      for tab in [0, 1] {
        order.segmentedControl.selectedIndex = tab
        order.segmentedControl.onSegmentChanged?(tab)
        // 수량과 총액 중 어느 입력란을 선택해도 자동으로 드러나야 한다.
        let fields = tab == 0 ? [order.bidView?.inputTradeAmount, order.bidView?.totalPriceTextField] : [order.askView?.inputTradeAmount, order.askView?.totalPriceTextField]
        for field in fields.compactMap({ $0 }) {
          XCTAssertEqual(field.traitCollection.userInterfaceStyle, style)
          XCTAssertEqual(
            field.textColor?.resolvedColor(with: field.traitCollection),
            UIColor.mobitColors(.tradeTextPrimary).resolvedColor(with: field.traitCollection)
          )
          XCTAssertTrue(field.becomeFirstResponder())
          // 키보드가 실제 등장했는지 확인하므로 하드웨어 키보드만 연결된 실행은 통과하지 않는다.
          let keyboardShown = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
              window.bounds.maxY - order.convert(order.keyboardLayoutGuide.layoutFrame, to: window).minY > 150
            },
            object: nil
          )
          wait(for: [keyboardShown], timeout: 5)
          waitForNoticeUpdates(0.4)
          controller.view.layoutIfNeeded()

          XCTAssertGreaterThan(scroll.bounds.height, field.bounds.height)
          XCTAssertLessThanOrEqual(scroll.convert(scroll.bounds, to: order).maxY, order.keyboardLayoutGuide.layoutFrame.minY + 0.5)
          XCTAssertTrue(scroll.bounds.insetBy(dx: -0.5, dy: -0.5).contains(field.convert(field.bounds, to: scroll)))
          // 오른쪽 영역을 움직여도 호가 자체 스크롤은 유지돼야 한다.
          let bookOffset = order.orderbookTableView.contentOffset
          // 키보드를 유지해도 버튼까지 직접 스크롤할 수 있어야 한다.
          let button = try XCTUnwrap(tab == 0 ? order.bidView?.orderButton : order.askView?.orderButton)
          scroll.scrollRectToVisible(button.convert(button.bounds, to: scroll), animated: false)
          XCTAssertTrue(scroll.bounds.insetBy(dx: -0.5, dy: -0.5).contains(button.convert(button.bounds, to: scroll)))
          // 키보드 위 공간보다 자산 영역이 커도 각 행에 끝까지 접근할 수 있어야 한다.
          for label in [order.cryptoAveragePrice, order.cryptoHoldingQuantity, order.cryptoEvalPrice, order.cryptoEvalLoss, order.cryptoProfitRate].compactMap({ $0 }) {
            scroll.scrollRectToVisible(label.convert(label.bounds, to: scroll), animated: false)
            XCTAssertTrue(scroll.bounds.insetBy(dx: -0.5, dy: -0.5).contains(label.convert(label.bounds, to: scroll)))
            XCTAssertGreaterThanOrEqual(label.bounds.height + 0.5, label.font.lineHeight)
          }
          XCTAssertEqual(order.orderbookTableView.convert(order.orderbookTableView.bounds, to: controller.view), bookFrame)
          XCTAssertEqual(order.orderbookTableView.contentOffset, bookOffset)
          XCTAssertTrue(field.isFirstResponder)
          // 키보드 위로 줄어든 영역에서도 마지막 자산 행에 접근한 결과를 보관한다.
          let capture = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { controller.view.layer.render(in: $0.cgContext) }
          // 키보드 자체는 별도 시스템 창이므로 이 캡처에는 주문 영역만 포함한다.
          let attachment = XCTAttachment(image: capture)
          attachment.name = "SpotScroll-keyboard-\(style == .dark ? "dark" : "light")-tab-\(tab)-\(field.accessibilityIdentifier ?? "input")"
          attachment.lifetime = .keepAlways
          add(attachment)
        }
      }
    }
    order.endEditing(true)
    waitForNoticeUpdates(0.5)
    XCTAssertEqual(scroll.convert(scroll.bounds, to: order.segmentedContainerView).maxY, order.segmentedContainerView.bounds.maxY, accuracy: 0.5)
    XCTAssertEqual(order.orderbookTableView.convert(order.orderbookTableView.bounds, to: controller.view), bookFrame)
  }
}

private final class MainIndicatorDelegateSpy: MainCoordinatorDelegate {
  // 화면 계층과 무관하게 Coordinator 종료 요청이 전달된 횟수다.
  var finishCount = 0
  // 실제 공통 인디케이터를 소유한 테스트 탭을 약하게 참조한다.
  weak var tabs: MobitTabBarViewController?

  func mainCoordinatorDidRequestFinishForegroundIndicator() {
    finishCount += 1
    tabs?.finishForegroundIndicator()
  }
}

extension FuturesAccountReactorTests {
  @MainActor
  func testPNLCardKeepsDecimalPrecisionBelowIntegerThreshold() throws {
    // Double 변환으로 1,000에 반올림되기 쉬운 손익도 원래 Decimal로 표시한다.
    let position = try FuturesCalculator.open(domesticFuturesOrder())
    // 양수·음수 모두 절댓값 1,000 미만의 소수점 8자리 절삭 정책을 지킨다.
    let samples = [
      ("999.99999999999999", "+999.99999999"),
      ("-999.99999999999999", "-999.99999999")
    ]
    // 한 셀을 재사용해 손익 부호가 바뀔 때 표시가 남는지도 확인한다.
    let cell = try XCTUnwrap(
      UINib(nibName: "PNLTableViewCell", bundle: .main)
        .instantiate(withOwner: nil).first as? PNLTableViewCell
    )
    for (input, expected) in samples {
      // 원본 문자열에서 Double을 거치지 않고 정밀한 손익을 구성한다.
      let pnl = try XCTUnwrap(Decimal(string: input))
      // 저장된 체결 결과의 손익만 화면에 전달한다.
      let record = FuturesTransactionRecord(
        eventID: UUID(),
        positionID: position.id,
        kind: .closing,
        instrument: position.order.instrument,
        side: position.order.side,
        leverage: position.order.leverage,
        quantity: position.quantity,
        intervalStart: 120_000,
        intervalEndExclusive: nil,
        recordedAt: Date(timeIntervalSince1970: 120),
        price: 100_000_000,
        realizedPnL: pnl
      )

      cell.configure(record: record, position: position)

      XCTAssertEqual(cell.pnlLabel.text, expected + " " + FuturesText.text("currency_krw_unit"))
    }
  }

  @MainActor
  func testPNLCardUsesPartialClosingMarginAndEntryPriceForRealizedReturn() throws {
    // 종료 기록의 원가와 증거금을 현재 보유 포지션과 구분해 검증한다.
    let position = try FuturesCalculator.open(domesticFuturesOrder())
    // 부분 종료 당시의 증거금과 평균 진입가는 이후 포지션 값에 영향받지 않는다.
    let record = FuturesTransactionRecord(
      eventID: UUID(),
      positionID: position.id,
      kind: .closing,
      instrument: position.order.instrument,
      side: position.order.side,
      leverage: position.order.leverage,
      quantity: position.quantity / 4,
      intervalStart: 120_000,
      intervalEndExclusive: nil,
      recordedAt: Date(timeIntervalSince1970: 120),
      price: 110_000_000,
      realizedPnL: 10_000,
      margin: 25_000,
      entryPrice: 90_000_000
    )
    // 실제 XIB와 화면 구성 경로로 표시값을 확인한다.
    let cell = try XCTUnwrap(
      UINib(nibName: "PNLTableViewCell", bundle: .main)
        .instantiate(withOwner: nil).first as? PNLTableViewCell
    )

    cell.configure(record: record, position: position)

    XCTAssertEqual(cell.marketNameLabel.text, FuturesText.symbol(record.instrument))
    XCTAssertEqual(cell.positionBadgeLabel.text, "\(FuturesText.side(record.side)) \(record.leverage)×")
    XCTAssertEqual(cell.statusLabel.text, FuturesText.text("futures_pnl_closed"))
    XCTAssertFalse(cell.positionBadgeView.isHidden)
    XCTAssertFalse(cell.statusLabel.isHidden)
    XCTAssertFalse(cell.marginView.isHidden)
    XCTAssertEqual(cell.marginLabel.text, "25,000 " + FuturesText.text("currency_krw_unit"))
    XCTAssertEqual(cell.entryPriceLabel.text, "90,000,000 " + FuturesText.text("currency_krw_unit"))
    XCTAssertEqual(cell.exitPriceLabel.text, "110,000,000 " + FuturesText.text("currency_krw_unit"))
    XCTAssertEqual(cell.pnlLabel.text, "+10,000 " + FuturesText.text("currency_krw_unit"))
    XCTAssertEqual(cell.roiLabel.text, "+40%")
    XCTAssertEqual(try FuturesText.shareUnit(record, position: position).roi, 40)
  }

  @MainActor
  func testPNLReusePreservesXIBRowsAndCardColorsAcrossThemes() throws {
    // 현물·선물 구성을 번갈아 적용해도 XIB 행 배치가 바뀌면 안 된다.
    let cell = try XCTUnwrap(UINib(nibName: "PNLTableViewCell", bundle: .main).instantiate(withOwner: nil).first as? PNLTableViewCell)
    // 날짜 푸터와 두 지표 행은 재사용 중 같은 계층에 남아야 한다.
    let dateRow = try XCTUnwrap(cell.transactionDateLabel.superview)
    // 날짜 행의 소유 행이 재사용 중 바뀌지 않는지 비교한다.
    let dateParent = try XCTUnwrap(dateRow.superview)
    // 기존 두 행의 객체와 순서가 유지돼야 한다.
    let rows = cell.metricsStackView.arrangedSubviews
    // 헤더·날짜만 한 줄 축소를 허용하고 본문 지표의 동적 글씨를 유지한다.
    let compactLabels: [UILabel] = [cell.marketNameLabel, cell.positionBadgeLabel, cell.statusLabel, cell.transactionDateLabel]
    // 셀 표면의 named color가 실제 trait 변경을 따라가는지 검사한다.
    let card = try XCTUnwrap(cell.cardView)
    // 창에 넣어 실제 라이트·다크 전환을 전달한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = UIViewController()
    window.rootViewController?.view.addSubview(cell)
    cell.frame = CGRect(x: 0, y: 0, width: 320, height: 1_000)
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    // 거래 계산을 바꾸지 않고 셀의 현물 표시 경로만 실행한다.
    let spot = UserPNLHistoryModel(
      marketName: "BTC/KRW",
      entryPrice: 100,
      exitPrice: 110,
      transactionTimestamp: 1_700_000_000_000,
      orderQuantity: 1,
      pnl: 10
    )
    // 선물 종료 셀과 현물 셀의 재사용 전이를 비교할 포지션이다.
    let position = try FuturesCalculator.open(domesticFuturesOrder())
    // 주문을 제출하지 않고 종료 표시 데이터만 만든다.
    let record = FuturesTransactionRecord(
      eventID: UUID(),
      positionID: position.id,
      kind: .closing,
      instrument: position.order.instrument,
      side: position.order.side,
      leverage: position.order.leverage,
      quantity: position.quantity,
      intervalStart: 120_000,
      intervalEndExclusive: nil,
      recordedAt: Date(timeIntervalSince1970: 120),
      price: 110_000_000,
      realizedPnL: 10
    )
    for style in [UIUserInterfaceStyle.light, .dark, .light] {
      window.overrideUserInterfaceStyle = style
      // 셀에 전달되는 테마와 XIB 동적 색상을 같은 시점에서 확인한다.
      if #available(iOS 17.0, *) { window.updateTraitsIfNeeded() }
      waitForNoticeUpdates(0.05)
      XCTAssertEqual(cell.traitCollection.userInterfaceStyle, style)
      for isFutures in [true, false, true] {
        if isFutures { cell.configure(record: record, position: position) }
        else { cell.configure(pnlHistory: spot) }
        // 배지·증거금 표시 여부에 맞는 자연 높이에서 재사용 결과를 비교한다.
        let fitting = cell.systemLayoutSizeFitting(
          CGSize(width: 320, height: UIView.layoutFittingCompressedSize.height),
          withHorizontalFittingPriority: .required,
          verticalFittingPriority: .fittingSizeLevel
        )
        cell.frame.size.height = ceil(fitting.height)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        XCTAssertTrue(cell.transactionDateLabel.superview === dateRow)
        XCTAssertTrue(dateRow.superview === dateParent)
        XCTAssertEqual(cell.metricsStackView.arrangedSubviews, rows)
        XCTAssertEqual(rows.count, 2)
        for label in compactLabels {
          XCTAssertEqual(label.numberOfLines, 1)
          XCTAssertTrue(label.adjustsFontSizeToFitWidth)
          XCTAssertFalse(label.adjustsFontForContentSizeCategory)
        }
        // 날짜와 공유 버튼은 현물·선물 재사용 모두 같은 행을 유지한다.
        let dateFrame = cell.transactionDateLabel.convert(cell.transactionDateLabel.bounds, to: cell.contentView)
        // 날짜와 같은 행에 놓인 공유 버튼의 셀 기준 영역이다.
        let shareFrame = cell.shareButton.convert(cell.shareButton.bounds, to: cell.contentView)
        XCTAssertEqual(dateFrame.midY, shareFrame.midY, accuracy: 1)
        XCTAssertLessThanOrEqual(dateFrame.maxX, shareFrame.minX)
        XCTAssertGreaterThanOrEqual(cell.shareButton.bounds.height, cell.shareButton.intrinsicContentSize.height)
        XCTAssertTrue(cell.pnlLabel.adjustsFontSizeToFitWidth)
        XCTAssertTrue(cell.roiLabel.adjustsFontSizeToFitWidth)
        XCTAssertEqual(cell.positionBadgeView.isHidden, !isFutures)
        XCTAssertEqual(cell.statusLabel.isHidden, !isFutures)
        XCTAssertEqual(cell.marginView.isHidden, !isFutures)
        if isFutures {
          // 재사용과 테마 전환 뒤에도 종목·배지·상태의 같은 행 정렬을 보존한다.
          let marketFrame = cell.marketNameLabel.convert(cell.marketNameLabel.bounds, to: cell.contentView)
          // 배지의 배경 영역까지 포함해 종목과 상태의 겹침을 검사한다.
          let badgeFrame = cell.positionBadgeView.convert(cell.positionBadgeView.bounds, to: cell.contentView)
          // 종료 상태가 별도 행으로 내려가지 않았는지 비교한다.
          let statusFrame = cell.statusLabel.convert(cell.statusLabel.bounds, to: cell.contentView)
          XCTAssertEqual(marketFrame.midY, badgeFrame.midY, accuracy: 1)
          XCTAssertEqual(marketFrame.midY, statusFrame.midY, accuracy: 1)
          XCTAssertLessThanOrEqual(marketFrame.maxX, badgeFrame.minX)
          XCTAssertLessThanOrEqual(badgeFrame.maxX, statusFrame.minX)
          XCTAssertEqual(cell.positionBadgeLabel.text, "\(FuturesText.side(record.side)) \(record.leverage)×")
          XCTAssertEqual(cell.statusLabel.text, FuturesText.text("futures_pnl_closed"))
          XCTAssertTrue(cell.marginLabel.text?.contains(FuturesText.number(try position.margin)) == true)
        } else {
          XCTAssertNil(cell.positionBadgeLabel.text)
          XCTAssertNil(cell.statusLabel.text)
          XCTAssertNil(cell.marginLabel.text)
        }
        XCTAssertEqual(card.backgroundColor?.resolvedColor(with: cell.traitCollection), UIColor.mobitColors(.backgroundPrimary).resolvedColor(with: cell.traitCollection))
        XCTAssertEqual(cell.contentView.backgroundColor?.resolvedColor(with: cell.traitCollection), UIColor.mobitColors(.investmentSurface).resolvedColor(with: cell.traitCollection))
      }
    }
  }

  @MainActor
  func testMarketCellXIBTransparencyPreservesTintAcrossThemesAndReuse() throws {
    // 사용자 설정은 테스트가 끝나면 원래 값으로 복구한다.
    let previousTint = UserDataManager.marketCellTintEnabled
    defer { UserDataManager.marketCellTintEnabled = previousTint }
    // 실제 XIB의 투명 스택을 사용하는 시세 셀이다.
    let cell = try XCTUnwrap(UINib(nibName: "MainCryptoTableViewCell", bundle: .main).instantiate(withOwner: nil).first as? MainCryptoTableViewCell)
    // 동적 색상 전환을 UIKit 창에서 전달한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = UIViewController()
    window.rootViewController?.view.addSubview(cell)
    cell.frame = CGRect(x: 0, y: 0, width: 320, height: 60)
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    for style in [UIUserInterfaceStyle.light, .dark, .light] {
      window.overrideUserInterfaceStyle = style
      // 셀에 전달되는 테마와 XIB 동적 색상을 같은 시점에서 확인한다.
      if #available(iOS 17.0, *) { window.updateTraitsIfNeeded() }
      waitForNoticeUpdates(0.05)
      XCTAssertEqual(cell.traitCollection.userInterfaceStyle, style)
      for enabled in [true, false] {
        UserDataManager.marketCellTintEnabled = enabled
        for rate in [-0.1, 0, 0.1] {
          // 상승·보합·하락을 같은 셀에 반복 적용해 이전 색상 잔류도 확인한다.
          let crypto = CryptoCellInfo(
            cryptoName: "Bitcoin",
            market: "BTC/KRW",
            tradePrice: 100,
            signedChangeRate: rate,
            change: rate > 0 ? "RISE" : rate < 0 ? "FALL" : "EVEN",
            accTradePrice24h: 1000
          )
          cell.configure(crypto: crypto, isScrolling: true)
          // XIB 스택이 불투명해지면 시세 배경 강조가 가려진다.
          for container in [cell.priceBox.superview, cell.cryptoName.superview].compactMap({ $0 }) {
            XCTAssertEqual(container.backgroundColor?.cgColor.alpha, 0)
          }
          // 기존 설정과 등락 방향에 해당하는 배경색을 유지한다.
          let expected: UIColor = !enabled ? .clear : rate == 0 ? .mobitColors(.surfacePrimary)
            : (rate > 0 ? MarketColorPalette.riseColor : MarketColorPalette.fallColor).withAlphaComponent(0.04)
          XCTAssertEqual(cell.contentView.backgroundColor?.resolvedColor(with: cell.traitCollection), expected.resolvedColor(with: cell.traitCollection))
        }
      }
    }
  }
}

extension FuturesAccountReactorTests {
  private func readyOrderCompletionState(
    _ reactor: FuturesAccountReactor,
    position: FuturesPosition? = nil
  ) throws -> FuturesAccountReactor.State {
    // 시세 유효기간과 포지션 검증 완료 시각을 같은 현재 시각에 맞춘다.
    let timestamp = try FuturesHistoryCheckState.milliseconds(Date())
    // 실제 거래를 저장하지 않고 화면의 주문 가능 조건만 준비한다.
    var state = reactor.reduce(
      state: reactor.initialState,
      mutation: .snapshot(
        .init(
          revision: 1,
          accounts: [.init(id: account, availableBalance: 1000)],
          positions: position.map { [$0] } ?? [],
          historyCheckStates: try position.map { [try .initial(for: $0)] } ?? []
        ),
        [:]
      )
    )
    state = reactor.reduce(
      state: state,
      mutation: .status(.finished(position.map {
        [.init(positionID: $0.id, verifiedThrough: timestamp, liquidated: false, hold: nil)]
      } ?? []))
    )
    return state
  }

  @MainActor
  func testFuturesOrderTopGapMatchesSpotCardAndClipsScrollingAcrossThemes() throws {
    for style in [UIUserInterfaceStyle.light, .dark] {
      for width: CGFloat in [320, 375] {
        // 같은 창 크기에서 현물 XIB 카드와 선물 첫 블록의 간격을 비교한다.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 667))
        window.overrideUserInterfaceStyle = style
        defer { window.isHidden = true; window.rootViewController = nil }
        // 기준 간격은 코드로 만든 숫자가 아니라 기존 현물 카드에서 읽는다.
        let spot = try makeSpotOrderLayoutController()
        window.rootViewController = spot
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        // 실제 세그먼트와 매수·매도 XIB가 연결된 주문 영역이다.
        let spotOrder = try XCTUnwrap(spot.orderView)
        for tab in [0, 1] {
          spotOrder.segmentedControl.selectedIndex = tab
          spotOrder.segmentedControl.onSegmentChanged?(tab)
          window.layoutIfNeeded()
          // 배경과 모서리가 그려지는 카드가 시각적인 주문 폼의 시작이다.
          let card = try XCTUnwrap(tab == 0 ? spotOrder.bidView?.contentContainerView : spotOrder.askView?.contentContainerView)
          XCTAssertEqual(
            card.convert(card.bounds, to: spotOrder).minY - spotOrder.segmentedControl.convert(spotOrder.segmentedControl.bounds, to: spotOrder).maxY,
            20,
            accuracy: 0.5
          )
        }
        // 현물과 동일한 XIB 컨테이너를 통해 선물 자식 화면을 배치한다.
        let futures = reactor()
        futures.stub.state.value = try readyOrderCompletionState(futures)
        // 상세 화면 전체를 사용해 안전영역 자동 보정까지 함께 확인한다.
        let host = try makeSpotOrderLayoutController()
        host.futuresReactor = futures
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        // 별도 부모 탐색 없이 UIKit 자식 화면으로 연결된 주문 컨트롤러다.
        let order = try XCTUnwrap(host.children.compactMap { $0 as? FuturesOrderViewController }.first)
        // 현물과 공유하는 상단 세그먼트다.
        let orderView = try XCTUnwrap(host.orderView)
        // 선물 화면에서 첫 번째로 보이는 테두리 블록이다.
        let market = try XCTUnwrap(descendants(order.view).first { $0.accessibilityIdentifier == "futuresMarketOrder" })
        // 주문 내용의 이동이 세그먼트 영역으로 새어 나오면 안 된다.
        let scroll = try XCTUnwrap(order.view.subviews.compactMap { $0 as? UIScrollView }.first)
        for tab in [0, 1] {
          orderView.segmentedControl.selectedIndex = tab
          orderView.segmentedControl.onSegmentChanged?(tab)
          scroll.setContentOffset(.zero, animated: false)
          window.layoutIfNeeded()
          XCTAssertEqual(scroll.contentInsetAdjustmentBehavior, .never)
          XCTAssertEqual(scroll.adjustedContentInset, .zero)
          XCTAssertEqual(
            market.convert(market.bounds, to: orderView).minY - orderView.segmentedControl.convert(orderView.segmentedControl.bounds, to: orderView).maxY,
            20,
            accuracy: 0.5
          )
          XCTAssertEqual(order.traitCollection.userInterfaceStyle, style)
          XCTAssertEqual(market.layer.borderColor, UIColor.mobitColors(.tradeSeparator).resolvedColor(with: order.traitCollection).cgColor)
          for offset: CGFloat in [-40, 60] {
            scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            XCTAssertTrue(scroll.clipsToBounds)
            XCTAssertEqual(
              scroll.convert(scroll.bounds, to: orderView).minY,
              orderView.segmentedControl.convert(orderView.segmentedControl.bounds, to: orderView).maxY,
              accuracy: 0.5
            )
          }
        }
        scroll.setContentOffset(.zero, animated: false)
        // 좁은 폭과 두 테마의 실제 간격을 결과 파일에서도 확인한다.
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) })
        attachment.name = "Futures-gap-\(Int(width))-\(style == .dark ? "dark" : "light")"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
    }
  }

  @MainActor
  func testFuturesOpeningCompletionEmitsOncePerOwnSubmissionAndPresentsErrorsInAlert() throws {
    // 이전 화면에서 남은 성공 상태를 재구독해도 완료 이벤트를 만들면 안 된다.
    let futures = reactor()
    // 포지션 없는 검증 완료 계좌에서 신규 진입만 검증한다.
    var state = try readyOrderCompletionState(futures)
    state.message = FuturesText.text("futures_order_done")
    futures.stub.state.value = state
    // 다른 화면과 공유하는 Reactor에서도 현재 화면 제출만 안내해야 한다.
    let instrument = domesticFuturesOrder().instrument
    // 시세와 탭 렌더링을 재현할 실제 주문 화면이다.
    let order = FuturesOrderViewController(reactor: futures, instrument: instrument)
    order.captureOrderPrice = {
      // 유효기간 만료가 완료 안내 검증에 간섭하지 않도록 매번 최신 시각을 사용한다.
      let timestamp = (try? FuturesHistoryCheckState.milliseconds(Date())) ?? 0
      return .init(quote: .init(instrument: instrument, price: 100, timestamp: timestamp), requestedAt: timestamp)
    }
    // 콜백 횟수로 중복 렌더와 별개인 실제 성공 이벤트를 센다.
    var completionCount = 0
    order.tradeCompletedCallBack = { completionCount += 1 }
    // 실패 결과도 실제 알럿으로 전달되는지 확인할 화면 소유 창이다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 667))
    window.rootViewController = order
    window.makeKeyAndVisible()
    defer { order.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil }
    order.selectTab(0)
    // 버튼 탭 경로를 통해 화면의 제출 소유권을 설정한다.
    let submit = try XCTUnwrap(descendants(order.view).first { $0.accessibilityIdentifier == "futuresSubmit" } as? UIButton)
    // 잘못된 입력 실패와 실제 주문 결과를 혼동하지 않는 유효 증거금이다.
    let amount = try XCTUnwrap(descendants(order.view).first { $0.accessibilityIdentifier == "futuresMargin" } as? UITextField)
    amount.text = "100"
    amount.sendActions(for: .editingChanged)
    XCTAssertEqual(completionCount, 0)
    XCTAssertFalse(descendants(order.view).compactMap { $0 as? UILabel }.contains { !$0.isHidden && $0.text == FuturesText.text("futures_order_done") })
    for completedCount in 1...2 {
      order.selectTab(0)
      submit.sendActions(for: .touchUpInside)
      XCTAssertTrue(futures.stub.actions.contains { if case .clearMessage = $0 { return true }; return false })
      XCTAssertEqual(futures.stub.actions.filter { if case .open = $0 { return true }; return false }.count, completedCount)
      // Reactor stub은 Action을 실행하지 않으므로 실제 execute 순서대로 상태를 전달한다.
      state.message = nil
      state.submitting = true
      futures.stub.state.value = state
      state.message = FuturesText.text("futures_order_done")
      futures.stub.state.value = state
      XCTAssertEqual(completionCount, completedCount - 1)
      state.submitting = false
      futures.stub.state.value = state
      XCTAssertEqual(completionCount, completedCount)
      for tab in [1, 2, 0] {
        state.quotes[instrument] = .init(instrument: instrument, price: Decimal(100 + tab), timestamp: Int64(1000 + tab))
        futures.stub.state.value = state
        order.selectTab(tab)
        XCTAssertEqual(completionCount, completedCount)
      }
      XCTAssertFalse(descendants(order.view).compactMap { $0 as? UILabel }.contains { !$0.isHidden && $0.text == FuturesText.text("futures_order_done") })
    }
    submit.sendActions(for: .touchUpInside)
    state.message = nil
    state.submitting = true
    futures.stub.state.value = state
    state.message = FuturesText.text("futures_retry_order")
    futures.stub.state.value = state
    state.submitting = false
    futures.stub.state.value = state
    XCTAssertEqual(completionCount, 2)
    waitForNoticeUpdates(0.35)
    XCTAssertEqual((order.presentedViewController as? UIAlertController)?.message, FuturesText.text("futures_retry_order"))
    XCTAssertFalse(descendants(order.view).compactMap { $0 as? UILabel }.contains { $0.text == FuturesText.text("futures_retry_order") })
    futures.stub.state.value = state
    XCTAssertEqual(completionCount, 2)
  }

  @MainActor
  func testFuturesCloseCompletionArrivesOnceAndAllowsReentryWithoutLeavingScreen() throws {
    // 전량 종료로 포지션이 사라져도 시트 완료 콜백은 한 번만 발생해야 한다.
    let futures = reactor()
    // 종료 시트에 표시하고 실제 입력 계산에 사용할 보유 포지션이다.
    let position = try FuturesCalculator.open(domesticFuturesOrder(margin: 100, price: 100))
    // 현재 검증 결과와 주문 가능 현금을 준비한다.
    var state = try readyOrderCompletionState(futures, position: position)
    futures.stub.state.value = state
    // 종료 시트의 콜백이 기존 주문 화면으로 전달되는 실제 경로다.
    let order = FuturesOrderViewController(reactor: futures, instrument: position.order.instrument)
    order.captureOrderPrice = {
      // 종료 계산에는 화면 시세와 같은 값 및 현재 요청 시각을 전달한다.
      let timestamp = (try? FuturesHistoryCheckState.milliseconds(Date())) ?? 0
      return .init(quote: .init(instrument: position.order.instrument, price: 105, timestamp: timestamp), requestedAt: timestamp)
    }
    // 실제 UIKit presentation 완료 시점으로 콜백 순서를 확인한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
    window.rootViewController = order
    window.makeKeyAndVisible()
    defer { order.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil }
    // 반복 상태 갱신에서도 콜백은 단 한 번이어야 한다.
    var completionCount = 0
    // 시트가 사라진 후에만 완료 안내를 표시할 수 있다.
    let completed = expectation(description: "Close completion after sheet dismissal")
    order.tradeCompletedCallBack = { [weak order] in
      completionCount += 1
      XCTAssertNil(order?.presentedViewController)
      completed.fulfill()
    }
    // 실제 포지션 카드 버튼으로 종료 시트를 연다.
    let openSheet = try XCTUnwrap(descendants(order.view).first { $0.accessibilityIdentifier == "futuresClose" } as? UIButton)
    openSheet.sendActions(for: .touchUpInside)
    waitForNoticeUpdates(0.6)
    // 콜백이 설정된 실제 종료 시트와 제출 버튼을 가져온다.
    let sheet = try XCTUnwrap(order.presentedViewController as? FuturesCloseViewController)
    // 기본 100% 선택을 그대로 제출한다.
    let submit = try XCTUnwrap(descendants(sheet.view).first { $0.accessibilityIdentifier == "futuresCloseSubmit" } as? UIButton)
    submit.sendActions(for: .touchUpInside)
    XCTAssertEqual(futures.stub.actions.filter { if case .closeQuantity = $0 { return true }; return false }.count, 1)
    state.message = nil
    state.submitting = true
    futures.stub.state.value = state
    state.snapshot = .init(revision: 2, accounts: [.init(id: account, availableBalance: 1150)])
    futures.stub.state.value = state
    state.message = FuturesText.text("futures_order_done")
    futures.stub.state.value = state
    XCTAssertEqual(completionCount, 0)
    XCTAssertTrue(order.presentedViewController === sheet)
    state.submitting = false
    futures.stub.state.value = state
    wait(for: [completed], timeout: 3)
    XCTAssertEqual(completionCount, 1)
    XCTAssertNil(sheet.presentingViewController)
    // 전량 종료 직후 화면과 탭을 유지해도 증거금과 레버리지를 다시 입력할 수 있어야 한다.
    let margin = try XCTUnwrap(descendants(order.view).first { $0.accessibilityIdentifier == "futuresMargin" } as? UITextField)
    // 새 포지션은 이전 포지션의 레버리지 잠금을 이어받지 않는다.
    let leverage = try XCTUnwrap(descendants(order.view).compactMap { $0 as? FuturesLeverageControl }.first)
    XCTAssertTrue(margin.isEnabled)
    XCTAssertTrue(leverage.isEnabled)
    XCTAssertTrue(openSheet.isHidden)
    // 주문 비율도 종료 전 잔액 대신 정산 후 가용 잔액을 사용한다.
    let all = try XCTUnwrap(descendants(order.view).first { $0.accessibilityIdentifier == "futuresOrderPercent100" } as? UIButton)
    all.sendActions(for: .touchUpInside)
    XCTAssertEqual(margin.text, "1,150")
    margin.text = "100"
    margin.sendActions(for: .editingChanged)
    for _ in 0..<3 { futures.stub.state.value = state }
    waitForNoticeUpdates(0.1)
    XCTAssertEqual(completionCount, 1)
    // 과거 포지션의 추가 진입 ID가 신규 주문에 남지 않아야 한다.
    let open = try XCTUnwrap(descendants(order.view).first { $0.accessibilityIdentifier == "futuresSubmit" } as? UIButton)
    open.sendActions(for: .touchUpInside)
    // 이 화면에서 다시 누른 신규 진입 Action만 검사한다.
    let opening = try XCTUnwrap(futures.stub.actions.last { if case .open = $0 { return true }; return false })
    if case let .open(_, _, amount, _, positionID, _) = opening {
      XCTAssertEqual(amount, 100)
      XCTAssertNil(positionID)
    } else {
      XCTFail("Expected a new position opening")
    }
  }

  @MainActor
  func testTradeCompletionToastUsesFullHostAboveBannerAndClearsOnExit() throws {
    for style in [UIUserInterfaceStyle.light, .dark] {
      // 성공 안내를 좁은 오른쪽 폼이 아닌 실제 상세 화면에 연결한다.
      let futures = reactor()
      futures.stub.state.value = try readyOrderCompletionState(futures)
      // 광고 영역과 주문 자식 컨트롤러가 함께 있는 실제 XIB 화면이다.
      let host = try makeSpotOrderLayoutController()
      host.futuresReactor = futures
      // 가장 좁은 폭에서도 전체 화면 기준 하단 여백을 검증한다.
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 667))
      window.overrideUserInterfaceStyle = style
      window.rootViewController = host
      window.makeKeyAndVisible()
      defer { window.isHidden = true; window.rootViewController = nil }
      window.layoutIfNeeded()
      // 상위 화면에서 연결한 완료 콜백을 그대로 실행한다.
      let order = try XCTUnwrap(host.children.compactMap { $0 as? FuturesOrderViewController }.first)
      order.tradeCompletedCallBack?()
      waitForNoticeUpdates(0.25)
      window.layoutIfNeeded()
      // 호가·주문 양쪽을 포함하는 호스트의 직계 안내 뷰다.
      let toast = try XCTUnwrap(host.view.subviews.first { $0.accessibilityIdentifier == "mobitToast" })
      // 사용자가 보는 문구는 기존 주문 완료 번역을 그대로 사용한다.
      let message = try XCTUnwrap(descendants(toast).first { $0.accessibilityIdentifier == "mobitToastMessage" } as? UILabel)
      XCTAssertEqual(message.text, FuturesText.text("futures_order_done"))
      XCTAssertEqual(toast.traitCollection.userInterfaceStyle, style)
      XCTAssertEqual(toast.frame.midX, host.view.bounds.midX, accuracy: 0.5)
      XCTAssertGreaterThanOrEqual(toast.frame.minX, 19.5)
      XCTAssertLessThanOrEqual(toast.frame.maxX, host.view.bounds.maxX - 19.5)
      XCTAssertLessThanOrEqual(toast.frame.maxY, host.bannerContainerView.frame.minY - 19.5)
      XCTAssertFalse(toast.isDescendant(of: order.view))
      XCTAssertEqual(descendants(host.view).filter { $0.accessibilityIdentifier == "mobitToast" }.count, 1)
      // 두 테마의 광고 위 표시 결과를 테스트 첨부로 남긴다.
      let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) })
      attachment.name = "Trade-completion-toast-320-\(style == .dark ? "dark" : "light")"
      attachment.lifetime = .keepAlways
      add(attachment)
      host.viewWillDisappear(false)
      XCTAssertNil(toast.superview)
      window.rootViewController = UIViewController()
      order.tradeCompletedCallBack?()
      waitForNoticeUpdates(0.1)
      XCTAssertFalse(descendants(host.view).contains { $0.accessibilityIdentifier == "mobitToast" })
    }
  }
}

private final class SpotRecoveryOrderBookFixture: OrderBookSocketServiceProtocol {
  // 주문 재시도 중 외부 호가 소켓은 생성하지 않는다.
  var isConnected = false
  // 외부 호가 수신 없이 주문 폼의 결제 시세 흐름만 검증한다.
  var stream: Observable<Orderbook> { .empty() }
  func connect() { isConnected = true }
  func disconnect(userInitiated: Bool) { isConnected = false }
  func reconnectIfNeeded() { connect() }
  func subscribe(market: String) {}
}

extension FuturesAccountReactorTests {
  private func futuresHistoryLayoutSnapshot() throws -> FuturesAccountSnapshot {
    // 추가 진입의 체결 수량과 최초 진입을 각각 표시할 롱 포지션이다.
    let firstLongPosition = try FuturesCalculator.open(domesticFuturesOrder())
    // 증거금과 체결금액을 혼동하지 않도록 다른 수량의 추가 진입을 만든다.
    let longPosition = try FuturesCalculator.adding(
      domesticFuturesOrder(margin: 200_000, date: Date(timeIntervalSince1970: 120)),
      to: firstLongPosition
    )
    // 롱 종료에는 양수 실현 손익을 표시한다.
    let longCloseQuote = try FuturesCalculator.closingQuote(
      longPosition,
      executionPrice: 110_000_000,
      exitFeeRate: 0
    )
    // 숏 진입은 매도, 숏 종료는 매수로 표시할 포지션이다.
    let shortPosition = try FuturesCalculator.open(
      domesticFuturesOrder(side: .short, date: Date(timeIntervalSince1970: 240))
    )
    // 수익과 별개로 음수 실현 손익의 부호도 확인한다.
    let shortCloseQuote = try FuturesCalculator.closingQuote(
      shortPosition,
      executionPrice: 105_000_000,
      exitFeeRate: 0
    )
    // 청산의 발생 분과 저장 시각을 구분할 별도 롱 포지션이다.
    let liquidatedPosition = try FuturesCalculator.open(
      domesticFuturesOrder(date: Date(timeIntervalSince1970: 360))
    )
    // 추가 진입 이후 검증 경계를 포함한 정상 롱 내역을 만든다.
    var longHistoryCheck = try FuturesHistoryCheckState.initial(for: longPosition)
    longHistoryCheck.verifiedThrough = 180_000
    longHistoryCheck.lastVerifiedMark = 110_000_000
    // 숏 종료 전 시세 검증도 정상 완료 상태로 둔다.
    var shortHistoryCheck = try FuturesHistoryCheckState.initial(for: shortPosition)
    shortHistoryCheck.verifiedThrough = 300_000
    shortHistoryCheck.lastVerifiedMark = 105_000_000
    // 청산 구간은 7분이며 정산은 10분에 저장된 상황이다.
    var liquidationHistoryCheck = try FuturesHistoryCheckState.initial(for: liquidatedPosition)
    liquidationHistoryCheck.verifiedThrough = 480_000
    liquidationHistoryCheck.lastVerifiedMark = 80_000_000
    liquidationHistoryCheck.liquidation = .init(
      intervalStart: 420_000,
      intervalEndExclusive: 480_000,
      observedLiquidationPrice: 80_000_000,
      settledAt: Date(timeIntervalSince1970: 600)
    )
    return FuturesAccountSnapshot(
      revision: 1,
      accounts: [.init(id: account, availableBalance: 10_150_000)],
      positions: [longPosition, shortPosition, liquidatedPosition],
      historyCheckStates: [longHistoryCheck, shortHistoryCheck, liquidationHistoryCheck],
      closedPositions: [
        .init(
          order: .init(
            requestID: UUID(),
            positionID: longPosition.id,
            executionPrice: 110_000_000,
            executedAt: Date(timeIntervalSince1970: 180)
          ),
          returnedMargin: longCloseQuote.returnedMargin,
          realizedPnL: longCloseQuote.realizedPnL,
          settledAt: Date(timeIntervalSince1970: 185)
        ),
        .init(
          order: .init(
            requestID: UUID(),
            positionID: shortPosition.id,
            executionPrice: 105_000_000,
            executedAt: Date(timeIntervalSince1970: 300)
          ),
          returnedMargin: shortCloseQuote.returnedMargin,
          realizedPnL: shortCloseQuote.realizedPnL,
          settledAt: Date(timeIntervalSince1970: 305)
        )
      ]
    )
  }

  @MainActor
  func testFuturesEmptyHistoryStaysCenteredAcrossTabsAndHistoryUpdates() throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Trait overrides require iOS 17") }
    for width: CGFloat in [320, 393] {
      for style in [UIUserInterfaceStyle.light, .dark] {
        // 실제 저장소 대신 빈 계좌와 체결 이력을 번갈아 전달한다.
        let futures = reactor()
        // 거래내역이 없는 정상 조회 상태다.
        let emptyState = try readyOrderCompletionState(futures)
        futures.stub.state.value = emptyState
        // TradeVC의 호가·세그먼트·선물 자식 화면을 함께 검사한다.
        let host = try makeSpotOrderLayoutController()
        host.futuresReactor = futures
        // 화면마다 달라지는 실제 내역 표시 영역을 제공한다.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: width == 320 ? 568 : 852))
        window.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        // 실제 탭 액션과 표시 영역을 소유하는 주문 화면이다.
        let orderView = try XCTUnwrap(host.orderView)
        // 선물 주문은 기존 현물 컨테이너 안의 자식 화면이다.
        let order = try XCTUnwrap(host.children.compactMap { $0 as? FuturesOrderViewController }.first)
        // 키보드 가이드를 반영한 현재 가용 영역이다.
        let scroll = try XCTUnwrap(order.view.subviews.compactMap { $0 as? UIScrollView }.first)
        for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge, .large] {
          host.traitOverrides.preferredContentSizeCategory = category
          host.updateTraitsIfNeeded()
          order.updateTraitsIfNeeded()
          for tab in [2, 0, 2, 1, 2] {
            orderView.segmentedControl.selectedIndex = tab
            orderView.segmentedControl.onSegmentChanged?(tab)
            window.layoutIfNeeded()
            guard tab == 2 else { continue }
            // 문구 존재뿐 아니라 사용자가 보는 스크롤 좌표의 중앙을 확인한다.
            let label = try XCTUnwrap(descendants(order.view).compactMap { $0 as? UILabel }.first {
              $0.text == FuturesText.text("futures_empty_history")
            })
            // 현물의 빈 영역도 위 10pt·아래 0pt로 중심이 표시 영역보다 5pt 낮다.
            let frame = label.convert(label.bounds, to: scroll)
            XCTAssertEqual(label.textAlignment, .center)
            XCTAssertEqual(frame.midX, scroll.bounds.midX, accuracy: 0.5)
            XCTAssertEqual(frame.midY, scroll.bounds.midY + 5, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(label.bounds.height + 0.5, label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height)
            XCTAssertFalse(label.hasAmbiguousLayout)
            XCTAssertFalse(try XCTUnwrap(label.superview).hasAmbiguousLayout)
          }
          // 긴 내역의 마지막까지 스크롤한 뒤 빈 계좌로 돌아오는 상황이다.
          var populatedState = emptyState
          populatedState.snapshot = try futuresHistoryLayoutSnapshot()
          futures.stub.state.value = populatedState
          order.selectTab(2)
          window.layoutIfNeeded()
          XCTAssertTrue(descendants(order.view).contains {
            $0.accessibilityIdentifier?.hasPrefix("futuresHistoryEntry.") == true
          })
          scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)), animated: false)
          futures.stub.state.value = emptyState
          order.selectTab(2)
          window.layoutIfNeeded()
          // 이전 목록의 스크롤 위치가 빈 문구를 화면 밖으로 밀어내면 안 된다.
          let restoredLabel = try XCTUnwrap(descendants(order.view).compactMap { $0 as? UILabel }.first {
            $0.text == FuturesText.text("futures_empty_history")
          })
          // 데이터가 바뀐 뒤에도 현재 표시 영역을 기준으로 배치한다.
          let restoredFrame = restoredLabel.convert(restoredLabel.bounds, to: scroll)
          XCTAssertEqual(restoredFrame.midY, scroll.bounds.midY + 5, accuracy: 0.5)
          XCTAssertEqual(scroll.contentSize.width, scroll.bounds.width, accuracy: 0.5)
          // 두 테마와 글자 크기별 실제 분할 화면을 남긴다.
          let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) })
          attachment.name = "Futures-empty-history-\(Int(width))-\(style.rawValue)-\(category.rawValue)"
          attachment.lifetime = .keepAlways
          add(attachment)
        }
      }
    }
  }

  @MainActor
  func testSpotEmptyHistoryMessageFitsLongTextWithinItsPanel() throws {
    // 빈 내역 fixture가 실제 거래 이력 저장값에 남지 않도록 보존한다.
    let previousTransactions = UserDefaults.standard.object(forKey: UserDataManager.Keys.userTransactionList)
    // 현물 상세 fixture의 거래소와 조회 대상 계좌를 일치시킨다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    ExchangeSelectionStore.currentExchange = .upbit
    UserDataManager.userTransactionList = []
    defer {
      UserDefaults.standard.set(previousTransactions, forKey: UserDataManager.Keys.userTransactionList)
      ExchangeSelectionStore.currentExchange = previousExchange
    }
    // 호가 150pt를 제외한 실제 오른쪽 패널에서 줄바꿈을 확인한다.
    for width: CGFloat in [320, 393] {
      // 외부 시세 요청 없이 기존 TradeVC와 XIB를 그대로 표시한다.
      let host = try makeSpotOrderLayoutController()
      // 실제 부모와 Safe Area가 존재하는 표시 환경이다.
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: width == 320 ? 568 : 852))
      window.rootViewController = host
      window.makeKeyAndVisible()
      defer { window.isHidden = true; window.rootViewController = nil }
      // 실제 매수·거래내역 탭 콜백을 통해 빈 상태를 표시한다.
      let order = try XCTUnwrap(host.orderView)
      // 현물의 빈 상태는 전체 주문 화면이 아니라 거래내역 영역에 정렬된다.
      let history = try XCTUnwrap(order.historyView)
      order.segmentedControl.selectedIndex = 2
      order.segmentedControl.onSegmentChanged?(2)
      window.layoutIfNeeded()
      // 기존 XIB에서 이미 중앙에 배치하는 안내 라벨이다.
      let label = try XCTUnwrap(history.noHistoryView.subviews.compactMap { $0 as? UILabel }.first)
      // 언어별 문구가 길어져도 패널 바깥으로 넘치지 않아야 한다.
      for text in [label.text ?? "", "Transaction history is empty for this market. Completed trades will appear here."] {
        label.text = text
        label.setNeedsLayout()
        history.setNeedsLayout()
        window.layoutIfNeeded()
        history.layoutIfNeeded()
        XCTAssertFalse(history.noHistoryView.isHidden)
        XCTAssertEqual(label.textAlignment, .center)
        XCTAssertGreaterThanOrEqual(label.frame.minX, 0)
        XCTAssertLessThanOrEqual(label.frame.maxX, history.noHistoryView.bounds.width)
        XCTAssertEqual(label.center.x, history.noHistoryView.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(label.center.y, history.noHistoryView.bounds.midY, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(label.bounds.height + 0.5, label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height)
        XCTAssertFalse(label.hasAmbiguousLayout)
      }
      // 좁은 주문 패널에서 긴 문구의 실제 줄바꿈과 중앙 위치도 검토한다.
      let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) })
      attachment.name = "Spot-empty-history-long-message-\(Int(width))"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }

  @MainActor
  func testFuturesHistoryCardsPreserveExecutionDataAcrossNarrowScreensThemesAndLargeText() throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Trait overrides require iOS 17") }
    // 실제 내역 변환을 통과한 진입·추가 진입·종료·청산 자료다.
    let snapshot = try futuresHistoryLayoutSnapshot()
    // 현재 상세 화면은 동일 계좌의 BTC 내역만 표시한다.
    let instrument = try XCTUnwrap(snapshot.positions.first?.order.instrument)
    // 화면이 기존 거래 내역의 최신순을 그대로 유지해야 한다.
    let records = Array(try snapshot.transactionHistory(for: account).filter { $0.instrument == instrument }.reversed())
    XCTAssertEqual(records.count, 7)
    XCTAssertEqual(Set(records.map { $0.kind.rawValue }), Set(["opening", "addition", "closing", "liquidation"]))
    XCTAssertTrue(records.contains { ($0.realizedPnL ?? 0) > 0 })
    XCTAssertTrue(records.contains { ($0.realizedPnL ?? 0) < 0 })
    func historyLabel(_ identifier: String, in entry: UIView) throws -> UILabel {
      try XCTUnwrap(descendants(entry).first { $0.accessibilityIdentifier == "futuresHistory.\(identifier)" } as? UILabel)
    }
    // 320pt에서는 150pt 호가를 제외한 실제 주문 패널이 170pt가 된다.
    for width: CGFloat in [320, 393] {
      // 밝은 카드와 어두운 카드에서 같은 내용과 크기 흐름을 확인한다.
      for style in [UIUserInterfaceStyle.light, .dark] {
        // 저장소나 소켓을 호출하지 않고 정상 스냅샷을 전달한다.
        let futures = reactor()
        // 화면 렌더링에 필요한 내역과 정상 조회 상태만 준비한다.
        var state = futures.reduce(state: futures.initialState, mutation: .snapshot(snapshot, [:]))
        state.status = .finished([])
        futures.stub.state.value = state
        // 실제 XIB의 호가와 오른쪽 주문 컨테이너를 함께 사용한다.
        let host = try makeSpotOrderLayoutController()
        host.futuresReactor = futures
        // 키보드 가이드와 스크롤의 실제 높이를 계산할 작은 화면이다.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: width == 320 ? 568 : 852))
        window.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        // 상단 거래내역 탭의 실제 연결 액션을 실행한다.
        let orderView = try XCTUnwrap(host.orderView)
        // 별도 화면 복제 없이 실제 오른쪽 자식 화면을 검사한다.
        let order = try XCTUnwrap(host.children.compactMap { $0 as? FuturesOrderViewController }.first)
        orderView.segmentedControl.selectedIndex = 2
        orderView.segmentedControl.onSegmentChanged?(2)
        // 기본 글씨와 최대 접근성 글씨를 같은 내역에서 확인한다.
        for large in [false, true] {
          host.traitOverrides.preferredContentSizeCategory = large ? .accessibilityExtraExtraExtraLarge : .large
          host.updateTraitsIfNeeded()
          order.updateTraitsIfNeeded()
          window.layoutIfNeeded()
          host.view.layoutIfNeeded()
          order.view.layoutIfNeeded()
          // 주문과 거래내역이 공유하는 기존 내부 스크롤이다.
          let scroll = try XCTUnwrap(order.view.subviews.compactMap { $0 as? UIScrollView }.first)
          // 새 디자인이 실제 기록을 생략하거나 순서를 바꾸지 않아야 한다.
          let entries = descendants(order.view).filter { $0.accessibilityIdentifier?.hasPrefix("futuresHistoryEntry.") == true }
          XCTAssertEqual(order.view.bounds.width, width - 150, accuracy: 1)
          XCTAssertEqual(scroll.contentSize.width, scroll.bounds.width, accuracy: 1)
          XCTAssertGreaterThan(scroll.bounds.height, 0)
          XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
          XCTAssertEqual(entries.compactMap(\.accessibilityIdentifier), records.map { "futuresHistoryEntry.\($0.id)" })
          // 표시 항목을 같은 위치의 원본 체결 기록과 대조한다.
          for (entry, record) in zip(entries, records) {
            // 추가 진입도 같은 진입 제목을 쓰고 청산은 수동 종료와 구분한다.
            let headerKey: String
            switch record.kind {
            case .opening, .addition: headerKey = "futures_history_open"
            case .closing: headerKey = "futures_history_close"
            case .liquidation: headerKey = "futures_history_liquidation"
            }
            // 증거금 대신 실제 체결 가격과 수량으로 거래금액을 계산한다.
            let tradeAmount = try FuturesDecimal.multiply(record.price, record.quantity)
            // 종료·청산은 체결금액 대신 실현 손익을 표시한다.
            let amount = record.realizedPnL ?? tradeAmount
            // 양수 실현 손익의 더하기 부호도 보존한다.
            let amountPrefix = (record.realizedPnL ?? 0) > 0 ? "+" : ""
            // 숫자와 통화·코인 단위를 각 원본 값의 정밀도로 표시한다.
            let expectedTexts = [
              "orderType": String(format: FuturesText.text(headerKey), FuturesText.side(record.side)),
              "date": FuturesText.occurrenceDate(record),
              "price": "\(FuturesText.number(record.price)) KRW",
              "quantity": "\(FuturesText.number(record.quantity)) BTC",
              "amount": "\(amountPrefix)\(FuturesText.number(amount)) KRW"
            ]
            // 원본과 다른 문구가 남지 않도록 모든 핵심 값을 확인한다.
            for (identifier, expected) in expectedTexts {
              XCTAssertEqual(try historyLabel(identifier, in: entry).text, expected, record.id)
            }
            // 방향 문구와 동작 문구에 실제 적용된 개별 글자 색을 확인한다.
            let attributedTitle = try XCTUnwrap(try historyLabel("orderType", in: entry).attributedText)
            // 번역된 롱·숏 부분의 UTF-16 범위만 방향 색을 사용한다.
            let sideRange = (attributedTitle.string as NSString).range(of: FuturesText.side(record.side))
            XCTAssertNotEqual(sideRange.location, NSNotFound)
            // 공백과 진입·종료·청산을 포함해 나머지 글자는 기본 색을 유지한다.
            for offset in 0..<attributedTitle.length {
              // 현재 글자가 방향 문구에 속하는지에 따라 기대 색을 구분한다.
              let expectedColor: UIColor = NSLocationInRange(offset, sideRange)
                ? (record.side == .long ? MarketColorPalette.riseColor : MarketColorPalette.fallColor)
                : .mobitColors(.tradeTextPrimary)
              // attributedText는 기본 색도 모든 글자에 명시해야 한다.
              let actualColor = attributedTitle.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? UIColor
              XCTAssertEqual(
                actualColor?.resolvedColor(with: entry.traitCollection),
                expectedColor.resolvedColor(with: entry.traitCollection),
                record.id
              )
            }
            // 포지션 항목은 제목에 표시한 체결 종류를 반복하지 않는다.
            let positionLabel = try historyLabel("position", in: entry)
            XCTAssertEqual(positionLabel.text, "\(FuturesText.side(record.side)) · \(record.leverage)×")
            if let amountTitle = descendants(entry).first(where: { $0.accessibilityIdentifier == "futuresHistory.amountTitle" }) as? UILabel {
              XCTAssertEqual(amountTitle.text, FuturesText.text(record.realizedPnL == nil ? "futures_history_amount" : "futures_realized"))
            }
            if record.kind == .liquidation {
              // 정산 시각이 아닌 실제 발생 분만 청산 날짜로 표시한다.
              let occurredMinute = try XCTUnwrap(record.occurredMinute)
              // 기존 날짜 포맷에서 초를 제외한 발생 시각이다.
              let occurrence = Date(timeIntervalSince1970: Double(occurredMinute) / 1000)
              XCTAssertEqual(try historyLabel("date", in: entry).text, String(FuturesText.date(occurrence).dropLast(3)))
              XCTAssertNotEqual(try historyLabel("date", in: entry).text, FuturesText.date(record.recordedAt))
            }
            XCTAssertFalse(entry.hasAmbiguousLayout)
            XCTAssertGreaterThan(entry.bounds.height, 0)
            // 스크롤하더라도 항목 자체가 오른쪽 패널 밖으로 나가면 안 된다.
            let entryFrame = entry.convert(entry.bounds, to: order.view)
            XCTAssertGreaterThanOrEqual(entryFrame.minX, -1)
            XCTAssertLessThanOrEqual(entryFrame.maxX, order.view.bounds.width + 1)
            // 작은 카드에서도 제목·숫자·단위가 잘리지 않아야 한다.
            for label in descendants(entry).compactMap({ $0 as? UILabel }).filter({ !$0.isHidden && !($0.text ?? "").isEmpty }) {
              XCTAssertFalse(label.hasAmbiguousLayout, label.text ?? "")
              XCTAssertGreaterThan(label.bounds.width, 0, label.text ?? "")
              XCTAssertGreaterThanOrEqual(
                label.bounds.height + 1,
                label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height,
                label.text ?? ""
              )
              if label.numberOfLines == 1 {
                XCTAssertGreaterThanOrEqual(
                  label.bounds.width + 1,
                  label.intrinsicContentSize.width * (label.adjustsFontSizeToFitWidth ? label.minimumScaleFactor : 1),
                  label.text ?? ""
                )
              }
              // 카드 내부의 실제 좌표로 잘린 텍스트를 확인한다.
              let labelFrame = label.convert(label.bounds, to: entry)
              XCTAssertGreaterThanOrEqual(labelFrame.minX, -1)
              XCTAssertGreaterThanOrEqual(labelFrame.minY, -1)
              XCTAssertLessThanOrEqual(labelFrame.maxX, entry.bounds.width + 1)
              XCTAssertLessThanOrEqual(labelFrame.maxY, entry.bounds.height + 1)
            }
          }
          // 긴 내역의 첫 항목과 마지막 항목을 실제 분할 화면에서 남긴다.
          for bottom in [false, true] {
            scroll.setContentOffset(CGPoint(x: 0, y: bottom ? max(0, scroll.contentSize.height - scroll.bounds.height) : 0), animated: false)
            // 호가와 주문 탭을 포함한 상위 화면으로 범위 외 변경도 확인한다.
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) })
            attachment.name = "Futures-history-\(Int(width))-\(style == .dark ? "dark" : "light")-\(large ? "large" : "normal")-\(bottom ? "bottom" : "top")"
            attachment.lifetime = .keepAlways
            add(attachment)
          }
        }
      }
    }
  }
}

extension FuturesAccountReactorTests {
  @MainActor
  func testSpotHistoryCellSelfSizesAndPreservesCurrencyAndLegacyTextAcrossReuse() throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Trait overrides require iOS 17") }
    // 원화 거래는 기존 단위 생략과 숫자 정밀도를 유지한다.
    let krwTransaction = TransactionInfo(
      marketName: "BTC/KRW",
      orderType: .bid,
      executedDate: "10.15 12:34:56",
      executedPrice: 123_456_789.9,
      executedQuantity: 0.01234567,
      executedAmount: 1_234_567.89
    )
    // 긴 소수와 BTC 단위도 좁은 값 영역에서 생략하지 않는다.
    let btcTransaction = TransactionInfo(
      marketName: "ETH/BTC",
      orderType: .ask,
      executedDate: "10.15 12:35:56",
      executedPrice: 0.00012345,
      executedQuantity: 123_456_789,
      executedAmount: 0.12345678
    )
    // 시스템 정산의 원화 금액과 별도 교환손익 문구를 보존한다.
    var legacyTransaction = TransactionInfo(
      marketName: "ETH/BTC",
      orderType: .ask,
      executedDate: "10.15 12:36:56",
      executedPrice: 0.00003,
      executedQuantity: 20_000_000_000,
      executedAmount: 600_000,
      recordType: .legacyBTCSettlement
    )
    legacyTransaction.settlementProfitLossKRW = 1_234
    // 정산 다음에 일반 거래를 다시 표시해 이전 여러 줄 문구의 잔류도 확인한다.
    let records: [(transaction: TransactionInfo, price: String, quantity: String, amount: String)] = [
      (krwTransaction, "123,456,789", "0.01234567", "1,234,567"),
      (btcTransaction, "0.00012345 BTC", "123,456,789", "0.12345678 BTC"),
      (legacyTransaction, "0.00003 BTC", "20,000,000,000", "600,000 \(FuturesText.text("currency_krw_unit"))\nBTC 교환손익 +1,234원"),
      (btcTransaction, "0.00012345 BTC", "123,456,789", "0.12345678 BTC"),
      (krwTransaction, "123,456,789", "0.01234567", "1,234,567")
    ]
    // 실제 분할 패널에서 거래내역이 차지하는 좁은 폭을 사용한다.
    for width: CGFloat in [150, 223] {
      // 테마를 바꾸어도 폰트와 저장된 거래 문구는 동일하게 유지한다.
      for style in [UIUserInterfaceStyle.light, .dark] {
        // 기존 XIB와 IBOutlet의 배치를 그대로 검증한다.
        let cell = try XCTUnwrap(
          UINib(nibName: "TradeHistoryTableViewCell", bundle: .main)
            .instantiate(withOwner: nil).first as? TradeHistoryTableViewCell
        )
        // 전역 거래내역을 바꾸지 않고 셀의 UIKit 글자 크기 환경만 만든다.
        let host = UIViewController()
        // 큰 글씨의 셀 높이는 화면 밖으로 늘어날 수 있는 실제 창에서 계산한다.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.overrideUserInterfaceStyle = style
        window.rootViewController = host
        host.view.addSubview(cell)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        // 접근성 글씨가 실제로 셀 높이를 늘렸는지 같은 기록과 비교한다.
        var normalHeights: [Int: CGFloat] = [:]
        // 숫자 상수를 복제하지 않고 실제 각 라벨의 글자 확대를 확인한다.
        var normalFontSizes: [ObjectIdentifier: CGFloat] = [:]
        // 기본 상태와 최대 글씨를 같은 셀에서 전환해 재사용 흐름을 검사한다.
        for large in [false, true] {
          host.traitOverrides.preferredContentSizeCategory = large ? .accessibilityExtraExtraExtraLarge : .large
          host.updateTraitsIfNeeded()
          window.layoutIfNeeded()
          // 거래 통화와 시스템 정산을 바꿔도 원본 문구를 유지해야 한다.
          for (index, record) in records.enumerated() {
            cell.configure(marketName: record.transaction.marketName, transactionInfo: record.transaction)
            cell.frame = CGRect(x: 0, y: 0, width: width, height: 2_000)
            cell.setNeedsLayout()
            cell.layoutIfNeeded()
            // 현재 폭에서 모든 내용을 담는 자체 높이를 실제 제약으로 계산한다.
            let fittedHeight = cell.contentView.systemLayoutSizeFitting(
              CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
              withHorizontalFittingPriority: .required,
              verticalFittingPriority: .fittingSizeLevel
            ).height
            XCTAssertGreaterThan(fittedHeight, 0)
            cell.frame.size.height = ceil(fittedHeight)
            cell.setNeedsLayout()
            cell.layoutIfNeeded()
            XCTAssertEqual(cell.contentView.bounds.height, ceil(fittedHeight), accuracy: 1)
            XCTAssertFalse(cell.contentView.hasAmbiguousLayout)
            XCTAssertEqual(cell.marketName.text, record.transaction.marketName)
            XCTAssertEqual(cell.tradeDate.text, record.transaction.executedDate)
            XCTAssertEqual(cell.orderTypeLabel.text, record.transaction.recordType == .legacyBTCSettlement ? "시스템 정산" : record.transaction.orderType == .ask ? "매도" : "매수")
            XCTAssertEqual(cell.tradeCryptoPrice.text, record.price)
            XCTAssertEqual(cell.tradeAmount.text, record.quantity)
            XCTAssertEqual(cell.tradeTotalPrice.text, record.amount)
            if large {
              XCTAssertGreaterThan(fittedHeight, try XCTUnwrap(normalHeights[index]))
            } else {
              normalHeights[index] = fittedHeight
            }
            // 값 라벨과 함께 왼쪽 항목 제목도 같은 가변 높이 행에 남아야 한다.
            for value in [cell.marketName, cell.tradeCryptoPrice, cell.tradeAmount, cell.tradeTotalPrice].compactMap({ $0 }) {
              // XIB에 있는 실제 항목명·값 행이다.
              let row = try XCTUnwrap(value.superview as? UIStackView)
              // 재사용한 셀에서도 항목 제목이 사라지거나 다른 계층으로 이동하지 않는다.
              let title = try XCTUnwrap(row.arrangedSubviews.compactMap { $0 as? UILabel }.first { $0 !== value })
              XCTAssertGreaterThan(title.bounds.width, 0)
              XCTAssertGreaterThan(title.bounds.height, 0)
              XCTAssertFalse(row.hasAmbiguousLayout)
            }
            // 모든 보이는 문구의 크기와 경계를 검사해 실제 잘림을 검출한다.
            for label in descendants(cell.contentView).compactMap({ $0 as? UILabel }).filter({ !$0.isHidden && !($0.text ?? "").isEmpty }) {
              XCTAssertFalse(label.hasAmbiguousLayout, label.text ?? "")
              XCTAssertGreaterThan(label.bounds.width, 0, label.text ?? "")
              XCTAssertTrue(label.adjustsFontForContentSizeCategory, label.text ?? "")
              XCTAssertGreaterThanOrEqual(
                label.bounds.height + 1,
                label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height,
                label.text ?? ""
              )
              if label.numberOfLines == 1 {
                XCTAssertGreaterThanOrEqual(
                  label.bounds.width + 1,
                  label.intrinsicContentSize.width * (label.adjustsFontSizeToFitWidth ? label.minimumScaleFactor : 1),
                  label.text ?? ""
                )
              }
              if large {
                XCTAssertGreaterThan(label.font.pointSize, try XCTUnwrap(normalFontSizes[ObjectIdentifier(label)]), label.text ?? "")
              } else {
                normalFontSizes[ObjectIdentifier(label)] = label.font.pointSize
              }
              // 화면 밖의 긴 셀도 셀 자체의 콘텐츠 영역에서 빠져나가지 않는다.
              let labelFrame = label.convert(label.bounds, to: cell.contentView)
              XCTAssertGreaterThanOrEqual(labelFrame.minX, -1)
              XCTAssertGreaterThanOrEqual(labelFrame.minY, -1)
              XCTAssertLessThanOrEqual(labelFrame.maxX, cell.contentView.bounds.width + 1)
              XCTAssertLessThanOrEqual(labelFrame.maxY, cell.contentView.bounds.height + 1)
            }
            if (!large && index == 0) || (large && index == 2) {
              // 기본 거래와 긴 정산 문구를 두 테마에서 육안으로도 비교한다.
              let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: cell.bounds).image { cell.layer.render(in: $0.cgContext) })
              attachment.name = "Spot-history-\(Int(width))-\(style == .dark ? "dark" : "light")-\(large ? "large-legacy" : "normal-krw")"
              attachment.lifetime = .keepAlways
              add(attachment)
            }
          }
        }
      }
    }
  }
}
