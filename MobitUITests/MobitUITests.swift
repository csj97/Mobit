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
            let selector = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS %@", "bit", "˅")
            ).firstMatch
            XCTAssertTrue(selector.waitForExistence(timeout: 10), "거래소 셀렉터 버튼을 찾지 못함")
            selector.tap()
        }

        // Upbit -> Bithumb (액션시트 라벨은 한글: "빗썸")
        tapSelector()
        sleep(1)
        let btnLabels = app.buttons.allElementsBoundByIndex.map { $0.label }.joined(separator: " ⎮ ")
        let sheetExists = app.sheets.firstMatch.exists
        XCTContext.runActivity(named: "AFTER_SELECTOR_TAP sheet=\(sheetExists) buttons=[\(btnLabels)]") { _ in }
        let bithumbAction = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "빗썸")
        ).firstMatch
        XCTAssertTrue(bithumbAction.waitForExistence(timeout: 5), "빗썸 액션 없음")
        bithumbAction.tap()
        sleep(8)
        // 빗썸 전환 직후 알럿(있으면 닫기)
        if app.alerts.firstMatch.waitForExistence(timeout: 2) {
            let msg1 = app.alerts.firstMatch.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " | ")
            XCTContext.runActivity(named: "ALERT_AFTER_UPBIT_TO_BITHUMB: \(msg1)") { _ in }
            app.alerts.buttons.firstMatch.tap()
            sleep(1)
        }

        // Bithumb -> Upbit (액션시트 라벨: "업비트")
        tapSelector()
        let upbitAction = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "업비트")
        ).firstMatch
        XCTAssertTrue(upbitAction.waitForExistence(timeout: 5), "업비트 액션 없음")
        upbitAction.tap()
        sleep(8)

        // 시세 로드 실패 알럿이 뜨는지 + 텍스트(원인 포함) 확인
        let alert = app.alerts.firstMatch
        let appeared = alert.waitForExistence(timeout: 5)
        let msg = appeared
            ? alert.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " | ")
            : "no-alert"
        XCTContext.runActivity(named: "ALERT_AFTER_BITHUMB_TO_UPBIT(appeared=\(appeared)): \(msg)") { _ in }
        XCTAssertFalse(appeared, "빗썸→업비트 전환 후 시세 로드 실패 알럿 발생: \(msg)")
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
