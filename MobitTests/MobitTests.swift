//
//  MobitTests.swift
//  MobitTests
//
//  Created by 조성재 on 7/10/24.
//

import XCTest
import UIKit
import WebKit
@testable import Mobit

final class MobitTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

    @MainActor
    func testTradeChartIntervalRowKeepsLabelWidthAcrossScreenSizes() throws {
        // 네트워크 구성을 실행하지 않고 실제 XIB의 간격 행을 검사한다.
        let chartView = try XCTUnwrap(
            UINib(nibName: "TradeChartView", bundle: Bundle(for: TradeChartView.self))
                .instantiate(withOwner: nil, options: nil).first as? TradeChartView
        )
        // 간격 선택 컨트롤의 실제 배치 결과를 확인한다.
        let intervalControl = try XCTUnwrap(chartView.intervalSegmentedControl)
        // 라벨과 선택 컨트롤이 가로 공간을 나누는 행이다.
        let intervalRow = try XCTUnwrap(intervalControl.superview as? UIStackView)
        // 짧은 제목이 남는 가로 공간 때문에 늘어나지 않아야 한다.
        let intervalLabel = try XCTUnwrap(
            intervalRow.arrangedSubviews.compactMap { $0 as? UILabel }.first
        )

        // 작은 휴대폰부터 넓은 화면까지 같은 콘텐츠 배치를 유지한다.
        for screenWidth: CGFloat in [320, 393, 768] {
            chartView.frame = CGRect(x: 0, y: 0, width: screenWidth, height: 600)
            chartView.setNeedsLayout()
            chartView.layoutIfNeeded()

            XCTAssertFalse(intervalLabel.hasAmbiguousLayout)
            XCTAssertFalse(intervalControl.hasAmbiguousLayout)
            XCTAssertEqual(intervalLabel.frame.width, intervalLabel.intrinsicContentSize.width, accuracy: 1)
            XCTAssertLessThanOrEqual(intervalLabel.frame.maxX, intervalControl.frame.minX)
            XCTAssertLessThanOrEqual(intervalControl.frame.maxX, intervalRow.bounds.maxX + 1)
            XCTAssertGreaterThan(intervalLabel.bounds.height, 0)
            XCTAssertGreaterThan(intervalControl.bounds.height, 0)
        }
    }

}

// 실제 nib을 로드하되 네트워크·광고를 시작하는 화면 생명주기는 분리한다.
@MainActor
final class XIBLayoutTests: XCTestCase {
    // 앱 리소스에 포함된 전체 XIB를 빠짐없이 검사한다.
    private let nibNames = [
        "MobitAlertViewController", "MobitBottomSheetViewController",
        "InvestmentTableViewCell", "InvestmentViewController", "PNLShareView",
        "PNLTableViewCell", "PNLViewController", "MainCryptoTableViewCell",
        "NoticeForceUpdateViewController", "TradeAskView", "TradeAverageCalcView",
        "TradeBidView", "TradeChartView", "TradeHistoryTableViewCell",
        "TradeHistoryView", "TradeInfoCollectionViewCell", "TradeInformationView",
        "TradeOrderView", "TradeViewController", "LeaderBoardViewController",
        "MobitCommunityViewController", "MoreViewController", "NewsViewController",
        "MobitLaunchScreen"
    ]

    func testEveryNibAtPhoneWidths() throws {
        print("XIB layout audit language: \(Locale.preferredLanguages), locale: \(Locale.current.identifier)")
        for nibName in nibNames {
            for width: CGFloat in [320, 393, 440] {
                // 셀과 재사용 뷰의 최상위 크기는 실제 사용처처럼 외부에서 제공한다.
                let owner = LayoutNibOwner()
                let root = try loadNib(nibName, owner: owner)
                root.frame.size = CGSize(width: width, height: width == 320 ? 568 : 852)
                if let cell = root as? UITableViewCell {
                    cell.contentView.frame.size.width = width
                    let fitting = cell.systemLayoutSizeFitting(
                        CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                        withHorizontalFittingPriority: .required,
                        verticalFittingPriority: .fittingSizeLevel
                    )
                    root.frame.size.height = max(fitting.height, 1)
                }
                // Safe Area와 trait가 존재하는 실제 표시 계층에서 계산한다.
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: width == 320 ? 568 : 852))
                window.rootViewController = UIViewController()
                window.rootViewController?.view.addSubview(root)
                window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil }
                root.setNeedsLayout()
                window.layoutIfNeeded()
                root.layoutIfNeeded()
                assertUnambiguous(root, context: "\(nibName) width=\(width)")
                attach(root, name: "\(nibName)-\(Int(width))")
            }
        }
    }

    func testOrderPanelsCanHideAndReappear() throws {
        for nibName in ["TradeBidView", "TradeAskView", "TradeHistoryView"] {
            // 호가 열을 제외한 주문 패널을 세로 스택이 직접 숨기는 실제 구조다.
            let panel = try loadNib(nibName)
            let stack = UIStackView(arrangedSubviews: [panel])
            stack.axis = .vertical
            stack.frame = CGRect(x: 0, y: 0, width: 243, height: 600)
            // 숨김 제약도 실제 윈도우의 레이아웃 엔진에서 활성화한다.
            let window = host(stack, width: 320)
            defer { window.isHidden = true; window.rootViewController = nil }
            stack.layoutIfNeeded()
            panel.isHidden = true
            stack.frame.size.height = 0
            stack.layoutIfNeeded()
            // 숨긴 자식의 보존된 frame 대신 부모가 차지하는 콘텐츠 높이를 확인한다.
            XCTAssertEqual(
                stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height,
                0,
                accuracy: 1,
                nibName
            )
            panel.isHidden = false
            stack.frame.size.height = 600
            stack.layoutIfNeeded()
            assertUnambiguous(panel, context: nibName)
        }
        // 보유 내역과 계산 결과 카드도 각각의 부모 스택에서 접힌다.
        let order = try XCTUnwrap(loadNib("TradeOrderView") as? TradeOrderView)
        order.frame = CGRect(x: 0, y: 0, width: 393, height: 700)
        // 보유 내역 숨김도 외부 크기가 결정된 계층에서 확인한다.
        let orderWindow = host(order, width: 393)
        defer { orderWindow.isHidden = true; orderWindow.rootViewController = nil }
        for hidden in [false, true, false] {
            order.investLiveView.isHidden = hidden
            order.layoutIfNeeded()
        }
        // 콘텐츠로 높이가 결정되는 주문 폼의 스크롤 경계를 확인한다.
        let scroll = try XCTUnwrap(order.segmentedContainerStackView.superview?.superview as? UIScrollView)
        for index in [0, 1] {
            for (panelIndex, panel) in order.segmentedContainerStackView.arrangedSubviews.enumerated() {
                panel.isHidden = panelIndex != index
            }
            order.layoutIfNeeded()
            assertUnambiguous(order, context: "order tab \(index)")
            XCTAssertEqual(scroll.contentSize.width, scroll.bounds.width, accuracy: 1)
            // 보유 내역의 하단까지 스크롤로 도달할 수 있어야 한다.
            let bottom = order.investLiveView.convert(order.investLiveView.bounds, to: scroll).maxY
            XCTAssertGreaterThanOrEqual(scroll.contentSize.height + 1, bottom)
        }
        let calculator = try XCTUnwrap(loadNib("TradeAverageCalcView") as? TradeAverageCalcView)
        calculator.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        // 계산 결과의 접힘 전후를 실제 표시 계층에 반영한다.
        let calculatorWindow = host(calculator, width: 320)
        defer { calculatorWindow.isHidden = true; calculatorWindow.rootViewController = nil }
        for hidden in [false, true, false] {
            calculator.calcResultView.isHidden = hidden
            calculator.layoutIfNeeded()
        }
        calculator.newBuyQuantityTextField.text = "2"
        calculator.newBuyPriceTextField.text = "100"
        calculator.newBuyQuantityTextField.sendActions(for: .editingChanged)
        calculator.newBuyPriceTextField.sendActions(for: .editingChanged)
        calculator.tapOnCalcButton(calculator.calcButton)
        calculator.layoutIfNeeded()
        XCTAssertFalse(calculator.calcResultView.isHidden)
        XCTAssertFalse(calculator.newBuyQuantitySymbolLabel.isHidden)
        XCTAssertFalse(calculator.newBuyAveragePriceCurrencyLabel.isHidden)
        assertUnambiguous(calculator, context: "calculated average")
    }

    func testAlertConfigurationsAndLongSheetRows() throws {
        for width: CGFloat in [320, 393, 440] {
            for (alertType, title) in [
                (AlertType.canCancel, "모의 투자 안내"),
                (.canCancel, ""),
                (.onlyConfirm, "모의 투자 안내"),
                (.onlyConfirm, "")
            ] {
                // 제목·취소 버튼이 실제 configure 경로에서 숨겨지는 상태를 검사한다.
                let alert = MobitAlertViewController(
                    alertType: alertType,
                    title: title,
                    content: String(repeating: "긴 안내 문구가 여러 줄로 표시됩니다. ", count: 8),
                    callBack: nil
                )
                alert.loadViewIfNeeded()
                // 컨트롤러의 trait와 실제 Safe Area도 함께 전달한다.
                let window = hostAlert(alert, width: width)
                defer { window.isHidden = true; window.rootViewController = nil }
                alert.view.layoutIfNeeded()
                assertUnambiguous(alert.view, context: "alert \(alertType) \(title)")
                XCTAssertEqual(alert.titleLabel.isHidden, title.isEmpty)
                XCTAssertEqual(alert.cancelButton.isHidden, alertType == .onlyConfirm)
                XCTAssertTrue(alert.dividerView.isHidden)
                XCTAssertTrue(alert.buttonDividerView.isHidden)
                XCTAssertEqual(alert.labelStackView.spacing, 10)
                XCTAssertEqual(alert.buttonStackView.spacing, 10)
                XCTAssertGreaterThanOrEqual(alert.confirmButton.bounds.height, 50)
                XCTAssertEqual(alert.cancelButton.configuration?.title ?? alert.cancelButton.title(for: .normal), "취소")
                XCTAssertEqual(alert.confirmButton.configuration?.title ?? alert.confirmButton.title(for: .normal), "확인")
                if alertType == .canCancel {
                    XCTAssertEqual(alert.cancelButton.bounds.width, alert.confirmButton.bounds.width, accuracy: 1)
                    XCTAssertEqual(alert.cancelButton.bounds.height, alert.confirmButton.bounds.height, accuracy: 1)
                    XCTAssertEqual(alert.confirmButton.frame.minX - alert.cancelButton.frame.maxX, 10, accuracy: 1)
                } else {
                    XCTAssertEqual(alert.confirmButton.bounds.width, alert.buttonStackView.bounds.width, accuracy: 1)
                }
                XCTAssertEqual(alert.titleLabel.font.pointSize, 20, accuracy: 0.5)
                XCTAssertEqual(alert.contentLabel.font.pointSize, 15, accuracy: 0.5)
                attach(alert.view, name: "alert-\(alertType)-\(title.isEmpty)-\(Int(width))")
                alert.configure(alertType: .canCancel, title: "복원된 제목", content: "내용", callBack: nil)
                alert.view.setNeedsLayout()
                alert.view.layoutIfNeeded()
                XCTAssertFalse(alert.cancelButton.isHidden)
                XCTAssertFalse(alert.titleLabel.isHidden)
                XCTAssertTrue(alert.dividerView.isHidden)
                XCTAssertTrue(alert.buttonDividerView.isHidden)
                XCTAssertEqual(alert.cancelButton.bounds.width, alert.confirmButton.bounds.width, accuracy: 1)
                // 짧은 안내의 기존 중앙 배치와 새 카드 안쪽 여백을 확인한다.
                let card = try XCTUnwrap(alert.buttonStackView.superview)
                XCTAssertTrue(alert.labelStackView.superview === card)
                XCTAssertEqual(card.layer.cornerRadius, 24, accuracy: 0.5)
                XCTAssertEqual(alert.cancelButton.configuration?.background.cornerRadius ?? alert.cancelButton.layer.cornerRadius, 14, accuracy: 0.5)
                XCTAssertEqual(alert.confirmButton.configuration?.background.cornerRadius ?? alert.confirmButton.layer.cornerRadius, 14, accuracy: 0.5)
                XCTAssertEqual(alert.labelStackView.frame.minX, 24, accuracy: 1)
                XCTAssertEqual(alert.labelStackView.frame.minY, 28, accuracy: 1)
                XCTAssertEqual(card.bounds.maxX - alert.labelStackView.frame.maxX, 24, accuracy: 1)
                XCTAssertEqual(alert.buttonStackView.frame.minX, 24, accuracy: 1)
                XCTAssertEqual(card.bounds.maxX - alert.buttonStackView.frame.maxX, 24, accuracy: 1)
                XCTAssertEqual(card.bounds.maxY - alert.buttonStackView.frame.maxY, 24, accuracy: 1)
                XCTAssertEqual(alert.buttonStackView.frame.minY - alert.labelStackView.frame.maxY, 28, accuracy: 1)
                XCTAssertEqual(card.convert(card.bounds, to: alert.view).midY, alert.view.bounds.midY, accuracy: 1)
                assertColor(card.backgroundColor, matches: .white, traits: alert.traitCollection)
                assertColor(
                    alert.confirmButton.configuration?.background.backgroundColor ?? alert.confirmButton.backgroundColor,
                    matches: .mobitColors(.accentPrimary),
                    traits: alert.traitCollection
                )
                assertColor(
                    alert.confirmButton.configuration?.baseForegroundColor ?? alert.confirmButton.titleColor(for: .normal),
                    matches: .white,
                    traits: alert.traitCollection
                )
                alert.configure(alertType: .onlyConfirm, title: "", content: "제목 없는 안내", callBack: nil)
                alert.view.setNeedsLayout()
                alert.view.layoutIfNeeded()
                XCTAssertTrue(alert.titleLabel.isHidden)
                XCTAssertTrue(alert.cancelButton.isHidden)
                XCTAssertEqual(alert.confirmButton.bounds.width, alert.buttonStackView.bounds.width, accuracy: 1)
            }
        }
        // 정렬 선택 문구가 길어져도 라디오 아이콘과 겹치면 안 된다.
        let sheet = MobitBottomSheetViewController(
            titleString: "정렬 방법",
            contentList: [String(repeating: "긴 정렬 기준 ", count: 12), "이름순"],
            sortType: .name,
            callBack: nil
        )
        sheet.loadViewIfNeeded()
        sheet.view.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        // 문구 높이와 아이콘 위치는 표시 계층에서 확인한다.
        let sheetWindow = host(sheet.view, width: 320)
        defer { sheetWindow.isHidden = true; sheetWindow.rootViewController = nil }
        sheet.view.layoutIfNeeded()
        for row in sheet.stackView.arrangedSubviews {
            guard let label = row.subviews.compactMap({ $0 as? UILabel }).first,
                  let image = row.subviews.compactMap({ $0 as? UIImageView }).first else { continue }
            XCTAssertLessThanOrEqual(label.frame.maxX + 9, image.frame.minX)
            XCTAssertGreaterThanOrEqual(row.bounds.height, label.bounds.height + 19)
        }
        attach(sheet.view, name: "sheet-long-rows-320")
    }

    func testAlertLongContentScrollsAcrossWidthsThemesAndTextSizes() throws {
        for width: CGFloat in [320, 393, 440] {
            for style in [UIUserInterfaceStyle.light, .dark] {
                for category in [UIContentSizeCategory.small, .accessibilityExtraExtraExtraLarge] {
                    // 실제 앱 문구를 교체하지 않고 긴 동적 내용을 테스트에만 주입한다.
                    let alert = MobitAlertViewController(
                        alertType: .canCancel,
                        title: "안내 내용을 확인해 주세요",
                        content: String(repeating: "테스트용 긴 안내입니다. 여러 줄의 내용을 끝까지 읽고 버튼을 누를 수 있어야 합니다.\n", count: 35),
                        callBack: nil
                    )
                    // 작은·접근성 글자 크기를 컨트롤러 trait로 전달한다.
                    let window = hostAlert(alert, width: width, style: style, category: category)
                    defer { window.isHidden = true; window.rootViewController = nil }
                    // 기존 두 스택의 직접 부모가 완성된 카드다.
                    let card = try XCTUnwrap(alert.buttonStackView.superview)
                    // 카드 전체가 늘어나며 스크롤되는 최종 표시 계층이다.
                    let scroll = try XCTUnwrap(card.superview?.superview as? UIScrollView)
                    XCTAssertEqual(alert.traitCollection.preferredContentSizeCategory, category)
                    XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
                    XCTAssertEqual(scroll.contentSize.width, scroll.bounds.width, accuracy: 1)
                    XCTAssertLessThanOrEqual(card.bounds.width, 341)
                    XCTAssertEqual(card.layer.cornerRadius, 24, accuracy: 0.5)
                    XCTAssertGreaterThanOrEqual(alert.confirmButton.bounds.height, 50)
                    XCTAssertEqual(alert.cancelButton.bounds.height, alert.confirmButton.bounds.height, accuracy: 1)
                    XCTAssertEqual(alert.cancelButton.bounds.width, alert.confirmButton.bounds.width, accuracy: 1)
                    XCTAssertTrue(alert.dividerView.isHidden)
                    XCTAssertTrue(alert.buttonDividerView.isHidden)
                    if category.isAccessibilityCategory {
                        XCTAssertGreaterThan(alert.titleLabel.font.pointSize, 20)
                        XCTAssertGreaterThan(alert.contentLabel.font.pointSize, 15)
                        XCTAssertEqual(alert.buttonStackView.axis, .vertical)
                        XCTAssertEqual(alert.cancelButton.bounds.width, alert.buttonStackView.bounds.width, accuracy: 1)
                        XCTAssertEqual(alert.confirmButton.bounds.width, alert.buttonStackView.bounds.width, accuracy: 1)
                        XCTAssertEqual(alert.confirmButton.frame.minY - alert.cancelButton.frame.maxY, 10, accuracy: 1)
                    } else {
                        XCTAssertLessThan(alert.titleLabel.font.pointSize, 20)
                        XCTAssertLessThan(alert.contentLabel.font.pointSize, 15)
                        XCTAssertEqual(alert.buttonStackView.axis, .horizontal)
                        XCTAssertEqual(alert.confirmButton.frame.minX - alert.cancelButton.frame.maxX, 10, accuracy: 1)
                    }
                    for label in [alert.titleLabel, alert.contentLabel] {
                        // 스크롤이 길이를 수용하고 라벨 자체의 텍스트를 압축하지 않아야 한다.
                        let value = try XCTUnwrap(label)
                        XCTAssertGreaterThanOrEqual(
                            value.bounds.height + 1,
                            value.sizeThatFits(CGSize(width: value.bounds.width, height: .greatestFiniteMagnitude)).height
                        )
                    }
                    assertColor(
                        alert.confirmButton.configuration?.background.backgroundColor ?? alert.confirmButton.backgroundColor,
                        matches: .mobitColors(.accentPrimary),
                        traits: alert.traitCollection
                    )
                    // 밝은 primary를 사용하는 다크 테마에서는 기존 배경색 글자로 대비를 유지한다.
                    let foreground = style == .dark ? UIColor.mobitColors(.backgroundPrimary) : .white
                    assertColor(
                        alert.confirmButton.configuration?.baseForegroundColor ?? alert.confirmButton.titleColor(for: .normal),
                        matches: foreground,
                        traits: alert.traitCollection
                    )
                    assertUnambiguous(alert.view, context: "alert long \(width) \(style.rawValue) \(category.rawValue)")
                    scroll.setContentOffset(.zero, animated: false)
                    alert.view.layoutIfNeeded()
                    // 긴 안내에서도 첫 제목은 스크롤의 시작 영역에서 읽을 수 있어야 한다.
                    let titleFrame = alert.titleLabel.convert(alert.titleLabel.bounds, to: alert.view)
                    // Safe Area 안에서 실제로 보이는 스크롤 표시 영역이다.
                    let viewport = scroll.convert(scroll.bounds, to: alert.view)
                    XCTAssertGreaterThanOrEqual(viewport.minY, alert.view.safeAreaLayoutGuide.layoutFrame.minY + 23)
                    XCTAssertLessThanOrEqual(viewport.maxY, alert.view.safeAreaLayoutGuide.layoutFrame.maxY - 23)
                    XCTAssertGreaterThanOrEqual(titleFrame.minY, viewport.minY - 1)
                    attach(alert.view, name: "alert-long-top-\(Int(width))-\(style.rawValue)-\(category.rawValue)")
                    scroll.setContentOffset(
                        CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height),
                        animated: false
                    )
                    alert.view.layoutIfNeeded()
                    // 마지막 버튼과 카드 하단 여백까지 스크롤로 접근할 수 있어야 한다.
                    let buttonsFrame = alert.buttonStackView.convert(alert.buttonStackView.bounds, to: alert.view)
                    XCTAssertGreaterThanOrEqual(buttonsFrame.minY, viewport.minY - 1)
                    XCTAssertLessThanOrEqual(buttonsFrame.maxY, viewport.maxY - 23)
                    attach(alert.view, name: "alert-long-bottom-\(Int(width))-\(style.rawValue)-\(category.rawValue)")
                    if category.isAccessibilityCategory {
                        alert.configure(alertType: .onlyConfirm, title: "", content: alert.contentLabel.text ?? "", callBack: nil)
                        alert.view.setNeedsLayout()
                        alert.view.layoutIfNeeded()
                        XCTAssertTrue(alert.cancelButton.isHidden)
                        XCTAssertTrue(alert.titleLabel.isHidden)
                        XCTAssertEqual(alert.confirmButton.bounds.width, alert.buttonStackView.bounds.width, accuracy: 1)
                        alert.configure(alertType: .canCancel, title: "복원된 제목", content: "복원된 안내", callBack: nil)
                        alert.view.setNeedsLayout()
                        alert.view.layoutIfNeeded()
                        XCTAssertFalse(alert.cancelButton.isHidden)
                        XCTAssertFalse(alert.titleLabel.isHidden)
                        XCTAssertEqual(alert.buttonStackView.axis, .vertical)
                        XCTAssertEqual(alert.cancelButton.bounds.width, alert.buttonStackView.bounds.width, accuracy: 1)
                        // 긴 카드의 이전 스크롤 위치가 짧아진 콘텐츠 밖에 남지 않아야 한다.
                        let maximumOffset = max(0, scroll.contentSize.height - scroll.bounds.height)
                        XCTAssertGreaterThanOrEqual(scroll.contentOffset.y, -1)
                        XCTAssertLessThanOrEqual(scroll.contentOffset.y, maximumOffset + 1)
                        if card.bounds.height <= scroll.bounds.height + 1 {
                            // 카드 전체가 들어오는 경우에는 다시 표시 영역 중앙에 놓인다.
                            let restoredFrame = card.convert(card.bounds, to: alert.view)
                            // 콘텐츠 크기 변경 후 실제 스크롤 표시 영역을 다시 측정한다.
                            let restoredViewport = scroll.convert(scroll.bounds, to: alert.view)
                            XCTAssertGreaterThanOrEqual(restoredFrame.minY, restoredViewport.minY - 1)
                            XCTAssertLessThanOrEqual(restoredFrame.maxY, restoredViewport.maxY + 1)
                            XCTAssertEqual(restoredFrame.midX, restoredViewport.midX, accuracy: 1)
                            XCTAssertEqual(restoredFrame.midY, restoredViewport.midY, accuracy: 1)
                        }
                    }
                }
            }
        }
    }

    func testAlertButtonsDismissBeforeCallingBackExactlyOnce() throws {
        for (alertType, confirmed) in [
            (AlertType.canCancel, false),
            (.canCancel, true),
            (.onlyConfirm, true)
        ] {
            // 실제 모달 표시와 해제 완료 순서까지 확인할 호스트다.
            let presenter = UIViewController()
            // UIKit 표시 계층을 갖는 독립 테스트 창이다.
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = presenter
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            // 버튼 입력 한 번이 중복 결과를 전달하지 않는지 기록한다.
            var results: [Bool] = []
            // dismiss 완료 뒤 기존 Bool 콜백이 호출되어야 한다.
            let completed = expectation(description: "Alert dismissed before callback")
            completed.assertForOverFulfill = true
            // 실제 앱과 같은 전체 화면 위 알럿을 표시한다.
            let alert = MobitAlertViewController(
                alertType: alertType,
                title: "알림 검증",
                content: "테스트용 안내입니다.",
                callBack: { value in
                    XCTAssertNil(presenter.presentedViewController)
                    results.append(value)
                    completed.fulfill()
                }
            )
            alert.modalPresentationStyle = .overFullScreen
            alert.modalTransitionStyle = .crossDissolve
            // 버튼을 누르기 전에 표시 전환이 끝났음을 확인한다.
            let presented = expectation(description: "Alert presentation completed")
            presenter.present(alert, animated: false) { presented.fulfill() }
            wait(for: [presented], timeout: 3)
            XCTAssertTrue(presenter.presentedViewController === alert)
            // IBAction 연결을 포함하는 실제 사용자 입력 경로다.
            let button = try XCTUnwrap(confirmed ? alert.confirmButton : alert.cancelButton)
            XCTAssertFalse(button.isHidden)
            button.sendActions(for: .touchUpInside)
            wait(for: [completed], timeout: 3)
            XCTAssertEqual(results, [confirmed])
            XCTAssertNil(presenter.presentedViewController)
        }
    }

    func testTradeHeaderPreservesRateBeforeCompressingAmount() throws {
        // 등락률보다 긴 절대금액이 먼저 줄어들어야 하는 실제 시세 조합이다.
        let samples: [(price: Double, rate: Double, change: Double)] = [
            (100_000_000, 0.05, 5_000_000),
            (100_000_000, -0.9999, 99_990_000),
            (0.00001234, 0.1234, 0.00000123)
        ]
        for sample in samples {
            // 화면 구독 없이 실제 헤더의 IBOutlet과 포맷을 사용한다.
            let owner = LayoutNibOwner()
            let root = try loadNib("TradeViewController", owner: owner)
            // 짧은 비율은 보존하고 긴 금액의 표시 영역만 압축한다.
            let rate = try XCTUnwrap(owner.outlets["cryptoChangedRate"] as? UILabel)
            // 등락금액의 컨테이너 경계도 함께 검사한다.
            let amount = try XCTUnwrap(owner.outlets["cryptoChangedPrice"] as? UILabel)
            (owner.outlets["cryptoPrice"] as? UILabel)?.text = sample.price.formatTradingValue()
            rate.text = String(format: "%.2f%%", sample.rate * 100)
            amount.text = sample.change.formatTradingValue()
            root.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
            // 헤더도 실제 Safe Area가 있는 표시 계층에서 검사한다.
            let window = host(root, width: 320)
            defer { window.isHidden = true; window.rootViewController = nil }
            root.layoutIfNeeded()
            assertUnambiguous(root, context: "trade header \(sample)")
            XCTAssertGreaterThanOrEqual(rate.bounds.width + 1, rate.intrinsicContentSize.width)
            XCTAssertLessThanOrEqual(rate.frame.maxX + 14, try XCTUnwrap(amount.superview).frame.minX)
        }
    }

    func testHistoryCellFitsMultilineSettlementAndAccessibilityText() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Trait overrides require iOS 17") }
        // BTC 교환손익이 포함된 체결금액과 긴 마켓명을 재현한다.
        let cell = try XCTUnwrap(loadNib("TradeHistoryTableViewCell") as? TradeHistoryTableViewCell)
        cell.marketName.text = "LONG_MARKET_SYMBOL/BTC"
        cell.tradeDate.text = "2026.10.20 12:34:56"
        cell.tradeCryptoPrice.text = "123,456,789.12345678"
        cell.tradeAmount.text = "123,456,789.12345678"
        cell.tradeTotalPrice.text = "123,456,789 원\nBTC 교환손익 +123,456,789 원"
        cell.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
        // 셀의 trait 변경과 실제 자동 높이 계산을 같은 표시 계층에서 수행한다.
        let window = host(cell, width: 320)
        defer { window.isHidden = true; window.rootViewController = nil }
        for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge, .large] {
            window.rootViewController?.traitOverrides.preferredContentSizeCategory = category
            window.rootViewController?.updateTraitsIfNeeded()
            // 줄바꿈과 접근성 축 전환이 끝난 뒤 필요한 높이를 계산한다.
            let size = cell.systemLayoutSizeFitting(
                CGSize(width: 320, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
            cell.frame.size.height = size.height
            cell.setNeedsLayout()
            cell.layoutIfNeeded()
            assertUnambiguous(cell, context: "history \(category.rawValue)")
            for label in [cell.marketName, cell.tradeDate, cell.tradeCryptoPrice, cell.tradeAmount, cell.tradeTotalPrice] {
                // 긴 숫자와 명시적 두 줄 내용이 잘리지 않아야 한다.
                let value = try XCTUnwrap(label)
                XCTAssertGreaterThanOrEqual(
                    value.bounds.height + 1,
                    value.sizeThatFits(CGSize(width: value.bounds.width, height: .greatestFiniteMagnitude)).height
                )
                XCTAssertLessThanOrEqual(value.convert(value.bounds, to: cell.contentView).maxY, size.height + 1)
            }
            attach(cell, name: "history-long-values-\(category.rawValue)")
        }
    }

    private func assertColor(
        _ actual: UIColor?,
        matches expected: UIColor,
        traits: UITraitCollection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Expected a visible color", file: file, line: line)
            return
        }
        // 회색·RGB 색 공간 차이 대신 실제 표시되는 성분을 비교한다.
        var actualComponents = (red: CGFloat(0), green: CGFloat(0), blue: CGFloat(0), alpha: CGFloat(0))
        // 의미 색상은 현재 테마에서 해석한 뒤 비교한다.
        var expectedComponents = (red: CGFloat(0), green: CGFloat(0), blue: CGFloat(0), alpha: CGFloat(0))
        XCTAssertTrue(actual.resolvedColor(with: traits).getRed(&actualComponents.red, green: &actualComponents.green, blue: &actualComponents.blue, alpha: &actualComponents.alpha), file: file, line: line)
        XCTAssertTrue(expected.resolvedColor(with: traits).getRed(&expectedComponents.red, green: &expectedComponents.green, blue: &expectedComponents.blue, alpha: &expectedComponents.alpha), file: file, line: line)
        for (component, expectedComponent) in zip(
            [actualComponents.red, actualComponents.green, actualComponents.blue, actualComponents.alpha],
            [expectedComponents.red, expectedComponents.green, expectedComponents.blue, expectedComponents.alpha]
        ) {
            XCTAssertEqual(component, expectedComponent, accuracy: 0.001, file: file, line: line)
        }
    }

    private func hostAlert(
        _ alert: MobitAlertViewController,
        width: CGFloat,
        style: UIUserInterfaceStyle = .light,
        category: UIContentSizeCategory = .large
    ) -> UIWindow {
        // 실제 컨트롤러에 글자 크기·테마를 전달하는 부모다.
        let container = UIViewController()
        // 작은 화면과 일반 화면의 실제 표시 영역을 제공한다.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: width == 320 ? 568 : 852))
        window.rootViewController = container
        window.overrideUserInterfaceStyle = style
        container.view.frame = window.bounds
        container.addChild(alert)
        container.view.addSubview(alert.view)
        alert.view.frame = container.view.bounds
        alert.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: category), forChild: alert)
        alert.didMove(toParent: container)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        alert.view.layoutIfNeeded()
        return window
    }

    private func host(_ view: UIView, width: CGFloat) -> UIWindow {
        // 외부 크기를 가진 뷰를 화면 생명주기와 분리해 표시한다.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: width == 320 ? 568 : 852))
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(view)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return window
    }

    private func loadNib(_ name: String, owner: LayoutNibOwner? = nil) throws -> UIView {
        // 기본 인스턴스도 메인 액터 안에서 생성한다.
        let nibOwner = owner ?? LayoutNibOwner()
        if name == "MobitBottomSheetViewController" {
            // 빈 스택에는 호출자가 항상 제공하는 정렬 옵션을 실제 경로로 채운다.
            let sheet = MobitBottomSheetViewController(
                titleString: "정렬 방법",
                contentList: ["이름순", "수익률순", "평가금액순"],
                sortType: .name,
                callBack: nil
            )
            nibOwner.outlets["controller"] = sheet
            return sheet.view
        }
        if name == "MoreViewController" {
            // 계좌 카드·광고·메뉴의 콘텐츠 크기를 공급하는 실제 구성 코드를 실행한다.
            let controller = MoreViewController(
                accountsUseCase: MoreAccountsUseCase(
                    spotBalance: { _ in 0 },
                    futuresSnapshot: { FuturesAccountSnapshot(revision: 0, accounts: []) }
                ),
                presentRewardedAd: { _, _ in },
                loadBannerAd: { _ in }
            )
            nibOwner.outlets["controller"] = controller
            return controller.view
        }
        if name == "TradeAverageCalcView" {
            // 초기 숨김과 입력 대상 연결을 포함하는 실제 생성 경로다.
            return TradeAverageCalcView.instanceFromNib(holdingQuantity: 1, holdingAverage: 100, cryptoSymbol: "BTC")
        }
        // File's Owner의 연결을 보존하면서 실제 custom view와 셀을 생성한다.
        let objects = UINib(nibName: name, bundle: Bundle(for: TradeChartView.self))
            .instantiate(withOwner: nibOwner, options: nil)
        // 런타임에 삽입되는 주문 패널이 스크롤 콘텐츠의 높이를 결정한다.
        let root = try XCTUnwrap(objects.compactMap { $0 as? UIView }.first, name)
        if let chart = root as? TradeChartView {
            // symbol이 없으므로 외부 차트를 요청하지 않고 설정 UI만 구성한다.
            chart.configure()
        }
        if let order = root as? TradeOrderView {
            for (index, panelName) in ["TradeBidView", "TradeAskView", "TradeHistoryView"].enumerated() {
                // 실제 주문 탭과 같이 하나의 패널만 표시한다.
                let panel = try loadNib(panelName)
                order.segmentedContainerStackView.addArrangedSubview(panel)
                panel.isHidden = index != 0
            }
        }
        return root
    }

    private func assertUnambiguous(_ view: UIView, context: String) {
        guard !view.isHidden else { return }
        // UIKit 내부 구현 뷰와 외부에서 크기를 제공하는 최상위 뷰는 제외한다.
        if !view.translatesAutoresizingMaskIntoConstraints, view.superview != nil {
            XCTAssertFalse(view.hasAmbiguousLayout, "\(context): \(type(of: view)) \(view.accessibilityIdentifier ?? "") \(view.frame)")
        }
        if view is WKWebView || view is UITableView || view is UICollectionView { return }
        view.subviews.forEach { assertUnambiguous($0, context: context) }
    }

    private func attach(_ view: UIView, name: String) {
        // 잘림·겹침은 제약 모호성 검사만으로 알 수 없으므로 렌더링도 남긴다.
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { context in
            view.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class LayoutNibOwner: NSObject {
    // 화면 생명주기 없이 XIB의 연결 대상들을 로드하는 동안 유지한다.
    var outlets: [String: Any] = [:]

    override func setValue(_ value: Any?, forUndefinedKey key: String) {
        outlets[key] = value
    }
}
