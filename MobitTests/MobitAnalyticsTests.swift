import XCTest
@testable import Mobit

#if DEBUG
final class MobitAnalyticsTests: XCTestCase {
  func testFourAccountsHaveDistinctKoreanNamesAndStableIdentifiers() {
    // 사용자 계좌 번호 대신 거래소와 상품 조합만 분석에 사용한다.
    let expectedNames = ["업비트_현물", "업비트_선물", "빗썸_현물", "빗썸_선물"]
    // 앱에서 실제 제공하는 네 계좌를 같은 순서로 검사한다.
    let accounts = MoreAccountsUseCase.accounts
    XCTAssertEqual(accounts.count, expectedNames.count)
    for (account, expectedName) in zip(accounts, expectedNames) {
      // 콘솔 한글 표시와 기존 영문 식별자가 함께 유지되어야 한다.
      let parameters = MobitAnalyticsUtil.accountParameters(account)
      XCTAssertEqual(parameters["account_name"] as? String, expectedName)
      XCTAssertEqual(parameters["exchange"] as? String, account.exchange.rawValue)
      XCTAssertEqual(parameters["product"] as? String, account.product.rawValue)
      XCTAssertEqual(parameters["currency"] as? String, "KRW")
      XCTAssertEqual(parameters.count, 6)
    }
  }

  func testSpotBTCMarketDoesNotBecomeAnotherAccount() {
    // 현물 BTC 마켓도 업비트 현물 계좌에 속한다.
    let instrument = TradingInstrumentID(exchange: .upbit, product: .spot, rawSymbol: "BTC-ETH", settlementCurrency: .btc)
    // 계좌 통화와 실제 결제 마켓 통화를 구분한다.
    let parameters = MobitAnalyticsUtil.accountParameters(nil, instrument: instrument)
    XCTAssertEqual(parameters["account_name"] as? String, "업비트_현물")
    XCTAssertEqual(parameters["currency"] as? String, "KRW")
    XCTAssertEqual(parameters["market_currency"] as? String, "BTC")
    XCTAssertEqual(parameters["market"] as? String, "BTC-ETH")
  }

  func testDifferentAccountInstrumentCannotMixAnalyticsContext() {
    // 요청 계좌와 다른 거래소 시세가 전달돼도 종목 문맥을 섞지 않는다.
    let instrument = TradingInstrumentID(exchange: .bithumb, product: .perpetual, rawSymbol: "KRW-BTC", settlementCurrency: .krw)
    // 원래 업비트 현물 계좌만 남고 불일치 종목은 제외된다.
    let parameters = MobitAnalyticsUtil.accountParameters(.spot(for: .upbit), instrument: instrument)
    XCTAssertEqual(parameters["account_name"] as? String, "업비트_현물")
    XCTAssertNil(parameters["market"])
    XCTAssertNil(parameters["market_currency"])
  }

  func testAdditionalParametersCannotReplaceCapturedAccountOrBehavior() {
    // 부가 지표가 계좌 식별자와 한글 행동 경로를 덮어쓰는 실수를 차단한다.
    let parameters = MobitAnalyticsUtil.eventParameters(
      location: "더보기_화면",
      stepDepth01: "계좌_초기화",
      stepDepth02: "초기화_성공",
      account: .spot(for: .upbit),
      extraParameters: ["exchange": "bithumb", "account_name": "빗썸_선물", "Step_depth_02": "다른_행동", "entry_point": "초기화_시트"]
    )
    XCTAssertEqual(parameters["exchange"] as? String, "upbit")
    XCTAssertEqual(parameters["account_name"] as? String, "업비트_현물")
    XCTAssertEqual(parameters["Step_depth_02"] as? String, "초기화_성공")
    XCTAssertEqual(parameters["entry_point"] as? String, "초기화_시트")
  }

  @MainActor
  func testExistingEventsKeepNamesAndKoreanBehaviorPaths() {
    // 이벤트명을 바꾸지 않아 기존 콘솔 보고서의 연속성을 유지한다.
    let events = captureEvents {
      MobitAnalyticsUtil.sendScreenEvent(event: .trade_order)
      MobitAnalyticsUtil.sendClickEvent(event: .trade_order_buy_complete)
      MobitAnalyticsUtil.sendAdEvent(event: .reward_finish)
    }
    XCTAssertEqual(events.map { $0.name }, ["mobit_screen_event", "mobit_click_event", "mobit_ad_event"])
    XCTAssertEqual(events.map { $0.parameters["Step_depth_02"] as? String }, ["트레이딩_탭_주문", "트레이딩_주문_매수_성공", "광고_시청_완료"])
    XCTAssertTrue(events.allSatisfy { $0.parameters["account_name"] == nil })
  }

  @MainActor
  func testCapturedAccountIsIndependentOfGlobalSelectionAndEventType() {
    // 테스트가 전역 거래소·상품 설정을 다음 시나리오에 남기지 않게 복구한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    // 분석 대상은 실제 요청 계좌이므로 현재 모드와 달라도 유지한다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    defer {
      ExchangeSelectionStore.currentExchange = previousExchange
      ExchangeSelectionStore.currentProduct = previousProduct
    }
    ExchangeSelectionStore.currentExchange = .upbit
    ExchangeSelectionStore.currentProduct = .spot
    // 빗썸 선물 충전을 요청한 뒤 화면의 전역 선택이 달라진 상황이다.
    let account = TradingAccountID(exchange: .bithumb, product: .perpetual, currency: .krw)
    // 화면·클릭·광고가 모두 같은 명시적 계좌를 전송하는지 검사한다.
    let events = captureEvents {
      MobitAnalyticsUtil.sendScreenEvent(location: "선물_주문_화면", stepDepth01: "선물_주문", stepDepth02: "거래내역_조회", account: account)
      MobitAnalyticsUtil.sendClickEvent(location: "더보기_화면", stepDepth01: "계좌_충전", stepDepth02: "충전_확인", account: account)
      MobitAnalyticsUtil.sendAdEvent(event: .reward_present, account: account)
    }
    XCTAssertEqual(events.count, 3)
    XCTAssertTrue(events.allSatisfy { $0.parameters["account_name"] as? String == "빗썸_선물" })
    XCTAssertTrue(events.allSatisfy { $0.parameters["exchange"] as? String == "bithumb" })
  }

  func testEventParametersFitFirebaseLimitsAndExcludeAssetData() {
    // 가장 상세한 선물 행동도 Firebase의 25개 파라미터 제한 안에서 전송한다.
    let parameters = MobitAnalyticsUtil.eventParameters(
      location: "선물_주문_화면",
      stepDepth01: "선물_진입",
      stepDepth02: "주문_실패",
      stepDepth03: "추가_진입",
      account: TradingAccountID(exchange: .upbit, product: .perpetual, currency: .krw),
      instrument: TradingInstrumentID(exchange: .upbit, product: .perpetual, rawSymbol: "KRW-BTC", settlementCurrency: .krw),
      extraParameters: ["side": "롱", "leverage": 10, "failure_reason": "시세_확인_필요"]
    )
    XCTAssertLessThanOrEqual(parameters.count, 25)
    for (key, value) in parameters {
      XCTAssertLessThanOrEqual(key.count, 40)
      XCTAssertNotNil(key.range(of: "^[A-Za-z][A-Za-z0-9_]*$", options: .regularExpression))
      if let text = value as? String { XCTAssertLessThanOrEqual(text.count, 100) }
      else { XCTAssertTrue(value is Int || value is Double) }
    }
    XCTAssertTrue(Set(parameters.keys).isDisjoint(with: ["balance", "quantity", "margin", "price", "pnl", "request_id", "position_id", "reward_id"]))
  }

  @MainActor
  func testPushOpenSendsOneCustomEventWithOnlyNormalizedParameters() {
    // 실제 탭 호출 한 번이 기본 Firebase 이벤트와 중복되지 않는지 확인한다.
    let events = captureEvents {
      MobitAnalyticsUtil.sendPushOpenEvent(
        destination: "  InVeStMeNt\n",
        campaignID: "  notice_2026-10.23\n"
      )
    }
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events.first?.name, "push_open")
    XCTAssertEqual(events.first?.parameters["destination"] as? String, "investment")
    XCTAssertEqual(events.first?.parameters["campaign_id"] as? String, "notice_2026-10.23")
    XCTAssertEqual(Set(events.first?.parameters.keys.map { $0 } ?? []), ["destination", "campaign_id"])
  }

  @MainActor
  func testPushOpenOmitsMissingOrInvalidCampaignIdentifiers() {
    // 빈 식별자와 원문·URL 같은 잘못된 캠페인 값은 전송하지 않는다.
    let campaignIDs: [String?] = [nil, " \n", "notice message", "https://example.com", "notice\n2026"]
    for campaignID in campaignIDs {
      // 캠페인이 없어도 한 번의 앱 진입 이벤트는 유지한다.
      let events = captureEvents {
        MobitAnalyticsUtil.sendPushOpenEvent(destination: "app", campaignID: campaignID)
      }
      XCTAssertEqual(events.count, 1)
      XCTAssertEqual(events.first?.name, "push_open")
      XCTAssertEqual(events.first?.parameters["destination"] as? String, "app")
      XCTAssertEqual(events.first?.parameters.count, 1)
    }
  }

  @MainActor
  func testPushOpenUsesAppForInvalidDestinationAndLimitsCampaignLength() {
    // Firebase의 최대 문자열 길이보다 긴 운영 캠페인 식별자를 준비한다.
    let campaignID = String(repeating: "a", count: 120)
    // 임의 경로는 앱 진입으로 정규화하고 식별자는 앞의 100자만 남긴다.
    let events = captureEvents {
      MobitAnalyticsUtil.sendPushOpenEvent(destination: "unknown?token=value", campaignID: campaignID)
    }
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events.first?.parameters["destination"] as? String, "app")
    XCTAssertEqual(events.first?.parameters["campaign_id"] as? String, String(repeating: "a", count: 100))
  }

  @MainActor
  func testPushOpenPreservesEveryTabAndNewDestinationIdentifier() {
    // 지원 화면의 추가가 분석 유틸의 별도 허용 목록을 요구하지 않아야 한다.
    let destinations = ["exchange", "investment", "news", "more", "new_screen"]
    for destination in destinations {
      // 화면 이름의 형식만 정규화하고 값 자체는 유지하는지 확인한다.
      let events = captureEvents {
        MobitAnalyticsUtil.sendPushOpenEvent(destination: " \(destination.uppercased())\n", campaignID: nil)
      }
      XCTAssertEqual(events.count, 1)
      XCTAssertEqual(events.first?.name, "push_open")
      XCTAssertEqual(events.first?.parameters["destination"] as? String, destination)
      XCTAssertEqual(events.first?.parameters.count, 1)
    }
  }

  @MainActor
  func testPushOpenPreservesNormalizedActionAndMaximumLengthIdentifiers() {
    // 식별자 규칙의 최대 길이인 40자를 화면과 동작에 동일하게 적용한다.
    let maximumLengthIdentifier = "a" + String(repeating: "1", count: 39)
    // 등록된 동작 목록과 무관하게 유효한 식별자를 분석에 남긴다.
    let actions = ["  SHOW_NOTICE\n", maximumLengthIdentifier]
    for action in actions {
      // 선택적인 동작이 다른 푸시 식별자와 함께 한 번만 기록돼야 한다.
      let events = captureEvents {
        MobitAnalyticsUtil.sendPushOpenEvent(
          destination: maximumLengthIdentifier,
          action: action,
          campaignID: "action_notice"
        )
      }
      XCTAssertEqual(events.count, 1)
      XCTAssertEqual(events.first?.parameters["destination"] as? String, maximumLengthIdentifier)
      XCTAssertEqual(events.first?.parameters["action"] as? String, action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
      XCTAssertEqual(events.first?.parameters["campaign_id"] as? String, "action_notice")
      XCTAssertEqual(events.first?.parameters.count, 3)
    }
  }

  @MainActor
  func testPushOpenFallsBackForInvalidDestinationAndOmitsInvalidAction() {
    // 빈 값·문장·URL·숫자 시작·비ASCII·길이 초과를 식별자로 사용하지 않는다.
    let invalidIdentifiers = ["", " \n", "show notice", "https://example.com", "1screen", "화면", String(repeating: "a", count: 41)]
    for identifier in invalidIdentifiers {
      // 잘못된 목적지는 앱 진입으로 대체하고 잘못된 동작은 제외한다.
      let events = captureEvents {
        MobitAnalyticsUtil.sendPushOpenEvent(
          destination: identifier,
          action: identifier,
          campaignID: nil
        )
      }
      XCTAssertEqual(events.count, 1)
      XCTAssertEqual(events.first?.parameters["destination"] as? String, "app")
      XCTAssertNil(events.first?.parameters["action"])
      XCTAssertEqual(events.first?.parameters.count, 1)
    }
  }

  private func captureEvents(_ action: () -> Void) -> [(name: String, parameters: [String: Any])] {
    // 동기식 공통 전송 경계를 검사하고 SDK 업로드는 대체한다.
    var events: [(name: String, parameters: [String: Any])] = []
    // 다른 계측 테스트가 설치한 콜백이 있다면 원래대로 복원한다.
    let previousCallBack = MobitAnalyticsUtil.eventCallBack
    MobitAnalyticsUtil.eventCallBack = { events.append(($0, $1)) }
    defer { MobitAnalyticsUtil.eventCallBack = previousCallBack }
    action()
    return events
  }
}
#endif
