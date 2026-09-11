//
//  TradeReactor.swift
//  Mobit
//
//  Created by 조성재 on 8/19/24.
//

import Foundation
import FirebaseDatabase
import UIKit
import RxSwift
import ReactorKit
import RxRelay

class TradeReactor: Reactor {
  
  enum SelectedWholeTab {
	case trade, chart, info
  }
  
  // ReactorKit 외부에서 mutation을 주입하려면 이게 필요
  private let mutationSubject = PublishSubject<TradeMutation>()
  private var firebaseDB = Database.database().reference()
  private let cryptoDetailUseCase: CryptoDetailUseCase
  private let mainUseCase: MainUseCaseProtocol
  private let disposeBag = DisposeBag()
  private let tickerSocketService: TickerSocketServiceProtocol
  private let orderBookSocketService: OrderBookSocketServiceProtocol
  private var isSettlementRateRefreshInFlight = false
  private var nextSettlementRateRefreshAllowedAt = Date.distantPast
  private var isSocketMonitoringEnabled = false
  
  let selectCrypto: CryptoCellInfo
  let initialState: TradeState
  var cmcInformation: FirebaseCMCResponse?
  var cmcList: [FirebaseCMCResponse]?
  private(set) var isTickerConnected = false
  private(set) var isOrderBookConnected = false

  /// 선택 종목의 결제 통화. BTC 마켓이면 결제용 BTC/KRW 시세를 함께 구독한다.
  let settlementCurrency: SettlementCurrency
  private let selectedMarketCode: String
  private let settlementRateMarketCode: String?
  let exchange: Exchange

  init(
    selectCrypto: CryptoCellInfo,
	cmcInformation: FirebaseCMCResponse?,
    cryptoDetailUseCase: CryptoDetailUseCase,
    mainUseCase: MainUseCaseProtocol,
    tickerSocketService: TickerSocketServiceProtocol = TickerSocketService(),
    orderBookSocketService: OrderBookSocketServiceProtocol = OrderBookSocketService()
  ) {
    let exchange = ExchangeSelectionStore.currentExchange
    self.exchange = exchange
    self.selectCrypto = selectCrypto
	self.cmcInformation = cmcInformation
    self.cryptoDetailUseCase = cryptoDetailUseCase
    self.mainUseCase = mainUseCase
    self.tickerSocketService = tickerSocketService
    self.orderBookSocketService = orderBookSocketService

    let currency = ExchangeMarketCodeConverter.settlementCurrency(
      fromDisplayMarket: selectCrypto.market,
      exchange: exchange
    ) ?? .krw
    self.settlementCurrency = currency
    self.selectedMarketCode = MarketFormat.apiMarket(fromDisplayMarket: selectCrypto.market)
    self.settlementRateMarketCode = currency.holdingDisplayMarket.map {
      MarketFormat.apiMarket(fromDisplayMarket: $0)
    }
    self.initialState = TradeState(
      settlementRatePrice: currency == .btc
        ? AppDataManager.shared.freshBTCKRWPrice(for: exchange)
        : nil
    )

	UserDataManager.userCryptoListObservable
      .observe(on: MainScheduler.asyncInstance)
	  .map { TradeMutation.setUserCrypto($0) }
	  .bind(to: mutationSubject)
	  .disposed(by: disposeBag)

    self.tickerSocketService.stream
      .observe(on: MainScheduler.asyncInstance)
      .map { [weak self] ticker -> TradeMutation? in
        guard let self = self,
              self.exchange == ExchangeSelectionStore.currentExchange else { return nil }

        // 결제용 BTC/KRW를 함께 구독하므로 종목을 구분하지 않으면 선택 종목 시세가 덮인다.
        if let settlementRateMarketCode = self.settlementRateMarketCode,
           ticker.code == settlementRateMarketCode {
          // 투자내역·손익 화면도 같은 시세로 환산해야 하므로 공용 저장소에 함께 반영한다.
          AppDataManager.shared.updateBTCKRWPrice(
            ticker.tradePrice,
            for: self.exchange
          )
          return .setSettlementRate(price: ticker.tradePrice)
        }

        guard ticker.code == self.selectedMarketCode else { return nil }

        var updatedCryptoCellInfo = self.selectCrypto
        updatedCryptoCellInfo.tradePrice = ticker.tradePrice
        updatedCryptoCellInfo.change = ticker.change
        updatedCryptoCellInfo.changePrice = ticker.changePrice
        updatedCryptoCellInfo.signedChangeRate = ticker.signedChangeRate

        return .setCryptoInfo(cryptoInfo: updatedCryptoCellInfo)
      }
      .compactMap { $0 }
      .bind(to: mutationSubject)
      .disposed(by: disposeBag)

    self.orderBookSocketService.stream
      .observe(on: MainScheduler.asyncInstance)
      .compactMap { [weak self] orderBook -> TradeMutation? in
        guard let self,
              self.exchange == ExchangeSelectionStore.currentExchange else { return nil }
        return .setOrderBookInfo(obTicker: orderBook)
      }
      .bind(to: mutationSubject)
      .disposed(by: disposeBag)

    Observable<Int>.interval(.seconds(5), scheduler: MainScheduler.asyncInstance)
      .map { _ in TradeAction.validateSocketState }
      .bind(to: self.action)
      .disposed(by: disposeBag)
  }

  var hasInformationTabData: Bool {
	guard self.cmcInformation != nil else { return false }
	return self.selectCrypto.accTradePrice24h != nil &&
	  self.selectCrypto.accTradeVolume24h != nil &&
	  self.selectCrypto.prevPrice != nil &&
	  self.selectCrypto.highest52WeekPrice != nil &&
	  self.selectCrypto.lowest52WeekPrice != nil
  }
}

extension TradeReactor {
  enum TradeAction {
    case connectSockets
    case disconnectSockets(userInitiated: Bool)
    case pauseSocket
    case resumeSocket
	case getCryptoInformation
	case getCandleListMinutes(market: String, unit: Int32 = 60, to: String?, count: Int?)
	case getCandleListDays(market: String, to: String?, count: Int?, convertingPriceUnit: String?)
	case setSelectedWholeTab(selectedWholeTab: SelectedWholeTab)
    case loadTransactions
    case validateSocketState
    case refreshSettlementRate
  }
  
  enum TradeMutation {
    case setCryptoInfo(cryptoInfo: CryptoCellInfo)
    case setOrderBookInfo(obTicker: Orderbook)
	case setCryptoInformation(cryptoQuoteResponse: CryptoQuoteResponse)
	case setCandleListMinutes(minuteResponseModelList: [MinuteResponseModel])
	case setCandleListDays(dayResponseModelList: [DayResponseModel])
	case setSelectedWholeTab(tab: SelectedWholeTab)
	case setUserCrypto([CryptoTransactionDataModel]?)
	case setSettlementRate(price: Double?)
  }

  struct TradeState {
    var cryptoCellInfo: CryptoCellInfo? = nil
    var obTicker: Orderbook?
	var cryptoQuotesInfo: CryptoQuoteResponse? = nil
	var candleMinuteResponse: [MinuteResponseModel]? = nil
	var candleDayResponse: [DayResponseModel]? = nil
	var selectedWholeTab: SelectedWholeTab = .trade
	var cryptoTransactionDatas: [CryptoTransactionDataModel] = []
	/// BTC 마켓 결제·평가에 쓰는 BTC/KRW 현재가. 원화 마켓에서는 채우지 않는다.
	var settlementRatePrice: Double? = nil
  }
}

extension TradeReactor {
  func mutate(action: TradeAction) -> Observable<TradeMutation> {
    switch action {
    case .connectSockets:
      return self.connectSockets(crypto: self.selectCrypto)

    case .disconnectSockets(let userInitiated):
      return self.disconnectSockets(userInitiated: userInitiated)

    case .pauseSocket:
      return self.pauseSocket()

    case .resumeSocket:
      return self.resumeSocket()
	  
	case .getCryptoInformation:
	  let symbol = self.selectCrypto.market.components(separatedBy: "/").first ?? ""
	  return self.getCryptoInformation(market: symbol)
	  
	case .getCandleListMinutes(let market, let unit, let to, let count):
	  return self.getCandleListMinutes(market: market, unit: unit, to: to, count: count)
	  
	case .getCandleListDays(let market, let to, let count, let convertingPriceUnit):
	  return self.getCandleListDays(market: market, to: to, count: count, convertingPriceUnit: convertingPriceUnit)
	  
	case .setSelectedWholeTab(let tab):
	  return self.setSelectedWholeTab(tab: tab)
	  
	case .loadTransactions:
	  return .just(.setUserCrypto(UserDataManager.userCryptoList))

    case .validateSocketState:
      return self.validateSocketState()

    case .refreshSettlementRate:
      return self.refreshSettlementRate(force: true)
    }
  }
  
  func reduce(state: TradeState, mutation: TradeMutation) -> TradeState {
    var newState = state
    self.isTickerConnected = tickerSocketService.isConnected
    self.isOrderBookConnected = orderBookSocketService.isConnected
    
    switch mutation {
    case .setCryptoInfo(let cryptoCellInfo):
      newState.cryptoCellInfo = cryptoCellInfo
    case .setOrderBookInfo(let obTicker):
      newState.obTicker = obTicker
	case .setCryptoInformation(let cryptoQuotesResponse):
	  newState.cryptoQuotesInfo = cryptoQuotesResponse
	case .setCandleListMinutes(let minuteResponseModelList):
	  newState.candleMinuteResponse = minuteResponseModelList
	case .setCandleListDays(let dayResponseModelList):
	  newState.candleDayResponse = dayResponseModelList
	case .setSelectedWholeTab(let tab):
	  newState.selectedWholeTab = tab
	case .setUserCrypto(let cryptoTransactionDatas):
	  newState.cryptoTransactionDatas = cryptoTransactionDatas ?? []
	case .setSettlementRate(let price):
	  newState.settlementRatePrice = price
    }
    
    return newState
  }
}

extension TradeReactor {
  private func connectSockets(crypto: CryptoCellInfo) -> Observable<TradeMutation> {
    isSocketMonitoringEnabled = true
    let market = self.transformMarketForm(market: crypto.market)

    tickerSocketService.connect()
    tickerSocketService.subscribe(markets: self.tickerMarketsToSubscribe)

    orderBookSocketService.connect()
    orderBookSocketService.subscribe(market: market)

    isTickerConnected = tickerSocketService.isConnected
    isOrderBookConnected = orderBookSocketService.isConnected

    return Observable.concat([
      .just(.setSettlementRate(price: AppDataManager.shared.freshBTCKRWPrice(for: self.exchange))),
      refreshSettlementRate()
    ])
  }

  private func disconnectSockets(userInitiated: Bool) -> Observable<TradeMutation> {
    isSocketMonitoringEnabled = false
    tickerSocketService.disconnect(userInitiated: userInitiated)
    orderBookSocketService.disconnect(userInitiated: userInitiated)

    isTickerConnected = tickerSocketService.isConnected
    isOrderBookConnected = orderBookSocketService.isConnected

    return .empty()
  }

  private func pauseSocket() -> Observable<TradeMutation> {
    return disconnectSockets(userInitiated: true)
  }

  private func resumeSocket() -> Observable<TradeMutation> {
    isSocketMonitoringEnabled = true
    tickerSocketService.reconnectIfNeeded()
    if !tickerSocketService.isConnected {
      tickerSocketService.connect()
    }

    orderBookSocketService.reconnectIfNeeded()
    if !orderBookSocketService.isConnected {
      orderBookSocketService.connect()
    }

    let market = self.transformMarketForm(market: self.selectCrypto.market)
    tickerSocketService.subscribe(markets: self.tickerMarketsToSubscribe)
    orderBookSocketService.subscribe(market: market)

    isTickerConnected = tickerSocketService.isConnected
    isOrderBookConnected = orderBookSocketService.isConnected

    return Observable.concat([
      .just(.setSettlementRate(price: AppDataManager.shared.freshBTCKRWPrice(for: self.exchange))),
      refreshSettlementRate()
    ])
  }

  /// 연결이 끊기면 재구독하고, BTC/KRW가 15초간 갱신되지 않으면 REST로 검증한다.
  private func validateSocketState() -> Observable<TradeMutation> {
    guard isSocketMonitoringEnabled else { return .empty() }

    if !tickerSocketService.isConnected {
      tickerSocketService.reconnectIfNeeded()
      if !tickerSocketService.isConnected { tickerSocketService.connect() }
      tickerSocketService.subscribe(markets: tickerMarketsToSubscribe)
    }

    if !orderBookSocketService.isConnected {
      orderBookSocketService.reconnectIfNeeded()
      if !orderBookSocketService.isConnected { orderBookSocketService.connect() }
      orderBookSocketService.subscribe(market: transformMarketForm(market: selectCrypto.market))
    }

    return refreshSettlementRate()
  }

  /// 주문에는 성공한 REST 시세만 갱신하고, 실패 시 마지막 표시값과 주문용 시세를 분리한다.
  private func refreshSettlementRate(force: Bool = false) -> Observable<TradeMutation> {
    guard settlementCurrency == .btc,
          let market = settlementRateMarketCode,
          force || AppDataManager.shared.needsBTCKRWPriceRefresh(for: exchange),
          !isSettlementRateRefreshInFlight,
          force || Date() >= nextSettlementRateRefreshAllowedAt else { return .empty() }

    isSettlementRateRefreshInFlight = true
    nextSettlementRateRefreshAllowedAt = Date().addingTimeInterval(15)
    return mainUseCase.loadCryptoTicker(markets: [market])
      .timeout(.seconds(10), scheduler: MainScheduler.asyncInstance)
      .flatMap { [weak self] tickers -> Observable<TradeMutation> in
        guard let self else { return .empty() }
        guard self.exchange == ExchangeSelectionStore.currentExchange else { return .empty() }
        guard let price = tickers.first(where: { $0.market == market })?.tradePrice,
              price.isFinite,
              price > 0 else {
          return .just(.setSettlementRate(price: nil))
        }

        AppDataManager.shared.updateBTCKRWPrice(price, for: self.exchange)
        self.nextSettlementRateRefreshAllowedAt = .distantPast
        return .just(.setSettlementRate(price: price))
      }
      .catch { error in
        Log.error("BTC/KRW refresh failed: \(error.localizedDescription)")
        return .just(.setSettlementRate(price: nil))
      }
      .do(onDispose: { [weak self] in
        self?.isSettlementRateRefreshInFlight = false
      })
  }

  /// BTC 마켓은 결제 자산 평가를 위해 BTC/KRW 시세도 함께 받아야 한다.
  private var tickerMarketsToSubscribe: [String] {
    guard let settlementRateMarketCode else { return [self.selectedMarketCode] }
    return [self.selectedMarketCode, settlementRateMarketCode]
  }

  private func getCryptoInformation(market: String) -> Observable<TradeMutation> {
	return self.cryptoDetailUseCase.getCryptoInformation(market: market)
	  .map { cryptoQuoteResponse in
		return .setCryptoInformation(cryptoQuoteResponse: cryptoQuoteResponse)
	  }
  }
  
  private func getCandleListMinutes(market: String, unit: Int32 = 60, to: String?, count: Int?) -> Observable<TradeMutation> {
	return self.cryptoDetailUseCase.getCandleMinutes(market: market, unit: unit, to: to, count: count)
	  .map { minuteResponseModelList in
		return .setCandleListMinutes(minuteResponseModelList: minuteResponseModelList)
	  }
  }
  
  private func getCandleListDays(market: String, to: String?, count: Int?, convertingPriceUnit: String?) -> Observable<TradeMutation> {
	return self.cryptoDetailUseCase.getCandleDays(
	  market: market,
	  to: to,
	  count: count,
	  convertingPriceUnit: convertingPriceUnit
	)
	.map { dayResponseModelList in
	  return .setCandleListDays(dayResponseModelList: dayResponseModelList)
	}
  }
  
  private func setSelectedWholeTab(tab: SelectedWholeTab) -> Observable<TradeMutation> {
	let tabObservable = Observable<TradeMutation>.create { observer in
	  
	  observer.onNext(.setSelectedWholeTab(tab: tab))
	  observer.onCompleted()
	  
	  return Disposables.create()
	}
	
	return tabObservable
  }
  
  func transformMarketForm(market: String) -> String {
    return MarketFormat.apiMarket(fromDisplayMarket: market)
  }
  
  func transform(mutation: Observable<TradeMutation>) -> Observable<TradeMutation> {
	return Observable.merge(
	  mutation,                      // 원래 액션 기반의 내부 스트림
	  mutationSubject.asObservable() // 외부 이벤트 기반의 스트림
	)
  }
}
