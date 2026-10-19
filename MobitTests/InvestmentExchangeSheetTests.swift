import XCTest
import UIKit
import ReactorKit
import RxSwift
@testable import Mobit

final class InvestmentExchangeSheetTests: XCTestCase {
  @MainActor
  func testPassedExchangeStartsSelectedAndSelectionDoesNotChangeGlobalAccount() throws {
    // 선택창을 닫은 뒤 다른 테스트에 거래소 선택을 남기지 않는다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    // 상품 선택도 시트에서 바뀌지 않는지 확인하고 원래 값으로 복구한다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    defer {
      ExchangeSelectionStore.currentExchange = previousExchange
      ExchangeSelectionStore.currentProduct = previousProduct
    }
    ExchangeSelectionStore.currentExchange = .upbit
    ExchangeSelectionStore.currentProduct = .spot
    // 카드 선택만으로 전환 콜백을 실행하면 안 된다.
    var confirmedExchanges: [Exchange] = []
    // 전역값과 다른 기본 선택을 전달해 해당 화면의 계좌가 우선하는지 검사한다.
    let controller = ExchangeSelectionSheetViewController(
      selectedExchange: .bithumb,
      callBack: { confirmedExchanges.append($0) }
    )
    // 실제 모달로 열어 최초 선택과 사용자 입력 경계를 확인한다.
    let window = host(controller)
    defer { window.isHidden = true; window.rootViewController = nil }
    XCTAssertEqual(controller.view.accessibilityIdentifier, "investment.exchangeSheet")
    try assertSelection(.bithumb, in: controller)
    try control(controller, "investment.exchangeOption.upbit").sendActions(for: .touchUpInside)
    try assertSelection(.upbit, in: controller)
    try control(controller, "investment.exchangeOption.bithumb").sendActions(for: .touchUpInside)
    try assertSelection(.bithumb, in: controller)
    XCTAssertTrue(confirmedExchanges.isEmpty)
    XCTAssertEqual(ExchangeSelectionStore.currentExchange, .upbit)
    XCTAssertEqual(ExchangeSelectionStore.currentProduct, .spot)
    XCTAssertTrue(window.rootViewController?.presentedViewController === controller)
  }

  @MainActor
  func testConfirmationDismissesBeforeReportingPendingExchangeExactlyOnce() throws {
    // 선택 결과와 콜백 시점의 표시 상태를 각각 확인한다.
    var confirmedExchanges: [Exchange] = []
    // 거래소 전환은 표시 중인 시트가 닫힌 뒤에만 시작해야 한다.
    var presentedDuringConfirmation: [Bool] = []
    // 콜백이 창을 보유하여 시트 수명이 늘어나지 않게 한다.
    weak var presentedWindow: UIWindow?
    // 최초 선택과 다른 거래소를 확인해 임시 선택값 전달을 검사한다.
    let controller = ExchangeSelectionSheetViewController(
      selectedExchange: .upbit,
      callBack: {
        confirmedExchanges.append($0)
        presentedDuringConfirmation.append(presentedWindow?.rootViewController?.presentedViewController != nil)
      }
    )
    // 실제 dismiss 완료를 기다릴 수 있도록 UIKit 표시 계층을 구성한다.
    let window = host(controller)
    presentedWindow = window
    defer { window.isHidden = true; window.rootViewController = nil }
    try control(controller, "investment.exchangeOption.bithumb").sendActions(for: .touchUpInside)
    XCTAssertTrue(confirmedExchanges.isEmpty)
    try control(controller, "investment.exchangeConfirm").sendActions(for: .touchUpInside)
    try control(controller, "investment.exchangeConfirm").sendActions(for: .touchUpInside)
    waitUntil { !confirmedExchanges.isEmpty && window.rootViewController?.presentedViewController == nil }
    XCTAssertEqual(confirmedExchanges, [.bithumb])
    XCTAssertEqual(presentedDuringConfirmation, [false])
  }

  @MainActor
  func testCloseAndSystemDismissDiscardPendingSelection() throws {
    for closeWithButton in [true, false] {
      // 닫기 버튼과 시스템 dismiss 모두 선택 확정을 전달하지 않는다.
      var confirmedExchanges: [Exchange] = []
      // 매번 새 시트를 열어 이전 시트의 임시 선택이 재사용되지 않게 한다.
      let controller = ExchangeSelectionSheetViewController(
        selectedExchange: .upbit,
        callBack: { confirmedExchanges.append($0) }
      )
      // 사용자가 선택을 바꾼 뒤 닫는 실제 표시 환경이다.
      let window = host(controller)
      defer { window.isHidden = true; window.rootViewController = nil }
      try control(controller, "investment.exchangeOption.bithumb").sendActions(for: .touchUpInside)
      if closeWithButton {
        try control(controller, "investment.exchangeClose").sendActions(for: .touchUpInside)
      } else {
        controller.dismiss(animated: false)
      }
      waitUntil { window.rootViewController?.presentedViewController == nil }
      XCTAssertTrue(confirmedExchanges.isEmpty)
    }
  }

  @MainActor
  func testSheetKeepsConfirmationVisibleOnSmallScreensBothThemesAndAccessibilityText() throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Trait overrides require iOS 17") }
    for width: CGFloat in [320, 375] {
      for style in [UIUserInterfaceStyle.light, .dark] {
        // 레이아웃 검사는 실제 계좌 전환 없이 시트를 표시한다.
        let controller = ExchangeSelectionSheetViewController(
          selectedExchange: .upbit,
          callBack: { _ in XCTFail("Layout must not switch exchange") }
        )
        // 작은 화면의 높이까지 제한해 본문 스크롤과 고정 버튼을 검사한다.
        let window = host(controller, width: width, height: width == 320 ? 568 : 812, style: style)
        defer { window.isHidden = true; window.rootViewController = nil }
        XCTAssertEqual(controller.modalPresentationStyle, .pageSheet)
        XCTAssertTrue(try XCTUnwrap(controller.sheetPresentationController).prefersGrabberVisible)
        XCTAssertFalse(try XCTUnwrap(controller.sheetPresentationController).detents.isEmpty)
        for large in [false, true, false] {
          controller.traitOverrides.preferredContentSizeCategory = large ? .accessibilityExtraExtraExtraLarge : .large
          controller.updateTraitsIfNeeded()
          window.layoutIfNeeded()
          controller.view.layoutIfNeeded()
          // 본문만 스크롤하고 확인 버튼은 화면 안에 남아 있어야 한다.
          let scroll = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIScrollView }.first)
          // 확인 버튼은 스크롤 콘텐츠와 분리되어 있어야 한다.
          let confirm = try control(controller, "investment.exchangeConfirm")
          // 시트의 Safe Area를 공통 좌표계로 사용해 화면 밖 잘림을 검사한다.
          let safeFrame = controller.view.safeAreaLayoutGuide.layoutFrame
          // 스크롤 전 확인 위치는 이후에도 그대로 유지되어야 한다.
          let confirmFrame = confirm.convert(confirm.bounds, to: controller.view)
          // 본문은 고정 확인 버튼 위까지만 높이를 사용한다.
          let scrollFrame = scroll.convert(scroll.bounds, to: controller.view)
          XCTAssertGreaterThan(scroll.bounds.height, 0)
          XCTAssertEqual(scroll.contentSize.width, scroll.bounds.width, accuracy: 1)
          XCTAssertGreaterThanOrEqual(confirmFrame.minX, safeFrame.minX - 1)
          XCTAssertLessThanOrEqual(confirmFrame.maxX, safeFrame.maxX + 1)
          XCTAssertGreaterThanOrEqual(confirmFrame.minY, safeFrame.minY - 1)
          XCTAssertLessThanOrEqual(confirmFrame.maxY, safeFrame.maxY + 1)
          XCTAssertLessThanOrEqual(scrollFrame.maxY, confirmFrame.minY + 1)
          XCTAssertFalse(descendants(scroll).contains { $0 === confirm })
          XCTAssertEqual(scroll.contentInsetAdjustmentBehavior, .never)
          XCTAssertEqual(scroll.adjustedContentInset, .zero)
          if !large {
            XCTAssertFalse(scroll.isScrollEnabled, "기본 글자 크기에서는 본문 전체가 시트 안에 보여야 한다.")
            XCTAssertLessThanOrEqual(scroll.contentSize.height, scroll.bounds.height + 0.5)
            XCTAssertEqual(scroll.contentOffset, .zero)
          }
          if large && width == 320 {
            XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
            XCTAssertTrue(scroll.isScrollEnabled, "화면보다 큰 접근성 글자에서는 본문을 끝까지 읽을 수 있어야 한다.")
          }
          if scroll.contentSize.height <= scroll.bounds.height {
            XCTAssertFalse(scroll.isScrollEnabled, "자연 높이가 화면 안에 맞으면 스크롤이 필요하지 않다.")
          }
          for identifier in ["investment.exchangeClose", "investment.exchangeConfirm", "investment.exchangeOption.upbit", "investment.exchangeOption.bithumb"] {
            // 작은 아이콘도 실제 선택 영역은 최소 44pt를 제공해야 한다.
            let button = try control(controller, identifier)
            XCTAssertGreaterThanOrEqual(button.bounds.width, 44, identifier)
            XCTAssertGreaterThanOrEqual(button.bounds.height, 44, identifier)
            XCTAssertFalse(button.hasAmbiguousLayout, identifier)
          }
          for label in descendants(controller.view).compactMap({ $0 as? UILabel }).filter({
            self.isVisible($0) && !($0.text ?? "").isEmpty
          }) {
            XCTAssertGreaterThan(label.bounds.width, 0, label.text ?? "")
            XCTAssertGreaterThanOrEqual(
              label.bounds.height + 1,
              label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height,
              label.text ?? ""
            )
          }
          XCTAssertFalse(controller.view.hasAmbiguousLayout)
          XCTAssertFalse(scroll.hasAmbiguousLayout)
          scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)), animated: false)
          XCTAssertEqual(confirm.convert(confirm.bounds, to: controller.view), confirmFrame)
          // 실제 시트 색상과 글자 배치를 검토할 이미지를 테스트 결과에 남긴다.
          let capture = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) })
          capture.name = "InvestmentExchange-\(Int(width))-\(style == .dark ? "dark" : "light")-\(large ? "large" : "normal")"
          capture.lifetime = .keepAlways
          add(capture)
        }
      }
    }
  }

  @MainActor
  func testNaturalSheetHeightIncludesTopSafeAreaAndRemeasuresAfterSelection() throws {
    // 시스템 손잡이와 겹치지 않도록 추가된 안전 영역도 자연 높이에 반영한다.
    let controller = ExchangeSelectionSheetViewController(
      selectedExchange: .upbit,
      callBack: { _ in XCTFail("Layout must not switch exchange") }
    )
    // 화면 최대 높이까지 여유가 있는 표시 환경에서 자연 높이 변화를 비교한다.
    let window = host(controller)
    defer { window.isHidden = true; window.rootViewController = nil }
    // 추가 안전 영역이 없는 최초 콘텐츠 높이를 비교 기준으로 사용한다.
    let originalHeight = controller.preferredContentSize.height
    controller.additionalSafeAreaInsets.top = 18
    window.layoutIfNeeded()
    controller.view.layoutIfNeeded()
    waitUntil { controller.preferredContentSize.height >= originalHeight + 18 }
    XCTAssertEqual(controller.preferredContentSize.height, originalHeight + 18, accuracy: 1)
    // 선택 배지가 다른 카드로 이동해도 카드 전체가 보이는 높이를 유지한다.
    let scroll = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIScrollView }.first)
    try control(controller, "investment.exchangeOption.bithumb").sendActions(for: .touchUpInside)
    window.layoutIfNeeded()
    controller.view.layoutIfNeeded()
    XCTAssertFalse(scroll.isScrollEnabled)
    XCTAssertLessThanOrEqual(scroll.contentSize.height, scroll.bounds.height + 0.5)
    controller.additionalSafeAreaInsets.top = 0
    window.layoutIfNeeded()
    controller.view.layoutIfNeeded()
    waitUntil { abs(controller.preferredContentSize.height - originalHeight) <= 1 }
    XCTAssertFalse(scroll.isScrollEnabled)
    XCTAssertLessThanOrEqual(scroll.contentSize.height, scroll.bounds.height + 0.5)
  }

  @MainActor
  func testMainExchangeSelectorUsesSharedSheetAndConfirmsThroughCoordinatorForBothProducts() throws {
    // UIKit이 연결된 Scene 안에서만 메인과 시트를 표시한다.
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    // 테스트 창을 닫은 뒤 기존 앱 창으로 키보드·터치 소유권을 돌려준다.
    let previousWindow = scene.windows.first { $0.isKeyWindow }
    // 화면 생성 전의 선택을 복원해 다른 거래 테스트의 계좌를 유지한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    // 현물과 선물 양쪽 진입을 확인한 뒤 원래 상품으로 복구한다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    // 메인 진입 시 정규화하는 보유 내역의 저장 원본도 보존한다.
    let previousHoldingsData = UserDefaults.standard.object(forKey: UserDataManager.Keys.userCryptoList)
    // 구독 중인 다른 화면에도 원래 보유 내역을 돌려준다.
    let previousHoldings = UserDataManager.userCryptoList
    defer {
      ExchangeSelectionStore.currentExchange = previousExchange
      ExchangeSelectionStore.currentProduct = previousProduct
      UserDataManager.userCryptoList = previousHoldings ?? []
      UserDefaults.standard.set(previousHoldingsData, forKey: UserDataManager.Keys.userCryptoList)
      previousWindow?.makeKeyAndVisible()
    }
    UserDataManager.userCryptoList = []
    for product in [TradingProduct.spot, .perpetual] {
      ExchangeSelectionStore.currentExchange = .upbit
      ExchangeSelectionStore.currentProduct = product
      // 실제 시세 조회 없이 메인의 사용자 입력과 표시 경로만 실행한다.
      let market = MainReactor(mainUseCase: MainExchangeSheetUseCase(), tickerSocketService: MainExchangeSheetSocket())
      market.isStubEnabled = true
      // 선물 계좌 검증 역시 외부 서비스에 전달하지 않는다.
      let futures = FuturesAccountReactor(
        account: TradingAccountID(exchange: .upbit, product: .perpetual, currency: .krw),
        networkAvailability: .empty()
      )
      futures.isStubEnabled = true
      // 광고 표시만 생략하고 실제 메인의 선택 버튼과 이벤트 처리를 사용한다.
      let main = ExchangeSheetMainViewController(
        reactor: market,
        futuresReactor: product == .perpetual ? futures : nil,
        networkAvailability: .empty()
      )
      main.selectedTab = .favorite
      // 앱과 같은 내비게이션 표시 계층에서 시트의 dismiss를 검사한다.
      let navigation = UINavigationController(rootViewController: main)
      navigation.setNavigationBarHidden(true, animated: false)
      // 기존 Coordinator의 전달 경로를 통해서만 선택이 확정돼야 한다.
      let coordinator = MainCoordinator(navigationController: navigation, dataManager: .shared)
      // 확인 결과와 전달 당시 시트 표시 여부를 기록한다.
      let delegate = MainExchangeSheetDelegate()
      delegate.main = main
      coordinator.delegate = delegate
      main.coordinator = coordinator
      // 실제 표시·닫기를 실행할 독립 창이다.
      let window = UIWindow(windowScene: scene)
      window.frame = CGRect(x: 0, y: 0, width: 375, height: 812)
      window.rootViewController = navigation
      window.makeKeyAndVisible()
      defer {
        window.isHidden = true
        window.rootViewController = nil
      }
      window.layoutIfNeeded()
      waitUntil {
        main.viewIfLoaded?.window === window
          && navigation.visibleViewController === main
          && main.view.bounds.width > 0
          && navigation.transitionCoordinator == nil
      }
      // 메인과 투자내역이 같은 컨트롤러를 여는지 확인할 실제 버튼이다.
      let selector = try control(main, "main.exchange")
      selector.sendActions(for: .touchUpInside)
      // 표시 중 연속 탭해도 현재 시트 위에 다른 시트를 쌓으면 안 된다.
      let firstSheet = try XCTUnwrap(main.presentedViewController as? ExchangeSelectionSheetViewController)
      selector.sendActions(for: .touchUpInside)
      waitUntil { !firstSheet.isBeingPresented }
      XCTAssertTrue(main.presentedViewController === firstSheet)
      XCTAssertNil(firstSheet.presentedViewController)
      try assertSelection(.upbit, in: firstSheet)
      // 메인 위에 표시된 공통 시트와 기존 로고를 결과 이미지로 확인한다.
      let capture = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image {
        window.layer.render(in: $0.cgContext)
      })
      capture.name = "MainExchangeSheet-\(product.rawValue)"
      capture.lifetime = .keepAlways
      add(capture)
      try control(firstSheet, "investment.exchangeOption.bithumb").sendActions(for: .touchUpInside)
      XCTAssertTrue(delegate.exchanges.isEmpty)
      XCTAssertEqual(ExchangeSelectionStore.currentExchange, .upbit)
      XCTAssertEqual(ExchangeSelectionStore.currentProduct, product)
      try control(firstSheet, "investment.exchangeClose").sendActions(for: .touchUpInside)
      waitUntil { main.presentedViewController == nil }
      XCTAssertTrue(delegate.exchanges.isEmpty)

      selector.sendActions(for: .touchUpInside)
      // 닫은 시트의 미확정 선택은 다음 표시에서 재사용하지 않는다.
      let unchangedSheet = try XCTUnwrap(main.presentedViewController as? ExchangeSelectionSheetViewController)
      waitUntil { !unchangedSheet.isBeingPresented }
      try assertSelection(.upbit, in: unchangedSheet)
      try control(unchangedSheet, "investment.exchangeConfirm").sendActions(for: .touchUpInside)
      waitUntil { main.presentedViewController == nil }
      XCTAssertTrue(delegate.exchanges.isEmpty)

      selector.sendActions(for: .touchUpInside)
      // 최종 확인만 기존 Coordinator에 새 거래소를 전달한다.
      let changedSheet = try XCTUnwrap(main.presentedViewController as? ExchangeSelectionSheetViewController)
      waitUntil { !changedSheet.isBeingPresented }
      try control(changedSheet, "investment.exchangeOption.bithumb").sendActions(for: .touchUpInside)
      try control(changedSheet, "investment.exchangeConfirm").sendActions(for: .touchUpInside)
      try control(changedSheet, "investment.exchangeConfirm").sendActions(for: .touchUpInside)
      waitUntil { main.presentedViewController == nil && !delegate.exchanges.isEmpty }
      XCTAssertEqual(delegate.exchanges, [.bithumb])
      XCTAssertEqual(delegate.presentedDuringConfirmation, [false])
      XCTAssertEqual(main.selectedTab, .favorite)
      XCTAssertEqual(ExchangeSelectionStore.currentExchange, .upbit)
      XCTAssertEqual(ExchangeSelectionStore.currentProduct, product)
      XCTAssertTrue(main.coordinator === coordinator)
    }
  }

  @MainActor
  private func host(
    _ controller: ExchangeSelectionSheetViewController,
    width: CGFloat = 375,
    height: CGFloat = 812,
    style: UIUserInterfaceStyle = .light
  ) -> UIWindow {
    // 실제 시스템 시트의 표시와 닫기 완료를 검사할 전용 창이다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
    // 시트 아래 화면을 대신하는 표시 전용 컨트롤러다.
    let presenter = UIViewController()
    window.rootViewController = presenter
    window.overrideUserInterfaceStyle = style
    window.makeKeyAndVisible()
    controller.prepareSheet(for: width)
    presenter.present(controller, animated: false)
    window.layoutIfNeeded()
    controller.view.layoutIfNeeded()
    waitUntil { !controller.isBeingPresented }
    return window
  }

  @MainActor
  private func assertSelection(_ selected: Exchange, in controller: UIViewController) throws {
    for exchange in [Exchange.upbit, .bithumb] {
      // 두 거래소 중 하나만 선택 상태로 표시되어야 한다.
      let option = try control(controller, "investment.exchangeOption.\(exchange.rawValue)")
      XCTAssertEqual(option.isSelected, exchange == selected)
    }
  }

  @MainActor
  private func control(_ controller: UIViewController, _ identifier: String) throws -> UIControl {
    try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == identifier } as? UIControl)
  }

  @MainActor
  private func isVisible(_ view: UIView) -> Bool {
    !sequence(first: view, next: { $0.superview }).contains { $0.isHidden || $0.alpha == 0 }
  }

  @MainActor
  private func descendants(_ view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }

  @MainActor
  private func waitUntil(
    timeout: TimeInterval = 5,
    _ condition: @escaping () -> Bool
  ) {
    // UIKit 표시와 dismiss 애니메이션이 끝나는 조건을 기다린다.
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
    wait(for: [ready], timeout: timeout)
  }
}

private final class ExchangeSheetMainViewController: MainViewController {
  override func viewDidAppear(_ animated: Bool) {
    // 거래소 선택 검증에서 화면 진입 광고 요청이 발생하지 않게 한다.
  }
}

private final class MainExchangeSheetUseCase: MainUseCase {
  init() { super.init(mainRepository: MainRepository()) }

  override func fetchCryptoList() -> Observable<CryptoList> { .never() }
  override func fetchCryptoTicker(markets: [String]) -> Observable<CryptoTickerList> { .never() }
  override func fetchFearGreedIndex() -> Observable<FearGreedIndex> { .never() }
}

private final class MainExchangeSheetSocket: TickerSocketServiceProtocol {
  // 선택 시트 검증 중 실제 소켓 연결은 만들지 않는다.
  var isConnected = false
  // 메인 Reactor에 시세 이벤트가 유입되지 않게 한다.
  var stream: Observable<CryptoSocketTicker> { .never() }
  func connect() {}
  func disconnect(userInitiated: Bool) {}
  func reconnectIfNeeded() {}
  func subscribe(markets: [String]) {}
}

private final class MainExchangeSheetDelegate: MainCoordinatorDelegate {
  // 모달이 완전히 닫힌 뒤 전환을 요청하는지 확인한다.
  weak var main: MainViewController?
  // 기존 Coordinator로 전달된 확정 거래소를 기록한다.
  var exchanges: [Exchange] = []
  // 거래소 전환 요청 당시의 시트 표시 상태다.
  var presentedDuringConfirmation: [Bool] = []

  func mainCoordinatorDidRequestExchangeSwitch(to exchange: Exchange) {
    exchanges.append(exchange)
    presentedDuringConfirmation.append(main?.presentedViewController != nil)
  }
}
