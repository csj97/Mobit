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

@MainActor
final class InvestmentXIBLayoutTests: XCTestCase {
  func testSummaryAccommodatesAccessibilityTextAndHiddenEmptyState() throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Trait overrides require iOS 17") }
    for width: CGFloat in [320, 393, 440] {
      // 화면 생명주기와 시세 구독 없이 실제 XIB 연결을 검사한다.
      let owner = InvestmentLayoutNibOwner()
      // 테이블 헤더의 너비와 높이는 실제 사용처와 동일하게 외부에서 결정한다.
      let root = try loadNib("InvestmentViewController", owner: owner)
      // 접근성 글자 크기를 전달할 표시 전용 컨트롤러다.
      let controller = UIViewController()
      controller.view = root
      // 각 화면 너비에서 요약 콘텐츠의 실제 배치를 확인한다.
      let window = host(controller, width: width)
      defer { window.isHidden = true; window.rootViewController = nil }
      // 현물과 선물이 공유하는 요약 헤더를 직접 구성한다.
      let header = try XCTUnwrap(owner.outlets["summaryHeaderView"] as? InvestmentSummaryView)
      // 목록에서 헤더의 자연 높이를 계산하는 실제 테이블이다.
      let table = try XCTUnwrap(owner.outlets["transactionTableview"] as? UITableView)
      // 숨김 전환 시 내부 여백과 접힘 제약이 충돌하지 않아야 한다.
      let empty = try XCTUnwrap(owner.outlets["noResultView"] as? UIView)
      header.configure(product: .perpetual)
      header.updateCount(42)
      // 양쪽 열의 줄 수가 다를 때도 각 제목과 금액의 높이가 결정되어야 한다.
      (owner.outlets["availableUserBalance"] as? UILabel)?.text = "0"
      (owner.outlets["totalUserBalance"] as? UILabel)?.text = "9,999,999,999,999,999"
      (owner.outlets["totalBuyPrice"] as? UILabel)?.text = "1,234,567,890,123,456"
      (owner.outlets["totalEvaluationAmount"] as? UILabel)?.text = "0"
      (owner.outlets["totalEvalProfitLoss"] as? UILabel)?.text = "-9,999,999,999"
      (owner.outlets["totalProfitRate"] as? UILabel)?.text = "+123,456.78%"
      (owner.outlets["sortLabel"] as? UILabel)?.text = "Evaluation Profit and Loss: Highest First"
      for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge, .large] {
        controller.traitOverrides.preferredContentSizeCategory = category
        controller.updateTraitsIfNeeded()
        for hidden in [false, true, false] {
          empty.isHidden = hidden
          root.layoutIfNeeded()
          header.updateLayout(in: table)
          header.layoutIfNeeded()
          // 부모의 다음 레이아웃에서 줄바꿈 후 자연 높이를 재확인하는 실제 흐름이다.
          header.updateLayout(in: table)
          header.layoutIfNeeded()
          XCTAssertGreaterThan(header.bounds.height, 0)
          XCTAssertEqual(header.bounds.width, table.bounds.width, accuracy: 1)
          assertLabelsFit(in: header)
          // 숫자 개수를 여러 줄로 나누거나 일반 제목을 한 글자 폭으로 압축하면 안 된다.
          let headerLabels = descendants(header).compactMap { $0 as? UILabel }
          // 개수는 접근성 크기에서도 하나의 숫자로 읽을 수 있어야 한다.
          let count = try XCTUnwrap(headerLabels.first { $0.text == "42" })
          XCTAssertGreaterThanOrEqual(count.bounds.width + 1, ("42" as NSString).size(withAttributes: [.font: count.font as Any]).width)
          if !category.isAccessibilityCategory {
            // 일반 배치에서는 원래 한 줄 제목 너비를 정렬 문구보다 먼저 보존한다.
            let list = try XCTUnwrap(headerLabels.first { $0.text == FuturesText.text("investment_positions") })
            XCTAssertGreaterThanOrEqual(list.bounds.width + 1, ((list.text ?? "") as NSString).size(withAttributes: [.font: list.font as Any]).width)
          }
          if category.isAccessibilityCategory {
            // 제목과 통화 단위가 한 글자보다 좁게 눌리는 시각적 잘림을 검사한다.
            let labels = descendants(header).compactMap { $0 as? UILabel }
            // 두 글자 이상을 함께 읽을 수 있어야 하는 자산 제목이다.
            let title = try XCTUnwrap(labels.first { $0.text == FuturesText.text("investment_my_assets") })
            // 통화 기호를 세로 글자 조각으로 표시하면 안 된다.
            let unit = try XCTUnwrap(labels.first { $0.text == FuturesText.text("investment_unit_krw") })
            // 언어별 실제 글꼴에서 가장 넓은 글자를 기준으로 최소 폭을 비교한다.
            let glyphWidth = (title.text ?? "").map {
              (String($0) as NSString).size(withAttributes: [.font: title.font as Any]).width
            }.max() ?? 0
            // 통화 단위는 적어도 공백으로 구분한 한 단어를 온전히 표시한다.
            let unitWordWidth = (unit.text ?? "").split(separator: " ").map {
              (String($0) as NSString).size(withAttributes: [.font: unit.font as Any]).width
            }.max() ?? 0
            XCTAssertGreaterThanOrEqual(title.bounds.width + 1, glyphWidth * 2)
            XCTAssertGreaterThanOrEqual(unit.bounds.width + 1, unitWordWidth)
            // 긴 정렬 문구는 제목·개수와 별도 행에서 가로 공간을 사용한다.
            let sort = try XCTUnwrap(owner.outlets["sortLabel"] as? UILabel)
            XCTAssertGreaterThanOrEqual(sort.bounds.width + 1, width - 32 - 38)
          }
        }
        attach(header, name: "InvestmentSummary-\(Int(width))-\(category.rawValue)")
      }
    }
  }

  func testEmptyInvestmentMessageCentersInRemainingListViewport() throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Trait overrides require iOS 17") }
    for product in [TradingProduct.spot, .perpetual] {
      for width: CGFloat in [320, 393, 440] {
        // 두 상품 화면이 실제로 공유하는 요약·정렬·빈 목록 계층이다.
        let owner = InvestmentLayoutNibOwner()
        // 부모 테이블의 가용 높이에서 빈 안내 위치를 검사한다.
        let root = try loadNib("InvestmentViewController", owner: owner)
        // Dynamic Type 변경을 실제 화면 계층에 전달한다.
        let controller = UIViewController()
        controller.view = root
        // 작은 화면에서도 긴 요약은 스크롤 흐름을 유지해야 한다.
        let window = host(controller, width: width)
        defer { window.isHidden = true; window.rootViewController = nil }
        // 높이 변경 뒤 원래 viewport로 돌아오는지도 확인한다.
        let originalWindowHeight = window.bounds.height
        // 목록 너비와 viewport를 제공하는 실제 테이블이다.
        let table = try XCTUnwrap(owner.outlets["transactionTableview"] as? UITableView)
        table.contentInset.bottom = 16
        // 요약과 정렬 아래에 붙은 기존 빈 목록 영역이다.
        let header = try XCTUnwrap(owner.outlets["summaryHeaderView"] as? InvestmentSummaryView)
        // 데이터 유무에 따라 접히는 실제 컨테이너다.
        let empty = try XCTUnwrap(owner.outlets["noResultView"] as? UIView)
        // 빈 상태뿐 아니라 여러 줄 오류도 같은 목록 영역에서 읽을 수 있어야 한다.
        let label = try XCTUnwrap(owner.outlets["emptyLabel"] as? UILabel)
        header.configure(product: product)
        header.updateCount(0)
        for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge, .large] {
          controller.traitOverrides.preferredContentSizeCategory = category
          controller.updateTraitsIfNeeded()
          for message in [
            FuturesText.text(product == .spot ? "trade_no_coins" : "futures_no_position"),
            FuturesText.text("futures_storage_error")
          ] {
            label.text = message
            // inset 16→60→16과 viewport 확대·복원에서 높이가 누적되지 않아야 한다.
            let layouts: [(CGFloat, CGFloat)] = [
              (16, originalWindowHeight), (60, originalWindowHeight),
              (16, originalWindowHeight + 160), (16, originalWindowHeight)
            ]
            for (bottomInset, windowHeight) in layouts {
              table.contentInset.bottom = bottomInset
              window.frame.size.height = windowHeight
              empty.isHidden = false
              window.layoutIfNeeded()
              root.layoutIfNeeded()
              header.updateLayout(in: table)
              header.layoutIfNeeded()
              header.updateLayout(in: table)
              header.layoutIfNeeded()
              // 요약과 정렬을 뺀 뒤 남는 테이블 높이가 빈 안내의 기준이다.
              let viewportHeight = table.bounds.height - table.adjustedContentInset.top - table.adjustedContentInset.bottom
              // 기존 상·하 48pt를 지킬 수 없으면 안내를 화면 밖으로 밀지 않고 스크롤한다.
              let minimumHeight = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height + 96
              // 빈 안내 위에 있는 실제 요약과 정렬의 콘텐츠 높이다.
              let prefixHeight = empty.frame.minY
              XCTAssertEqual(empty.frame.height, max(minimumHeight, viewportHeight - prefixHeight), accuracy: 1)
              XCTAssertEqual(label.center.y, empty.bounds.midY, accuracy: 1)
              XCTAssertEqual(label.center.x, empty.bounds.midX, accuracy: 1)
              XCTAssertGreaterThanOrEqual(label.frame.minY + 1, 48)
              XCTAssertLessThanOrEqual(label.frame.maxY - 1, empty.bounds.height - 48)
              XCTAssertEqual(header.bounds.height, prefixHeight + empty.bounds.height, accuracy: 1)
              assertLabelsFit(in: header)
              // 같은 입력으로 반복 측정해도 정수·픽셀 반올림 오차가 쌓이지 않아야 한다.
              let stableHeight = header.bounds.height
              for _ in 0..<10 {
                header.updateLayout(in: table)
                header.layoutIfNeeded()
                XCTAssertEqual(header.bounds.height, stableHeight, accuracy: 0.001)
              }
              empty.isHidden = true
              root.layoutIfNeeded()
              header.updateLayout(in: table)
              header.layoutIfNeeded()
              XCTAssertEqual(header.bounds.height, prefixHeight, accuracy: 1)
              XCTAssertFalse(header.hasAmbiguousLayout)
            }
          }
          label.text = FuturesText.text(product == .spot ? "trade_no_coins" : "futures_no_position")
          empty.isHidden = false
          header.updateLayout(in: table)
          header.layoutIfNeeded()
          attach(header, name: "InvestmentEmpty-\(product)-\(Int(width))-\(category.rawValue)")
        }
        empty.isHidden = false
        header.updateLayout(in: table)
        header.layoutIfNeeded()
        attach(root, name: "InvestmentEmpty-\(product)-\(Int(width))")
      }
    }
  }

  func testPNLEmptyMessageUsesTableViewport() throws {
    for width: CGFloat in [320, 393, 440] {
      // 실현 손익은 요약 헤더가 없는 별도 목록 화면이다.
      let owner = InvestmentLayoutNibOwner()
      // 기존 목록 overlay를 화면 전체 중앙과 구별해 확인한다.
      let root = try loadNib("PNLViewController", owner: owner)
      // Safe Area를 포함한 실제 부모 크기를 제공한다.
      let controller = UIViewController()
      controller.view = root
      // 화면 너비별 목록 영역을 표시한다.
      let window = host(controller, width: width)
      defer { window.isHidden = true; window.rootViewController = nil }
      // 비어 있는 거래 내역의 목록 영역이다.
      let table = try XCTUnwrap(owner.outlets["pnlTableView"] as? UITableView)
      // 목록과 같은 경계를 가진 빈 상태 overlay다.
      let empty = try XCTUnwrap(owner.outlets["noResultView"] as? UIView)
      // 긴 오류 문구도 목록 중앙을 유지한다.
      let label = try XCTUnwrap(owner.outlets["emptyLabel"] as? UILabel)
      label.text = FuturesText.text("futures_storage_error")
      root.layoutIfNeeded()
      XCTAssertEqual(empty.frame, table.frame)
      XCTAssertEqual(label.center.x, empty.bounds.midX, accuracy: 1)
      XCTAssertEqual(label.center.y, empty.bounds.midY, accuracy: 1)
      assertLabelsFit(in: empty)
    }
  }

  func testPNLCellShowsLongPricesAndCompleteExecutionTime() throws {
    for width: CGFloat in [320, 393, 440] {
      // 거래 내역의 실제 nib과 configure 경로로 표시 누락을 검사한다.
      let cell = try XCTUnwrap(try loadNib("PNLTableViewCell") as? PNLTableViewCell)
      // 긴 가격과 수량도 항목명 옆에 전체 값을 보존한다.
      let history = UserPNLHistoryModel(
        marketName: "BTC/KRW",
        entryPrice: 1_234_567_890_123_456,
        exitPrice: 1_234_567_890_123_457,
        transactionDate: "2026.10.20 12:34:56",
        orderQuantity: 123_456_789.12345678,
        pnl: 1
      )
      cell.configure(pnlHistory: history)
      cell.frame = CGRect(x: 0, y: 0, width: width, height: 200)
      // XIB의 한 줄 지표 배치로 필요한 높이가 계산되는지 확인한다.
      let fitting = cell.systemLayoutSizeFitting(
        CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
        withHorizontalFittingPriority: .required,
        verticalFittingPriority: .fittingSizeLevel
      )
      cell.frame.size.height = fitting.height
      cell.setNeedsLayout()
      cell.layoutIfNeeded()
      XCTAssertGreaterThan(fitting.height, 0)
      XCTAssertEqual(cell.metricsStackView.arrangedSubviews.count, 2)
      XCTAssertEqual(cell.quantityLabel.text, "123,456,789 BTC")
      XCTAssertEqual(cell.entryPriceLabel.text, "1,234,567,890,123,456 " + FuturesText.text("currency_krw_unit"))
      XCTAssertEqual(cell.exitPriceLabel.text, "1,234,567,890,123,457 " + FuturesText.text("currency_krw_unit"))
      XCTAssertEqual(cell.transactionDateLabel.text, "2026.10.20 12:34:56")
      XCTAssertEqual(cell.transactionDateLabel.accessibilityValue, cell.transactionDateLabel.text)
      XCTAssertEqual(cell.transactionDateLabel.numberOfLines, 1)
      XCTAssertGreaterThanOrEqual(cell.shareButton.bounds.height, cell.shareButton.intrinsicContentSize.height)
      assertPNLLabelsFit(in: cell)
      for label in [cell.quantityLabel, cell.entryPriceLabel, cell.exitPriceLabel] {
        // 전체 값이 카드의 가로 영역 안에 남아 있어야 한다.
        let value = try XCTUnwrap(label)
        XCTAssertTrue(value.adjustsFontSizeToFitWidth)
        // 셀 좌표계에서 텍스트 영역이 좌우 가장자리 밖으로 나가지 않는지 확인한다.
        let frame = value.convert(value.bounds, to: cell.contentView)
        XCTAssertGreaterThanOrEqual(frame.minX, 28 - 1)
        XCTAssertLessThanOrEqual(frame.maxX, width - 28 + 1)
        XCTAssertFalse(value.hasAmbiguousLayout)
      }
      attach(cell, name: "PNLCell-long-values-\(Int(width))")
    }
  }

  func testPNLAutomaticTableRowsUseResponsiveContentHeight() throws {
    for width: CGFloat in [320, 393, 440] {
      // UIKit의 실제 자동 높이 계산에서도 긴 데이터가 잘리지 않아야 한다.
      let cell = try XCTUnwrap(try loadNib("PNLTableViewCell") as? PNLTableViewCell)
      cell.configure(pnlHistory: UserPNLHistoryModel(
        marketName: "BTC/KRW",
        entryPrice: 1_234_567_890_123_456,
        exitPrice: 1_234_567_890_123_457,
        transactionDate: "2026.10.20 12:34:56",
        orderQuantity: 123_456_789.12345678,
        pnl: 1
      ))
      // 실데이터 소스와 같은 경로로 셀을 테이블에 전달한다.
      let source = InvestmentLayoutTableSource(cell: cell)
      // 직접 fitting한 높이와 실제 UITableView의 결과를 비교한다.
      let table = UITableView()
      table.dataSource = source
      table.rowHeight = UITableView.automaticDimension
      table.estimatedRowHeight = 200
      // 자동 높이를 계산할 실제 표시 환경이다.
      let controller = UIViewController()
      controller.view = table
      // 각 기기 너비를 유지한 독립 창이다.
      let window = host(controller, width: width)
      defer { window.isHidden = true; window.rootViewController = nil }
      table.reloadData()
      table.layoutIfNeeded()
      // 같은 너비에서 요구하는 콘텐츠의 최소 높이다.
      let fitting = cell.systemLayoutSizeFitting(
        CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
        withHorizontalFittingPriority: .required,
        verticalFittingPriority: .fittingSizeLevel
      )
      XCTAssertGreaterThanOrEqual(table.rectForRow(at: IndexPath(row: 0, section: 0)).height + 1, fitting.height)
      assertPNLLabelsFit(in: cell)
    }
  }

  func testPNLCardsFitProfitLossAndShortWithAccessibilityText() throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Trait overrides require iOS 17") }
    // 같은 진입 가격과 증거금으로 손익 방향과 포지션 배지를 비교한다.
    let samples: [(name: String, side: FuturesSide, kind: FuturesTransactionRecord.Kind, pnl: Decimal, exitPrice: Decimal)] = [
      ("long-profit", .long, .closing, 25_000, 101_250_000),
      ("long-loss", .long, .closing, -10_000, 99_500_000),
      ("short-profit", .short, .closing, 10_000, 99_500_000),
      ("liquidated", .long, .liquidation, -100_000, 95_000_000)
    ]
    for (width, category) in [
      (CGFloat(320), UIContentSizeCategory.large),
      (CGFloat(393), UIContentSizeCategory.large),
      (CGFloat(440), UIContentSizeCategory.large),
      (CGFloat(320), UIContentSizeCategory.accessibilityExtraExtraExtraLarge)
    ] {
      for sample in samples {
        for tableName in ["Localizable(KO)", "Localizable(EN)"] {
          // 주문을 제출하지 않고 실제 거래 셀에 전달할 포지션만 생성한다.
          let position = try FuturesCalculator.open(domesticFuturesOrder(side: sample.side, leverage: 20))
          // 수수료 없는 현재 모의거래 정책의 종료 결과다.
          let record = FuturesTransactionRecord(
            eventID: UUID(),
            positionID: position.id,
            kind: sample.kind,
            instrument: position.order.instrument,
            side: sample.side,
            leverage: position.order.leverage,
            quantity: position.quantity,
            intervalStart: 1_792_562_832_000,
            intervalEndExclusive: nil,
            recordedAt: Date(timeIntervalSince1970: 1_792_562_832),
            price: sample.exitPrice,
            realizedPnL: sample.pnl,
            margin: try position.margin,
            entryPrice: try position.averageEntryPrice
          )
          // 실제 XIB의 제약과 폰트 설정을 그대로 검사한다.
          let cell = try XCTUnwrap(try loadNib("PNLTableViewCell") as? PNLTableViewCell)
          // 기본·접근성 설정을 실제 표시 환경에 전달한다.
          let controller = UIViewController()
          controller.overrideUserInterfaceStyle = .light
          controller.traitOverrides.preferredContentSizeCategory = category
          controller.view.addSubview(cell)
          cell.frame = CGRect(x: 0, y: 0, width: width, height: 2_000)
          // 접근성 설정이 전달된 실제 창 계층에서 검증한다.
          let window = host(controller, width: width)
          defer { window.isHidden = true; window.rootViewController = nil }
          controller.updateTraitsIfNeeded()
          cell.configure(record: record, position: position)
          // 앱 언어를 바꾸지 않고 두 번역의 실제 배지·상태·항목명 길이를 검사한다.
          let sideKey = sample.side == .long ? "futures_long" : "futures_short"
          // 청산과 일반 종료의 번역 문구를 같은 한 줄 제약에서 비교한다.
          let statusKey = sample.kind == .liquidation ? "futures_pnl_liquidated" : "futures_pnl_closed"
          XCTAssertEqual(cell.statusLabel.text, FuturesText.text(statusKey))
          cell.positionBadgeLabel.text = "\(NSLocalizedString(sideKey, tableName: tableName, bundle: .main, value: sideKey, comment: "")) 20×"
          cell.statusLabel.text = NSLocalizedString(statusKey, tableName: tableName, bundle: .main, value: statusKey, comment: "")
          cell.shareButton.setTitle(
            NSLocalizedString("media_share", tableName: tableName, bundle: .main, value: "media_share", comment: ""),
            for: .normal
          )
          // 네 지표의 항목명도 현재 언어와 독립적으로 번역 길이를 검사한다.
          let detailKeys = ["trade_executed_quantity", "futures_entry_price", sample.kind == .liquidation ? "futures_liquidation_exit_price" : "futures_exit_price", "futures_margin"]
          // 실제 값 라벨의 부모에서 항목명을 찾아 기존 outlet 범위를 유지한다.
          let detailValues: [UILabel] = [cell.quantityLabel, cell.entryPriceLabel, cell.exitPriceLabel, cell.marginLabel]
          for (value, key) in zip(detailValues, detailKeys) {
            // XIB의 각 지표는 항목명과 값 순서를 유지한다.
            let title = try XCTUnwrap((value.superview as? UIStackView)?.arrangedSubviews.first as? UILabel)
            title.text = NSLocalizedString(key, tableName: tableName, bundle: .main, value: key, comment: "")
          }
          // 접근성 설정에서도 손익과 상세 지표의 한 줄 배치를 유지한다.
          let fitting = cell.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
          )
          cell.frame.size.height = ceil(fitting.height)
          cell.setNeedsLayout()
          cell.layoutIfNeeded()

          XCTAssertGreaterThan(fitting.height, 0)
          XCTAssertFalse(cell.contentView.hasAmbiguousLayout)
          XCTAssertEqual(cell.marketNameLabel.text, FuturesText.symbol(record.instrument))
          XCTAssertEqual(cell.positionBadgeLabel.text, "\(NSLocalizedString(sideKey, tableName: tableName, bundle: .main, value: sideKey, comment: "")) 20×")
          XCTAssertEqual(cell.statusLabel.text, NSLocalizedString(statusKey, tableName: tableName, bundle: .main, value: statusKey, comment: ""))
          XCTAssertEqual(cell.quantityLabel.text, FuturesText.number(record.quantity) + " BTC")
          XCTAssertEqual(cell.entryPriceLabel.text, FuturesText.number(try position.averageEntryPrice) + " " + FuturesText.text("currency_krw_unit"))
          XCTAssertEqual(cell.exitPriceLabel.text, FuturesText.number(record.price) + " " + FuturesText.text("currency_krw_unit"))
          XCTAssertEqual(cell.marginLabel.text, FuturesText.number(try position.margin) + " " + FuturesText.text("currency_krw_unit"))
          XCTAssertEqual(cell.transactionDateLabel.accessibilityValue, cell.transactionDateLabel.text)
          XCTAssertGreaterThanOrEqual(cell.shareButton.bounds.height, cell.shareButton.intrinsicContentSize.height)
          assertPNLLabelsFit(in: cell)
          // 통화 단위와 구분한 금액 숫자의 실제 굵기와 크기를 확인한다.
          let amountFont = try XCTUnwrap(cell.pnlLabel.attributedText?.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
          XCTAssertEqual(amountFont.pointSize, cell.quantityLabel.font.pointSize)
          XCTAssertEqual(cell.roiLabel.font.pointSize, cell.quantityLabel.font.pointSize)
          XCTAssertTrue(amountFont.fontDescriptor.symbolicTraits.contains(.traitBold))
          attach(cell, name: "PNLCard-\(sample.name)-\(Int(width))-\(tableName)-\(category.isAccessibilityCategory ? "accessibility" : "normal")")
        }
      }
    }
  }

  func testShareCardBoundsLongValuesAndErrorMessage() throws {
    for width: CGFloat in [320, 393, 440] {
      // 공유 이미지에도 실제 계좌·가격·체결 시각을 빠짐없이 표시한다.
      let share = try XCTUnwrap(try loadNib("PNLShareView") as? PNLShareView)
      share.configure(pnlShareUnit: PNLShareUnit(
        marketName: "BTC/KRW",
        roi: 123_456.78,
        pnl: 1_234_567_890_123_456,
        quantity: 1_234_567_890_123_456,
        entryPrice: 1_234_567_890_123_456,
        exitPrice: 1_234_567_890_123_457,
        transactionDate: "2026.10.20 12:34:56",
        product: .perpetual,
        exchange: .upbit
      ))
      // 작은 화면에서도 닫기와 저장·공유에 접근할 수 있어야 한다.
      let controller = UIViewController()
      controller.view = share
      // 320pt 기기는 568pt의 실제 작은 화면 높이를 사용한다.
      let window = host(controller, width: width)
      defer { window.isHidden = true; window.rootViewController = nil }
      share.layoutIfNeeded()
      assertLabelsFit(in: share.pnlView)
      // 오른쪽 로고의 원래 비율을 줄여 긴 값의 공간을 확보하면 안 된다.
      let logo = try XCTUnwrap(share.pnlView.subviews.compactMap { $0 as? UIImageView }.first)
      XCTAssertEqual(logo.bounds.width, 44, accuracy: 1)
      XCTAssertEqual(logo.bounds.height, 214, accuracy: 1)
      XCTAssertFalse(logo.hasAmbiguousLayout)
      for label in [share.marketName, share.roiLabel, share.pnlLabel, share.entryPriceLabel, share.exitPriceLabel, share.quantityLabel, share.transactionDateLabel] {
        // 자산 숫자와 줄바꿈된 마켓명이 공유 카드 밖으로 넘치지 않아야 한다.
        let value = try XCTUnwrap(label)
        // 카드 내부 좌표계로 모든 동적 텍스트의 경계를 비교한다.
        let frame = value.convert(value.bounds, to: share.pnlView)
        XCTAssertGreaterThanOrEqual(frame.minX, 15 - 1)
        XCTAssertLessThanOrEqual(frame.maxX, share.pnlView.bounds.width - 15 + 1)
      }
      // 화면 밖 카드가 있으면 스크롤을 통해 하단 제어에 도달할 수 있어야 한다.
      let cardFrame = share.pnlView.convert(share.pnlView.bounds, to: share)
      if let scroll = descendants(share).compactMap({ $0 as? UIScrollView }).first {
        XCTAssertEqual(scroll.contentSize.width, scroll.bounds.width, accuracy: 1)
        XCTAssertGreaterThanOrEqual(scroll.contentSize.height + 1, scroll.bounds.height)
        XCTAssertGreaterThanOrEqual(cardFrame.minY, share.safeAreaLayoutGuide.layoutFrame.minY - 1)
        attach(share, name: "PNLShare-long-values-top-\(Int(width))")
        scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)), animated: false)
        share.layoutIfNeeded()
        XCTAssertLessThanOrEqual(
          share.buttonStackView.convert(share.buttonStackView.bounds, to: share).maxY,
          share.safeAreaLayoutGuide.layoutFrame.maxY + 1
        )
      } else {
        XCTAssertGreaterThanOrEqual(cardFrame.minY, share.safeAreaLayoutGuide.layoutFrame.minY - 1)
        XCTAssertLessThanOrEqual(share.buttonStackView.convert(share.buttonStackView.bounds, to: share).maxY, share.safeAreaLayoutGuide.layoutFrame.maxY + 1)
      }
      attach(share, name: "PNLShare-long-values-bottom-\(Int(width))")
      attach(share.pnlView, name: "PNLShare-complete-card-\(Int(width))")

      // 저장 오류 문구는 XIB의 중앙 정렬만으로 너비가 정해지지 않던 사례다.
      let owner = InvestmentLayoutNibOwner()
      // 거래 내역 화면의 네트워크·저장소 접근 없이 오류 UI만 구성한다.
      let root = try loadNib("PNLViewController", owner: owner)
      root.frame = CGRect(x: 0, y: 0, width: width, height: 568)
      // 양쪽 언어의 오류 문구가 모두 여러 줄로 표시될 수 있어야 한다.
      let message = try XCTUnwrap(owner.outlets["emptyLabel"] as? UILabel)
      message.text = "Unable to read saved assets. Retry without resetting your data."
      root.layoutIfNeeded()
      XCTAssertLessThanOrEqual(message.bounds.width, width - 32 + 1)
      assertLabelsFit(in: try XCTUnwrap(owner.outlets["noResultView"] as? UIView))
    }
  }

  func testShareImageIncludesCardTallerThanScreen() throws {
    for width: CGFloat in [320, 393, 440] {
      // 일반 카드와 화면보다 긴 본문 모두 기존 중심 위치와 출력 크기를 검사한다.
      let share = try XCTUnwrap(try loadNib("PNLShareView") as? PNLShareView)
      // 미리보기와 저장 캔버스를 실제 표시 환경에서 비교한다.
      let controller = UIViewController()
      controller.view = share
      // 작은 기기부터 넓은 화면까지 같은 카드 중심 정책을 사용한다.
      let window = host(controller, width: width)
      defer { window.isHidden = true; window.rootViewController = nil }
      share.layoutIfNeeded()
      // 원본 XIB는 카드와 버튼을 합친 스택의 중심을 root 중심에 연결했다.
      let stack = try XCTUnwrap(share.pnlView.superview as? UIStackView)
      // Safe Area 안에서 root 중심을 유지할 수 있는 최대 세로 영역이다.
      let safeFrame = share.safeAreaLayoutGuide.layoutFrame
      // 양쪽 중 더 큰 안전 여백을 대칭으로 확보한다.
      let centeredHeight = share.bounds.height - 2 * max(safeFrame.minY, share.bounds.maxY - safeFrame.maxY)
      if stack.bounds.height <= centeredHeight + 1 {
        XCTAssertEqual(stack.convert(stack.bounds, to: share).midY, share.bounds.midY, accuracy: 1)
      }
      // 일반 카드의 기존 화면 크기 출력 형식은 바뀌지 않아야 한다.
      let normalImage = try XCTUnwrap(share.makeShareImage())
      if width == 320 { XCTAssertEqual(normalImage.size, UIScreen.main.bounds.size) }
      guard width == 320 else { continue }
      share.marketName.text = Array(repeating: "BTC/KRW · Long market description", count: 45).joined(separator: "\n")
      share.setNeedsLayout()
      share.layoutIfNeeded()
      XCTAssertGreaterThan(share.pnlView.bounds.height, UIScreen.main.bounds.height)
      // 버튼이 호출하는 실제 공유 이미지 생성 경로다.
      let image = try XCTUnwrap(share.makeShareImage())
      XCTAssertGreaterThanOrEqual(image.size.height, share.pnlView.bounds.height + 32)
      XCTAssertGreaterThanOrEqual(image.size.width, share.pnlView.bounds.width + 32)
      // 출력 이미지 자체를 보존해 위·아래 카드 경계도 직접 확인한다.
      let attachment = XCTAttachment(image: image)
      attachment.name = "PNLShare-export-taller-than-screen"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }

  private func loadNib(_ name: String, owner: InvestmentLayoutNibOwner? = nil) throws -> UIView {
    // IBOutlet을 보존한 채 화면 생명주기 없이 실제 뷰 계층을 만든다.
    let objects = UINib(nibName: name, bundle: Bundle(for: PNLShareView.self))
      .instantiate(withOwner: owner, options: nil)
    return try XCTUnwrap(objects.compactMap { $0 as? UIView }.first)
  }

  private func host(_ controller: UIViewController, width: CGFloat) -> UIWindow {
    // 동적 글꼴과 Safe Area가 실제 표시 계층에서 계산되도록 한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: width == 320 ? 568 : 852))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
    controller.view.layoutIfNeeded()
    return window
  }

  private func assertPNLLabelsFit(in cell: PNLTableViewCell) {
    // 실현손익과 수익률도 제목 옆에서 값을 한 줄로 표시한다.
    let summaryValues: [UILabel] = [cell.pnlLabel, cell.roiLabel]
    // 상세 지표의 항목명·값은 한 줄 축소를 허용한다.
    let detailValues: [UILabel] = [cell.quantityLabel, cell.entryPriceLabel, cell.exitPriceLabel, cell.marginLabel]
    // 요약과 상세 지표에 같은 행 정렬 검증을 적용한다.
    let inlineValues = summaryValues + detailValues
    // 숨겨진 증거금 항목은 일반 라벨 검사와 같은 가시성 규칙을 따른다.
    let inlineLabels = inlineValues.flatMap { ($0.superview as? UIStackView)?.arrangedSubviews.compactMap { $0 as? UILabel } ?? [] }
    // 헤더와 날짜의 기존 한 줄 배치도 계속 검사한다.
    let compactLabels: [UILabel] = [cell.marketNameLabel, cell.positionBadgeLabel, cell.statusLabel, cell.transactionDateLabel] + inlineLabels
    assertLabelsFit(
      in: cell.contentView,
      scaledSingleLineLabels: compactLabels
    )
    for value in inlineValues where isVisible(value) {
      guard let title = (value.superview as? UIStackView)?.arrangedSubviews.first as? UILabel else {
        XCTFail("지표 항목명과 값은 같은 스택에 있어야 한다.")
        continue
      }
      // 셀 좌표계에서 두 라벨이 같은 행에 있고 겹치지 않는지 확인한다.
      let titleFrame = title.convert(title.bounds, to: cell.contentView)
      // 값은 각 지표 영역의 오른쪽에 정렬한다.
      let valueFrame = value.convert(value.bounds, to: cell.contentView)
      XCTAssertEqual(titleFrame.midY, valueFrame.midY, accuracy: 1)
      XCTAssertLessThanOrEqual(titleFrame.maxX, valueFrame.minX)
      XCTAssertEqual(value.textAlignment, .right)
    }
    for (summaryValue, detailValue) in zip(summaryValues, [cell.quantityLabel, cell.entryPriceLabel]) {
      // 요약 두 열은 바로 아래 상세 지표의 좌우 경계를 따라야 한다.
      guard let summaryMetric = summaryValue.superview, let detailMetric = detailValue?.superview else {
        XCTFail("요약과 상세 지표의 열이 모두 있어야 한다.")
        continue
      }
      // 서로 다른 부모의 좌우 경계를 셀 좌표계에서 비교한다.
      let summaryFrame = summaryMetric.convert(summaryMetric.bounds, to: cell.contentView)
      // 같은 열에 놓인 상세 지표의 전체 영역이다.
      let detailFrame = detailMetric.convert(detailMetric.bounds, to: cell.contentView)
      XCTAssertEqual(summaryFrame.minX, detailFrame.minX, accuracy: 1)
      XCTAssertEqual(summaryFrame.maxX, detailFrame.maxX, accuracy: 1)
    }
    // 서로 다른 컨테이너의 행 정렬을 동일한 셀 좌표계에서 비교한다.
    let marketFrame = cell.marketNameLabel.convert(cell.marketNameLabel.bounds, to: cell.contentView)
    // 날짜와 공유 버튼은 글자 크기와 관계없이 같은 푸터 행에 남아야 한다.
    let dateFrame = cell.transactionDateLabel.convert(cell.transactionDateLabel.bounds, to: cell.contentView)
    // 버튼의 최소 터치 영역을 포함한 실제 프레임이다.
    let shareFrame = cell.shareButton.convert(cell.shareButton.bounds, to: cell.contentView)
    XCTAssertEqual(dateFrame.midY, shareFrame.midY, accuracy: 1)
    XCTAssertLessThanOrEqual(dateFrame.maxX, shareFrame.minX)
    if !cell.positionBadgeView.isHidden && !cell.statusLabel.isHidden {
      // 배경 여백까지 포함한 배지 영역이 이웃 텍스트와 겹치면 안 된다.
      let badgeFrame = cell.positionBadgeView.convert(cell.positionBadgeView.bounds, to: cell.contentView)
      // 종료 상태는 종목·배지와 같은 행의 오른쪽에 배치한다.
      let statusFrame = cell.statusLabel.convert(cell.statusLabel.bounds, to: cell.contentView)
      XCTAssertEqual(marketFrame.midY, badgeFrame.midY, accuracy: 1)
      XCTAssertEqual(marketFrame.midY, statusFrame.midY, accuracy: 1)
      XCTAssertLessThanOrEqual(marketFrame.maxX, badgeFrame.minX)
      XCTAssertLessThanOrEqual(badgeFrame.maxX, statusFrame.minX)
    }
  }

  private func assertLabelsFit(
    in root: UIView,
    scaledSingleLineLabels: [UILabel] = []
  ) {
    for label in descendants(root).compactMap({ $0 as? UILabel }) where isVisible(label) && !(label.text ?? "").isEmpty {
      XCTAssertGreaterThan(label.bounds.width, 0, label.text ?? "")
      if scaledSingleLineLabels.contains(where: { $0 === label }) {
        XCTAssertEqual(label.numberOfLines, 1)
        XCTAssertTrue(label.adjustsFontSizeToFitWidth)
        XCTAssertFalse(label.adjustsFontForContentSizeCategory)
        XCTAssertGreaterThan(label.minimumScaleFactor, 0)
        // 숫자와 단위의 개별 글씨 크기에 같은 최소 축소 비율을 적용한다.
        let minimumText = NSMutableAttributedString(
          string: label.text ?? "",
          attributes: [.font: label.font.withSize(label.font.pointSize * label.minimumScaleFactor)]
        )
        label.attributedText?.enumerateAttribute(
          .font,
          in: NSRange(location: 0, length: minimumText.length)
        ) { value, range, _ in
          // 단위에 지정한 작은 폰트도 실제 표시 비율로 측정한다.
          guard let font = value as? UIFont else { return }
          minimumText.addAttribute(
            .font,
            value: font.withSize(font.pointSize * label.minimumScaleFactor),
            range: range
          )
        }
        // 허용된 최소 글씨에서도 전체 문자열을 표시할 수 있는지 검사한다.
        let minimumTextSize = minimumText.size()
        XCTAssertLessThanOrEqual(minimumTextSize.width, label.bounds.width + 1, label.text ?? "")
        XCTAssertLessThanOrEqual(minimumTextSize.height, label.bounds.height + 1, label.text ?? "")
      } else {
        XCTAssertGreaterThanOrEqual(
          label.bounds.height + 1,
          label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height,
          label.text ?? ""
        )
      }
      XCTAssertFalse(label.hasAmbiguousLayout, label.text ?? "")
    }
  }

  private func isVisible(_ view: UIView) -> Bool {
    !sequence(first: view, next: { $0.superview }).contains { $0.isHidden || $0.alpha == 0 }
  }

  private func descendants(_ view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }

  private func attach(_ view: UIView, name: String) {
    // 제약 검사와 별개로 잘림·겹침을 직접 검토할 이미지를 보존한다.
    let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: view.bounds).image { view.layer.render(in: $0.cgContext) })
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}

@MainActor
private final class InvestmentLayoutNibOwner: NSObject {
  // XIB가 연결한 화면 객체를 검사하는 동안 유지한다.
  var outlets: [String: Any] = [:]

  override func setValue(_ value: Any?, forUndefinedKey key: String) {
    outlets[key] = value
  }
}

@MainActor
private final class InvestmentLayoutTableSource: NSObject, UITableViewDataSource {
  // 실제 테이블의 자동 높이 계산에 전달할 구성 완료된 셀이다.
  let cell: UITableViewCell

  init(cell: UITableViewCell) {
    self.cell = cell
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { cell }
}
