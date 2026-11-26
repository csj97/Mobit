//
//  PortfolioCalculatorTests.swift
//  MobitTests
//
//  Created by Codex on 6/29/26.
//

import XCTest
import UIKit
import RxSwift
@testable import Mobit

final class PortfolioCalculatorTests: XCTestCase {
  func testHoldingAlertJournalCoalescesPartialSalesAndPersistsOfflineClosure() throws {
    // 동일 보유 건 UUID를 분할 매수와 매도에서 계속 사용한다.
    var holding = CryptoTransactionDataModel(
      staticData: .init(exchange: .bithumb, marketName: "BTC/KRW", cryptoName: nil, holdingQuantity: 1, averageBuyPrice: 100, buyAmount: 100),
      dynamicData: .init(exchange: .bithumb, marketName: "BTC/KRW", profitRate: 0, evaluationProfitLoss: 0, evaluationPrice: 100)
    )
    // 앱이 종료돼도 갱신과 종료 중 더 최신 요청만 남는지 검사한다.
    var journal = HoldingAlertSync.Journal()
    func update() -> Bool {
      journal.reconcile(HoldingAlertSnapshot.spot([holding], trades: []), verificationSince: nil)
    }
    XCTAssertTrue(update())
    XCTAssertEqual(journal.entries[holding.identifier]?.snapshot?.market, "KRW-BTC")
    holding.staticData.averageBuyPrice = 90
    XCTAssertTrue(update())
    let buyRevision = try XCTUnwrap(journal.entries[holding.identifier]?.revision)
    holding.staticData.holdingQuantity = 0.5
    XCTAssertFalse(update())
    XCTAssertTrue(journal.reconcile([], verificationSince: nil))
    let restored = try JSONDecoder().decode(HoldingAlertSync.Journal.self, from: JSONEncoder().encode(journal))
    let closed = try XCTUnwrap(restored.entries[holding.identifier])
    XCTAssertGreaterThan(closed.revision, buyRevision)
    XCTAssertNil(closed.snapshot)
    XCTAssertTrue(closed.pending)
  }

  func testHoldingAlertUsesNewAverageAndDistinguishesDisplayFromLossBoundary() {
    // 예시의 동일 수량 분할 매수로 실제 앱 계산기가 산출하는 평단이다.
    let average = PortfolioCalculator.weightedAverageBuyPrice(
      previousQuantity: 1,
      previousAveragePrice: 100_000_000,
      addedQuantity: 1,
      addedPrice: 80_000_000
    )
    XCTAssertEqual(average, 90_000_000)
    XCTAssertEqual(PortfolioCalculator.profitRate(currentPrice: 94_500_000, averageBuyPrice: average), 5)
    XCTAssertEqual(PortfolioCalculator.profitRate(currentPrice: 99_000_000, averageBuyPrice: average), 10)
    XCTAssertFalse(PortfolioCalculator.isFullySold(holdingQuantity: 2, sellQuantity: 0.5))
    XCTAssertTrue(PortfolioCalculator.isFullySold(holdingQuantity: 1.5, sellQuantity: 1.5))
    // 분할 수량이 다르면 산술평균 대신 수량 가중 평단을 전달해야 한다.
    XCTAssertEqual(
      PortfolioCalculator.weightedAverageBuyPrice(
        previousQuantity: 3,
        previousAveragePrice: 100_000_000,
        addedQuantity: 1,
        addedPrice: 80_000_000
      ),
      95_000_000
    )
    // 실제 손실률은 −4.991%지만 앱의 두 자리 내림 표시는 −5.00%다.
    XCTAssertEqual(PortfolioCalculator.profitRate(currentPrice: 95_009, averageBuyPrice: 100_000), -5)
  }

  func testDelistingFetchesBTCRateOnlyWhenMissingOrStale() throws {
    // 테스트 후 기존 거래소 선택으로 돌아간다.
    let originalExchange = ExchangeSelectionStore.currentExchange
    defer { ExchangeSelectionStore.currentExchange = originalExchange }
    for exchange in [Exchange.upbit, .bithumb] {
      ExchangeSelectionStore.currentExchange = exchange
      AppDataManager.shared.invalidateBTCKRWPrice(for: exchange)
      defer { AppDataManager.shared.invalidateBTCKRWPrice(for: exchange) }
      // 실제 통신 없이 요청 횟수와 적용된 거래소 시세를 확인한다.
      let useCase = DelistingMarketFixtureUseCase()
      // 목록 확인과 시세 조회에 같은 거래소의 저장소를 사용한다.
      let reactor = InvestReactor(mainUseCase: useCase)
      useCase.tickerResponse = .just(try JSONDecoder().decode(
        CryptoTickerListDTO.self,
        from: Data(#"[{"market":"KRW-BTC","change":"EVEN","trade_price":110000000,"timestamp":1}]"#.utf8)
      ).toDomain())

      XCTAssertNil(try verifiedRate(reactor, currency: .krw))
      XCTAssertTrue(useCase.tickerRequests.isEmpty)
      XCTAssertEqual(try verifiedRate(reactor, currency: .btc), 110_000_000)
      XCTAssertEqual(useCase.tickerRequests, [["KRW-BTC"]])
      AppDataManager.shared.updateBTCKRWPrice(105_000_000, for: exchange, updatedAt: Date().addingTimeInterval(-12))
      XCTAssertEqual(try verifiedRate(reactor, currency: .btc), 105_000_000)
      XCTAssertEqual(useCase.tickerRequests.count, 1)
      AppDataManager.shared.updateBTCKRWPrice(95_000_000, for: exchange, updatedAt: Date().addingTimeInterval(-16))
      XCTAssertEqual(try verifiedRate(reactor, currency: .btc), 110_000_000)
      XCTAssertEqual(try verifiedRate(reactor, currency: .btc), 110_000_000)
      XCTAssertEqual(useCase.tickerRequests, [["KRW-BTC"], ["KRW-BTC"]])
    }
  }

  func testDelistingRejectsUnverifiedMarketsAndUnusableRateResponses() throws {
    // 거래소 오류와 잘못된 종목 응답을 차례로 재현한다.
    let useCase = DelistingMarketFixtureUseCase()
    // 유효한 새 시세가 도착한 경우에만 정산 콜백으로 전달해야 한다.
    let reactor = InvestReactor(mainUseCase: useCase)
    AppDataManager.shared.updateBTCKRWPrice(90_000_000, for: reactor.exchange, updatedAt: Date().addingTimeInterval(-20))
    defer { AppDataManager.shared.invalidateBTCKRWPrice(for: reactor.exchange) }
    for markets in [[], ["BTC-ABC"]] {
      useCase.marketResponse = .just(markets.map(DelistingMarketFixtureUseCase.crypto))
      XCTAssertThrowsError(try verifiedRate(reactor, currency: .btc))
      XCTAssertTrue(useCase.tickerRequests.isEmpty)
    }
    useCase.marketResponse = .just([DelistingMarketFixtureUseCase.crypto("KRW-BTC")])
    // BTC/KRW가 누락됐거나 양수가 아닌 응답도 기존 환율로 대체하지 않는다.
    let invalidTickers = try JSONDecoder().decode(
      CryptoTickerListDTO.self,
      from: Data(#"[{"market":"KRW-ETH","change":"EVEN","trade_price":5,"timestamp":1},{"market":"KRW-BTC","change":"EVEN","trade_price":0,"timestamp":1}]"#.utf8)
    ).toDomain()
    // 스트림 종료, 통신 실패, 비어 있거나 잘못된 티커를 각각 검증한다.
    let responses: [Observable<CryptoTickerList>] = [
      .empty(), .error(URLError(.notConnectedToInternet)), .just([]),
      .just([invalidTickers[0]]), .just([invalidTickers[1]])
    ]
    for response in responses {
      useCase.tickerResponse = response
      XCTAssertThrowsError(try verifiedRate(reactor, currency: .btc)) { error in
        XCTAssertEqual(error as? InvestReactor.DelistingVerificationError, .rateUnavailable)
      }
      XCTAssertNil(AppDataManager.shared.freshBTCKRWPrice(for: reactor.exchange))
    }
    XCTAssertEqual(useCase.tickerRequests.count, responses.count)
  }

  private func verifiedRate(_ reactor: InvestReactor, currency: SettlementCurrency) throws -> Double? {
    // 비동기 정산 경로가 단 한 번 환율 또는 오류를 반환할 때까지 기다린다.
    let received = expectation(description: "종료 정산 환율 확인")
    // 원화 정산 성공(nil)과 결과 누락을 구분한다.
    var result: Result<Double?, Error>?
    // 목록에는 없는 정산 대상 종목이다.
    let pairID = ExchangePairID(exchange: reactor.exchange, rawMarketCode: currency.rawValue + "-ABC")
    // 검증 종료 시 구독을 해제해 다음 조회와 겹치지 않게 한다.
    let subscription = reactor.verifiedDelistingSettlementRate(for: pairID, currency: currency)
      .subscribe(
        onNext: {
          result = .success($0)
          received.fulfill()
        },
        onError: {
          result = .failure($0)
          received.fulfill()
        }
      )
    defer { subscription.dispose() }
    wait(for: [received], timeout: 2)
    return try XCTUnwrap(result).get()
  }

  func testSupportedMarketsRejectEmptyAndMalformedResponses() {
    // 목록 조회 결과를 직접 제어한다.
    let useCase = DelistingMarketFixtureUseCase()
    // 저장소와 같은 거래소를 기준으로 확인한다.
    let reactor = InvestReactor(mainUseCase: useCase)
    for markets in [[], [""], ["KRW-"], ["bad"], ["KRW--BTC"], ["BTC/KRW"]] {
      useCase.marketResponse = .just(markets.map(DelistingMarketFixtureUseCase.crypto))
      // 유효하지 않은 목록이 반환될 때는 실패만 발생해야 한다.
      var receivedError = false
      _ = reactor.fetchSupportedMarketPairIDs(for: reactor.exchange).subscribe(
        onNext: { _ in XCTFail("유효하지 않은 목록을 허용하면 안 됩니다.") },
        onError: { _ in receivedError = true }
      )
      XCTAssertTrue(receivedError)
    }
    useCase.marketResponse = .just([DelistingMarketFixtureUseCase.crypto("KRW-BTC")])
    // 정상 목록만 해당 거래소의 마켓 집합으로 변환한다.
    var pairIDs: Set<ExchangePairID>?
    _ = reactor.fetchSupportedMarketPairIDs(for: reactor.exchange).subscribe(onNext: { pairIDs = $0 })
    XCTAssertEqual(pairIDs, [ExchangePairID(exchange: reactor.exchange, rawMarketCode: "KRW-BTC")])
    useCase.marketResponse = .empty()
    var emptySequenceFailed = false
    _ = reactor.fetchSupportedMarketPairIDs(for: reactor.exchange).subscribe(onError: { _ in emptySequenceFailed = true })
    XCTAssertTrue(emptySequenceFailed)
  }

  func testSupportedMarketFailuresAndLateResponsesClearOldState() {
    // 응답 순서가 바뀌어도 마지막 요청만 적용한다.
    let reactor = InvestReactor(mainUseCase: DelistingMarketFixtureUseCase())
    let exchange = reactor.exchange
    let firstRequest = UUID()
    let secondRequest = UUID()
    let supported: Set<ExchangePairID> = [ExchangePairID(exchange: exchange, rawMarketCode: "KRW-BTC")]
    var state = reactor.reduce(state: reactor.initialState, mutation: .beginSupportedMarketsRequest(firstRequest, exchange))
    state = reactor.reduce(state: state, mutation: .setSupportedMarketPairIDs(firstRequest, exchange, supported))
    XCTAssertEqual(state.supportedMarketPairIDs, supported)
    state = reactor.reduce(state: state, mutation: .beginSupportedMarketsRequest(secondRequest, exchange))
    XCTAssertNil(state.supportedMarketPairIDs)
    state = reactor.reduce(state: state, mutation: .setSupportedMarketPairIDs(firstRequest, exchange, supported))
    XCTAssertNil(state.supportedMarketPairIDs)
    state = reactor.reduce(state: state, mutation: .setSupportedMarketPairIDs(secondRequest, exchange, nil))
    XCTAssertNil(state.supportedMarketPairIDs)
    XCTAssertTrue(state.supportedMarketsFailed)
    state = reactor.reduce(state: state, mutation: .setSupportedMarketPairIDs(secondRequest, exchange, supported))
    XCTAssertNil(state.supportedMarketPairIDs)
  }

  func testSupportedMarketsDoNotApplyAfterExchangeChanges() {
    // 거래소 변경으로 현재 응답이 오래된 상태가 되는지 확인한다.
    let previous = ExchangeSelectionStore.currentExchange
    defer { ExchangeSelectionStore.currentExchange = previous }
    ExchangeSelectionStore.currentExchange = .upbit
    let reactor = InvestReactor(mainUseCase: DelistingMarketFixtureUseCase())
    let request = UUID()
    var state = reactor.reduce(state: reactor.initialState, mutation: .beginSupportedMarketsRequest(request, .upbit))
    ExchangeSelectionStore.currentExchange = .bithumb
    state = reactor.reduce(
      state: state,
      mutation: .setSupportedMarketPairIDs(request, .upbit, [ExchangePairID(exchange: .upbit, rawMarketCode: "KRW-BTC")])
    )
    XCTAssertNil(state.supportedMarketPairIDs)
    state = reactor.reduce(state: state, mutation: .invalidateSupportedMarkets)
    ExchangeSelectionStore.currentExchange = .upbit
    state = reactor.reduce(
      state: state,
      mutation: .setSupportedMarketPairIDs(request, .upbit, [ExchangePairID(exchange: .upbit, rawMarketCode: "KRW-BTC")])
    )
    XCTAssertNil(state.supportedMarketPairIDs)
  }

  @MainActor
  func testInvestmentScrollEndsWithLatestHoldingsAndMarketSupport() {
    // 거래소 응답과 보유 시세의 도착 순서를 독립적으로 제어한다.
    let reactor = InvestReactor(mainUseCase: DelistingMarketFixtureUseCase())
    reactor.isStubEnabled = true
    // 동일 종목의 평가금액만 바꿔 화면과 대기 중인 목록을 구분한다.
    var holding = makeCrypto(evaluationPrice: 1_000_000, evaluationProfitLoss: 0, buyAmount: 1_000_000)
    holding.staticData.exchange = reactor.exchange
    holding.dynamicData.exchange = reactor.exchange
    // 다른 정상 종목만 목록에 남으면 보유 종목의 거래지원 종료가 표시된다.
    let otherMarket = ExchangePairID(exchange: reactor.exchange, rawMarketCode: "KRW-ETH")
    // 최초 상태에서는 보유한 비트코인의 거래가 가능하다.
    var state = reactor.initialState
    state.cryptos = [holding]
    state.supportedMarketPairIDs = [holding.staticData.exchangePairID]
    reactor.stub.state.value = state
    // 테이블에 실제로 적용된 행과 거래지원 종료 표시를 함께 확인한다.
    let controller = InvestmentViewController(reactor: reactor)
    // 셀의 표시 상태를 확인할 테스트 화면이다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }

    func waitUntil(_ condition: @escaping () -> Bool) {
      // 시세 구독의 throttle과 비동기 스냅샷 적용을 기다린다.
      let ready = expectation(for: NSPredicate { _, _ in condition() }, evaluatedWith: nil)
      wait(for: [ready], timeout: 5)
    }
    func rowMatches(_ expected: CryptoTransactionDataModel, unsupported: Bool) -> Bool {
      guard controller.dataSource?.snapshot().itemIdentifiers == [expected],
            let cell = controller.transactionTableview.visibleCells.first as? InvestmentTableViewCell else { return false }
      return cell.unsupportedOverlayView.isHidden == !unsupported
        && cell.cryptoEvalPrice.text?.hasPrefix(TradingNumberFormat.string(expected.dynamicData.evaluationPrice)) == true
    }
    waitUntil { rowMatches(holding, unsupported: false) }

    for holdingsFirst in [true, false] {
      // 스크롤 중 화면에는 직전에 표시한 평가금액이 유지된다.
      let previous = holding
      holding.dynamicData.evaluationPrice += 10_000
      holding.dynamicData.evaluationProfitLoss += 10_000
      controller.scrollViewWillBeginDragging(controller.transactionTableview)
      func sendMarketSupport() {
        state.supportedMarketPairIDs = holdingsFirst ? [otherMarket] : [holding.staticData.exchangePairID]
        reactor.stub.state.value = state
      }
      if !holdingsFirst {
        sendMarketSupport()
        waitUntil { controller.pendingUserHeldCryptos == [previous] }
      }
      state.cryptos = [holding]
      reactor.stub.state.value = state
      waitUntil { controller.pendingUserHeldCryptos == [holding] }
      if holdingsFirst { sendMarketSupport() }
      XCTAssertEqual(controller.pendingUserHeldCryptos, [holding])
      XCTAssertTrue(rowMatches(previous, unsupported: !holdingsFirst))

      controller.scrollViewDidEndDragging(controller.transactionTableview, willDecelerate: !holdingsFirst)
      if !holdingsFirst {
        XCTAssertTrue(rowMatches(previous, unsupported: true))
        controller.scrollViewDidEndDecelerating(controller.transactionTableview)
      }
      waitUntil { rowMatches(holding, unsupported: holdingsFirst) }
      XCTAssertNil(controller.pendingUserHeldCryptos)
    }

    // 시세가 그대로여도 스크롤이 끝나면 같은 행의 거래지원 표시를 다시 그린다.
    controller.scrollViewWillBeginDragging(controller.transactionTableview)
    state.supportedMarketPairIDs = [otherMarket]
    reactor.stub.state.value = state
    waitUntil { controller.pendingUserHeldCryptos == [holding] }
    XCTAssertTrue(rowMatches(holding, unsupported: false))
    controller.scrollViewDidEndDragging(controller.transactionTableview, willDecelerate: false)
    waitUntil { rowMatches(holding, unsupported: true) }

    controller.scrollViewWillBeginDragging(controller.transactionTableview)
    state.cryptos = []
    reactor.stub.state.value = state
    waitUntil { controller.pendingUserHeldCryptos == [] }
    state.supportedMarketPairIDs = [holding.staticData.exchangePairID]
    reactor.stub.state.value = state
    controller.scrollViewDidEndDragging(controller.transactionTableview, willDecelerate: false)
    waitUntil { controller.dataSource?.snapshot().numberOfItems == 0 && !controller.noResultView.isHidden }
  }

  @MainActor
  func testMarketRetryAlertAppearsOnlyForCurrentExchangeHoldings() throws {
    // 화면이 확인할 거래소를 고정하고 다른 테스트의 설정은 복구한다.
    let previousExchange = ExchangeSelectionStore.currentExchange
    defer { ExchangeSelectionStore.currentExchange = previousExchange }
    ExchangeSelectionStore.currentExchange = .upbit
    // 조회 실패와 보유 데이터 도착 순서를 직접 제어한다.
    let reactor = InvestReactor(mainUseCase: DelistingMarketFixtureUseCase())
    reactor.isStubEnabled = true
    var state = reactor.initialState
    state.supportedMarketsFailed = true
    reactor.stub.state.value = state
    // 보유 목록이 없는 상태에서 실제 투자내역 화면을 연다.
    let controller = InvestmentViewController(reactor: reactor)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    // 메인 큐에 늦게 전달된 실패 상태로도 팝업이 열리지 않아야 한다.
    let noHoldingsAlert = expectation(for: NSPredicate { _, _ in
      controller.presentedViewController is MobitAlertViewController
    }, evaluatedWith: nil)
    noHoldingsAlert.isInverted = true
    wait(for: [noHoldingsAlert], timeout: 0.3)

    // 다른 거래소의 보유 종목만으로는 현재 화면에 안내하지 않는다.
    var otherExchangeHolding = makeCrypto(evaluationPrice: 100, evaluationProfitLoss: 0, buyAmount: 100)
    otherExchangeHolding.staticData.exchange = .bithumb
    state.cryptos = [otherExchangeHolding]
    reactor.stub.state.value = state
    // 다른 거래소 보유 상태도 비동기 전달이 끝난 뒤까지 확인한다.
    let otherExchangeAlert = expectation(for: NSPredicate { _, _ in
      controller.presentedViewController is MobitAlertViewController
    }, evaluatedWith: nil)
    otherExchangeAlert.isInverted = true
    wait(for: [otherExchangeAlert], timeout: 0.3)

    // 조회 실패 뒤 현재 거래소 보유 종목이 도착해도 안내가 나타나야 한다.
    state.cryptos = [makeCrypto(evaluationPrice: 100, evaluationProfitLoss: 0, buyAmount: 100)]
    reactor.stub.state.value = state
    let alertShown = expectation(for: NSPredicate { _, _ in
      controller.presentedViewController is MobitAlertViewController
    }, evaluatedWith: nil)
    wait(for: [alertShown], timeout: 5)
    let alert = try XCTUnwrap(controller.presentedViewController as? MobitAlertViewController)
    alert.loadViewIfNeeded()
    XCTAssertEqual(alert.titleString, FuturesText.text("spot_delisting_market_check_title"))
    XCTAssertEqual(alert.content, FuturesText.text("spot_delisting_market_check_message"))
    XCTAssertEqual(alert.cancelButton.configuration?.title, FuturesText.text("settings_close"))
    XCTAssertEqual(alert.confirmButton.configuration?.title, FuturesText.text("spot_delisting_market_check_retry"))
  }

  func testExecutedAmountFloorsFractionalValue() {
    let amount = PortfolioCalculator.executedAmount(price: 12.34, quantity: 3.2)

    XCTAssertEqual(amount, 39)
  }

  func testBTCExecutionUsesDecimalBeforeEightDigitFloor() {
    // 이진 곱셈 뒤 내림하면 0.00029999가 되던 체결 금액이다.
    let amount = PortfolioCalculator.executedAmount(price: 0.01, quantity: 0.03, currency: .btc)
    XCTAssertEqual(amount, 0.0003)
    XCTAssertEqual(PortfolioCalculator.executedAmount(price: 0.000001, quantity: 0.12345678, currency: .btc), 0.00000012)
    XCTAssertEqual(PortfolioCalculator.executedAmount(price: 333.33, quantity: 3, currency: .krw), 999)
    XCTAssertEqual(PortfolioCalculator.executedAmount(price: -1.123456789, quantity: 1, currency: .btc), -1.12345679)
  }

  func testHoldingCalculationsUseDecimalBeforeReturningDouble() {
    XCTAssertEqual(PortfolioCalculator.cumulativeHoldingQuantity(previousQuantity: 0.1, newQuantity: 0.2), 0.3)
    XCTAssertEqual(
      PortfolioCalculator.cumulativeBuyAmount(previousBuyAmount: 0.0001, price: 0.01, quantity: 0.03, currency: .btc),
      0.0004
    )
    XCTAssertEqual(
      PortfolioCalculator.weightedAverageBuyPrice(
        previousQuantity: 0.1,
        previousAveragePrice: 1,
        addedQuantity: 0.2,
        addedPrice: 1.75
      ),
      1.5
    )
  }

  func testValuationAndProfitUseDecimalBeforeRounding() {
    XCTAssertEqual(PortfolioCalculator.evaluationPrice(currentPrice: 0.01, holdingQuantity: 0.03), 0.0003)
    XCTAssertEqual(PortfolioCalculator.evaluationProfitLoss(currentPrice: 0.3, holdingQuantity: 3, averageBuyPrice: 0.1), 0.6)
    XCTAssertEqual(PortfolioCalculator.realizedProfitLoss(entryPrice: 0.1, exitPrice: 0.3, quantity: 3), 0.6)
    XCTAssertEqual(PortfolioCalculator.profitRate(currentPrice: 0.3, averageBuyPrice: 0.1), 200)
    XCTAssertEqual(PortfolioCalculator.profitRate(currentPrice: 0.1, averageBuyPrice: 0.3), -66.67)
    XCTAssertEqual(PortfolioCalculator.totalProfitRate(totalProfitLoss: 0.3, totalAssetValue: 0.1), 300)
    XCTAssertEqual(PortfolioCalculator.krwValue(amount: 0.1, currency: .btc, btcKRWPrice: 3), 0.3)
  }

  func testExecutionPreservesDoubleFallbackOutsideDecimalRange() {
    XCTAssertEqual(PortfolioCalculator.executedAmount(price: 1e150, quantity: 1, currency: .krw), 1e150)
    XCTAssertTrue(PortfolioCalculator.executedAmount(price: .infinity, quantity: 1, currency: .krw).isInfinite)
  }

  func testExtremeExponentsFallBackToDoubleArithmetic() {
    // Foundation Decimal 곱셈의 지수 범위를 벗어나는 작은 값이다.
    let small = 1e-100
    XCTAssertEqual(PortfolioCalculator.evaluationPrice(currentPrice: small, holdingQuantity: small), 0)
    XCTAssertEqual(PortfolioCalculator.executedAmount(price: small, quantity: small), 0)
    XCTAssertEqual(PortfolioCalculator.evaluationProfitLoss(currentPrice: small, holdingQuantity: small, averageBuyPrice: 0), small * small)
    XCTAssertEqual(PortfolioCalculator.realizedProfitLoss(entryPrice: 0, exitPrice: small, quantity: small), small * small)
    XCTAssertEqual(PortfolioCalculator.krwValue(amount: small, currency: .btc, btcKRWPrice: small), small * small)
    XCTAssertEqual(
      PortfolioCalculator.weightedAverageBuyPrice(previousQuantity: small, previousAveragePrice: small, addedQuantity: 0, addedPrice: 0),
      small * small / small
    )
    // 거래 수량보다 충분히 작은 경계에서도 십진수 계산은 그대로 사용한다.
    XCTAssertEqual(PortfolioCalculator.krwValue(amount: 1e-20, currency: .btc, btcKRWPrice: 1e-20), 1e-40)
    // 원화 환산 결과를 Decimal로 표현하지 못하면 잘못된 큰 숫자 대신 표시하지 않는다.
    let crypto = makeCrypto(evaluationPrice: small, evaluationProfitLoss: 0, buyAmount: 0, marketName: "ETH/BTC", costBasisKRW: 1)
    XCTAssertNil(PortfolioCalculator.valuation(of: crypto, btcKRWPrice: small).evaluationKRW)
  }

  func testDecimalResultsConvertToNearestDoubleAtStorageBoundary() throws {
    // 가중평균처럼 반복 소수가 되는 십진수 결과다.
    let value = try XCTUnwrap(Decimal(string: "3.05")) / XCTUnwrap(Decimal(string: "0.3"))
    XCTAssertEqual(PortfolioCalculator.double(value), 10.166666666666666)
    XCTAssertEqual(PortfolioCalculator.double(-value), -10.166666666666666)
    XCTAssertEqual(PortfolioCalculator.double(0), 0)
    XCTAssertEqual(PortfolioCalculator.double(try XCTUnwrap(Decimal(string: "1e127"))), 1e127)
    XCTAssertTrue(PortfolioCalculator.double(.nan).isNaN)
  }

  func testProfitRateTruncatesToTwoDigits() {
    let rate = PortfolioCalculator.profitRate(
      currentPrice: 123,
      averageBuyPrice: 100
    )

    XCTAssertEqual(rate, 23)
  }

  func testProfitRateReturnsZeroWhenAverageBuyPriceIsZero() {
    let rate = PortfolioCalculator.profitRate(
      currentPrice: 123,
      averageBuyPrice: 0
    )

    XCTAssertEqual(rate, 0)
  }

  func testEvaluationValues() {
    let evaluationPrice = PortfolioCalculator.evaluationPrice(
      currentPrice: 11.123456789,
      holdingQuantity: 2
    )
    let profitLoss = PortfolioCalculator.evaluationProfitLoss(
      currentPrice: 120,
      holdingQuantity: 3,
      averageBuyPrice: 100
    )

    XCTAssertEqual(evaluationPrice, 22.24691357)
    XCTAssertEqual(profitLoss, 60)
  }

  func testPortfolioTotals() {
    let cryptos = [
      makeCrypto(evaluationPrice: 1_200, evaluationProfitLoss: 200, buyAmount: 1_000),
      makeCrypto(evaluationPrice: 500, evaluationProfitLoss: -100, buyAmount: 600)
    ]

    let totalAsset = PortfolioCalculator.totalAssetValue(
      availableBalance: 300,
      cryptos: cryptos,
      btcKRWPrice: nil
    )
    let totalProfitLoss = PortfolioCalculator.totalEvaluationProfitLoss(
      cryptos: cryptos,
      btcKRWPrice: nil
    )
    let totalEvaluationPrice = PortfolioCalculator.totalEvaluationPrice(
      cryptos: cryptos,
      btcKRWPrice: nil
    )
    let totalBuyAmount = PortfolioCalculator.totalBuyAmount(
      cryptos: cryptos,
      btcKRWPrice: nil
    )
    let totalProfitRate = PortfolioCalculator.totalProfitRate(
      totalProfitLoss: totalProfitLoss ?? 0,
      totalAssetValue: totalAsset ?? 0
    )

    // 원화 마켓만 있으면 환산 시세가 없어도 기존과 동일하게 합산된다.
    XCTAssertEqual(totalAsset, 2_000)
    XCTAssertEqual(totalProfitLoss, 100)
    XCTAssertEqual(totalEvaluationPrice, 1_700)
    XCTAssertEqual(totalBuyAmount, 1_600)
    XCTAssertEqual(totalProfitRate, 5)
  }

  func testPortfolioTotalsConvertBTCMarketHoldingToKRW() {
    let cryptos = [
      makeCrypto(evaluationPrice: 1_000_000, evaluationProfitLoss: 200_000, buyAmount: 800_000),
      makeCrypto(
        evaluationPrice: 0.035,
        evaluationProfitLoss: 0.0035,
        buyAmount: 0.0315,
        marketName: "ETH/BTC",
        costBasisKRW: 3_150_000
      )
    ]

    let totalAsset = PortfolioCalculator.totalAssetValue(
      availableBalance: 500_000,
      cryptos: cryptos,
      btcKRWPrice: 100_000_000
    )
    let totalProfitLoss = PortfolioCalculator.totalEvaluationProfitLoss(
      cryptos: cryptos,
      btcKRWPrice: 100_000_000
    )
    let totalBuyAmount = PortfolioCalculator.totalBuyAmount(
      cryptos: cryptos,
      btcKRWPrice: 100_000_000
    )

    XCTAssertEqual(try XCTUnwrap(totalAsset), 500_000 + 1_000_000 + 3_500_000, accuracy: 1)
    XCTAssertEqual(try XCTUnwrap(totalProfitLoss), 200_000 + 350_000, accuracy: 1)
    XCTAssertEqual(try XCTUnwrap(totalBuyAmount), 800_000 + 3_150_000, accuracy: 1)
  }

  func testPortfolioTotalsReturnNilWhenBTCRateIsMissing() {
    let cryptos = [
      makeCrypto(evaluationPrice: 1_000_000, evaluationProfitLoss: 0, buyAmount: 1_000_000),
      makeCrypto(
        evaluationPrice: 0.035,
        evaluationProfitLoss: 0,
        buyAmount: 0.0315,
        marketName: "ETH/BTC",
        costBasisKRW: 3_150_000
      )
    ]

    // 평가금액은 환산 불가지만 저장된 원화 원가는 BTC/KRW 시세 없이도 유지된다.
    XCTAssertNil(
      PortfolioCalculator.totalAssetValue(
        availableBalance: 0,
        cryptos: cryptos,
        btcKRWPrice: nil
      )
    )
    XCTAssertEqual(
      PortfolioCalculator.totalBuyAmount(cryptos: cryptos, btcKRWPrice: nil),
      4_150_000
    )
  }

  func testKRWValueLeavesKRWAmountUntouched() {
    XCTAssertEqual(
      PortfolioCalculator.krwValue(amount: 1_234, currency: .krw, btcKRWPrice: nil),
      1_234
    )
    XCTAssertEqual(
      PortfolioCalculator.krwValue(amount: 0.5, currency: .btc, btcKRWPrice: 100_000_000),
      50_000_000
    )
    XCTAssertNil(
      PortfolioCalculator.krwValue(amount: 0.5, currency: .btc, btcKRWPrice: 0)
    )
  }

  func testFixedCostDoesNotChangeWhenOnlyBTCRateChanges() throws {
    let crypto = makeCrypto(evaluationPrice: 0.05, evaluationProfitLoss: 0,
                            buyAmount: 0.05, marketName: "ETH/BTC", costBasisKRW: 5_000_000)
    let valued = PortfolioCalculator.valuation(of: crypto, btcKRWPrice: 120_000_000)
    XCTAssertEqual(valued.costBasisKRW, 5_000_000)
    XCTAssertEqual(valued.evaluationKRW, 6_000_000)
    XCTAssertEqual(valued.profitLossKRW, 1_000_000)
    XCTAssertEqual(valued.profitRate, 20)
    let missingRate = PortfolioCalculator.valuation(of: crypto, btcKRWPrice: nil)
    XCTAssertEqual(missingRate.costBasisKRW, 5_000_000)
    XCTAssertNil(missingRate.evaluationKRW)
    XCTAssertNil(missingRate.profitLossKRW)
  }

  func testLegacyBTCHoldingKeepsLegacyKRWDisplayValueUntilSettlement() throws {
    let crypto = makeCrypto(evaluationPrice: 0.05, evaluationProfitLoss: 0,
                            buyAmount: 0.05, marketName: "ETH/BTC")
    let decoded = try JSONDecoder().decode(CryptoTransactionDataModel.self, from: JSONEncoder().encode(crypto))
    let value = PortfolioCalculator.valuation(of: decoded, btcKRWPrice: 120_000_000)
    XCTAssertNil(value.costBasisKRW)
    XCTAssertNil(value.profitLossKRW)
    XCTAssertEqual(value.evaluationKRW, 0.05)
    XCTAssertNil(PortfolioCalculator.totalBuyAmount(cryptos: [decoded], btcKRWPrice: 120_000_000))
  }

  func testFutureUSDTValuationNeedsExplicitRateAndDoesNotFallbackToKRW() {
    let crypto = makeCrypto(evaluationPrice: 2_000, evaluationProfitLoss: 0,
                            buyAmount: 1_800, marketName: "ETH/USDT", costBasisKRW: 2_500_000)
    XCTAssertNil(PortfolioCalculator.valuation(of: crypto, btcKRWPrice: 120_000_000).evaluationKRW)
    let value = PortfolioCalculator.valuation(of: crypto, quoteKRWPrices: ["USDT": 1_400])
    XCTAssertEqual(value.evaluationKRW, 2_800_000)
    XCTAssertEqual(value.profitLossKRW, 300_000)
    XCTAssertEqual(value.profitRate, 12)
  }

  func testMixedHoldingsTotalsAndUnknownSorting() throws {
    let cryptos = [
      makeCrypto(evaluationPrice: 6_000_000, evaluationProfitLoss: 1_000_000, buyAmount: 5_000_000),
      makeCrypto(evaluationPrice: 6_000_000, evaluationProfitLoss: 2_000_000, buyAmount: 4_000_000, marketName: "ETH/KRW"),
      makeCrypto(evaluationPrice: 0.05, evaluationProfitLoss: 0, buyAmount: 0.05, marketName: "ETH/BTC", costBasisKRW: 5_000_000)
    ]
    XCTAssertEqual(PortfolioCalculator.totalAssetValue(availableBalance: 1_000_000, cryptos: cryptos, btcKRWPrice: 120_000_000), 19_000_000)
    XCTAssertEqual(PortfolioCalculator.totalBuyAmount(cryptos: cryptos, btcKRWPrice: nil), 14_000_000)
    XCTAssertEqual(PortfolioCalculator.totalEvaluationProfitLoss(cryptos: cryptos, btcKRWPrice: 120_000_000), 4_000_000)
    for ascending in [true, false] {
      XCTAssertTrue(PortfolioCalculator.orderedBefore(-1, nil, ascending: ascending))
      XCTAssertFalse(PortfolioCalculator.orderedBefore(nil, 0, ascending: ascending))
    }
  }

  func testLargeDecimalCostAndTotalsPreserveSingleWon() throws {
    // Double로 바꾸면 1원이 손실되는 저장 원가다.
    let largeCost = try XCTUnwrap(Decimal(string: "9007199254740993"))
    // 합산 후에는 Double로도 정확히 표현 가능한 값을 만든다.
    let holdings = [
      makeCrypto(evaluationPrice: 10, evaluationProfitLoss: 0, buyAmount: 0, costBasisKRW: largeCost),
      makeCrypto(evaluationPrice: 1, evaluationProfitLoss: 0, buyAmount: 0, marketName: "ETH/KRW", costBasisKRW: 1)
    ]
    XCTAssertEqual(PortfolioCalculator.valuation(of: holdings[0], btcKRWPrice: nil).costBasisKRW, largeCost)
    XCTAssertEqual(PortfolioCalculator.totalBuyAmountDecimal(cryptos: holdings, btcKRWPrice: nil), largeCost + 1)
    XCTAssertEqual(PortfolioCalculator.totalBuyAmount(cryptos: holdings, btcKRWPrice: nil), 9_007_199_254_740_994)

    // 실제 셀에서 단위와 접근성 설명까지 정확한 원가를 표시한다.
    let cell = try XCTUnwrap(UINib(nibName: "InvestmentTableViewCell", bundle: Bundle.main)
      .instantiate(withOwner: nil).first as? InvestmentTableViewCell)
    cell.configure(crypto: holdings[0], isLast: true)
    XCTAssertEqual(cell.cryptoBuyPrice.accessibilityLabel, "9,007,199,254,740,993 KRW")
  }

  @MainActor
  func testInvestmentSortPreservesSingleWonAndKeepsUnknownAndTiesStable() throws {
    // 서로 1원 차이의 원가는 Double에서 같은 값이 된다.
    let largerCost = try XCTUnwrap(Decimal(string: "9007199254740993"))
    // 두 자산의 같은 평가금액에서 원가 차이가 손익 차이가 된다.
    let smallerCost = largerCost - 1
    // 투자 목록 정렬만 검증하고 화면을 로드하지 않는다.
    let reactor = InvestReactor(mainUseCase: MainUseCase(mainRepository: MainRepository()))
    // 각 항목의 마켓 이름으로 정렬 결과를 확인한다.
    let controller = InvestmentViewController(reactor: reactor)
    // 지원하지 않는 결제 통화의 환율은 없으므로 평가손익이 nil이다.
    let holdings = [
      makeCrypto(evaluationPrice: 10, evaluationProfitLoss: 0, buyAmount: 0, marketName: "A/KRW", costBasisKRW: largerCost),
      makeCrypto(evaluationPrice: 10, evaluationProfitLoss: 0, buyAmount: 0, marketName: "B/KRW", costBasisKRW: smallerCost),
      makeCrypto(evaluationPrice: 10, evaluationProfitLoss: 0, buyAmount: 0, marketName: "C/KRW", costBasisKRW: smallerCost),
      makeCrypto(evaluationPrice: 10, evaluationProfitLoss: 0, buyAmount: 0, marketName: "D/USDT", costBasisKRW: 1),
      makeCrypto(evaluationPrice: 10, evaluationProfitLoss: 0, buyAmount: 0, marketName: "E/USDT", costBasisKRW: 1)
    ]
    XCTAssertEqual(
      controller.sortCryptos(sortType: .evalProfitLossHighToLow, cryptos: holdings).map { $0.staticData.marketName },
      ["B/KRW", "C/KRW", "A/KRW", "D/USDT", "E/USDT"]
    )
    XCTAssertEqual(
      controller.sortCryptos(sortType: .evalProfitLossLowToHigh, cryptos: holdings).map { $0.staticData.marketName },
      ["A/KRW", "B/KRW", "C/KRW", "D/USDT", "E/USDT"]
    )
    XCTAssertEqual(
      controller.sortCryptos(sortType: .evalPriceHighToLow, cryptos: holdings).map { $0.staticData.marketName },
      ["A/KRW", "B/KRW", "C/KRW", "D/USDT", "E/USDT"]
    )
  }

  func testInvestmentCellDisplaysFixedCostAndKRWProfit() throws {
    let cell = try XCTUnwrap(UINib(nibName: "InvestmentTableViewCell", bundle: Bundle.main)
      .instantiate(withOwner: nil).first as? InvestmentTableViewCell)
    var crypto = makeCrypto(evaluationPrice: 0.05, evaluationProfitLoss: 0,
                            buyAmount: 0.05, marketName: "ETH/BTC", costBasisKRW: 5_000_000)
    for exchange in [Exchange.upbit, .bithumb] {
      crypto.staticData.exchange = exchange
      AppDataManager.shared.updateBTCKRWPrice(120_000_000, for: exchange)
      cell.configure(crypto: crypto, isLast: true)
      XCTAssertEqual(cell.cryptoName.text, crypto.staticData.cryptoName)
      XCTAssertEqual(cell.marketSymbolLabel.text, "ETH/BTC")
      XCTAssertEqual(cell.cryptoBuyPrice.accessibilityLabel, "5,000,000 KRW")
      XCTAssertEqual(cell.cryptoEvalPrice.accessibilityLabel, "6,000,000 KRW")
      XCTAssertEqual(cell.cryptoEvalLoss.text, "+1,000,000")
      XCTAssertEqual(cell.cryptoProfitRate.text, "+20%")
      XCTAssertEqual(cell.cryptoAveragePrice.accessibilityLabel, "0.05 BTC")
    }

    let legacyCrypto = makeCrypto(
      evaluationPrice: 6_000_000,
      evaluationProfitLoss: 0,
      buyAmount: 4_000_000,
      marketName: "ETH/BTC"
    )
    cell.configure(crypto: legacyCrypto, isLast: false)
    XCTAssertEqual(cell.cryptoBuyPrice.accessibilityLabel, "— KRW")
    XCTAssertEqual(cell.cryptoEvalPrice.accessibilityLabel, "6,000,000 KRW")
    XCTAssertEqual(cell.cryptoProfitRate.text, "—")
  }

  @MainActor
  func testUnsupportedInvestmentOverlayShowsActionAndResetsAfterReuse() throws {
    // 지원 종료 여부만 바뀌는 동일한 보유 종목이다.
    var crypto = makeCrypto(
      evaluationPrice: 5_340,
      evaluationProfitLoss: 340,
      buyAmount: 5_000,
      marketName: "GEOD/KRW",
      costBasisKRW: 5_000
    )
    crypto.staticData.cryptoName = "지오드넷"

    for width: CGFloat in [320, 375, 393] {
      // 화면에 사용하는 실제 셀과 자동 높이 테이블을 사용한다.
      let cell = try XCTUnwrap(
        UINib(nibName: "InvestmentTableViewCell", bundle: .main)
          .instantiate(withOwner: nil).first as? InvestmentTableViewCell
      )
      // 정상 셀과 종료 셀을 같은 화면에서 비교한다.
      let supportedCell = try XCTUnwrap(
        UINib(nibName: "InvestmentTableViewCell", bundle: .main)
          .instantiate(withOwner: nil).first as? InvestmentTableViewCell
      )
      supportedCell.configure(crypto: crypto, isLast: false, isTradingUnsupported: false)
      // 구성한 셀을 실제 자동 높이 테이블에 제공한다.
      let source = InvestmentOverlayTableSource(cells: [supportedCell, cell])
      // 셀 표시 크기와 터치 경로를 검사한다.
      let table = UITableView()
      table.dataSource = source
      table.rowHeight = UITableView.automaticDimension
      table.estimatedRowHeight = 200
      // 테이블의 실제 화면 계층을 제공한다.
      let controller = UIViewController()
      controller.view = table
      // 각 기기 너비에서 표시할 테스트 창이다.
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 812))
      window.rootViewController = controller
      window.makeKeyAndVisible()
      defer { window.isHidden = true; window.rootViewController = nil }

      cell.configure(crypto: crypto, isLast: true, isTradingUnsupported: false)
      XCTAssertTrue(cell.unsupportedOverlayView.isHidden)
      cell.configure(crypto: crypto, isLast: true, isTradingUnsupported: true)
      table.reloadData()
      window.layoutIfNeeded()
      table.layoutIfNeeded()
      cell.layoutIfNeeded()

      // 지원 종료 상태에서 표시할 흐림 표면이다.
      let overlay = try XCTUnwrap(cell.unsupportedOverlayView)
      // 사용자가 확인할 거래지원 종료 안내다.
      let notice = try XCTUnwrap(cell.unsupportedNoticeLabel)
      // 기존 정산 확인을 여는 버튼이다.
      let button = try XCTUnwrap(cell.unsupportedSettlementButton)
      XCTAssertFalse(overlay.isHidden)
      XCTAssertNotNil(overlay.effect)
      XCTAssertTrue(supportedCell.unsupportedOverlayView.isHidden)
      XCTAssertFalse(supportedCell.metricsStackView.superview?.accessibilityElementsHidden ?? true)
      XCTAssertEqual(supportedCell.cryptoBuyPrice.accessibilityLabel, "5,000 KRW")
      XCTAssertEqual(notice.accessibilityIdentifier, "investment.unsupported.notice")
      XCTAssertEqual(button.accessibilityIdentifier, "investment.unsupported.settle")
      XCTAssertTrue(button.isDescendant(of: overlay))
      XCTAssertTrue(notice.text?.contains("GEOD/KRW") == true)
      XCTAssertTrue(cell.metricsStackView.superview?.accessibilityElementsHidden == true)
      XCTAssertGreaterThanOrEqual(button.bounds.width, 44)
      XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
      XCTAssertTrue(overlay.bounds.insetBy(dx: -0.5, dy: -0.5).contains(button.convert(button.bounds, to: overlay)))

      // 안내 버튼이 실제 터치 위치에서 다른 뷰에 가려지지 않아야 한다.
      let buttonCenter = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: cell)
      // 버튼 중앙 터치를 실제로 받는 뷰다.
      let hit = cell.hitTest(buttonCenter, with: nil)
      XCTAssertTrue(hit === button || hit?.isDescendant(of: button) == true)
      // 버튼 탭이 셀의 정산 콜백으로 전달된 횟수다.
      var actionCount = 0
      cell.unsupportedSettlementCallBack = { actionCount += 1 }
      button.sendActions(for: .touchUpInside)
      XCTAssertEqual(actionCount, 1)

      for style in [UIUserInterfaceStyle.light, .dark] {
        window.overrideUserInterfaceStyle = style
        window.layoutIfNeeded()
        cell.layoutIfNeeded()
        XCTAssertFalse(overlay.isHidden)
        XCTAssertNotNil(overlay.effect)
        XCTAssertFalse(button.isHidden)
      }
      if #available(iOS 17.0, *) {
        for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
          controller.traitOverrides.preferredContentSizeCategory = category
          controller.updateTraitsIfNeeded()
          table.reloadData()
          window.layoutIfNeeded()
          table.layoutIfNeeded()
          cell.layoutIfNeeded()
          // 확대된 안내와 버튼도 흐림 영역에 들어가야 한다.
          let noticeFrame = notice.convert(notice.bounds, to: overlay)
          // 같은 좌표계에서 안내 아래의 버튼 위치다.
          let buttonFrame = button.convert(button.bounds, to: overlay)
          XCTAssertTrue(overlay.bounds.insetBy(dx: -0.5, dy: -0.5).contains(noticeFrame))
          XCTAssertTrue(overlay.bounds.insetBy(dx: -0.5, dy: -0.5).contains(buttonFrame))
          XCTAssertLessThanOrEqual(noticeFrame.maxY, buttonFrame.minY)
          XCTAssertGreaterThanOrEqual(buttonFrame.height, 44)
        }
        controller.traitOverrides.preferredContentSizeCategory = .large
        controller.updateTraitsIfNeeded()
        table.reloadData()
        window.layoutIfNeeded()
        table.layoutIfNeeded()
        cell.layoutIfNeeded()
      }
      if width == 375 {
        window.overrideUserInterfaceStyle = .light
        window.layoutIfNeeded()
        cell.layoutIfNeeded()
        // 흐림과 버튼을 실제 표시 계층에서 함께 확인한다.
        let image = UIGraphicsImageRenderer(bounds: cell.bounds).image { _ in
          cell.drawHierarchy(in: cell.bounds, afterScreenUpdates: true)
        }
        // 작은 화면의 실제 표시 결과를 검토할 수 있도록 보관한다.
        let attachment = XCTAttachment(image: image)
        attachment.name = "Unsupported-investment-overlay-375"
        attachment.lifetime = .keepAlways
        add(attachment)
        // 실제 윈도우에서 일반 셀과 흐림 셀의 겹침을 함께 렌더링한다.
        let screenImage = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
          window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        // UIVisualEffectView가 적용된 실제 화면을 보관한다.
        let screenAttachment = XCTAttachment(image: screenImage)
        screenAttachment.name = "Supported-and-unsupported-investment-375"
        screenAttachment.lifetime = .keepAlways
        add(screenAttachment)
      }

      cell.prepareForReuse()
      XCTAssertTrue(overlay.isHidden)
      XCTAssertNil(cell.unsupportedSettlementCallBack)
      cell.configure(crypto: crypto, isLast: false, isTradingUnsupported: false)
      XCTAssertTrue(overlay.isHidden)
      XCTAssertFalse(cell.metricsStackView.superview?.accessibilityElementsHidden ?? true)
      withExtendedLifetime(source) {}
    }
  }

  @MainActor
  func testUnsupportedInvestmentButtonOpensExistingConfirmationAndCancelKeepsAssets() throws {
    // 지원이 종료된 보유 종목을 실제 목록의 diffable 데이터로 전달한다.
    var crypto = makeCrypto(
      evaluationPrice: 5_340,
      evaluationProfitLoss: 340,
      buyAmount: 5_000,
      marketName: "GEOD/KRW",
      costBasisKRW: 5_000
    )
    crypto.staticData.exchange = ExchangeSelectionStore.currentExchange
    // 확인창은 목록 상태가 아니라 실제 저장된 보유 자산을 기준으로 정산액을 산출한다.
    let previousHoldings = UserDefaults.standard.object(forKey: UserDataManager.Keys.userCryptoList)
    UserDataManager.userCryptoList = [crypto]
    defer {
      if let previousHoldings {
        UserDefaults.standard.set(previousHoldings, forKey: UserDataManager.Keys.userCryptoList)
      } else {
        UserDefaults.standard.removeObject(forKey: UserDataManager.Keys.userCryptoList)
      }
    }
    // 네트워크 없이 거래소 지원 목록을 확정한다.
    let reactor = InvestReactor(mainUseCase: MainUseCase(mainRepository: MainRepository()))
    reactor.isStubEnabled = true
    // 화면이 받을 지원 종료 및 보유 상태다.
    var state = reactor.initialState
    state.cryptos = [crypto]
    state.supportedMarketPairIDs = [ExchangePairID(exchange: crypto.staticData.exchange, rawMarketCode: "KRW-BTC")]
    reactor.stub.state.value = state
    // 실제 목록의 셀 제공 및 알림 표시 경로를 사용한다.
    let controller = InvestmentViewController(reactor: reactor)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }

    // 목록 스냅샷은 메인 큐에서 비동기로 적용된다.
    let cellReady = expectation(for: NSPredicate { _, _ in
      controller.transactionTableview.visibleCells.contains { $0 is InvestmentTableViewCell }
    }, evaluatedWith: nil)
    wait(for: [cellReady], timeout: 5)
    // 실제 diffable 목록이 만든 지원 종료 셀이다.
    let cell = try XCTUnwrap(controller.transactionTableview.visibleCells.first as? InvestmentTableViewCell)
    XCTAssertFalse(cell.unsupportedOverlayView.isHidden)
    // 취소 전의 저장 자산을 보존해 정산이 발생하지 않았는지 확인한다.
    let originalHoldings = UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList)
    // 취소 전의 원화 주문 가능 잔고다.
    let originalBalance = UserDataManager.userInformation?.userAvailableBalance

    cell.unsupportedSettlementButton.sendActions(for: .touchUpInside)
    // 정산은 기존 확인창에서 사용자가 동의한 뒤에만 실행한다.
    let alert = try XCTUnwrap(controller.presentedViewController as? MobitAlertViewController)
    XCTAssertEqual(alert.alertType, .canCancel)
    XCTAssertEqual(alert.titleString, FuturesText.text("spot_delisting_title"))
    alert.loadViewIfNeeded()
    alert.cancelButton.sendActions(for: .touchUpInside)
    // 닫기 애니메이션과 취소 콜백이 처리될 때까지 기다린다.
    let alertClosed = expectation(for: NSPredicate { _, _ in
      controller.presentedViewController == nil
    }, evaluatedWith: nil)
    wait(for: [alertClosed], timeout: 5)
    XCTAssertEqual(UserDefaults.standard.data(forKey: UserDataManager.Keys.userCryptoList), originalHoldings)
    XCTAssertEqual(UserDataManager.userInformation?.userAvailableBalance, originalBalance)

    // 마켓이 다시 지원되면 예전 셀의 지연된 버튼 동작도 무시한다.
    let staleCallBack = try XCTUnwrap(cell.unsupportedSettlementCallBack)
    state.supportedMarketPairIDs = [crypto.staticData.exchangePairID]
    reactor.stub.state.value = state
    let supportedCellReady = expectation(for: NSPredicate { _, _ in
      guard let current = controller.transactionTableview.visibleCells.first as? InvestmentTableViewCell else { return false }
      return current.unsupportedOverlayView.isHidden
    }, evaluatedWith: nil)
    wait(for: [supportedCellReady], timeout: 5)
    staleCallBack()
    XCTAssertNil(controller.presentedViewController)
  }

  func testTradeHoldingViewDisplaysBTCMarketAveragePriceInBTC() throws {
    let view = try XCTUnwrap(
      UINib(nibName: "TradeOrderView", bundle: Bundle.main)
        .instantiate(withOwner: nil).first as? TradeOrderView
    )
    let crypto = makeCrypto(
      evaluationPrice: 0.05,
      evaluationProfitLoss: 0,
      buyAmount: 0.05,
      marketName: "ETH/BTC",
      costBasisKRW: 5_000_000
    )

    AppDataManager.shared.updateBTCKRWPrice(120_000_000, for: .upbit)
    view.setInvestLiveData(data: crypto)

    XCTAssertEqual(view.cryptoAveragePrice.text, "0.05")
  }

  func testTradeHistoryCellDisplaysLegacySettlementInKRW() throws {
    let cell = try XCTUnwrap(
      UINib(nibName: "TradeHistoryTableViewCell", bundle: Bundle.main)
        .instantiate(withOwner: nil).first as? TradeHistoryTableViewCell
    )
    let transaction = TransactionInfo(
      marketName: "ETH/BTC",
      orderType: .ask,
      executedDate: "07.09 12:00",
      executedPrice: 0.00003,
      executedQuantity: 20_000_000_000,
      executedAmount: 600_000,
      recordType: .legacyBTCSettlement
    )

    cell.configure(marketName: "ETH/BTC", transactionInfo: transaction)

    XCTAssertEqual(cell.orderTypeLabel.text, "시스템 정산")
    XCTAssertEqual(cell.tradeCryptoPrice.text, "0.00003 BTC")
    XCTAssertEqual(cell.tradeTotalPrice.text, "600,000 원")
  }

  func testPNLCellDisplaysBTCMarketAndRealizedProfitInKRW() throws {
    let cell = try XCTUnwrap(
      UINib(nibName: "PNLTableViewCell", bundle: Bundle.main)
        .instantiate(withOwner: nil).first as? PNLTableViewCell
    )
    var history = UserPNLHistoryModel(
      exchange: .bithumb,
      marketName: "ETH/BTC",
      entryPrice: 0.04,
      exitPrice: 0.05,
      transactionTimestamp: 1_700_000_000_000,
      orderQuantity: 1,
      pnl: 0.01
    )
    history.realizedProfitLossKRW = 1_500_000
    history.costBasisKRW = 3_000_000

    cell.configure(pnlHistory: history)

    XCTAssertEqual(cell.marketNameLabel.text, "ETH/BTC")
    XCTAssertEqual(cell.pnlLabel.accessibilityLabel, "+1,500,000 " + FuturesText.text("currency_krw_unit"))
    XCTAssertEqual(cell.roiLabel.accessibilityLabel, "+50%")
    XCTAssertTrue(cell.positionBadgeView.isHidden)
    XCTAssertTrue(cell.statusLabel.isHidden)
    XCTAssertTrue(cell.marginView.isHidden)
  }

  func testPNLCellDoesNotDisplayNativeBTCProfitWhenKRWProfitIsMissing() throws {
    let cell = try XCTUnwrap(
      UINib(nibName: "PNLTableViewCell", bundle: Bundle.main)
        .instantiate(withOwner: nil).first as? PNLTableViewCell
    )
    let history = UserPNLHistoryModel(
      marketName: "ETH/BTC",
      entryPrice: 0.04,
      exitPrice: 0.05,
      transactionTimestamp: 1_700_000_000_000,
      orderQuantity: 1,
      pnl: 0.01
    )

    cell.configure(pnlHistory: UserPNLHistoryModel(
      marketName: "BTC/KRW",
      entryPrice: 100,
      exitPrice: 110,
      transactionTimestamp: 1_700_000_000_000,
      orderQuantity: 1,
      pnl: 10
    ))
    cell.configure(pnlHistory: history)

    XCTAssertEqual(cell.pnlLabel.accessibilityLabel, "-")
    XCTAssertEqual(cell.roiLabel.accessibilityLabel, "-")
    XCTAssertEqual(cell.pnlLabel.textColor, UIColor.mobitColors(.textSecondary))
  }

  func testPNLCellShowsNativeSpotReturnWithoutKRWCostBasis() throws {
    // 원화 원가가 없는 기존 기록도 진입·종료 가격 기준 수익률을 표시한다.
    let cell = try XCTUnwrap(
      UINib(nibName: "PNLTableViewCell", bundle: Bundle.main)
        .instantiate(withOwner: nil).first as? PNLTableViewCell
    )
    // 저장된 현물 거래의 가격 수익률은 25%다.
    let history = UserPNLHistoryModel(
      marketName: "BTC/KRW",
      entryPrice: 100,
      exitPrice: 125,
      transactionTimestamp: 1_700_000_000_000,
      orderQuantity: 2,
      pnl: 50
    )

    cell.configure(pnlHistory: history)

    XCTAssertEqual(cell.pnlLabel.accessibilityLabel, "+50 " + FuturesText.text("currency_krw_unit"))
    XCTAssertEqual(cell.roiLabel.accessibilityLabel, "+25%")
    XCTAssertTrue(cell.marginView.isHidden)
  }

  func testTradeInputsRemoveGroupingSeparatorsBeforeEditing() {
    let bidTextField = UITextField()
    bidTextField.text = "1,500,000"
    TradeBidView().textFieldDidBeginEditing(bidTextField)

    let askTextField = UITextField()
    askTextField.text = "1,500,000"
    TradeAskView().textFieldDidBeginEditing(askTextField)

    XCTAssertEqual(bidTextField.text, "1500000")
    XCTAssertEqual(askTextField.text, "1500000")
  }

  func testBTCKRWPriceExpiresAfterLiveQuoteWindow() {
    let receivedAt = Date(timeIntervalSince1970: 1_000)
    AppDataManager.shared.updateBTCKRWPrice(
      120_000_000,
      for: .upbit,
      updatedAt: receivedAt
    )

    XCTAssertFalse(
      AppDataManager.shared.needsBTCKRWPriceRefresh(
        for: .upbit,
        at: receivedAt.addingTimeInterval(AppDataManager.btcKRWPriceRefreshAge)
      )
    )
    XCTAssertEqual(AppDataManager.shared.freshBTCKRWPrice(for: .upbit, at: receivedAt.addingTimeInterval(15)), 120_000_000)

    XCTAssertEqual(
      AppDataManager.shared.btcKRWPrice(
        for: .upbit,
        at: receivedAt.addingTimeInterval(AppDataManager.btcKRWPriceMaxAge)
      ),
      120_000_000
    )
    XCTAssertTrue(
      AppDataManager.shared.needsBTCKRWPriceRefresh(
        for: .upbit,
        at: receivedAt.addingTimeInterval(AppDataManager.btcKRWPriceRefreshAge + 0.001)
      )
    )
    XCTAssertNil(
      AppDataManager.shared.btcKRWPrice(
        for: .upbit,
        at: receivedAt.addingTimeInterval(AppDataManager.btcKRWPriceMaxAge + 0.001)
      )
    )
    XCTAssertEqual(
      AppDataManager.shared.lastBTCKRWPrice(for: .upbit),
      120_000_000
    )
    XCTAssertNil(
      AppDataManager.shared.freshBTCKRWPrice(
        for: .upbit,
        at: receivedAt.addingTimeInterval(AppDataManager.btcKRWPriceRefreshAge + 0.001)
      )
    )
    AppDataManager.shared.invalidateBTCKRWPrice(for: .upbit)
  }

  private func makeCrypto(
    evaluationPrice: Double,
    evaluationProfitLoss: Double,
    buyAmount: Double,
    marketName: String = "BTC/KRW",
    costBasisKRW: Decimal? = nil
  ) -> CryptoTransactionDataModel {
    CryptoTransactionDataModel(
      staticData: .init(
        marketName: marketName,
        cryptoName: "비트코인",
        holdingQuantity: 1,
        averageBuyPrice: buyAmount,
        buyAmount: buyAmount,
        costBasisKRW: costBasisKRW
      ),
      dynamicData: .init(
        marketName: marketName,
        profitRate: 0,
        evaluationProfitLoss: evaluationProfitLoss,
        evaluationPrice: evaluationPrice
      )
    )
  }
}

// 거래지원 재조회에서 실제 네트워크 대신 지정한 목록을 사용한다.
final class DelistingMarketFixtureUseCase: MainUseCase {
  // 각 검증 단계에서 반환할 거래소 목록이다.
  var marketResponse: Observable<CryptoList> = .just([crypto("KRW-BTC")])
  // 정산 환율 조회에 돌려줄 응답이다.
  var tickerResponse: Observable<CryptoTickerList> = .empty()
  // 불필요한 재조회와 잘못된 조회 종목을 확인한다.
  private(set) var tickerRequests: [[String]] = []

  init() {
    super.init(mainRepository: MainRepository())
  }

  override func fetchCryptoList() -> Observable<CryptoList> { marketResponse }

  override func fetchCryptoTicker(markets: [String]) -> Observable<CryptoTickerList> {
    tickerRequests.append(markets)
    return tickerResponse
  }

  static func crypto(_ market: String) -> Crypto {
    Crypto(
      market: market,
      koreanName: "테스트",
      englishName: "Test",
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
  }
}

// 정상·지원 종료 셀을 같은 자동 높이 테이블에 제공한다.
@MainActor
private final class InvestmentOverlayTableSource: NSObject, UITableViewDataSource {
  // 캡처와 터치 검증에 사용하는 순서대로 정렬된 셀이다.
  private let cells: [UITableViewCell]

  init(cells: [UITableViewCell]) {
    self.cells = cells
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    cells.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    cells[indexPath.row]
  }
}
