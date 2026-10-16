import XCTest
import UIKit
import RxSwift
@testable import Mobit

final class MoreAccountResetSheetTests: XCTestCase {
  @MainActor
  func testCurrentAccountStartsSelectedAndDisplaysFourIndependentBalances() throws {
    // 초기 선택은 전달한 계좌를 사용하고 전역 거래소를 변경하지 않아야 한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    // 상품 선택도 테스트가 끝나면 기존 값으로 복구한다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    defer {
      ExchangeSelectionStore.currentExchange = previousExchange
      ExchangeSelectionStore.currentProduct = previousProduct
    }
    ExchangeSelectionStore.currentExchange = .upbit
    ExchangeSelectionStore.currentProduct = .spot
    // 현재 사용 중인 빗썸 선물 계좌를 기본 초기화 대상으로 전달한다.
    let currentAccount = MoreAccountsUseCase.accounts[3]
    // 실제 읽기 사용 사례를 주입하고 선택만으로 초기화하지 않는지 검사한다.
    let controller = MoreAccountResetViewController(
      accountsUseCase: fixture(),
      currentAccount: currentAccount,
      callBack: { _ in XCTFail("Opening the sheet must not reset an account") }
    )
    // 실제 시스템 시트에 표시하여 잔고 구독과 레이아웃을 활성화한다.
    let window = host(controller)
    defer { window.isHidden = true; window.rootViewController = nil }
    waitUntil { self.balanceText(in: controller, account: currentAccount).contains("0.73264486") }
    try assertSelection(currentAccount, in: controller)
    // 거래소와 상품이 다른 네 계좌의 잔고를 서로 섞지 않아야 한다.
    let expectedAmounts = ["449,968", "35,360,186", "20,653,266", "0.73264486"]
    for (account, amount) in zip(MoreAccountsUseCase.accounts, expectedAmounts) {
      XCTAssertTrue(balanceText(in: controller, account: account).contains(amount))
      // 현재 계좌 표시는 선택을 바꾸는 라디오와 구분하여 해당 계좌에만 붙인다.
      let badge = try XCTUnwrap(find(controller.view, "reset.account.badge.current.\(identifier(account))") as? UILabel)
      XCTAssertEqual(badge.isHidden, account != currentAccount)
    }
    XCTAssertEqual(ExchangeSelectionStore.currentExchange, .upbit)
    XCTAssertEqual(ExchangeSelectionStore.currentProduct, .spot)
  }

  @MainActor
  func testSelectionStaysInSheetAndConfirmationUsesChosenAccountAfterGlobalModeChanges() throws {
    // 선택창이 앱의 거래소·상품 선택을 덮어쓰는지 확인하고 원래 값으로 복구한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    // 초기화 콜백은 확인 순간의 전역 상품이 아닌 선택한 계좌를 전달해야 한다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    defer {
      ExchangeSelectionStore.currentExchange = previousExchange
      ExchangeSelectionStore.currentProduct = previousProduct
    }
    ExchangeSelectionStore.currentExchange = .upbit
    ExchangeSelectionStore.currentProduct = .spot
    // 실제 초기화 대신 전달된 계좌만 기록하여 선택과 확인의 경계를 확인한다.
    var confirmedAccounts: [TradingAccountID] = []
    // 네 행을 선택한 뒤 동일한 시트에서 확인 버튼을 누른다.
    let controller = MoreAccountResetViewController(
      accountsUseCase: fixture(),
      currentAccount: MoreAccountsUseCase.accounts[0],
      callBack: { confirmedAccounts.append($0) }
    )
    // dismiss 완료 이후에만 콜백이 실행되는 실제 표시 환경이다.
    let window = host(controller)
    defer { window.isHidden = true; window.rootViewController = nil }
    for account in MoreAccountsUseCase.accounts {
      try control(controller, "reset.account.\(identifier(account))").sendActions(for: .touchUpInside)
      try assertSelection(account, in: controller)
      XCTAssertTrue(window.rootViewController?.presentedViewController === controller)
      XCTAssertNil(controller.presentedViewController)
      XCTAssertTrue(confirmedAccounts.isEmpty)
    }
    // 마지막 전역 선택과 다른 계좌를 골라 콜백이 전역 상태를 다시 읽지 않게 한다.
    let selectedAccount = MoreAccountsUseCase.accounts[1]
    try control(controller, "reset.account.\(identifier(selectedAccount))").sendActions(for: .touchUpInside)
    ExchangeSelectionStore.currentExchange = .bithumb
    ExchangeSelectionStore.currentProduct = .spot
    try control(controller, "reset.confirm").sendActions(for: .touchUpInside)
    try control(controller, "reset.confirm").sendActions(for: .touchUpInside)
    waitUntil { confirmedAccounts.count == 1 && window.rootViewController?.presentedViewController == nil }
    XCTAssertEqual(confirmedAccounts, [selectedAccount])
    XCTAssertEqual(ExchangeSelectionStore.currentExchange, .bithumb)
    XCTAssertEqual(ExchangeSelectionStore.currentProduct, .spot)
  }

  @MainActor
  func testCancelAndCloseDiscardSelectionWithoutConfirmation() throws {
    for dismissIdentifier in ["reset.cancel", "reset.close"] {
      // 두 닫기 경로 모두 데이터를 갱신하는 콜백을 실행하지 않아야 한다.
      var confirmedAccounts: [TradingAccountID] = []
      // 매번 새 시트를 열어 이전 임시 선택이 저장되지 않는지 확인한다.
      let controller = MoreAccountResetViewController(
        accountsUseCase: fixture(),
        currentAccount: MoreAccountsUseCase.accounts[0],
        callBack: { confirmedAccounts.append($0) }
      )
      // 시스템 dismiss 애니메이션까지 실제 창에서 검사한다.
      let window = host(controller)
      defer { window.isHidden = true; window.rootViewController = nil }
      try control(controller, "reset.account.bithumb.perpetual").sendActions(for: .touchUpInside)
      try control(controller, dismissIdentifier).sendActions(for: .touchUpInside)
      waitUntil { window.rootViewController?.presentedViewController == nil }
      XCTAssertTrue(confirmedAccounts.isEmpty)
    }
  }

  #if DEBUG
  @MainActor
  func testResetAnalyticsKeepsChosenAccountAndRecordsConfirmationOnlyOnce() throws {
    // 다른 테스트의 분석 수집 경로를 종료 시 복구한다.
    let previousEventCallBack = MobitAnalyticsUtil.eventCallBack
    // 외부 선택이 바뀌어도 시트에서 확정한 계좌가 유지되는지 검사한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    // 전역 상품 선택은 계측 검사가 끝나면 원래대로 되돌린다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    defer {
      MobitAnalyticsUtil.eventCallBack = previousEventCallBack
      ExchangeSelectionStore.currentExchange = previousExchange
      ExchangeSelectionStore.currentProduct = previousProduct
    }
    // 실제 Firebase 전송 경계에서 시트의 사용자 행동만 수집한다.
    var events: [(name: String, parameters: [String: Any])] = []
    MobitAnalyticsUtil.eventCallBack = { name, parameters in
      if parameters["Step_depth_01"] as? String == "더보기_초기화" {
        events.append((name, parameters))
      }
    }
    // 확인은 초기화 실행 성공과 구분되는 선택 전달 단계다.
    var confirmedAccounts: [TradingAccountID] = []
    // 표시 중인 계좌와 다른 거래소·상품을 초기화 대상으로 선택한다.
    let selectedAccount = MoreAccountsUseCase.accounts[3]
    // 실제 시트와 행의 액션을 사용하고 자산 저장은 실행하지 않는다.
    let controller = MoreAccountResetViewController(
      accountsUseCase: fixture(),
      currentAccount: MoreAccountsUseCase.accounts[0],
      callBack: { confirmedAccounts.append($0) }
    )
    // 노출과 dismiss 완료는 실제 모달 생명주기를 따른다.
    let window = host(controller)
    defer { window.isHidden = true; window.rootViewController = nil }
    waitUntil { events.contains { $0.parameters["Step_depth_02"] as? String == "초기화_시트_노출" } }
    try control(controller, "reset.account.\(identifier(selectedAccount))").sendActions(for: .touchUpInside)
    try control(controller, "reset.account.\(identifier(selectedAccount))").sendActions(for: .touchUpInside)
    ExchangeSelectionStore.currentExchange = .upbit
    ExchangeSelectionStore.currentProduct = .spot
    try control(controller, "reset.confirm").sendActions(for: .touchUpInside)
    try control(controller, "reset.confirm").sendActions(for: .touchUpInside)
    waitUntil { confirmedAccounts.count == 1 && window.rootViewController?.presentedViewController == nil }

    XCTAssertEqual(confirmedAccounts, [selectedAccount])
    XCTAssertEqual(events.map(\.name), ["mobit_screen_event", "mobit_click_event", "mobit_click_event"])
    XCTAssertEqual(events.compactMap { $0.parameters["Step_depth_02"] as? String }, [
      "초기화_시트_노출", "초기화_대상_선택", "초기화_확인_요청"
    ])
    for event in events.dropFirst() {
      XCTAssertEqual(event.parameters["exchange"] as? String, selectedAccount.exchange.rawValue)
      XCTAssertEqual(event.parameters["product"] as? String, selectedAccount.product.rawValue)
      XCTAssertEqual(event.parameters["account_name"] as? String, "빗썸_선물")
      XCTAssertEqual(event.parameters["currency"] as? String, selectedAccount.currency.rawValue)
    }
  }

  @MainActor
  func testResetAnalyticsCancelCloseAndInteractiveDismissCallbackNeverRecordSuccess() throws {
    // 분석 수집 경로를 테스트 종료 뒤 원래 값으로 복구한다.
    let previousEventCallBack = MobitAnalyticsUtil.eventCallBack
    defer { MobitAnalyticsUtil.eventCallBack = previousEventCallBack }
    // 동일 시트에서 받은 실제 행동과 계좌 문맥만 기록한다.
    var events: [[String: Any]] = []
    MobitAnalyticsUtil.eventCallBack = { _, parameters in
      if parameters["Step_depth_01"] as? String == "더보기_초기화" { events.append(parameters) }
    }
    for dismissIdentifier in ["reset.cancel", "reset.close", "interactiveDismiss"] {
      events.removeAll()
      // 취소는 선택을 전달하거나 초기화 성공을 기록하면 안 된다.
      var confirmedAccounts: [TradingAccountID] = []
      // 기본 선택과 다른 계좌로 취소 문맥을 구분한다.
      let selectedAccount = MoreAccountsUseCase.accounts[2]
      // 버튼과 시스템 닫기 완료 콜백에서 같은 중복 방지 경계를 검사한다.
      let controller = MoreAccountResetViewController(
        accountsUseCase: fixture(),
        currentAccount: MoreAccountsUseCase.accounts[0],
        callBack: { confirmedAccounts.append($0) }
      )
      // 실제 표시 완료 뒤에만 사용자의 선택·닫기를 실행한다.
      let window = host(controller)
      defer { window.isHidden = true; window.rootViewController = nil }
      waitUntil { events.contains { $0["Step_depth_02"] as? String == "초기화_시트_노출" } }
      try control(controller, "reset.account.\(identifier(selectedAccount))").sendActions(for: .touchUpInside)
      if dismissIdentifier == "interactiveDismiss" {
        // 제스처 자체 대신 UIKit이 완료 시 전달하는 delegate 경계를 검사한다.
        let presentation = try XCTUnwrap(controller.presentationController)
        XCTAssertTrue(presentation.delegate === controller)
        controller.dismiss(animated: false)
        controller.presentationControllerDidDismiss(presentation)
        controller.presentationControllerDidDismiss(presentation)
      } else {
        try control(controller, dismissIdentifier).sendActions(for: .touchUpInside)
        try control(controller, dismissIdentifier).sendActions(for: .touchUpInside)
      }
      waitUntil { window.rootViewController?.presentedViewController == nil }
      XCTAssertTrue(confirmedAccounts.isEmpty)
      XCTAssertEqual(events.compactMap { $0["Step_depth_02"] as? String }, [
        "초기화_시트_노출", "초기화_대상_선택", "초기화_시트_취소"
      ])
      XCTAssertEqual(events.last?["exchange"] as? String, selectedAccount.exchange.rawValue)
      XCTAssertEqual(events.last?["product"] as? String, selectedAccount.product.rawValue)
      XCTAssertEqual(
        events.last?["Step_depth_03"] as? String,
        dismissIdentifier == "reset.cancel" ? "취소_버튼" : dismissIdentifier == "reset.close" ? "닫기_버튼" : "스와이프_닫기"
      )
    }
  }
  #endif

  @MainActor
  func testStorageFailureKeepsKnownBalancesAndRetryRestoresMissingAmounts() throws {
    // 첫 조회만 선물 저장소 오류를 반환하고 재시도에는 실제 잔고를 반환한다.
    var storageFailed = true
    // 최초 표시와 명시적인 다시 불러오기가 각각 한 번 읽어야 한다.
    var futuresReadCount = 0
    // 선물 실패 중에도 현물 계좌의 정상 금액을 유지하는 실제 사용 사례다.
    let useCase = MoreAccountsUseCase(
      spotBalance: { $0 == .upbit ? 449_968 : 20_653_266 },
      futuresSnapshot: {
        futuresReadCount += 1
        if storageFailed { throw AdRewardError.invalidStoredData }
        return self.futuresSnapshot()
      },
      scheduler: CurrentThreadScheduler.instance
    )
    // 읽기 오류가 초기화 요청이나 전체 화면 오류로 이어지면 안 된다.
    let controller = MoreAccountResetViewController(
      accountsUseCase: useCase,
      currentAccount: MoreAccountsUseCase.accounts[0],
      callBack: { _ in XCTFail("Retry must not reset an account") }
    )
    // 오류와 복구를 같은 시트에서 확인한다.
    let window = host(controller)
    defer { window.isHidden = true; window.rootViewController = nil }
    waitUntil { self.balanceText(in: controller, account: MoreAccountsUseCase.accounts[0]).contains("449,968") }
    XCTAssertTrue(balanceText(in: controller, account: MoreAccountsUseCase.accounts[2]).contains("20,653,266"))
    XCTAssertEqual(balanceText(in: controller, account: MoreAccountsUseCase.accounts[1]), "—")
    XCTAssertEqual(balanceText(in: controller, account: MoreAccountsUseCase.accounts[3]), "—")
    // 저장 실패를 잔고 0원으로 표시하지 않고 복구 동작을 제공한다.
    let retry = try control(controller, "reset.retry")
    XCTAssertTrue(isVisible(retry))
    XCTAssertTrue(retry.isEnabled)
    storageFailed = false
    retry.sendActions(for: .touchUpInside)
    waitUntil { self.balanceText(in: controller, account: MoreAccountsUseCase.accounts[1]).contains("35,360,186") }
    XCTAssertTrue(balanceText(in: controller, account: MoreAccountsUseCase.accounts[3]).contains("0.73264486"))
    XCTAssertFalse(isVisible(retry))
    XCTAssertEqual(futuresReadCount, 2)
    XCTAssertNil(controller.presentedViewController)
  }

  @MainActor
  func testSheetKeepsHeaderAndActionsVisibleOnSmallScreensBothThemesAndLargeText() throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Trait overrides require iOS 17") }
    for width: CGFloat in [320, 393] {
      for style in [UIUserInterfaceStyle.light, .dark] {
        // 외부 저장값이나 광고 없이 실제 초기화 시트의 콘텐츠를 표시한다.
        let controller = MoreAccountResetViewController(
          accountsUseCase: fixture(),
          currentAccount: MoreAccountsUseCase.accounts[1],
          callBack: { _ in XCTFail("Layout must not reset an account") }
        )
        // 작은 화면과 일반 화면의 사용 가능 높이를 각각 검증한다.
        let window = host(controller, width: width, height: width == 320 ? 568 : 852, style: style)
        defer { window.isHidden = true; window.rootViewController = nil }
        waitUntil { self.balanceText(in: controller, account: MoreAccountsUseCase.accounts[1]).contains("35,360,186") }
        XCTAssertEqual(controller.modalPresentationStyle, .pageSheet)
        XCTAssertTrue(try XCTUnwrap(controller.sheetPresentationController).prefersGrabberVisible)
        XCTAssertFalse(try XCTUnwrap(controller.sheetPresentationController).detents.isEmpty)
        // 글자 확대 후 기본 크기로 돌아와도 헤더와 설명 배치가 복원되어야 한다.
        for large in [false, true, false] {
          controller.traitOverrides.preferredContentSizeCategory = large ? .accessibilityExtraExtraExtraLarge : .large
          controller.updateTraitsIfNeeded()
          window.layoutIfNeeded()
          controller.view.layoutIfNeeded()
          // 시트 안쪽 카드가 시스템 Safe Area 경계를 넘어가지 않아야 한다.
          let card = try XCTUnwrap(find(controller.view, "reset.card"))
          // 계좌 목록과 경고문만 세로로 스크롤한다.
          let scroll = try XCTUnwrap(find(controller.view, "reset.scroll") as? UIScrollView)
          // 확인·취소 동작은 본문 아래에 고정한다.
          let actions = try XCTUnwrap(find(controller.view, "reset.actions"))
          // 닫기 버튼은 본문 위의 고정 헤더 안에 있어야 한다.
          let close = try control(controller, "reset.close")
          // 비교할 모든 프레임은 같은 시트 좌표계를 사용한다.
          let cardFrame = card.convert(card.bounds, to: controller.view)
          // 상태 표시줄과 홈 표시기를 제외한 시트의 가용 영역이다.
          let safeFrame = controller.view.safeAreaLayoutGuide.layoutFrame
          // 본문 스크롤 전 고정 헤더의 위치를 보관한다.
          let closeFrame = close.convert(close.bounds, to: controller.view)
          // 본문 스크롤 전 하단 동작의 위치를 보관한다.
          let actionsFrame = actions.convert(actions.bounds, to: controller.view)
          // 본문은 헤더와 하단 동작 사이의 높이만 사용한다.
          let scrollFrame = scroll.convert(scroll.bounds, to: controller.view)
          XCTAssertGreaterThanOrEqual(cardFrame.minX, safeFrame.minX - 1)
          XCTAssertGreaterThanOrEqual(cardFrame.minY, safeFrame.minY - 1)
          XCTAssertLessThanOrEqual(cardFrame.maxX, safeFrame.maxX + 1)
          XCTAssertLessThanOrEqual(cardFrame.maxY, safeFrame.maxY + 1)
          XCTAssertGreaterThan(scroll.bounds.height, 0)
          XCTAssertEqual(scroll.contentSize.width, scroll.bounds.width, accuracy: 1)
          XCTAssertLessThanOrEqual(closeFrame.maxY, scrollFrame.minY + 1)
          XCTAssertLessThanOrEqual(scrollFrame.maxY, actionsFrame.minY + 1)
          XCTAssertLessThanOrEqual(actionsFrame.maxY, cardFrame.maxY + 1)
          if large { XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height) }
          for identifier in ["reset.close", "reset.cancel", "reset.confirm"] + MoreAccountsUseCase.accounts.map({ "reset.account.\(self.identifier($0))" }) {
            // 아이콘 크기와 별개로 실제 터치 영역은 44pt 이상이어야 한다.
            let button = try control(controller, identifier)
            XCTAssertGreaterThanOrEqual(button.bounds.width, 44, identifier)
            XCTAssertGreaterThanOrEqual(button.bounds.height, 44, identifier)
            XCTAssertFalse(button.hasAmbiguousLayout, identifier)
            if ["reset.cancel", "reset.confirm"].contains(identifier), let label = (button as? UIButton)?.titleLabel {
              // 버튼 문구가 자체 프레임뿐 아니라 실제 터치 영역 안에도 들어가야 한다.
              let labelFrame = label.convert(label.bounds, to: button)
              XCTAssertGreaterThanOrEqual(labelFrame.minY, -1, identifier)
              XCTAssertLessThanOrEqual(labelFrame.maxY, button.bounds.maxY + 1, identifier)
            }
          }
          for label in descendants(card).compactMap({ $0 as? UILabel }).filter({ isVisible($0) && !($0.text ?? "").isEmpty }) {
            XCTAssertGreaterThan(label.bounds.width, 0, label.text ?? "")
            XCTAssertGreaterThanOrEqual(
              label.bounds.height + 1,
              label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height,
              label.text ?? ""
            )
          }
          // 긴 경고문을 포함한 마지막 콘텐츠도 같은 스크롤 안에 있어야 한다.
          let warning = try XCTUnwrap(find(controller.view, "reset.warning") as? UILabel)
          XCTAssertTrue(descendants(scroll).contains { $0 === warning })
          XCTAssertFalse(card.hasAmbiguousLayout)
          XCTAssertFalse(scroll.hasAmbiguousLayout)
          XCTAssertFalse(actions.hasAmbiguousLayout)
          for bottom in [false, true] {
            scroll.setContentOffset(CGPoint(x: 0, y: bottom ? max(0, scroll.contentSize.height - scroll.bounds.height) : 0), animated: false)
            XCTAssertEqual(close.convert(close.bounds, to: controller.view), closeFrame)
            XCTAssertEqual(actions.convert(actions.bounds, to: controller.view), actionsFrame)
            // 상하 스크롤 결과를 xcresult에 남겨 실제 텍스트·색상도 확인한다.
            let capture = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) })
            capture.name = "Reset-\(Int(width))-\(style == .dark ? "dark" : "light")-\(large ? "large" : "normal")-\(bottom ? "bottom" : "top")"
            capture.lifetime = .keepAlways
            add(capture)
          }
        }
      }
    }
  }

  @MainActor
  func testNormalSizeBadgesFitTheirContentAndTitleStaysOnOneLine() throws {
    // 기본 글자 크기에서는 시안처럼 제목과 짧은 배지가 한 줄에 배치되어야 한다.
    let controller = MoreAccountResetViewController(
      accountsUseCase: fixture(),
      currentAccount: MoreAccountsUseCase.accounts[1],
      callBack: { _ in XCTFail("Layout must not reset an account") }
    )
    // 시안과 같은 일반 화면 폭에서 실제 콘텐츠 배치를 확인한다.
    let window = host(controller)
    defer { window.isHidden = true; window.rootViewController = nil }
    // 기본 크기 제목이 배지의 빈 여백에 밀려 불필요하게 줄바꿈하면 안 된다.
    let title = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UILabel }.first {
      $0.text == FuturesText.text("more_reset_sheet_title")
    })
    // 한 줄 제목의 자연 폭을 보존해 초기화 배지가 바로 옆에 붙어야 한다.
    let titleFont = try XCTUnwrap(title.font)
    // 현재 표시 글꼴에서 제목이 차지하는 한 줄 크기다.
    let titleSize = (title.text ?? "").size(withAttributes: [.font: titleFont])
    waitUntil {
      title.bounds.height <= titleFont.lineHeight + 1 && abs(title.bounds.width - ceil(titleSize.width)) <= 1
    }
    XCTAssertLessThanOrEqual(title.bounds.height, titleFont.lineHeight + 1)
    XCTAssertEqual(
      title.bounds.width,
      ceil(titleSize.width),
      accuracy: 1,
      "intrinsic=\(title.intrinsicContentSize), preferredWidth=\(title.preferredMaxLayoutWidth)"
    )
    for label in descendants(controller.view).compactMap({ $0 as? UILabel }).filter({
      [FuturesText.text("futures_upbit"), FuturesText.text("futures_bithumb")].contains($0.text ?? "")
    }) {
      XCTAssertLessThanOrEqual(label.bounds.height, label.font.lineHeight + 1, label.text ?? "")
    }
    // 현재 계좌와 상품 배지는 글자와 양쪽 안쪽 여백만큼의 폭을 유지한다.
    let badgeTexts = ["more_reset_badge", "futures_spot", "futures_product", "more_current_account"].map(FuturesText.text)
    for label in descendants(controller.view).compactMap({ $0 as? UILabel }).filter({
      isVisible($0) && badgeTexts.contains($0.text ?? "")
    }) {
      // 실제 표시 글꼴을 사용해 배지 너비의 기준을 구한다.
      let font = try XCTUnwrap(label.font)
      // 배지에 쓰이는 실제 글꼴로 텍스트의 자연 폭을 비교한다.
      let textWidth = (label.text ?? "").size(withAttributes: [.font: font]).width
      XCTAssertEqual(label.bounds.width, ceil(textWidth) + 12, accuracy: 1, label.text ?? "")
      XCTAssertLessThanOrEqual(label.bounds.height, font.lineHeight + 7, label.text ?? "")
      XCTAssertLessThanOrEqual(label.bounds.width, ceil(textWidth) + 13, label.text ?? "")
    }
  }

  private func fixture() -> MoreAccountsUseCase {
    MoreAccountsUseCase(
      spotBalance: { $0 == .upbit ? 449_968 : 20_653_266 },
      futuresSnapshot: futuresSnapshot,
      scheduler: CurrentThreadScheduler.instance
    )
  }

  private func futuresSnapshot() -> FuturesAccountSnapshot {
    FuturesAccountSnapshot(
      revision: 0,
      accounts: [
        FuturesCashAccount(id: MoreAccountsUseCase.accounts[1], availableBalance: 35_360_186),
        FuturesCashAccount(id: MoreAccountsUseCase.accounts[3], availableBalance: Decimal(sign: .plus, exponent: -8, significand: 73_264_486))
      ]
    )
  }

  @MainActor
  private func host(
    _ controller: MoreAccountResetViewController,
    width: CGFloat = 393,
    height: CGFloat = 852,
    style: UIUserInterfaceStyle = .light
  ) -> UIWindow {
    // 실제 모달 표시와 닫기 완료를 검사할 전용 창이다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
    // 초기화 화면 뒤에서 시스템 시트를 표시하는 호스트다.
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
  private func assertSelection(_ selected: TradingAccountID, in controller: UIViewController) throws {
    for account in MoreAccountsUseCase.accounts {
      // 네 계좌 중 하나만 선택 상태이며 선택 테두리는 요청한 얇은 1pt를 사용한다.
      let button = try control(controller, "reset.account.\(identifier(account))")
      XCTAssertEqual(button.isSelected, account == selected)
      if button.isSelected { XCTAssertEqual(button.layer.borderWidth, 1, accuracy: 0.01) }
    }
  }

  private func identifier(_ account: TradingAccountID) -> String {
    "\(account.exchange.rawValue).\(account.product.rawValue)"
  }

  @MainActor
  private func balanceText(in controller: UIViewController, account: TradingAccountID) -> String {
    (find(controller.view, "reset.balance.\(identifier(account))") as? UILabel)?.text ?? ""
  }

  @MainActor
  private func control(_ controller: UIViewController, _ identifier: String) throws -> UIControl {
    try XCTUnwrap(find(controller.view, identifier) as? UIControl)
  }

  @MainActor
  private func isVisible(_ view: UIView) -> Bool {
    !sequence(first: view, next: { $0.superview }).contains { $0.isHidden || $0.alpha == 0 }
  }

  @MainActor
  private func find(_ view: UIView, _ identifier: String) -> UIView? {
    descendants(view).first { $0.accessibilityIdentifier == identifier }
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
    // 메인 큐의 잔고 반영과 시스템 시트 애니메이션이 끝나는 조건을 기다린다.
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
    wait(for: [ready], timeout: timeout)
  }
}
