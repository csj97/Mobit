import XCTest
import UIKit
import ReactorKit
import RxSwift
@testable import Mobit

final class SpotAccountIsolationQATests: XCTestCase {
  // 테스트가 실제 선물 저장 파일에 접근하지 않도록 전용 경로를 쓴다.
  private var directory: URL!
  // 네 계좌의 거래가 기록되는 선물 파일을 다시 여는 데 사용한다.
  private var futuresURL: URL { directory.appendingPathComponent("accounts.json") }
  // 기존 사용자 저장값을 테스트 전후에 보존한다.
  private var originalDefaults: [String: Any] = [:]
  // 현물 전체 상태와 선택 계좌를 함께 복구할 저장 키다.
  private let defaultsKeys = [
    UserDataManager.Keys.pendingInvestmentState,
    UserDataManager.Keys.isFirstLaunch,
    UserDataManager.Keys.userCryptoList,
    UserDataManager.Keys.userTransactionList,
    UserDataManager.Keys.userValidTransactionList,
    UserDataManager.Keys.userPNLHistory,
    UserDataManager.Keys.userInformation,
    UserDataManager.Keys.userInformationByExchange,
    "selected-exchange",
    "selected-trading-product"
  ]

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    for key in defaultsKeys {
      originalDefaults[key] = UserDefaults.standard.object(forKey: key)
      UserDefaults.standard.removeObject(forKey: key)
    }
    ExchangeSelectionStore.currentExchange = .upbit
    ExchangeSelectionStore.currentProduct = .spot
  }

  override func tearDownWithError() throws {
    for key in defaultsKeys {
      UserDefaults.standard.set(originalDefaults[key], forKey: key)
    }
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
    try super.tearDownWithError()
  }

  func testFourAccountTradingKeepsCashHoldingsAndHistoryIndependentAfterReopening() throws {
    XCTAssertTrue(UserDataManager.seedInitialUserInformationIfNeeded())
    // 선물 두 계좌는 실제 로컬 저장소와 동일한 경로로 생성·충전한다.
    let futuresStore = LocalFuturesAccountRepository(fileURL: futuresURL)
    for exchange in [Exchange.upbit, .bithumb] {
      // 표시 중인 계좌가 달라도 광고를 시작한 현물 계좌에만 지급한다.
      let spotClaim = try AdRewardClaim(account: .spot(for: exchange))
      ExchangeSelectionStore.currentExchange = exchange == .upbit ? .bithumb : .upbit
      ExchangeSelectionStore.currentProduct = .perpetual
      try UserDataManager.applyAdvertisementReward(spotClaim)
      try UserDataManager.applyAdvertisementReward(spotClaim)
      // 현물과 같은 거래소·종목이어도 별개의 선물 계좌와 체결 이력이다.
      let order = domesticFuturesOrder(exchange: exchange)
      try futuresStore.ensureAccount(order.account)
      try futuresStore.applyAdvertisementReward(AdRewardClaim(account: order.account))
      _ = try futuresStore.openTestPosition(order, expectedRevision: futuresStore.snapshot().revision)
      _ = try TradeOrderService.executeBid(
        marketName: "BTC/KRW",
        cryptoName: "비트코인",
        currentPrice: 100_000_000,
        quantity: 0.01,
        exchange: exchange
      ).get()
      _ = try TradeOrderService.executeAsk(
        marketName: "BTC/KRW",
        currentPrice: 110_000_000,
        quantity: 0.005,
        exchange: exchange
      ).get()
    }

    // 다른 저장소 인스턴스에서도 지급액·증거금·체결 이력이 유지되어야 한다.
    let reopened = try LocalFuturesAccountRepository(fileURL: futuresURL).snapshot()
    for exchange in [Exchange.upbit, .bithumb] {
      // 최초 지급액은 업비트 현물에만 포함된다.
      let expectedSpotBalance: Double = exchange == .upbit ? 10_550_000 : 9_550_000
      XCTAssertEqual(try UserDataManager.getAvailableBalance(for: exchange), expectedSpotBalance)
      // 매도 후 현물 BTC 수량과 실현손익은 선물 포지션에 영향을 주지 않는다.
      let holding = try XCTUnwrap(UserDataManager.userCryptoList?.first { $0.staticData.exchange == exchange })
      XCTAssertEqual(holding.staticData.holdingQuantity, 0.005, accuracy: 1e-12)
      XCTAssertEqual(holding.staticData.costBasisKRW, 500_000)
      XCTAssertEqual(UserDataManager.userTransactionList?.filter { $0.exchange == exchange }.count, 2)
      XCTAssertEqual(UserDataManager.userPNLHistory?.first { $0.exchange == exchange }?.realizedProfitLossKRW, 50_000)
      // 선물은 증거금 10만 원만 예약하고 현물 매도대금을 받지 않는다.
      let account = TradingAccountID(exchange: exchange, product: .perpetual, currency: .krw)
      XCTAssertEqual(reopened.accounts.first { $0.id == account }?.availableBalance, 9_900_000)
      XCTAssertEqual(reopened.positions.filter { $0.order.account == account }.count, 1)
      XCTAssertEqual(try reopened.transactionHistory(for: account).count, 1)
    }
    XCTAssertEqual(UserDataManager.userCryptoList?.count, 2)
    XCTAssertEqual(UserDataManager.userTransactionList?.count, 4)
    XCTAssertEqual(UserDataManager.userPNLHistory?.count, 2)
    XCTAssertEqual(reopened.positions.count, 2)
    XCTAssertEqual(reopened.ledger.count, 2)

    // 실제 저장소를 읽는 더보기 목록도 네 계좌의 순서와 금액을 그대로 표시한다.
    let accounts = MoreAccountsUseCase(
      futuresSnapshot: { try LocalFuturesAccountRepository(fileURL: self.futuresURL).snapshot() },
      scheduler: CurrentThreadScheduler.instance
    )
    // 동기 스케줄러에서 API·광고 요청 없이 계좌 목록 결과를 수집한다.
    var displayedBalances: [Decimal?] = []
    accounts.fetchBalances().subscribe(onSuccess: { displayedBalances = $0.map(\.availableBalance) }, onFailure: {
      XCTFail("네 계좌 조회 실패: \($0)")
    }).dispose()
    XCTAssertEqual(displayedBalances, [10_550_000, 9_900_000, 9_550_000, 9_900_000])
  }

  func testSpotResetPreservesBothFuturesPositionsAndNeverReplaysOldRewards() throws {
    XCTAssertTrue(UserDataManager.seedInitialUserInformationIfNeeded())
    // 초기화 전후 선물 파일의 바이트와 모든 이력을 비교한다.
    let futuresStore = LocalFuturesAccountRepository(fileURL: futuresURL)
    // 초기화 뒤 재전달되는 기존 광고 콜백이 자금을 다시 만들면 안 된다.
    let spotClaim = try AdRewardClaim(account: .spot(for: .upbit))
    try UserDataManager.applyAdvertisementReward(spotClaim)
    for exchange in [Exchange.upbit, .bithumb] {
      try UserDataManager.updateUserInformation(for: exchange) { $0.userAvailableBalance += 1_000_000 }
      _ = try TradeOrderService.executeBid(
        marketName: "ETH/KRW",
        cryptoName: "이더리움",
        currentPrice: 100_000,
        quantity: 1,
        exchange: exchange
      ).get()
      // 현물과 같은 종목을 양 거래소 선물에도 보유한다.
      let order = domesticFuturesOrder(exchange: exchange, symbol: "KRW-ETH")
      try futuresStore.ensureAccount(order.account)
      try futuresStore.applyAdvertisementReward(AdRewardClaim(account: order.account))
      _ = try futuresStore.openTestPosition(order, expectedRevision: futuresStore.snapshot().revision)
    }
    // 초기화 대상에 포함되지 않는 선물 계좌의 원본 파일이다.
    let futuresBytes = try Data(contentsOf: futuresURL)
    ExchangeSelectionStore.currentExchange = .bithumb
    ExchangeSelectionStore.currentProduct = .perpetual
    XCTAssertTrue(UserDataManager.resetInvestmentData())
    try UserDataManager.applyAdvertisementReward(spotClaim)
    XCTAssertEqual(try UserDataManager.getAvailableBalance(for: .upbit), 0)
    XCTAssertEqual(try UserDataManager.getAvailableBalance(for: .bithumb), 0)
    XCTAssertEqual(UserDataManager.userCryptoList?.count, 0)
    XCTAssertEqual(UserDataManager.userTransactionList?.count, 0)
    XCTAssertEqual(UserDataManager.userValidTransactionList?.count, 0)
    XCTAssertEqual(UserDataManager.userPNLHistory?.count, 0)
    XCTAssertFalse(UserDataManager.seedInitialUserInformationIfNeeded())
    XCTAssertEqual(try Data(contentsOf: futuresURL), futuresBytes)
    // 재실행 시에도 선물 두 계좌의 포지션과 원장 이력은 남아야 한다.
    let reopened = try LocalFuturesAccountRepository(fileURL: futuresURL).snapshot()
    XCTAssertEqual(reopened.positions.count, 2)
    XCTAssertEqual(reopened.ledger.count, 2)
    XCTAssertEqual(reopened.accounts.map(\.availableBalance), [9_900_000, 9_900_000])
  }

  func testCorruptFuturesStorageDoesNotStopSpotAndCorruptSpotDoesNotStopFutures() throws {
    XCTAssertTrue(UserDataManager.seedInitialUserInformationIfNeeded())
    // 깨진 선물 파일이 현물 주문의 저장 경로로 전파되지 않아야 한다.
    let brokenFuturesBytes = Data("invalid-futures-json".utf8)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try brokenFuturesBytes.write(to: futuresURL)
    XCTAssertThrowsError(try LocalFuturesAccountRepository(fileURL: futuresURL).snapshot())
    _ = try TradeOrderService.executeBid(
      marketName: "ETH/KRW",
      cryptoName: "이더리움",
      currentPrice: 100_000,
      quantity: 1,
      exchange: .upbit
    ).get()
    _ = try TradeOrderService.executeAsk(
      marketName: "ETH/KRW",
      currentPrice: 110_000,
      quantity: 1,
      exchange: .upbit
    ).get()
    XCTAssertEqual(try UserDataManager.getAvailableBalance(for: .upbit), 1_010_000)
    XCTAssertEqual(UserDataManager.userTransactionList?.count, 2)
    XCTAssertEqual(try Data(contentsOf: futuresURL), brokenFuturesBytes)

    try FileManager.default.removeItem(at: futuresURL)
    // 현물 보유 목록의 오류는 선물 계좌·체결 저장과 분리되어야 한다.
    let brokenSpotBytes = Data("invalid-spot-json".utf8)
    UserDefaults.standard.set(brokenSpotBytes, forKey: UserDataManager.Keys.userCryptoList)
    // 선물은 양 거래소 모두 실제 저장소에서 신규 진입을 완료한다.
    let futuresStore = LocalFuturesAccountRepository(fileURL: futuresURL)
    for exchange in [Exchange.upbit, .bithumb] {
      // 손상된 현물 데이터의 읽기·마이그레이션을 선물 주문이 요구하면 안 된다.
      let order = domesticFuturesOrder(exchange: exchange)
      try futuresStore.ensureAccount(order.account)
      try futuresStore.applyAdvertisementReward(AdRewardClaim(account: order.account))
      _ = try futuresStore.openTestPosition(order, expectedRevision: futuresStore.snapshot().revision)
    }
    XCTAssertEqual(try futuresStore.snapshot().positions.count, 2)
    XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList), brokenSpotBytes)
    XCTAssertEqual(try UserDataManager.getAvailableBalance(for: .upbit), 1_010_000)
  }

  @MainActor
  func testSpotBuyMaximumQuantityKeepsOriginalPrecisionAcrossTickerUpdates() throws {
    XCTAssertTrue(UserDataManager.seedInitialUserInformationIfNeeded())
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      try UserDataManager.updateUserInformation(for: exchange) { $0.userAvailableBalance = 10_000 }
      _ = try TradeOrderService.executeBid(
        marketName: "BTC/KRW",
        cryptoName: "비트코인",
        currentPrice: 100_000,
        quantity: 0.01,
        exchange: exchange
      ).get()
      // 현금과 보유 BTC를 각각 최대 매수 재원으로 사용한다.
      let markets: [(market: String, firstPrice: Double, nextPrice: Double, availableBalance: Double)] = [
        ("ETH/KRW", 7_000, 8_000, 9_000),
        ("ETH/BTC", 0.0033, 0.0034, 0.01)
      ]
      for scenario in markets {
        // 최대 수량 선택 후에는 네트워크 없이 시세 이벤트만 주입한다.
        let reactor = TradeReactor(
          selectCrypto: CryptoCellInfo(cryptoName: "이더리움", market: scenario.market, tradePrice: scenario.firstPrice),
          cmcInformation: nil,
          cryptoDetailUseCase: CryptoDetailUseCase(cryptoDetailRepository: CryptoDetailRepository()),
          mainUseCase: MainUseCase(mainRepository: MainRepository())
        )
        reactor.isStubEnabled = true
        // 선택 통화에 해당하는 최신 시세를 실제 매수 바인딩에 제공한다.
        var state = reactor.initialState
        state.cryptoCellInfo = reactor.selectCrypto
        reactor.stub.state.value = state
        // 테스트가 끝날 때 실제 매수 구독을 정리한다.
        let disposeBag = DisposeBag()
        // 최대 버튼은 표시값보다 정밀한 원본 수량을 보존해야 한다.
        let view = TradeBidView.instanceFromNib(reactor: reactor, disposeBag: disposeBag) { _ in }
        view.tapOnMaxAmount(view.maxAmountButton)
        // 주문에 사용할 수량을 화면의 8자리 표시값과 따로 비교한다.
        let maximumQuantity = scenario.availableBalance / scenario.firstPrice.formatDigits(digits: 8)
        XCTAssertEqual(view.inputAmount, maximumQuantity)
        XCTAssertLessThan(view.inputTradeAmount.text?.digitsOnlyDouble ?? 0, maximumQuantity)

        state.cryptoCellInfo?.tradePrice = scenario.nextPrice
        reactor.stub.state.value = state

        XCTAssertEqual(view.inputAmount, maximumQuantity)
        XCTAssertEqual(view.inputTradeAmount.text, maximumQuantity.formatTradingValue())
        XCTAssertEqual(
          view.totalPriceTextField.text,
          PortfolioCalculator.executedAmount(
            price: scenario.nextPrice.formatDigits(digits: 8),
            quantity: maximumQuantity,
            currency: reactor.settlementCurrency
          ).formatTradingValue()
        )
        XCTAssertEqual(try UserDataManager.getAvailableBalance(for: exchange), 9_000)
        XCTAssertEqual(UserDataManager.userTransactionList?.filter { $0.exchange == exchange }.count, 1)
      }
    }
  }

  @MainActor
  func testSpotInvestmentScreenReleasesAfterLeavingTradingMode() throws {
    XCTAssertTrue(UserDataManager.seedInitialUserInformationIfNeeded())
    // 화면 교체 이후에도 ViewController와 현물 구독이 남는지 확인한다.
    weak var previousController: InvestmentViewController?
    autoreleasepool {
      // 화면 생명주기의 외부 API 조회를 시작하지 않고 바인딩과 테이블만 준비한다.
      let reactor = InvestReactor(mainUseCase: MainUseCase(mainRepository: MainRepository()))
      // 상품 전환으로 Coordinator가 보유하던 화면 참조를 해제하는 상황이다.
      let controller = InvestmentViewController(reactor: reactor)
      controller.loadViewIfNeeded()
      previousController = controller
    }
    // 초기 바인딩에서 예약한 메인 큐 작업이 화면을 잠시 보유할 수 있다.
    let queuedUpdates = expectation(description: "초기 화면 갱신 완료")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { queuedUpdates.fulfill() }
    wait(for: [queuedUpdates], timeout: 2)
    XCTAssertNil(previousController, "상품·거래소 전환 이후 이전 현물 화면과 구독이 해제되어야 합니다.")
    // 실패해도 테스트가 만든 화면과 구독이 다음 시나리오에 남지 않게 정리한다.
    previousController?.dataSource = nil
  }
}
