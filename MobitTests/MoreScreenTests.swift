import XCTest
import GoogleMobileAds
import UIKit
import RxSwift
@testable import Mobit

final class MoreScreenTests: XCTestCase {
  func testReadsFourIndependentCashBalancesWithoutChangingSelection() throws {
    // 현재 선택이 목록 조회 결과나 충전 대상에 영향을 주지 않아야 한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    // 다른 테스트가 사용하던 모드를 돌려준다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    defer {
      ExchangeSelectionStore.currentExchange = previousExchange
      ExchangeSelectionStore.currentProduct = previousProduct
    }
    ExchangeSelectionStore.currentExchange = .bithumb
    ExchangeSelectionStore.currentProduct = .perpetual
    // 한 번의 전체 조회가 선물 저장소를 반복해서 열지 않는지 검사한다.
    var futureReads = 0
    // 현물 거래소가 서로 다른 잔고를 유지하는지 확인한다.
    var spotReads: [Exchange] = []
    // 읽기만 하는 실제 사용 사례를 동기 테스트 스케줄러에 연결한다.
    let useCase = MoreAccountsUseCase(
      spotBalance: { spotReads.append($0); return $0 == .upbit ? 123 : 456 },
      futuresSnapshot: {
        futureReads += 1
        return FuturesAccountSnapshot(revision: 0, accounts: [
          FuturesCashAccount(id: MoreAccountsUseCase.accounts[1], availableBalance: 789),
          FuturesCashAccount(id: MoreAccountsUseCase.accounts[3], availableBalance: 987)
        ])
      },
      scheduler: CurrentThreadScheduler.instance
    )
    XCTAssertEqual(try read(useCase).map(\.availableBalance), [123, 789, 456, 987])
    XCTAssertEqual(spotReads, [.upbit, .bithumb])
    XCTAssertEqual(futureReads, 1)
    XCTAssertEqual(ExchangeSelectionStore.currentExchange, .bithumb)
    XCTAssertEqual(ExchangeSelectionStore.currentProduct, .perpetual)
  }

  func testMissingFuturesAccountIsZeroAndDoesNotCreateOrFundIt() throws {
    // 미생성 계좌의 잔고를 읽고도 원본 스냅샷은 그대로여야 한다.
    let snapshot = FuturesAccountSnapshot(revision: 0, accounts: [])
    // 현물과 선물 모두 미충전인 정상 상태다.
    let useCase = MoreAccountsUseCase(spotBalance: { _ in 0 }, futuresSnapshot: { snapshot }, scheduler: CurrentThreadScheduler.instance)
    XCTAssertEqual(try read(useCase).map(\.availableBalance), [0, 0, 0, 0])
    XCTAssertTrue(snapshot.accounts.isEmpty)
  }

  func testStorageFailureDoesNotDisplayZeroOrHideOtherProductBalances() throws {
    // 계좌 목록은 저장 실패를 실제 잔고 0원과 구분해야 한다.
    let useCase = MoreAccountsUseCase(
      spotBalance: { $0 == .upbit ? 20 : 30 },
      futuresSnapshot: { throw AdRewardError.invalidStoredData },
      scheduler: CurrentThreadScheduler.instance
    )
    XCTAssertEqual(try read(useCase).map(\.availableBalance), [20, nil, 30, nil])
    // 잘못된 숫자는 정상 주문 가능 금액으로 표시하지 않는다.
    let invalid = MoreAccountsUseCase(
      spotBalance: { _ in -1 },
      futuresSnapshot: { FuturesAccountSnapshot(revision: 0, accounts: []) },
      scheduler: CurrentThreadScheduler.instance
    )
    XCTAssertEqual(try read(invalid).map(\.availableBalance), [nil, 0, nil, 0])
  }

  func testSpotCashReadDistinguishesUnfundedAccountAndCorruptStorage() throws {
    // 사용자 저장값은 이 읽기 검사가 끝난 뒤 원본으로 복구한다.
    let keys = [UserDataManager.Keys.userInformationByExchange, UserDataManager.Keys.userInformation, UserDataManager.Keys.pendingInvestmentState]
    // 기존 계좌 저장 형식을 변경하지 않고 정상/손상 읽기만 검사한다.
    let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
    defer { for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) } }
    UserDefaults.standard.removeObject(forKey: UserDataManager.Keys.pendingInvestmentState)
    UserDefaults.standard.set(try JSONEncoder().encode(["upbit": MobitUserInformation(userAvailableBalance: 123)]), forKey: keys[0])
    XCTAssertEqual(try UserDataManager.getAvailableBalance(for: .upbit), 123)
    XCTAssertEqual(try UserDataManager.getAvailableBalance(for: .bithumb), 0)
    // 읽기 실패 뒤 원본 바이트를 덮어쓰거나 새 자금을 지급하면 안 된다.
    let corrupt = Data("invalid".utf8)
    UserDefaults.standard.set(corrupt, forKey: keys[0])
    XCTAssertThrowsError(try UserDataManager.getAvailableBalance(for: .upbit))
    XCTAssertEqual(UserDefaults.standard.data(forKey: keys[0]), corrupt)
  }

  @MainActor
  func testMoreBannerUsesAvailableWidthAndPreservesAccountChargeButtons() throws {
    // 레이아웃 갱신이 광고 요청을 반복하지 않는지 실제 요청 크기를 수집한다.
    var requestedSizes: [AdSize] = []
    // 보상형 광고와 배너 광고를 각각 외부 요청 없이 검사한다.
    let controller = MoreViewController(
      accountsUseCase: fixture(),
      presentRewardedAd: { _, _ in XCTFail("Banner must not start a rewarded ad") },
      loadBannerAd: { requestedSizes.append($0.adSize) }
    )
    // 최초 가용 폭이 기본 배너와 같은 320pt여도 광고 요청을 생략하지 않는다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 360, height: 568))
    window.rootViewController = controller
    controller.view.frame = window.bounds
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 중앙 영역이 SDK 배너를 직접 담으며 충전 안내 카드로 남지 않아야 한다.
    let container = try XCTUnwrap(find(controller.view, "more.banner.container"))
    // 네트워크 응답과 무관하게 실제 SDK 배너 설정을 확인한다.
    let banner = try XCTUnwrap(container.subviews.first as? BannerView)
    // 광고와 로딩 콘텐츠도 계좌·메뉴 카드와 동일한 모서리 안에 표시한다.
    let accountCard = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? MoreCardView }.first { $0 !== container })
    XCTAssertEqual(container.layer.cornerRadius, accountCard.layer.cornerRadius)
    XCTAssertEqual(container.layer.cornerCurve, accountCard.layer.cornerCurve)
    XCTAssertTrue(container.clipsToBounds)
    XCTAssertEqual(banner.adUnitID, MobitConstants.bannerAdType)
    XCTAssertTrue(banner.rootViewController === controller)
    XCTAssertTrue(banner.delegate === controller)
    for width: CGFloat in [360, 320, 393] {
      window.frame.size.width = width
      window.setNeedsLayout()
      window.layoutIfNeeded()
      controller.view.layoutIfNeeded()
      waitUntil { requestedSizes.last?.size.width == floor(container.bounds.width) }
      // 현재 콘텐츠 폭과 SDK의 inline adaptive 요청 폭이 같아야 한다.
      let expectedSize = inlineAdaptiveBanner(width: floor(container.bounds.width), maxHeight: AdSizeLargeBanner.size.height)
      XCTAssertTrue(isAdSizeEqualToSize(size1: banner.adSize, size2: expectedSize))
      XCTAssertEqual(banner.bounds.width, container.bounds.width, accuracy: 0.5)
      XCTAssertLessThanOrEqual(banner.convert(banner.bounds, to: controller.view).maxX, width)
      XCTAssertGreaterThanOrEqual(banner.convert(banner.bounds, to: controller.view).minX, 0)
      // 잔고 갱신이나 동일 폭의 반복 레이아웃은 추가 광고 요청을 만들지 않는다.
      let requestCount = requestedSizes.count
      controller.view.setNeedsLayout()
      controller.view.layoutIfNeeded()
      // 다음 메인 큐에서 측정하는 광고 요청까지 끝난 뒤 중복 여부를 확인한다.
      let settled = expectation(description: "Banner layout settled")
      DispatchQueue.main.async { settled.fulfill() }
      wait(for: [settled], timeout: 3)
      XCTAssertEqual(requestedSizes.count, requestCount)
      for account in MoreAccountsUseCase.accounts {
        XCTAssertNotNil(find(controller.view, "more.charge.\(account.exchange.rawValue).\(account.product.rawValue)") as? UIButton)
      }
      XCTAssertFalse(banner.hasAmbiguousLayout)
      XCTAssertFalse(container.hasAmbiguousLayout)
      XCTAssertNil(controller.presentedViewController)
      XCTAssertFalse(MobitBaseViewController.isLoadingIndicatorVisible(in: window))
    }
    XCTAssertEqual(requestedSizes.map(\.size.width), [320, 280, 353])
  }

  @MainActor
  func testResetMenuOffersFourAccountsWithoutChangingSelectionOrStartingAds() throws {
    // 계좌 선택을 여는 동안 앱의 현재 거래 모드는 유지한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    // 현물·선물 초기화 대상을 앱의 현재 상품 선택과 분리한다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    defer {
      ExchangeSelectionStore.currentExchange = previousExchange
      ExchangeSelectionStore.currentProduct = previousProduct
    }
    ExchangeSelectionStore.currentExchange = .bithumb
    ExchangeSelectionStore.currentProduct = .perpetual
    // 초기화 진입에는 보상형 광고가 시작되면 안 된다.
    let controller = MoreViewController(
      accountsUseCase: fixture(),
      presentRewardedAd: { _, _ in XCTFail("Reset selection must not start an ad") },
      loadBannerAd: { _ in }
    )
    // 실제 메뉴 액션과 시스템 시트를 같은 창에서 확인한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 메뉴를 두 번 눌러도 하나의 계좌 선택창만 표시한다.
    let resetButton = try XCTUnwrap(find(controller.view, "more.reset") as? UIButton)
    resetButton.sendActions(for: .touchUpInside)
    // 거래소와 상품이 모두 명시된 네 선택지를 확인한다.
    let picker = try XCTUnwrap(controller.presentedViewController as? MoreAccountResetViewController)
    resetButton.sendActions(for: .touchUpInside)
    XCTAssertTrue(controller.presentedViewController === picker)
    XCTAssertEqual(picker.modalPresentationStyle, .pageSheet)
    XCTAssertEqual(picker.sheetPresentationController?.prefersGrabberVisible, true)
    for account in MoreAccountsUseCase.accounts {
      XCTAssertNotNil(find(picker.view, "reset.account.\(account.exchange.rawValue).\(account.product.rawValue)") as? UIControl)
    }
    XCTAssertNotNil(find(picker.view, "reset.cancel") as? UIButton)
    XCTAssertNotNil(find(picker.view, "reset.confirm") as? UIButton)
    XCTAssertEqual(ExchangeSelectionStore.currentExchange, .bithumb)
    XCTAssertEqual(ExchangeSelectionStore.currentProduct, .perpetual)
    waitUntil { !picker.isBeingPresented }
    picker.dismiss(animated: false)
    waitUntil { controller.presentedViewController == nil }
  }

  @MainActor
  func testMoreLayoutScrollsInSmallScreensBothThemesAndLargeText() throws {
    // 계좌 선택을 테스트 전 상태로 복구한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    // 상품 선택도 테스트 전 상태로 함께 복구한다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    defer {
      ExchangeSelectionStore.currentExchange = previousExchange
      ExchangeSelectionStore.currentProduct = previousProduct
    }
    ExchangeSelectionStore.currentExchange = .upbit
    ExchangeSelectionStore.currentProduct = .spot
    for width: CGFloat in [320, 393] {
      for style in [UIUserInterfaceStyle.light, .dark] {
        // 실제 XIB와 메뉴·계좌 뷰를 외부 광고 요청 없이 렌더링한다.
        let controller = MoreViewController(accountsUseCase: fixture(), presentRewardedAd: { _, _ in XCTFail("Layout must not start an ad") }, loadBannerAd: { _ in })
        // 작은 화면에서도 모든 카드가 세로 스크롤로 이어져야 한다.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: width == 320 ? 568 : 852))
        // 앱과 같은 커스텀 탭바에서도 마지막 메뉴가 가려지지 않아야 한다.
        let tabs = MobitTabBarViewController()
        tabs.setViewControllers([
          UIViewController(), UIViewController(), UIViewController(),
          UINavigationController(rootViewController: controller)
        ], selectedIndex: 3)
        window.rootViewController = tabs
        window.overrideUserInterfaceStyle = style
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        waitUntil { (self.find(controller.view, "more.balance.upbit.spot") as? UILabel)?.text != "—" }
        for large in [false, true] {
          if #available(iOS 17.0, *) {
            controller.traitOverrides.preferredContentSizeCategory = large ? .accessibilityExtraExtraExtraLarge : .large
            controller.updateTraitsIfNeeded()
          }
          window.layoutIfNeeded()
          controller.view.layoutIfNeeded()
          // 실제 화면 전체의 스크롤 컨테이너다.
          let scroll = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIScrollView }.first)
          XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
          XCTAssertEqual(scroll.contentSize.width, scroll.bounds.width, accuracy: 1)
          XCTAssertLessThanOrEqual(scroll.convert(scroll.bounds, to: tabs.view).maxY, tabs.mobitTabBar.frame.minY)
          for account in MoreAccountsUseCase.accounts {
            // 각 충전 버튼은 44pt 이상이고 화면 가로 경계 안에 남아야 한다.
            let button = try XCTUnwrap(find(controller.view, "more.charge.\(account.exchange.rawValue).\(account.product.rawValue)") as? UIButton)
            XCTAssertGreaterThanOrEqual(button.bounds.width, 44)
            XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
            // 카드 밖으로 벗어난 버튼은 스크롤해도 누를 수 없다.
            let frame = button.convert(button.bounds, to: controller.view)
            XCTAssertGreaterThanOrEqual(frame.minX, 0)
            XCTAssertLessThanOrEqual(frame.maxX, width + 1)
          }
          for row in descendants(controller.view).compactMap({ $0 as? MoreMenuButton }) {
            XCTAssertFalse(row.hasAmbiguousLayout)
            XCTAssertGreaterThanOrEqual(row.bounds.height, 44)
            for label in descendants(row).compactMap({ $0 as? UILabel }).filter({ !$0.isHidden && !($0.text ?? "").isEmpty }) {
              XCTAssertGreaterThan(label.bounds.width, 0)
              XCTAssertGreaterThanOrEqual(label.bounds.height + 1, label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height)
            }
          }
          // 현재 계좌와 초기화 경고가 같은 인라인 배지 배치를 유지해야 한다.
          for badgeKey in ["more_current_account", "more_caution"] {
            // 숨겨진 다른 계좌의 배지를 제외하고 실제 표시되는 문구를 찾는다.
            let badge = try XCTUnwrap(
              descendants(controller.view).compactMap { $0 as? UILabel }.first {
                !$0.isHidden && $0.text == FuturesText.text(badgeKey)
              }
            )
            if badgeKey == "more_current_account" {
              // 현재 사용 표시는 선택한 업비트 현물 행 안에 있어야 한다.
              let currentAccount = try XCTUnwrap(find(controller.view, "more.account.upbit.spot"))
              XCTAssertTrue(descendants(currentAccount).contains { $0 === badge })
            }
            // 현재 테마에서 배경이 투명해지거나 사라지지 않아야 한다.
            let badgeBackground = try XCTUnwrap(badge.backgroundColor)
            XCTAssertGreaterThan(badgeBackground.resolvedColor(with: badge.traitCollection).cgColor.alpha, 0)
            XCTAssertGreaterThan(badge.layer.cornerRadius, 0)
            XCTAssertGreaterThan(badge.bounds.width, 0)
            XCTAssertGreaterThan(badge.bounds.height, 0)
            XCTAssertGreaterThanOrEqual(
              badge.bounds.height + 1,
              badge.sizeThatFits(CGSize(width: badge.bounds.width, height: .greatestFiniteMagnitude)).height
            )
            // 배지는 관련 제목과 같은 행에 있어야 한다.
            let heading = try XCTUnwrap(badge.superview)
            // 바로 앞 제목을 찾아 다른 열이나 카드 끝으로 떨어지지 않는지 확인한다.
            let title = try XCTUnwrap(heading.subviews.compactMap { $0 as? UILabel }.first { $0 !== badge })
            // 한 줄로 들어갈 제목이 불필요하게 늘어나거나 줄바꿈하지 않아야 한다.
            let titleFont = try XCTUnwrap(title.font)
            // 현재 글꼴로 표시할 제목의 한 줄 크기를 기준으로 비교한다.
            let titleSize = (title.text ?? "").size(withAttributes: [.font: titleFont])
            if titleSize.width + badge.bounds.width + 8 <= heading.bounds.width + 1 {
              XCTAssertEqual(title.bounds.width, titleSize.width, accuracy: 1)
              XCTAssertLessThanOrEqual(title.bounds.height, titleFont.lineHeight + 1)
            }
            XCTAssertEqual(badge.frame.minX - title.frame.maxX, 8, accuracy: 1)
            XCTAssertEqual(badge.frame.midY, title.frame.midY, accuracy: 1)
            XCTAssertLessThanOrEqual(badge.frame.maxX, heading.bounds.maxX + 1)
            XCTAssertFalse(heading.hasAmbiguousLayout)
            XCTAssertFalse(title.hasAmbiguousLayout)
            XCTAssertFalse(badge.hasAmbiguousLayout)
          }
          XCTAssertFalse(MobitBaseViewController.isLoadingIndicatorVisible(in: window))
          for bottom in [false, true] {
            scroll.setContentOffset(CGPoint(x: 0, y: bottom ? max(0, scroll.contentSize.height - scroll.bounds.height) : 0), animated: false)
            // 결과 파일에서 상단 계좌·하단 메뉴를 두 테마로 비교할 수 있게 남긴다.
            let capture = XCTAttachment(image: UIGraphicsImageRenderer(bounds: tabs.view.bounds).image { tabs.view.layer.render(in: $0.cgContext) })
            capture.name = "More-\(Int(width))-\(style == .dark ? "dark" : "light")-\(large ? "large" : "normal")-\(bottom ? "bottom" : "top")"
            capture.lifetime = .keepAlways
            add(capture)
          }
        }
      }
    }
  }

  @MainActor
  func testSettingsSheetFitsSmallScreensBothThemesAndLargeText() throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Trait overrides require iOS 17") }
    // 작은 화면과 일반 화면에서 같은 실제 설정 진입 경로를 검사한다.
    for width: CGFloat in [320, 393] {
      // 선택한 앱 테마와 별개로 두 표시 테마의 색상과 배치를 확인한다.
      for style in [UIUserInterfaceStyle.light, .dark] {
        // 외부 광고 없이 실제 더보기 화면에서 설정을 연다.
        let controller = MoreViewController(accountsUseCase: fixture(), presentRewardedAd: { _, _ in XCTFail("Settings must not start an ad") }, loadBannerAd: { _ in })
        // 하단 시트가 작은 화면의 상하 경계를 넘지 않는지 검사한다.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: width == 320 ? 568 : 852))
        window.rootViewController = controller
        window.overrideUserInterfaceStyle = style
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        // 메뉴 버튼의 기존 액션으로 비공개 설정 화면을 표시한다.
        let settingsButton = try XCTUnwrap(find(controller.view, "more.settings") as? UIButton)
        settingsButton.sendActions(for: .touchUpInside)
        waitUntil(timeout: 8) { controller.presentedViewController != nil && controller.presentedViewController?.isBeingPresented == false }
        // 실제 표시한 화면에 글자 크기와 레이아웃 검증을 적용한다.
        let settings = try XCTUnwrap(controller.presentedViewController)
        // 시스템 시트가 표시와 확장·닫기 동작을 담당해야 한다.
        let sheet = try XCTUnwrap(settings.sheetPresentationController)
        XCTAssertEqual(settings.modalPresentationStyle, .pageSheet)
        XCTAssertFalse(sheet.detents.isEmpty)
        XCTAssertTrue(sheet.prefersGrabberVisible)
        XCTAssertFalse(settings.isModalInPresentation)
        // 기본 글씨와 최대 접근성 글씨를 같은 시트에서 차례로 검증한다.
        for large in [false, true] {
          settings.traitOverrides.preferredContentSizeCategory = large ? .accessibilityExtraExtraExtraLarge : .large
          settings.updateTraitsIfNeeded()
          window.layoutIfNeeded()
          settings.view.layoutIfNeeded()
          // 화면 상하를 제한하는 실제 카드다.
          let card = try XCTUnwrap(find(settings.view, "settings.card"))
          // 설정 본문만 스크롤되고 제목과 동작 버튼은 남아야 한다.
          let scroll = try XCTUnwrap(find(settings.view, "settings.scroll") as? UIScrollView)
          // 취소와 적용이 스크롤 바깥에 유지되는 하단 행이다.
          let actions = try XCTUnwrap(find(settings.view, "settings.actions") as? UIStackView)
          // 카드 위치를 설정 화면의 Safe Area와 같은 좌표계에서 비교한다.
          let cardFrame = card.convert(card.bounds, to: settings.view)
          // 홈 표시기와 상태 표시줄을 제외한 사용 가능 영역이다.
          let safeFrame = settings.view.safeAreaLayoutGuide.layoutFrame
          // 본문 아래에 고정 동작 행이 유지되는지 확인한다.
          let scrollFrame = scroll.convert(scroll.bounds, to: settings.view)
          // 적용 버튼을 찾기 위해 본문을 스크롤할 필요가 없어야 한다.
          let actionsFrame = actions.convert(actions.bounds, to: settings.view)
          XCTAssertGreaterThanOrEqual(cardFrame.minX, safeFrame.minX - 1)
          XCTAssertGreaterThanOrEqual(cardFrame.minY, safeFrame.minY - 1)
          XCTAssertLessThanOrEqual(cardFrame.maxX, safeFrame.maxX + 1)
          XCTAssertLessThanOrEqual(cardFrame.maxY, safeFrame.maxY + 1)
          XCTAssertGreaterThan(scroll.bounds.height, 0)
          XCTAssertEqual(scroll.contentSize.width, scroll.bounds.width, accuracy: 1)
          // 본문이 모두 들어갈 때 시스템 시트 아래에 불필요한 빈 공간을 남기지 않는다.
          if scroll.contentSize.height <= scroll.bounds.height + 1 {
            XCTAssertEqual(scroll.bounds.height, scroll.contentSize.height, accuracy: 3)
          }
          if large { XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height) }
          XCTAssertLessThanOrEqual(scrollFrame.maxY, actionsFrame.minY + 1)
          XCTAssertLessThanOrEqual(actionsFrame.maxY, cardFrame.maxY + 1)
          XCTAssertFalse(card.hasAmbiguousLayout)
          XCTAssertFalse(scroll.hasAmbiguousLayout)
          XCTAssertFalse(actions.hasAmbiguousLayout)
          // 장식 아이콘 크기와 별개로 실제 누르는 컨트롤은 44pt를 확보한다.
          for identifier in [
            "settings.close", "settings.cancel", "settings.apply",
            "settings.theme.system", "settings.theme.light", "settings.theme.dark",
            "settings.palette.riseRedFallBlue", "settings.palette.riseGreenFallRed"
          ] {
            // 표시 중인 컨트롤을 실제 버튼·옵션 영역으로 검사한다.
            let control = try XCTUnwrap(find(settings.view, identifier) as? UIControl)
            XCTAssertGreaterThanOrEqual(control.bounds.width, 44, identifier)
            XCTAssertGreaterThanOrEqual(control.bounds.height, 44, identifier)
            XCTAssertFalse(control.hasAmbiguousLayout, identifier)
          }
          // 숨긴 보조 문구를 제외하고 본문과 버튼의 실제 텍스트가 잘리지 않아야 한다.
          for label in descendants(card).compactMap({ $0 as? UILabel }).filter({
            !($0.text ?? "").isEmpty && !sequence(first: $0 as UIView, next: { $0.superview }).contains { $0.isHidden || $0.alpha == 0 }
          }) {
            XCTAssertGreaterThan(label.bounds.width, 0, label.text ?? "")
            XCTAssertGreaterThanOrEqual(
              label.bounds.height + 1,
              label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height,
              label.text ?? ""
            )
          }
          // 본문 위와 아래를 남겨 고정 헤더·하단 동작과 긴 글씨를 육안 확인한다.
          for bottom in [false, true] {
            scroll.setContentOffset(CGPoint(x: 0, y: bottom ? max(0, scroll.contentSize.height - scroll.bounds.height) : 0), animated: false)
            // 현재 시트와 뒤의 더보기 화면을 함께 보존한다.
            let capture = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) })
            capture.name = "Settings-\(Int(width))-\(style == .dark ? "dark" : "light")-\(large ? "large" : "normal")-\(bottom ? "bottom" : "top")"
            capture.lifetime = .keepAlways
            add(capture)
          }
        }
      }
    }
  }

  @MainActor
  func testSettingsCancelAndCloseDiscardChangesAndApplySavesAllValues() throws {
    // 값이 없던 저장 키도 테스트 뒤 원래 상태로 복구한다.
    let settingsKeys = [UserDataManager.Keys.appTheme, UserDataManager.Keys.marketColorTheme, UserDataManager.Keys.marketCellTintEnabled]
    // 기존 저장 형식과 기본값 유무를 함께 보존한다.
    let savedValues = settingsKeys.map { UserDefaults.standard.object(forKey: $0) }
    defer {
      // 원래 값이 없던 키는 새 기본값을 남기지 않는다.
      for (key, value) in zip(settingsKeys, savedValues) {
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
      }
    }
    UserDataManager.appTheme = .system
    UserDataManager.marketColorTheme = .riseRedFallBlue
    UserDataManager.marketCellTintEnabled = false
    // 앱 테마 적용이 실제 연결된 창까지 전달되는지 검사한다.
    let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    // 다른 설정과 분리된 실제 더보기 진입 화면이다.
    let controller = MoreViewController(accountsUseCase: fixture(), presentRewardedAd: { _, _ in XCTFail("Settings must not start an ad") }, loadBannerAd: { _ in })
    // 적용 시 connectedScenes의 창 목록에 포함될 테스트 창이다.
    let window = UIWindow(windowScene: windowScene)
    window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    // 적용 버튼이 다른 앱 창의 스타일도 바꾸므로 모두 원복한다.
    let savedWindowStyles = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .map { (window: $0, style: $0.overrideUserInterfaceStyle) }
    defer {
      savedWindowStyles.forEach { $0.window.overrideUserInterfaceStyle = $0.style }
      window.isHidden = true
      window.rootViewController = nil
    }
    window.overrideUserInterfaceStyle = .light
    // 같은 UI 변경 뒤 버튼과 시스템 dismiss의 저장 경계를 확인한다.
    for dismissalIdentifier in ["settings.cancel", "settings.close", "system.dismiss", "settings.apply"] {
      // 매번 새 설정 화면이 저장된 기본값으로 시작해야 한다.
      let settingsButton = try XCTUnwrap(find(controller.view, "more.settings") as? UIButton)
      settingsButton.sendActions(for: .touchUpInside)
      waitUntil(timeout: 8) { controller.presentedViewController != nil && controller.presentedViewController?.isBeingPresented == false }
      // 비공개 타입에 의존하지 않고 실제 UI 컨트롤로 상태를 바꾼다.
      let settings = try XCTUnwrap(controller.presentedViewController)
      // 취소한 선택이 새 설정 화면에 남지 않았는지 검사한다.
      let systemButton = try XCTUnwrap(find(settings.view, "settings.theme.system") as? UIButton)
      XCTAssertTrue(systemButton.isSelected)
      // 저장과 화면 적용은 확인 버튼을 누르기 전까지 발생하면 안 된다.
      let darkButton = try XCTUnwrap(find(settings.view, "settings.theme.dark") as? UIButton)
      darkButton.sendActions(for: .touchUpInside)
      XCTAssertTrue(darkButton.isSelected)
      XCTAssertFalse(systemButton.isSelected)
      // 상승·하락 팔레트도 같은 확인 시점에 저장한다.
      let palette = try XCTUnwrap(find(settings.view, "settings.palette.riseGreenFallRed") as? UIControl)
      palette.sendActions(for: .touchUpInside)
      // 스위치는 변경 이벤트까지 보내 실제 사용자 조작 경로를 사용한다.
      let priceTint = try XCTUnwrap(find(settings.view, "settings.priceTint") as? UISwitch)
      priceTint.setOn(true, animated: false)
      priceTint.sendActions(for: .valueChanged)
      XCTAssertEqual(UserDataManager.appTheme, .system)
      XCTAssertEqual(UserDataManager.marketColorTheme, .riseRedFallBlue)
      XCTAssertFalse(UserDataManager.marketCellTintEnabled)
      XCTAssertEqual(window.overrideUserInterfaceStyle, .light)
      if dismissalIdentifier == "system.dismiss" {
        // 시스템 presentation의 dismiss 경로도 저장 없이 닫혀야 한다.
        settings.dismiss(animated: true)
      } else {
        // 각 종료 버튼의 실제 연결 액션으로 확인·폐기 동작을 실행한다.
        let dismissButton = try XCTUnwrap(find(settings.view, dismissalIdentifier) as? UIButton)
        dismissButton.sendActions(for: .touchUpInside)
      }
      waitUntil(timeout: 8) { controller.presentedViewController == nil }
      if dismissalIdentifier == "settings.apply" {
        XCTAssertEqual(UserDataManager.appTheme, .dark)
        XCTAssertEqual(UserDataManager.marketColorTheme, .riseGreenFallRed)
        XCTAssertTrue(UserDataManager.marketCellTintEnabled)
        XCTAssertEqual(window.overrideUserInterfaceStyle, .dark)
      } else {
        XCTAssertEqual(UserDataManager.appTheme, .system)
        XCTAssertEqual(UserDataManager.marketColorTheme, .riseRedFallBlue)
        XCTAssertFalse(UserDataManager.marketCellTintEnabled)
        XCTAssertEqual(window.overrideUserInterfaceStyle, .light)
      }
    }
  }

  @MainActor
  func testEveryChargeButtonKeepsChosenAccountThroughConfirmation() throws {
    // 확인창 표시 중 모드가 달라져도 광고 요청은 원래 행의 계좌를 유지한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    // 현재 모드는 다른 테스트와 앱 상태에 돌려준다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    defer {
      ExchangeSelectionStore.currentExchange = previousExchange
      ExchangeSelectionStore.currentProduct = previousProduct
    }
    // 광고 SDK 대신 최종 계좌 전달만 검사한다.
    var requested: [TradingAccountID] = []
    // 실제 확인창과 UIButton 액션을 사용한다.
    let controller = MoreViewController(accountsUseCase: fixture(), presentRewardedAd: { _, account in requested.append(account) }, loadBannerAd: { _ in })
    // 확인창을 실제로 표시할 호스트 창이다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    for (index, account) in MoreAccountsUseCase.accounts.enumerated() {
      // 계좌 행마다 정확히 하나의 확인창을 표시한다.
      let button = try XCTUnwrap(find(controller.view, "more.charge.\(account.exchange.rawValue).\(account.product.rawValue)") as? UIButton)
      button.sendActions(for: .touchUpInside)
      waitUntil { controller.presentedViewController is MobitAlertViewController && controller.presentedViewController?.isBeingPresented == false }
      // 안내 내용도 선택한 거래소·상품·정책 금액을 표시해야 한다.
      let alert = try XCTUnwrap(controller.presentedViewController as? MobitAlertViewController)
      XCTAssertTrue(alert.content.contains(FuturesText.text(account.exchange == .upbit ? "futures_upbit" : "futures_bithumb")))
      XCTAssertTrue(alert.content.contains(FuturesText.text(account.product == .spot ? "futures_spot" : "futures_product")))
      XCTAssertTrue(alert.content.contains("10,000,000"))
      ExchangeSelectionStore.currentExchange = account.exchange == .upbit ? .bithumb : .upbit
      ExchangeSelectionStore.currentProduct = account.product == .spot ? .perpetual : .spot
      alert.confirmButton.sendActions(for: .touchUpInside)
      waitUntil { requested.count == index + 1 }
      XCTAssertEqual(requested.last, account)
    }
  }

  @MainActor
  func testRepeatedChargeTapShowsOneConfirmationAndCancelDoesNotStartAd() throws {
    // 확인창을 취소하면 어떤 계좌도 충전 요청을 받지 않아야 한다.
    var requests = 0
    // 실제 행의 연속 탭을 확인한다.
    let controller = MoreViewController(accountsUseCase: fixture(), presentRewardedAd: { _, _ in requests += 1 }, loadBannerAd: { _ in })
    // 버튼·알럿을 실제 창에 배치한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 좁은 화면에서도 충전 대상을 바꾸지 않는 버튼이다.
    let button = try XCTUnwrap(find(controller.view, "more.charge.upbit.spot") as? UIButton)
    button.sendActions(for: .touchUpInside)
    // 첫 탭이 표시 중인 동일한 확인창이다.
    let first = controller.presentedViewController
    button.sendActions(for: .touchUpInside)
    XCTAssertTrue(controller.presentedViewController === first)
    waitUntil { first?.isBeingPresented == false }
    // 알럿의 실제 취소 액션으로 광고 시작을 차단한다.
    let alert = try XCTUnwrap(first as? MobitAlertViewController)
    alert.cancelButton.sendActions(for: .touchUpInside)
    waitUntil { controller.presentedViewController == nil }
    XCTAssertEqual(requests, 0)
  }

  @MainActor
  func testRewardRefreshReadFailureAndRetryDoNotLockTheScreen() throws {
    // 보상 정산 뒤 변하는 저장된 잔고다.
    var cash: Decimal = 123
    // 저장 실패와 복구를 실제 다시 불러오기 버튼으로 검증한다.
    var failed = false
    // 네트워크·광고 없이 실제 화면의 읽기와 재시도 흐름을 연결한다.
    let useCase = MoreAccountsUseCase(
      spotBalance: { _ in
        if failed { throw AdRewardError.invalidStoredData }
        return cash
      },
      futuresSnapshot: { FuturesAccountSnapshot(revision: 0, accounts: []) },
      scheduler: CurrentThreadScheduler.instance
    )
    // 데이터 오류가 거래 기능이나 전체 화면 인디케이터를 만들지 않아야 한다.
    let controller = MoreViewController(accountsUseCase: useCase, presentRewardedAd: { _, _ in }, loadBannerAd: { _ in })
    // 실제 알림을 받을 보이는 창이다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 현물 잔고의 렌더링 결과를 읽는다.
    let label = try XCTUnwrap(find(controller.view, "more.balance.upbit.spot") as? UILabel)
    // 읽기 실패 안내가 실제 스택에서 나타나고 사라지는지 확인한다.
    let errorLabel = try XCTUnwrap(find(controller.view, "more.accounts.error") as? UILabel)
    // 오류 문구와 재시도 버튼을 함께 접는 XIB 컨테이너다.
    let errorStack = try XCTUnwrap(errorLabel.superview as? UIStackView)
    // 숨긴 오류 뷰의 잔존 frame 대신 실제 형제 간 배치를 검사한다.
    let contentStack = try XCTUnwrap(errorStack.superview as? UIStackView)
    // 오류 안내 직전의 계좌 목록이 차지하는 실제 영역이다.
    let accountsStack = try XCTUnwrap(contentStack.arrangedSubviews.first)
    // 오류 안내 직후 광고 영역과의 간격으로 접힘 여부를 확인한다.
    let bannerContainer = try XCTUnwrap(find(controller.view, "more.banner.container"))
    // 오류 안내의 실제 다시 불러오기 버튼이다.
    let retry = try XCTUnwrap(find(controller.view, "more.accounts.retry") as? UIButton)
    waitUntil { label.text?.contains("123") == true }
    controller.view.layoutIfNeeded()
    XCTAssertTrue(errorStack.isHidden)
    XCTAssertEqual(bannerContainer.frame.minY - accountsStack.frame.maxY, contentStack.spacing, accuracy: 0.5)
    cash = 10_000_123
    NotificationCenter.default.post(name: .futuresAccountDidChange, object: nil)
    waitUntil { label.text?.contains("10,000,123") == true }
    failed = true
    NotificationCenter.default.post(name: .futuresAccountDidChange, object: nil)
    waitUntil { label.text == "—" }
    controller.view.layoutIfNeeded()
    XCTAssertFalse(errorStack.isHidden)
    XCTAssertEqual(errorStack.frame.minY - accountsStack.frame.maxY, contentStack.spacing, accuracy: 0.5)
    XCTAssertEqual(bannerContainer.frame.minY - errorStack.frame.maxY, contentStack.spacing, accuracy: 0.5)
    XCTAssertGreaterThanOrEqual(retry.bounds.height, 44)
    XCTAssertGreaterThan(errorLabel.bounds.height, 0)
    XCTAssertLessThanOrEqual(errorLabel.frame.maxY, retry.frame.minY)
    for view in [errorStack, errorLabel, retry] {
      XCTAssertFalse(view.hasAmbiguousLayout)
    }
    if #available(iOS 17.0, *) {
      controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
      controller.updateTraitsIfNeeded()
      controller.view.layoutIfNeeded()
      XCTAssertEqual(errorStack.frame.minY - accountsStack.frame.maxY, contentStack.spacing, accuracy: 0.5)
      XCTAssertEqual(bannerContainer.frame.minY - errorStack.frame.maxY, contentStack.spacing, accuracy: 0.5)
      XCTAssertGreaterThanOrEqual(retry.bounds.height, 44)
      XCTAssertGreaterThan(errorLabel.bounds.height, 0)
      XCTAssertLessThanOrEqual(errorLabel.frame.maxY, retry.frame.minY)
      for view in [errorStack, errorLabel, retry] {
        XCTAssertFalse(view.hasAmbiguousLayout)
      }
    }
    XCTAssertFalse(MobitBaseViewController.isLoadingIndicatorVisible(in: window))
    failed = false
    retry.sendActions(for: .touchUpInside)
    waitUntil { label.text?.contains("10,000,123") == true }
    controller.view.layoutIfNeeded()
    XCTAssertTrue(errorStack.isHidden)
    XCTAssertEqual(bannerContainer.frame.minY - accountsStack.frame.maxY, contentStack.spacing, accuracy: 0.5)
    XCTAssertNil(controller.presentedViewController)
  }

  private func fixture() -> MoreAccountsUseCase {
    MoreAccountsUseCase(
      spotBalance: { $0 == .upbit ? 10_123_456 : 20_234_567 },
      futuresSnapshot: {
        FuturesAccountSnapshot(revision: 0, accounts: [
          FuturesCashAccount(id: MoreAccountsUseCase.accounts[1], availableBalance: 30_345_678),
          FuturesCashAccount(id: MoreAccountsUseCase.accounts[3], availableBalance: 40_456_789)
        ])
      },
      scheduler: CurrentThreadScheduler.instance
    )
  }

  private func read(_ useCase: MoreAccountsUseCase) throws -> [MoreAccountBalance] {
    // 동기 테스트 스케줄러의 실제 사용 사례 결과만 수집한다.
    var result: [MoreAccountBalance]?
    // 구독 중에는 작업이 해제되지 않도록 유지한다.
    let disposable = useCase.fetchBalances().subscribe(onSuccess: { result = $0 })
    defer { disposable.dispose() }
    return try XCTUnwrap(result)
  }

  @MainActor
  private func waitUntil(
    timeout: TimeInterval = 3,
    _ condition: @escaping () -> Bool
  ) {
    // UIKit 애니메이션·비동기 읽기의 완료 조건을 기다린다.
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
    wait(for: [ready], timeout: timeout)
  }

  @MainActor
  private func find(_ view: UIView, _ identifier: String) -> UIView? {
    descendants(view).first { $0.accessibilityIdentifier == identifier }
  }

  @MainActor
  private func descendants(_ view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }
}
