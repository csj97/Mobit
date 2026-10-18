import XCTest
import UIKit
import ReactorKit
import RxSwift
import SkeletonView
@testable import Mobit

final class TradingScreenReleaseQATests: XCTestCase {
  @MainActor
  func testInitialTickerAfterSwitchingFromSkeletonToFavorites() throws {
    try verifyInitialTickerDuringSkeletonTabSwitches(tabs: [.favorite])
  }

  @MainActor
  func testInitialTickerAfterSwitchingFromSkeletonToHold() throws {
    for product in [TradingProduct.spot, .perpetual] {
      try verifyInitialTickerDuringSkeletonTabSwitches(tabs: [.hold], product: product)
    }
  }

  @MainActor
  func testInitialTickerDuringRapidSkeletonTabSwitches() throws {
    for product in [TradingProduct.spot, .perpetual] {
      // 선물에는 BTC 탭을 제공하지 않는 실제 상품 정책을 따른다.
      let availableTabs: [SelectedTab] = product == .spot ? [.hold, .krw, .btc, .favorite] : [.hold, .krw, .favorite]
      for finalTab in availableTabs {
        // 중간 탭에서 응답을 받아도 남은 입력은 같은 실행 루프에서 이어진다.
        let tabs: [SelectedTab] = product == .spot
          ? [.hold, .krw, .btc, .favorite, .krw, .btc, .hold, finalTab]
          : [.hold, .krw, .favorite, .krw, .hold, .favorite, .krw, finalTab]
        for responseAfterTabCount in [3, tabs.count] {
          try verifyInitialTickerDuringSkeletonTabSwitches(
            tabs: tabs,
            product: product,
            responseAfterTabCount: responseAfterTabCount
          )
        }
      }
    }
  }

  @MainActor
  private func verifyInitialTickerDuringSkeletonTabSwitches(
    tabs: [SelectedTab],
    product: TradingProduct = .spot,
    responseAfterTabCount: Int? = nil
  ) throws {
    // SkeletonView가 XCTest에서 생략하는 실제 데이터 소스 교체도 검증한다.
    let testConfigurationPath = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]
    unsetenv("XCTestConfigurationFilePath")
    defer {
      if let testConfigurationPath { setenv("XCTestConfigurationFilePath", testConfigurationPath, 1) }
    }
    // 테스트가 변경한 사용자 설정을 종료 시 복구한다.
    let previousFavorites = UserDataManager.userFavoritePairs
    // 보유 종목의 원본 저장 데이터까지 그대로 복원한다.
    let previousHoldingData = UserDefaults.standard.object(forKey: UserDataManager.Keys.userCryptoList)
    // 보유 목록 Observable에도 테스트 전 값을 다시 전달한다.
    let previousHoldings = UserDataManager.userCryptoList
    // 즐겨찾기 필터와 응답 종목의 거래소를 일치시킨다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    // 상품별로 실제 제공되는 탭과 보유 데이터를 검사한다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    ExchangeSelectionStore.currentExchange = .upbit
    ExchangeSelectionStore.currentProduct = product
    // 테스트 중 광고 팝업이 앱 활성 상태와 표시 계층을 바꾸지 않도록 한다.
    let previousAdDate = UserDefaults.standard.object(forKey: "main_native_ad_popup_last_shown_date")
    // 실제 광고 정책과 같은 날짜 형식으로 이미 본 상태를 만든다.
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "ko_KR")
    dateFormatter.dateFormat = "yyyy-MM-dd"
    UserDefaults.standard.set(dateFormatter.string(from: Date()), forKey: "main_native_ad_popup_last_shown_date")
    defer {
      UserDataManager.userFavoritePairs = previousFavorites
      UserDataManager.userCryptoList = previousHoldings
      UserDefaults.standard.set(previousHoldingData, forKey: UserDataManager.Keys.userCryptoList)
      ExchangeSelectionStore.currentExchange = previousExchange
      ExchangeSelectionStore.currentProduct = previousProduct
      UserDefaults.standard.set(previousAdDate, forKey: "main_native_ad_popup_last_shown_date")
    }
    // 최종 선택에 맞는 마켓·보유 셀만 남는지 비교한다.
    let finalTab = try XCTUnwrap(tabs.last)
    // 빈 사용자 목록과 첫 응답에 포함된 보유·즐겨찾기를 같은 전환으로 확인한다.
    for hasUserCoins in [false, true] {
      UserDataManager.userFavoritePairs = hasUserCoins
        ? [FavoritePair(displayMarket: "BTC/KRW", exchange: .upbit)] : []
      UserDataManager.userCryptoList = hasUserCoins ? [holding(exchange: .upbit)] : []
      // 최초 시세 응답을 탭 전환 중 원하는 시점까지 지연한다.
      let response = PublishSubject<CryptoTickerList>()
      // 목록 조회와 시세 조회의 실제 Reactor 흐름을 유지한다.
      let useCase = ReleaseQAPendingMarketsUseCase(
        response: .just(["KRW-BTC", "BTC-ETH"].map {
          Crypto(
            market: $0,
            koreanName: $0,
            englishName: $0,
            marketEvent: .init(
              warning: false,
              caution: .init(
                priceFluctuations: false,
                tradingVolumeSoaring: false,
                depositAmountSoaring: false,
                globalPriceDifferences: false,
                concentrationOfSmallAccounts: false
              )
            )
          )
        })
      )
      useCase.tickerResponse = response.asObservable()
      // 실제 로딩 상태는 외부 응답을 받을 때만 끝난다.
      let market = MainReactor(
        mainUseCase: useCase,
        tickerSocketService: ReleaseQAQuietTickerSocket()
      )
      // 선물 보유 탭은 현물 저장 내역 대신 해당 계좌의 포지션을 사용한다.
      let futures = product == .perpetual
        ? FuturesAccountReactor(account: .init(exchange: .upbit, product: .perpetual, currency: .krw)) : nil
      if let futures {
        futures.isStubEnabled = true
        // 현물 fixture와 같은 수량 두 개의 선물 포지션이다.
        let position = try FuturesCalculator.open(domesticFuturesOrder(leverage: 1, margin: 2_000, price: 1_000))
        // 실제 거래 저장 없이 포지션 유무만 화면 상태에 주입한다.
        var state = futures.initialState
        state.snapshot = FuturesAccountSnapshot(
          revision: 1,
          accounts: [.init(id: futures.account, availableBalance: 10_000)],
          positions: hasUserCoins ? [position] : []
        )
        futures.stub.state.value = state
      }
      // 실제 테이블의 가짜 행과 Diffable 행 전환을 확인한다.
      let main = MainViewController(reactor: market, futuresReactor: futures, networkAvailability: .empty())
      // 스켈레톤 행을 생성할 실제 표시 영역이다.
      let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
      // 테스트 종료 후 원래 앱 창으로 돌아간다.
      let previousWindow = scene.windows.first { $0.isKeyWindow }
      // 앱의 Scene 안에서 실제 화면 생명주기와 스켈레톤을 표시한다.
      let window = UIWindow(windowScene: scene)
      window.rootViewController = main
      window.makeKeyAndVisible()
      window.setNeedsLayout()
      window.layoutIfNeeded()
      main.view.setNeedsLayout()
      main.view.layoutIfNeeded()
      defer {
        window.isHidden = true
        window.rootViewController = nil
        previousWindow?.makeKeyAndVisible()
      }
      func flush() {
        // 목록 구독의 throttle과 메인 큐 스냅샷 반영까지 기다린다.
        let rendered = expectation(description: "Initial tab list rendered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { rendered.fulfill() }
        wait(for: [rendered], timeout: 2)
        main.view.layoutIfNeeded()
        main.tableView.layoutIfNeeded()
      }
      func showSkeleton() {
        // 비활성 XCTest 호스트에서도 로딩용 데이터 소스가 있는 전환을 재현한다.
        main.tableView.showAnimatedGradientSkeleton(transition: .none)
        main.tableView.layoutIfNeeded()
        XCTAssertTrue(main.tableView.sk.isSkeletonActive)
        XCTAssertGreaterThan(main.tableView.numberOfRows(inSection: 0), 0)
        XCTAssertFalse(main.tableView.dataSource === main.dataSource)
      }
      // 서로 다른 마켓으로 응답하여 이전 탭의 스냅샷이 남는 경우도 구분한다.
      let tickers = try JSONDecoder().decode(
        CryptoTickerListDTO.self,
        from: Data("""
          [{"market":"KRW-BTC","change":"EVEN","trade_price":1000,"timestamp":1},
           {"market":"BTC-ETH","change":"EVEN","trade_price":0.01,"timestamp":1}]
          """.utf8)
      ).toDomain()
      flush()
      market.action.onNext(.loadCryptoList)
      flush()
      XCTAssertTrue(market.currentState.isLoading)
      showSkeleton()
      for (index, tab) in tabs.enumerated() {
        // 실제 버튼 입력으로만 선택 상태와 테이블 표시를 바꾼다.
        let button: UIButton
        switch tab {
        case .hold: button = main.holdButton
        case .krw: button = main.krwButton
        case .btc: button = main.btcButton
        case .favorite: button = main.favoriteButton
        }
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(main.selectedTab, tab)
        if market.currentState.isLoading && (tab == .krw || tab == .btc) {
          showSkeleton()
        } else {
          XCTAssertFalse(main.tableView.sk.isSkeletonActive)
          XCTAssertTrue(main.tableView.dataSource === main.dataSource)
          if market.currentState.isLoading {
            XCTAssertTrue(main.tableView.isHidden)
            XCTAssertEqual(main.tableView.numberOfRows(inSection: 0), 0)
          }
        }
        if index + 1 == (responseAfterTabCount ?? tabs.count) {
          response.onNext(tickers)
          response.onCompleted()
        }
      }
      flush()
      // 보유·즐겨찾기 탭만 저장된 사용자 종목의 유무에 따라 빈 화면이 된다.
      let shouldShowCoin = finalTab == .krw || finalTab == .btc || hasUserCoins
      // BTC 탭에만 다른 마켓의 응답이 표시되어야 한다.
      let expectedMarket = finalTab == .btc ? "ETH/BTC" : "BTC/KRW"
      // Diffable의 앞선 갱신이 끝나고 마지막 선택 목록까지 적용되었는지 기다린다.
      let displayed = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          main.dataSource?.snapshot().itemIdentifiers.map(\.market) == (shouldShowCoin ? [expectedMarket] : [])
        },
        object: nil
      )
      wait(for: [displayed], timeout: 3)
      main.tableView.layoutIfNeeded()
      XCTAssertFalse(market.currentState.isLoading)
      XCTAssertEqual(main.selectedTab, finalTab)
      XCTAssertFalse(main.tableView.sk.isSkeletonActive)
      XCTAssertTrue(main.tableView.dataSource === main.dataSource)
      XCTAssertEqual(main.tableView.isHidden, !shouldShowCoin)
      XCTAssertEqual(main.noHoldView.isHidden, finalTab != .hold || shouldShowCoin)
      XCTAssertEqual(main.noFavoriteView.isHidden, finalTab != .favorite || shouldShowCoin)
      XCTAssertEqual(main.dataSource?.snapshot().itemIdentifiers.map(\.market), shouldShowCoin ? [expectedMarket] : [])
      if shouldShowCoin {
        XCTAssertEqual(main.tableView.numberOfRows(inSection: 0), 1)
        if finalTab == .hold {
          XCTAssertTrue(main.tableView.cellForRow(at: IndexPath(row: 0, section: 0)) is MainHoldingTableViewCell)
          XCTAssertEqual(main.dataSource?.snapshot().itemIdentifiers.first?.holdingQuantity, 2)
        } else {
          XCTAssertTrue(main.tableView.cellForRow(at: IndexPath(row: 0, section: 0)) is MainCryptoTableViewCell)
          XCTAssertNil(main.dataSource?.snapshot().itemIdentifiers.first?.holdingQuantity)
        }
      }
    }
  }

  @MainActor
  func testHoldingSortHeaderMatchesValueColumnsAcrossProductsAndWidths() throws {
    // 상품별 탭 구성을 검사한 뒤 원래 선택을 복구한다.
    let previousProduct = ExchangeSelectionStore.currentProduct
    // 레이아웃 검증 중 광고 팝업이 화면을 가리지 않도록 한다.
    let previousAdDate = UserDefaults.standard.object(forKey: "main_native_ad_popup_last_shown_date")
    // 실제 광고 정책과 동일한 오늘 날짜로 표시를 생략한다.
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "ko_KR")
    dateFormatter.dateFormat = "yyyy-MM-dd"
    UserDefaults.standard.set(dateFormatter.string(from: Date()), forKey: "main_native_ad_popup_last_shown_date")
    defer {
      ExchangeSelectionStore.currentProduct = previousProduct
      UserDefaults.standard.set(previousAdDate, forKey: "main_native_ad_popup_last_shown_date")
    }
    func labels(in view: UIView) -> [UILabel] {
      ((view as? UILabel).map { [$0] } ?? [])
        + view.subviews.flatMap { labels(in: $0) }
    }
    for product in [TradingProduct.spot, .perpetual] {
      ExchangeSelectionStore.currentProduct = product
      // 네트워크 없이 실제 메인 화면과 정렬 버튼을 구성한다.
      let market = MainReactor(
        mainUseCase: ReleaseQAPendingMarketsUseCase(response: .never()),
        tickerSocketService: ReleaseQAQuietTickerSocket()
      )
      market.isStubEnabled = true
      // 선물에서는 실제 보유 셀의 상품별 표시 분기까지 사용한다.
      let futures = product == .perpetual
        ? FuturesAccountReactor(account: .init(exchange: .upbit, product: .perpetual, currency: .krw)) : nil
      futures?.isStubEnabled = true
      // 헤더와 테이블 셀을 같은 실제 화면 좌표계에서 비교한다.
      let main = MainViewController(reactor: market, futuresReactor: futures, networkAvailability: .empty())
      // 작은 화면과 일반·큰 화면의 열 너비를 각각 검증한다.
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 900))
      window.rootViewController = main
      window.isHidden = false
      defer {
        window.isHidden = true
        window.rootViewController = nil
      }
      // 첨부 화면과 같이 자릿수가 긴 평가금액·평균매수가를 표시한다.
      let info = CryptoCellInfo(
        cryptoName: "비트코인",
        market: "BTC/KRW",
        holdingQuantity: 0.00502118,
        averageBuyPrice: 111_338_995,
        evaluationPrice: 554_836,
        profitRate: -0.75,
        evaluationProfitLoss: -4_217
      )
      for width in [CGFloat(320), 393, 430] {
        window.frame.size.width = width
        main.view.frame = window.bounds
        main.holdButton.sendActions(for: .touchUpInside)
        // 탭 전환이 예약한 빈 목록 갱신을 마친 뒤 레이아웃 전용 데이터를 적용한다.
        let switched = expectation(description: "Holding tab layout selected")
        DispatchQueue.main.async { DispatchQueue.main.async { switched.fulfill() } }
        wait(for: [switched], timeout: 2)
        main.tableView.isHidden = false
        main.noHoldView.isHidden = true
        // 실제 Diffable 셀 공급자를 통해 보유 전용 셀을 생성한다.
        var snapshot = NSDiffableDataSourceSnapshot<TableViewSection, CryptoCellInfo>()
        snapshot.appendSections([.main])
        snapshot.appendItems([info], toSection: .main)
        // 이전 Diffable 작업과 셀 생성이 끝난 뒤 실제 텍스트 좌표를 확인한다.
        let applied = expectation(description: "Holding layout row applied")
        main.dataSource?.applySnapshotUsingReloadData(snapshot) { applied.fulfill() }
        wait(for: [applied], timeout: 2)
        window.setNeedsLayout()
        window.layoutIfNeeded()
        main.view.setNeedsLayout()
        main.view.layoutIfNeeded()
        main.tableView.layoutIfNeeded()
        // 빈 이름 영역까지 네 열이 모두 같은 비율을 차지해야 한다.
        let header = try XCTUnwrap(main.currentPriceButton.superview)
        // 셀과 공유한 좌우 여백을 제외한 한 열의 실제 너비다.
        let columnWidth = (main.tableView.bounds.width - MainHoldingTableViewCell.horizontalContentInset * 2) / 4
        XCTAssertEqual(header.subviews.count, 4)
        for (index, column) in header.subviews.enumerated() {
          XCTAssertEqual(column.bounds.width, columnWidth, accuracy: 1)
          XCTAssertEqual(
            column.frame.minX,
            MainHoldingTableViewCell.horizontalContentInset + CGFloat(index) * columnWidth,
            accuracy: 1
          )
        }
        // 헤더와 비교할 실제 표시 중인 보유 셀이다.
        let cell = try XCTUnwrap(main.tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? MainHoldingTableViewCell)
        // 셀 내부에서 네 열을 실제로 배치하는 스택이다.
        let contentStack = try XCTUnwrap(cell.contentView.subviews.compactMap { $0 as? UIStackView }.first)
        XCTAssertEqual(contentStack.arrangedSubviews.count, header.subviews.count)
        for (headerColumn, cellColumn) in zip(header.subviews, contentStack.arrangedSubviews) {
          // 서로 다른 부모 아래의 열 경계를 같은 화면 좌표로 비교한다.
          let headerFrame = headerColumn.convert(headerColumn.bounds, to: main.view)
          // 텍스트가 차지하는 너비가 아닌 셀의 실제 열 영역이다.
          let cellFrame = cellColumn.convert(cellColumn.bounds, to: main.view)
          XCTAssertEqual(headerFrame.minX, cellFrame.minX, accuracy: 1)
          XCTAssertEqual(headerFrame.maxX, cellFrame.maxX, accuracy: 1)
          XCTAssertEqual(headerFrame.width, cellFrame.width, accuracy: 1)
        }
        for (text, button) in [
          ("554,836", main.currentPriceButton),
          ("111,338,995", main.previousDayButton),
          ("-0.75%", main.tradingVolumeButton)
        ] {
          // 금액의 오른쪽 끝과 정렬 버튼 제목의 오른쪽 끝을 같은 좌표계로 옮긴다.
          let valueLabel = try XCTUnwrap(labels(in: cell.contentView).first { $0.text == text })
          // 정렬 화살표를 포함한 버튼 제목의 실제 배치 영역이다.
          let titleLabel = try XCTUnwrap(button.titleLabel)
          XCTAssertEqual(
            titleLabel.convert(titleLabel.bounds, to: main.view).maxX,
            valueLabel.convert(valueLabel.bounds, to: main.view).maxX,
            accuracy: 1,
            "\(product) width=\(width) value=\(text)"
          )
          XCTAssertEqual(button.contentHorizontalAlignment, .right)
          XCTAssertFalse(titleLabel.adjustsFontSizeToFitWidth)
          XCTAssertEqual(titleLabel.font.pointSize, main.currentPriceButton.titleLabel?.font.pointSize)
        }
        // 헤더와 행만 잘라 실제 열 경계를 바로 비교할 수 있게 한다.
        let previewFrame = header.convert(header.bounds, to: main.view)
          .union(cell.convert(cell.bounds, to: main.view))
        // 화면 크기에 따라 계산된 실제 헤더·셀 영역을 렌더링한다.
        let preview = UIGraphicsImageRenderer(size: previewFrame.size).image { context in
          context.cgContext.translateBy(x: -previewFrame.minX, y: -previewFrame.minY)
          main.view.layer.render(in: context.cgContext)
        }
        // 테스트 실행 호스트에서 시각 검증에 사용할 이미지 경로다.
        let previewURL = URL(fileURLWithPath: NSTemporaryDirectory())
          .appendingPathComponent("mobit-holding-\(product)-\(Int(width)).png")
        try preview.pngData()?.write(to: previewURL)
        print("Holding layout preview: \(previewURL.path)")
        for (button, titles) in [
          (main.currentPriceButton, ["평가금액↑", "평가금액↓", "평가금액 ↑↓"]),
          (main.previousDayButton, ["평균매수가↑", "평균매수가↓", "평균매수가 ↑↓"]),
          (main.tradingVolumeButton, ["수익률↑", "수익률↓", "수익률 ↑↓"])
        ] {
          for title in titles {
            button.sendActions(for: .touchUpInside)
            button.layoutIfNeeded()
            XCTAssertEqual(button.title(for: .normal), title)
            XCTAssertEqual(button.bounds.width, columnWidth, accuracy: 1)
          }
        }
        main.krwButton.sendActions(for: .touchUpInside)
        main.view.setNeedsLayout()
        main.view.layoutIfNeeded()
        for button in [main.currentPriceButton, main.previousDayButton, main.tradingVolumeButton] {
          XCTAssertEqual(button.contentHorizontalAlignment, .center)
          XCTAssertEqual(button.bounds.width, main.tableView.bounds.width / 4, accuracy: 1)
        }
      }
    }
  }

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
  // 첫 시세 수신 시점을 탭 전환 뒤로 지연할 때 사용한다.
  var tickerResponse: Observable<CryptoTickerList> = .never()
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

  override func fetchCryptoTicker(markets: [String]) -> Observable<CryptoTickerList> { tickerResponse }
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
