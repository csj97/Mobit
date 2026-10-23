//
//  MobitUITests.swift
//  MobitUITests
//
//  Created by 조성재 on 7/10/24.
//

import XCTest

final class MobitUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testExchangeSwitchBithumbToUpbit() throws {
        let app = XCUIApplication()
        app.launch()

        // 메인 로드 대기
        sleep(6)

        func tapSelector() {
            // 거래소명은 접근성 value에 표시되므로 공통 선택 버튼을 식별한다.
            let selector = app.buttons["main.exchange"]
            XCTAssertTrue(selector.waitForExistence(timeout: 10), "거래소 셀렉터 버튼을 찾지 못함")
            selector.tap()
        }

        // 공통 거래소 시트에서 빗썸을 선택하고 확정한다.
        tapSelector()
        sleep(1)
        let btnLabels = app.buttons.allElementsBoundByIndex.map { $0.label }.joined(separator: " ⎮ ")
        let sheetExists = app.buttons["investment.exchangeConfirm"].exists
        XCTContext.runActivity(named: "AFTER_SELECTOR_TAP sheet=\(sheetExists) buttons=[\(btnLabels)]") { _ in }
        // 선택 행과 상단 거래소 버튼의 이름이 같아도 행만 누른다.
        let bithumbAction = app.buttons["investment.exchangeOption.bithumb"]
        XCTAssertTrue(bithumbAction.waitForExistence(timeout: 5), "빗썸 액션 없음")
        bithumbAction.tap()
        app.buttons["investment.exchangeConfirm"].tap()
        sleep(8)
        // 빗썸 전환 직후 알럿(있으면 닫기)
        if app.buttons["mobitAlert.confirm"].waitForExistence(timeout: 2) {
            // 공통 알림의 본문만 기록해 화면의 다른 문자열을 섞지 않는다.
            let msg1 = app.staticTexts["mobitAlert.content"].label
            XCTContext.runActivity(named: "ALERT_AFTER_UPBIT_TO_BITHUMB: \(msg1)") { _ in }
            if app.buttons["mobitAlert.cancel"].exists {
                app.buttons["mobitAlert.cancel"].tap()
            } else {
                app.buttons["mobitAlert.confirm"].tap()
            }
            sleep(1)
        }

        // 공통 거래소 시트에서 업비트로 돌아간다.
        tapSelector()
        // 선택을 확정하기 전에는 현재 계좌가 바뀌지 않는다.
        let upbitAction = app.buttons["investment.exchangeOption.upbit"]
        XCTAssertTrue(upbitAction.waitForExistence(timeout: 5), "업비트 액션 없음")
        upbitAction.tap()
        app.buttons["investment.exchangeConfirm"].tap()
        sleep(8)

        // 시세 로드 실패 알럿이 뜨는지 + 텍스트(원인 포함) 확인
        // 공통 알림은 시스템 alert가 아닌 앱의 확인 버튼으로 찾는다.
        let confirmButton = app.buttons["mobitAlert.confirm"]
        let appeared = confirmButton.waitForExistence(timeout: 5)
        // 전환 후 새로 표시된 오류 본문을 실패 메시지에 남긴다.
        let msg = appeared
            ? app.staticTexts["mobitAlert.content"].label
            : "no-alert"
        XCTContext.runActivity(named: "ALERT_AFTER_BITHUMB_TO_UPBIT(appeared=\(appeared)): \(msg)") { _ in }
        XCTAssertFalse(appeared, "빗썸→업비트 전환 후 시세 로드 실패 알럿 발생: \(msg)")
    }

    func testExchangeAuditUpbitTradeScreenEntry() throws {
        try verifyTradeScreenEntry(exchangeName: "업비트")
    }

    func testExchangeAuditBithumbTradeScreenEntry() throws {
        try verifyTradeScreenEntry(exchangeName: "빗썸")
    }

    private func verifyTradeScreenEntry(exchangeName: String) throws {
        let app = XCUIApplication()
        app.launch()
        // 공통 거래소 선택 버튼은 현재 거래소명과 무관한 식별자로 찾는다.
        let selector = app.buttons["main.exchange"]
        XCTAssertTrue(selector.waitForExistence(timeout: 20))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: selector
        )], timeout: 20), .completed)
        selector.tap()
        // 앱의 거래소 시트에서 선택한 행을 별도 확인 버튼으로 확정한다.
        let action = app.buttons[exchangeName == "업비트" ? "investment.exchangeOption.upbit" : "investment.exchangeOption.bithumb"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.tap()
        app.buttons["investment.exchangeConfirm"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("BTC")
        let marketCell = app.tables.cells.containing(
            NSPredicate(format: "label CONTAINS %@", "BTC/KRW")
        ).firstMatch
        XCTAssertTrue(marketCell.waitForExistence(timeout: 20), "BTC/KRW 시세 행이 표시되지 않음")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: marketCell
        )], timeout: 20), .completed)
        marketCell.tap()
        XCTAssertTrue(app.buttons["차트"].waitForExistence(timeout: 10), "거래 상세 진입 실패")
        XCTAssertTrue(app.buttons["주문"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(exchangeName) 거래 상세"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
