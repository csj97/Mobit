//
//  MobitTests.swift
//  MobitTests
//
//  Created by 조성재 on 7/10/24.
//

import XCTest
import UIKit
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
