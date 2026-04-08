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
  private let disposeBag = DisposeBag()
  private let tickerSocketService: TickerSocketServiceProtocol
  private let orderBookSocketService: OrderBookSocketServiceProtocol
  
  let selectCrypto: CryptoCellInfo
  let initialState: TradeState = TradeState()
  var cmcInformation: FirebaseCMCResponse
  var cmcList: [FirebaseCMCResponse]?
  private(set) var isTickerConnected = false
  private(set) var isOrderBookConnected = false
  
  init(
    selectCrypto: CryptoCellInfo,
	cmcInformation: FirebaseCMCResponse,
    cryptoDetailUseCase: CryptoDetailUseCase,
    tickerSocketService: TickerSocketServiceProtocol = TickerSocketService(),
    orderBookSocketService: OrderBookSocketServiceProtocol = OrderBookSocketService()
  ) {
    self.selectCrypto = selectCrypto
	self.cmcInformation = cmcInformation
    self.cryptoDetailUseCase = cryptoDetailUseCase
    self.tickerSocketService = tickerSocketService
    self.orderBookSocketService = orderBookSocketService
	
	UserDataManager.userCryptoListObservable
      .observe(on: MainScheduler.asyncInstance)
	  .map { TradeMutation.setUserCrypto($0) }
	  .bind(to: mutationSubject)
	  .disposed(by: disposeBag)

    self.tickerSocketService.stream
      .observe(on: MainScheduler.asyncInstance)
      .map { [weak self] ticker -> TradeMutation? in
        guard let self = self else { return nil }

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
      .map { TradeMutation.setOrderBookInfo(obTicker: $0) }
      .bind(to: mutationSubject)
      .disposed(by: disposeBag)
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
  }
  
  enum TradeMutation {
    case setCryptoInfo(cryptoInfo: CryptoCellInfo)
    case setOrderBookInfo(obTicker: Orderbook)
	case setCryptoInformation(cryptoQuoteResponse: CryptoQuoteResponse)
	case setCandleListMinutes(minuteResponseModelList: [MinuteResponseModel])
	case setCandleListDays(dayResponseModelList: [DayResponseModel])
	case setSelectedWholeTab(tab: SelectedWholeTab)
	case setUserCrypto([CryptoTransactionDataModel]?)
  }
  
  struct TradeState {
    var cryptoCellInfo: CryptoCellInfo? = nil
    var obTicker: Orderbook?
	var cryptoQuotesInfo: CryptoQuoteResponse? = nil
	var candleMinuteResponse: [MinuteResponseModel]? = nil
	var candleDayResponse: [DayResponseModel]? = nil
	var selectedWholeTab: SelectedWholeTab = .trade
	var cryptoTransactionDatas: [CryptoTransactionDataModel] = []
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
    }
    
    return newState
  }
}

extension TradeReactor {
  private func connectSockets(crypto: CryptoCellInfo) -> Observable<TradeMutation> {
    let market = self.transformMarketForm(market: crypto.market)

    tickerSocketService.connect()
    tickerSocketService.subscribe(markets: [market])

    orderBookSocketService.connect()
    orderBookSocketService.subscribe(market: market)

    isTickerConnected = tickerSocketService.isConnected
    isOrderBookConnected = orderBookSocketService.isConnected

    return .empty()
  }

  private func disconnectSockets(userInitiated: Bool) -> Observable<TradeMutation> {
    tickerSocketService.disconnect(userInitiated: userInitiated)
    orderBookSocketService.disconnect(userInitiated: userInitiated)

    isTickerConnected = tickerSocketService.isConnected
    isOrderBookConnected = orderBookSocketService.isConnected

    return .empty()
  }

  private func pauseSocket() -> Observable<TradeMutation> {
    return disconnectSockets(userInitiated: false)
  }

  private func resumeSocket() -> Observable<TradeMutation> {
    tickerSocketService.reconnectIfNeeded()
    if !tickerSocketService.isConnected {
      tickerSocketService.connect()
    }

    orderBookSocketService.reconnectIfNeeded()
    if !orderBookSocketService.isConnected {
      orderBookSocketService.connect()
    }

    let market = self.transformMarketForm(market: self.selectCrypto.market)
    tickerSocketService.subscribe(markets: [market])
    orderBookSocketService.subscribe(market: market)

    isTickerConnected = tickerSocketService.isConnected
    isOrderBookConnected = orderBookSocketService.isConnected

    return .empty()
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
    var transformMarket = market
    let components = transformMarket.split(separator: "/")
    if components.count == 2 {
      transformMarket = "\(components[1])-\(components[0])"
    } else {
      // 기본값 유지
      transformMarket = market
    }
    return transformMarket
  }
  
  func transform(mutation: Observable<TradeMutation>) -> Observable<TradeMutation> {
	return Observable.merge(
	  mutation,                      // 원래 액션 기반의 내부 스트림
	  mutationSubject.asObservable() // 외부 이벤트 기반의 스트림
	)
  }
}
