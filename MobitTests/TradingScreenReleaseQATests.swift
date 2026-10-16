import XCTest
import UIKit
import ReactorKit
import RxSwift
import SkeletonView
@testable import Mobit

final class TradingScreenReleaseQATests: XCTestCase {
  @MainActor
  func testMainFailureSkeletonAndRetryAfterExplicitInitialLayout() throws {
    // 원본 실패 테스트와 같은 미완료 자산 검증 상태다.
    let futures = FuturesAccountReactor(account: .init(exchange: .upbit, product: .perpetual, currency: .krw))
    futures.isStubEnabled = true
    // 실제 목록 요청의 실패와 재시도만 외부 통신 없이 제어한다.
    let response = PublishSubject<CryptoList>()
    // 최초 조회와 재시도의 호출 횟수를 수집한다.
    let useCase = ReleaseQAPendingMarketsUseCase(response: response.asObservable())
    // 실제 오류 mutation을 화면 바인딩에 전달하는 Reactor다.
    let market = MainReactor(mainUseCase: useCase, tickerSocketService: ReleaseQAQuietTickerSocket())
    // 원본 테스트의 중간 컨테이너 계층까지 그대로 재현한다.
    let main = MainViewController(reactor: market, futuresReactor: futures, networkAvailability: .empty())
    // 기존 앱의 key window를 바꾸지 않는 독립 테스트 창이다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    // 복귀 검증 잠금과 목록 로딩을 함께 소유하는 실제 탭 컨테이너다.
    let tabs = MobitTabBarViewController()
    // 실제 계층 깊이가 로딩 종료 전달에 영향을 주지 않아야 한다.
    let wrapper = UIViewController()
    wrapper.addChild(main)
    wrapper.view.addSubview(main.view)
    main.view.frame = window.bounds
    main.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    main.didMove(toParent: wrapper)
    // 실패 시 공통 복귀 표시를 종료하는 실제 Coordinator 경로다.
    let coordinator = MainCoordinator(navigationController: UINavigationController(), dataManager: .shared)
    // 종료 요청 횟수와 탭의 실제 표시 해제를 함께 확인한다.
    let delegate = ReleaseQAIndicatorDelegate()
    delegate.tabs = tabs
    coordinator.delegate = delegate
    main.coordinator = coordinator
    tabs.setViewControllers([wrapper])
    tabs.bindForegroundVerification(futures)
    window.rootViewController = tabs
    window.isHidden = false
    main.viewWillAppear(false)
    defer {
      tabs.bindForegroundVerification(nil)
      main.dismiss(animated: false)
      main.viewWillDisappear(false)
      window.isHidden = true
      window.rootViewController = nil
    }
    func flush() {
      // 원본과 같이 Rx·알럿의 메인 큐 처리를 두 차례 기다린다.
      let rendered = expectation(description: "Explicit layout main error rendered")
      DispatchQueue.main.async { DispatchQueue.main.async { rendered.fulfill() } }
      wait(for: [rendered], timeout: 2)
    }
    flush()
    // 원본 실패 테스트와 달리 가짜 행 계산 전에 실제 테이블 크기를 확정한다.
    window.setNeedsLayout()
    window.layoutIfNeeded()
    main.view.setNeedsLayout()
    main.view.layoutIfNeeded()
    XCTAssertGreaterThan(main.tableView.bounds.width, 0)
    XCTAssertGreaterThan(main.tableView.bounds.height, 0)
    market.action.onNext(.loadCryptoList)
    flush()
    XCTAssertTrue(market.currentState.isLoading)
    XCTAssertTrue(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
    NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    flush()
    XCTAssertNotNil(window.viewWithTag(999999))
    response.onError(NSError(domain: "ReleaseQAMainLoad", code: -1))
    flush()
    XCTAssertFalse(market.currentState.isLoading)
    XCTAssertFalse(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
    XCTAssertFalse(futures.canSubmit)
    XCTAssertGreaterThan(delegate.finishCount, 0)
    XCTAssertTrue(main.coordinator === coordinator)
    // 로딩 실패 알럿의 확인과 재시도가 모두 제공되어야 한다.
    let alert = try XCTUnwrap(main.presentedViewController as? UIAlertController)
    XCTAssertEqual(alert.message, FuturesText.text("market_data_error"))
    XCTAssertEqual(alert.actions.map(\.title), [FuturesText.text("common_confirm"), FuturesText.text("data_retry")])
    // 닫힌 알럿이 남아 재시도 로딩을 막지 않도록 완료를 기다린다.
    let dismissed = expectation(description: "Explicit layout main error dismissed")
    main.dismiss(animated: false) { dismissed.fulfill() }
    wait(for: [dismissed], timeout: 2)
    flush()
    useCase.response = .never()
    main.retryMainData()
    flush()
    XCTAssertEqual(useCase.requests, 2)
    XCTAssertTrue(market.currentState.isLoading)
    XCTAssertNil(market.currentState.errorMessage)
    XCTAssertTrue(main.tableView.sk.isSkeletonActive)
    XCTAssertNil(window.viewWithTag(999999))
  }

  @MainActor
  func testLeavingTradeScreenReleasesOrderFormAndItsSubscriptions() throws {
    // 화면에서 분리한 주문 뷰의 소유권만 관찰한다.
    weak var releasedOrderView: TradeOrderView?
    // 주문 하위 뷰가 공유하던 구독 묶음도 함께 해제되어야 한다.
    weak var releasedBidView: TradeBidView?
    // 매도 상태 구독이 화면 이탈 이후 남지 않는지 확인한다.
    weak var releasedAskView: TradeAskView?
    autoreleasepool {
      // 외부 요청을 실행하지 않는 실제 거래 Reactor다.
      let reactor = makeTradeReactor()
      // 상세 화면이 생성하는 실제 현물 주문 뷰와 동일하다.
      let orderView = TradeOrderView.instanceFromNib(reactor: reactor) { _ in }
      releasedOrderView = orderView
      releasedBidView = orderView.bidView
      releasedAskView = orderView.askView
      XCTAssertNotNil(orderView.dataSource)
    }
    // 메인 큐에 예약된 초기 바인딩·테이블 갱신이 소유권을 잠시 유지할 수 있다.
    let settled = expectation(description: "Order form initial bindings settled")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settled.fulfill() }
    wait(for: [settled], timeout: 3)
    XCTAssertNil(
      releasedOrderView,
      "Leaving trade detail must release its order view and its subscriptions"
    )
    XCTAssertNil(releasedBidView)
    XCTAssertNil(releasedAskView)
    // 실패 시 테스트가 만든 순환 참조를 끊어 뒤 테스트의 Rx 구독에 남기지 않는다.
    releasedOrderView?.dataSource = nil
  }

  @MainActor
  func testSpotBuyEnteredQuantityTotalTracksPriceWithoutAnotherTrade() throws {
    // 두 현물 계좌에서 같은 사용자 시나리오를 재현하고 원래 선택을 복구한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    defer { ExchangeSelectionStore.currentExchange = previousExchange }
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      // KRW 정수 금액과 BTC 소수 금액은 각각 기존 결제 통화로 표시한다.
      let markets: [(market: String, firstPrice: Double, nextPrice: Double, firstText: String, nextText: String)] = [
        ("BTC/KRW", 1_000, 1_200, "1,000", "1,200"),
        ("ETH/BTC", 0.015625, 0.03125, "0.015625", "0.03125")
      ]
      for scenario in markets {
        // 네트워크와 실제 자산 저장 없이 실제 주문 XIB의 바인딩을 검사한다.
        let reactor = makeTradeReactor(market: scenario.market)
        // 수량 입력 이후 시세만 변경되는 사용자 흐름을 재현한다.
        var state = reactor.initialState
        state.cryptoCellInfo = coin(price: scenario.firstPrice, market: scenario.market)
        reactor.stub.state.value = state
        // 화면이 가진 Rx 구독을 테스트 종료와 함께 정리한다.
        let disposeBag = DisposeBag()
        // 실제 사용자의 수량 입력 직후와 같은 주문 폼이다.
        let view = TradeBidView.instanceFromNib(reactor: reactor, disposeBag: disposeBag) { _ in }
        view.inputAmount = 1
        view.inputTradeAmount.text = "1"
        view.totalPriceTextField.text = scenario.firstText
        XCTAssertEqual(view.currentPrice.text, scenario.firstText)

        state.cryptoCellInfo = coin(price: scenario.nextPrice, market: scenario.market)
        reactor.stub.state.value = state

        XCTAssertEqual(view.currentPrice.text, scenario.nextText)
        XCTAssertEqual(view.inputAmount, 1)
        XCTAssertEqual(view.inputTradeAmount.text, "1")
        XCTAssertEqual(view.totalPriceTextField.text, scenario.nextText, "\(exchange) \(scenario.market)")
      }
    }
  }

  @MainActor
  func testSpotBuyTickerPreservesActiveTotalInputAndUpdatesItsQuantity() throws {
    // 입력 중 총액 보존은 두 거래소와 두 결제 통화에서 동일해야 한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    defer { ExchangeSelectionStore.currentExchange = previousExchange }
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      // BTC 입력의 끝자리 0도 시세 이벤트가 임의로 정규화하지 않는다.
      let markets: [(market: String, firstPrice: Double, nextPrice: Double, input: String)] = [
        ("BTC/KRW", 1_000, 2_000, "2000"),
        ("ETH/BTC", 0.015625, 0.03125, "0.03125000")
      ]
      for scenario in markets {
        // 실제 필드의 first responder 상태에서 기존 편집 콜백을 실행한다.
        let reactor = makeTradeReactor(market: scenario.market)
        // 최초 입력은 두 개를 매수할 수 있는 총액이다.
        var state = reactor.initialState
        state.cryptoCellInfo = coin(price: scenario.firstPrice, market: scenario.market)
        reactor.stub.state.value = state
        // 실제 입력 포커스를 제공하되 앱의 기존 key window는 교체하지 않는다.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        // 주문 폼을 표시할 최소 화면 계층이다.
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        // 초기 필드 선택 이후에도 동일한 구독을 유지한다.
        let disposeBag = DisposeBag()
        // 총액을 직접 입력 중인 실제 주문 폼이다.
        let view = TradeBidView.instanceFromNib(reactor: reactor, disposeBag: disposeBag) { _ in }
        host.view.addSubview(view)
        defer {
          window.endEditing(true)
          window.isHidden = true
          window.rootViewController = nil
        }
        XCTAssertTrue(view.totalPriceTextField.becomeFirstResponder())
        view.totalPriceTextField.text = scenario.input
        view.textFieldDidChangeSelection(view.totalPriceTextField)
        XCTAssertEqual(view.inputAmount, 2)

        // 누락·비정상 시세와 주문 정밀도에서 0이 되는 가격은 편집 원본을 오염시키면 안 된다.
        for invalidPrice in [0, -1, Double.nan, Double.infinity, 0.000000001] {
          state.cryptoCellInfo = coin(price: invalidPrice, market: scenario.market)
          reactor.stub.state.value = state
          XCTAssertEqual(view.inputAmount, 2)
          XCTAssertEqual(view.inputTradeAmount.text, "2")
          XCTAssertEqual(view.totalPriceTextField.text, scenario.input)
        }

        state.cryptoCellInfo = coin(price: scenario.nextPrice, market: scenario.market)
        reactor.stub.state.value = state

        XCTAssertTrue(view.totalPriceTextField.isFirstResponder)
        XCTAssertEqual(view.totalPriceTextField.text, scenario.input)
        XCTAssertEqual(view.inputAmount, 1)
        XCTAssertEqual(view.inputTradeAmount.text, "1")
        XCTAssertEqual(view.currentPrice.text, scenario.nextPrice.formatTradingValue())

        // 수량 편집으로 바꾸면 시세는 수량 문자열을 건드리지 않고 총액만 갱신한다.
        XCTAssertTrue(view.inputTradeAmount.becomeFirstResponder())
        view.inputTradeAmount.text = "2."
        view.textFieldDidChangeSelection(view.inputTradeAmount)
        state.cryptoCellInfo = coin(price: scenario.firstPrice, market: scenario.market)
        reactor.stub.state.value = state
        XCTAssertEqual(view.inputTradeAmount.text, "2.")
        XCTAssertEqual(view.inputAmount, 2)
        XCTAssertEqual(view.totalPriceTextField.text, (scenario.firstPrice * 2).formatTradingValue())
      }
    }
  }

  @MainActor
  func testSpotBuyTickerKeepsEmptyAndResetInputsEmpty() throws {
    // 초기 진입·초기화 후 티커가 입력하지 않은 0을 필드에 만들면 안 된다.
    let reactor = makeTradeReactor()
    // 여러 티커가 이어져도 빈 입력 상태를 유지한다.
    var state = reactor.initialState
    state.cryptoCellInfo = coin(price: 1_000)
    reactor.stub.state.value = state
    // 주문 입력이 없는 실제 XIB의 바인딩을 유지한다.
    let disposeBag = DisposeBag()
    // 초기 진입 직후와 리셋 뒤의 사용자 입력 상태를 비교한다.
    let view = TradeBidView.instanceFromNib(reactor: reactor, disposeBag: disposeBag) { _ in }
    state.cryptoCellInfo = coin(price: 1_200)
    reactor.stub.state.value = state
    XCTAssertTrue(view.inputTradeAmount.text?.isEmpty ?? true)
    XCTAssertTrue(view.totalPriceTextField.text?.isEmpty ?? true)
    view.inputAmount = 1
    view.inputTradeAmount.text = "1"
    view.totalPriceTextField.text = "1,200"
    view.initTextFieldValue()
    state.cryptoCellInfo = coin(price: 1_500)
    reactor.stub.state.value = state
    XCTAssertEqual(view.inputAmount, 0)
    XCTAssertTrue(view.inputTradeAmount.text?.isEmpty ?? true)
    XCTAssertTrue(view.totalPriceTextField.text?.isEmpty ?? true)
  }

  @MainActor
  func testSpotSellMaximumAndEnteredTotalTrackPriceWithoutHoldingMutation() throws {
    // 시세 갱신은 동일 거래소의 주문 폼에만 영향을 주어야 한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    defer { ExchangeSelectionStore.currentExchange = previousExchange }
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      // 보유량이 바뀌지 않아도 티커 변화가 금액에 반영되는지 검사한다.
      let reactor = makeTradeReactor()
      // 두 개 보유 중 하나를 매도하는 사용자의 최초 상태다.
      var state = reactor.initialState
      state.cryptoCellInfo = coin(price: 1_000)
      state.cryptoTransactionDatas = [holding(exchange: exchange)]
      reactor.stub.state.value = state
      // 외부 요청 없이 실제 매도 XIB의 상태 구독을 사용한다.
      let disposeBag = DisposeBag()
      // 수량 입력 뒤 표시되는 총액과 최대 매도액을 확인한다.
      let view = TradeAskView.instanceFromNib(reactor: reactor, disposeBag: disposeBag) { _ in }
      view.inputAmount = 1
      view.inputTradeAmount.text = "1"
      view.updateCryptoData()
      XCTAssertEqual(view.availableTradePrice.text, "≈ 2,000")
      XCTAssertEqual(view.totalPriceTextField.text, "1,000")

      state.cryptoCellInfo = coin(price: 1_200)
      reactor.stub.state.value = state

      XCTAssertEqual(view.cryptoInfo?.tradePrice, 1_200)
      XCTAssertEqual(view.inputAmount, 1)
      XCTAssertEqual(
        view.availableTradePrice.text,
        "≈ 2,400",
        "\(exchange): holding 2 at live price 1,200 must show maximum 2,400, not previous amount 2,000"
      )
      XCTAssertEqual(
        view.totalPriceTextField.text,
        "1,200",
        "\(exchange): selling quantity 1 must show the latest price total 1,200"
      )
    }
  }

  @MainActor
  private func makeTradeReactor(market: String = "BTC/KRW") -> TradeReactor {
    // 상태를 직접 주입하므로 시세·호가·저장소 요청은 실행하지 않는다.
    let reactor = TradeReactor(
      selectCrypto: coin(price: 1_000, market: market),
      cmcInformation: nil,
      cryptoDetailUseCase: CryptoDetailUseCase(cryptoDetailRepository: CryptoDetailRepository()),
      mainUseCase: MainUseCase(mainRepository: MainRepository())
    )
    reactor.isStubEnabled = true
    return reactor
  }

  private func coin(price: Double, market: String = "BTC/KRW") -> CryptoCellInfo {
    CryptoCellInfo(cryptoName: "Bitcoin", market: market, tradePrice: price)
  }

  private func holding(exchange: Exchange) -> CryptoTransactionDataModel {
    CryptoTransactionDataModel(
      staticData: .init(
        exchange: exchange,
        marketName: "BTC/KRW",
        cryptoName: "Bitcoin",
        holdingQuantity: 2,
        averageBuyPrice: 1_000,
        buyAmount: 2_000
      ),
      dynamicData: .init(
        exchange: exchange,
        marketName: "BTC/KRW",
        profitRate: 0,
        evaluationProfitLoss: 0,
        evaluationPrice: 2_000
      )
    )
  }
}

private final class ReleaseQAPendingMarketsUseCase: MainUseCase {
  // 실패 후 재시도에 다른 응답을 주입한다.
  var response: Observable<CryptoList>
  // 초기 레이아웃 처리가 중복 조회를 만들지 않는지 확인한다.
  private(set) var requests = 0

  init(response: Observable<CryptoList>) {
    self.response = response
    super.init(mainRepository: MainRepository())
  }

  override func fetchCryptoList() -> Observable<CryptoList> {
    requests += 1
    return response
  }

  override func fetchCryptoTicker(markets: [String]) -> Observable<CryptoTickerList> { .never() }
  override func fetchFearGreedIndex() -> Observable<FearGreedIndex> { .never() }
}

private final class ReleaseQAQuietTickerSocket: TickerSocketServiceProtocol {
  // 테스트가 실제 WebSocket에 연결되지 않도록 상태만 기록한다.
  var isConnected = false
  // 목록 실패 전에는 시세 이벤트를 발생시키지 않는다.
  var stream: Observable<CryptoSocketTicker> { .empty() }
  func connect() { isConnected = true }
  func disconnect(userInitiated: Bool) { isConnected = false }
  func reconnectIfNeeded() { connect() }
  func subscribe(markets: [String]) {}
}

private final class ReleaseQAIndicatorDelegate: MainCoordinatorDelegate {
  // 목록 실패가 공통 복귀 표시를 종료했는지 기록한다.
  private(set) var finishCount = 0
  // 부모 탭의 생명주기를 테스트가 연장하지 않는다.
  weak var tabs: MobitTabBarViewController?

  func mainCoordinatorDidRequestFinishForegroundIndicator() {
    finishCount += 1
    tabs?.finishForegroundIndicator()
  }
}
