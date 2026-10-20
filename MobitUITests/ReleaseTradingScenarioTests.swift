import XCTest

final class ReleaseTradingScenarioTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testFourAccountNavigationAndMarketAvailability() throws {
    // 실제 앱을 통해 거래소와 상품을 바꿀 때 표시되는 거래 범위를 확인한다.
    let application = XCUIApplication()
    application.launchArguments += ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
    application.launch()
    for exchangeName in ["업비트", "빗썸"] {
      try selectExchange(exchangeName, in: application)
      application.buttons["selectSpot"].tap()
      XCTAssertTrue(application.buttons["BTC마켓"].waitForExistence(timeout: 10))
      capture("\(exchangeName) 현물 메인", application: application)
      try openBitcoinOrder(in: application)
      XCTAssertTrue(application.buttons["매수"].exists)
      XCTAssertTrue(application.buttons["매도"].exists)
      XCTAssertFalse(application.textFields["futuresMargin"].exists)
      capture("\(exchangeName) 현물 주문", application: application)
      navigateBack(in: application)
      XCTAssertTrue(application.buttons["selectFutures"].waitForExistence(timeout: 10))
      application.buttons["selectFutures"].tap()
      XCTAssertTrue(application.staticTexts["futures.main.equity"].waitForExistence(timeout: 10))
      XCTAssertFalse(application.buttons["BTC마켓"].exists)
      capture("\(exchangeName) 선물 메인", application: application)
      try openBitcoinOrder(in: application)
      XCTAssertTrue(application.textFields["futuresMargin"].waitForExistence(timeout: 10))
      XCTAssertTrue(application.buttons["futuresSubmit"].exists)
      XCTAssertTrue(application.descendants(matching: .any)["futuresLeverage"].exists)
      capture("\(exchangeName) 선물 주문", application: application)
      navigateBack(in: application)
      XCTAssertTrue(application.buttons["selectSpot"].waitForExistence(timeout: 10))
      application.buttons["selectSpot"].tap()
      XCTAssertTrue(application.buttons["BTC마켓"].waitForExistence(timeout: 10))
    }
  }

  func testMoreResetSheetSelectsEachAccountWithoutResetting() throws {
    // 한국어 화면에서 초기화 선택과 취소 흐름을 확인한다.
    let application = XCUIApplication()
    application.launchArguments += ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
    application.launch()
    // 커스텀 탭바의 더보기 레이블로 화면을 연다.
    let moreTab = application.staticTexts["더보기"].firstMatch
    XCTAssertTrue(moreTab.waitForExistence(timeout: 25))
    moreTab.tap()
    // 화면 아래의 초기화 메뉴가 보일 때까지 스크롤한다.
    let resetButton = application.buttons["more.reset"]
    XCTAssertTrue(resetButton.waitForExistence(timeout: 10))
    for _ in 0..<6 where !resetButton.isHittable {
      application.scrollViews.firstMatch.swipeUp()
    }
    XCTAssertTrue(resetButton.isHittable)
    // 거래소별 현물·선물 네 행의 독립적인 선택을 검사한다.
    let accountIdentifiers = ["upbit.spot", "upbit.perpetual", "bithumb.spot", "bithumb.perpetual"]
    resetButton.tap()
    // 계좌 목록과 고정 하단 동작을 가진 앱의 새 초기화 시트다.
    let accountSheet = application.descendants(matching: .any)["reset.card"].firstMatch
    XCTAssertTrue(accountSheet.waitForExistence(timeout: 5))
    // 스크롤 여부와 무관하게 네 계좌의 선택 영역이 모두 존재해야 한다.
    for identifier in accountIdentifiers {
      XCTAssertTrue(application.buttons["reset.account.\(identifier)"].exists)
    }
    XCTAssertTrue(application.buttons["reset.cancel"].isHittable)
    XCTAssertTrue(application.buttons["reset.confirm"].isHittable)
    // 최종 실행 버튼을 누르지 않고 계좌 선택만 바꾸어 실제 데이터를 보존한다.
    for identifier in accountIdentifiers {
      // 작은 화면에서는 본문만 스크롤하여 선택할 계좌를 찾는다.
      let accountButton = application.buttons["reset.account.\(identifier)"]
      for _ in 0..<4 where !accountButton.isHittable {
        application.scrollViews["reset.scroll"].swipeUp()
      }
      XCTAssertTrue(accountButton.isHittable)
      accountButton.tap()
      XCTAssertTrue(accountButton.isSelected)
      XCTAssertTrue(accountSheet.exists, "계좌 선택만으로 초기화를 실행하면 안 된다")
      XCTAssertEqual(accountIdentifiers.filter { application.buttons["reset.account.\($0)"].isSelected }, [identifier])
      XCTAssertTrue(application.staticTexts["reset.warning"].exists)
      capture("초기화 계좌 선택 \(identifier)", application: application)
    }
    application.buttons["reset.cancel"].tap()
    expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: accountSheet)
    waitForExpectations(timeout: 5)
    // 시트의 두 닫기 경로 모두 초기화 없이 더보기로 돌아와야 한다.
    for identifier in ["reset.cancel", "reset.close"] {
      resetButton.tap()
      // 같은 식별자로 찾은 실제 닫기 버튼만 누른다.
      let dismissButton = application.buttons[identifier]
      XCTAssertTrue(dismissButton.waitForExistence(timeout: 5))
      dismissButton.tap()
      expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: dismissButton)
      waitForExpectations(timeout: 5)
      XCTAssertTrue(resetButton.isHittable)
    }
  }

  private func selectExchange(_ exchangeName: String, in application: XCUIApplication) throws {
    // 거래소명은 접근성 value에 있으므로 고정 식별자로 선택 버튼을 찾는다.
    let selector = application.buttons["main.exchange"]
    XCTAssertTrue(selector.waitForExistence(timeout: 25))
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: selector)],
        timeout: 15
      ),
      .completed
    )
    selector.tap()
    // 현재 공용 거래소 시트에서 선택을 확정해야 메인 계좌가 바뀐다.
    let exchangeAction = application.buttons[exchangeName == "업비트" ? "investment.exchangeOption.upbit" : "investment.exchangeOption.bithumb"]
    XCTAssertTrue(exchangeAction.waitForExistence(timeout: 5))
    exchangeAction.tap()
    application.buttons["investment.exchangeConfirm"].tap()
  }

  private func openBitcoinOrder(in application: XCUIApplication) throws {
    // 같은 KRW 종목으로 현물과 선물의 주문 화면을 비교한다.
    let searchField = application.searchFields.firstMatch
    XCTAssertTrue(searchField.waitForExistence(timeout: 10))
    searchField.tap()
    if !(searchField.value as? String ?? "").isEmpty,
      application.buttons["Clear text"].exists {
      application.buttons["Clear text"].tap()
    }
    searchField.typeText("BTC")
    // 네트워크 시세가 실제로 표시된 행을 선택한다.
    let marketCell = application.tables.cells.containing(
      NSPredicate(format: "label CONTAINS %@", "BTC/KRW")
    ).firstMatch
    XCTAssertTrue(marketCell.waitForExistence(timeout: 25), "BTC/KRW 시세 로드 실패")
    marketCell.tap()
    XCTAssertTrue(application.buttons["주문"].waitForExistence(timeout: 10))
    application.buttons["주문"].tap()
  }

  private func capture(_ name: String, application: XCUIApplication) {
    // 화면 결과를 xcresult에 남겨 실제 렌더링을 확인한다.
    let attachment = XCTAttachment(screenshot: application.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func navigateBack(in application: XCUIApplication) {
    // 상세 화면은 시스템 내비게이션 바 대신 XIB의 뒤로가기 버튼을 사용한다.
    let backButton = application.buttons.firstMatch
    XCTAssertTrue(backButton.exists)
    backButton.tap()
  }
}
