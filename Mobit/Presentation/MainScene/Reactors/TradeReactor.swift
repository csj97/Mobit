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
  
  let selectCrypto: CryptoCellInfo
  let initialState: TradeState = TradeState()
  var tickerSocketManager: NewWebSocketManager? = nil
  var orderBookSocketManager: NewWebSocketManager? = nil
  var cmcInformation: FirebaseCMCResponse
  var cmcList: [FirebaseCMCResponse]?
  
  init(
    selectCrypto: CryptoCellInfo,
	cmcInformation: FirebaseCMCResponse,
    cryptoDetailUseCase: CryptoDetailUseCase
  ) {
    self.selectCrypto = selectCrypto
	self.cmcInformation = cmcInformation
    self.cryptoDetailUseCase = cryptoDetailUseCase
	
	UserDataManager.userCryptoListObservable
	  .map { TradeMutation.setUserCrypto($0) }
	  .bind(to: mutationSubject)
	  .disposed(by: disposeBag)
  }
}

extension TradeReactor {
  enum TradeAction {
    case connectTickerSocket
    case connectOrderBookSocket
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
	case setCandleList(candleResponseModelList: [any CandleModel])
	case setSelectedWholeTab(tab: SelectedWholeTab)
	case setUserCrypto([CryptoTransactionDataModel]?)
  }
  
  struct TradeState {
    var cryptoCellInfo: CryptoCellInfo? = nil
    var obTicker: Orderbook?
	var cryptoQuotesInfo: CryptoQuoteResponse? = nil
	var candleMinuteResponse: [MinuteResponseModel]? = nil
	var candleResponse: [any CandleModel]? = nil
	var selectedWholeTab: SelectedWholeTab = .trade
	var cryptoTransactionDatas: [CryptoTransactionDataModel] = []
  }
}

extension TradeReactor {
  func mutate(action: TradeAction) -> Observable<TradeMutation> {
    switch action {
    case .connectTickerSocket:
      return self.connectTickerSocket(crypto: self.selectCrypto)
      
    case .connectOrderBookSocket:
      return self.connectOrderBookTicker(crypto: self.selectCrypto)
	  
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
    
    switch mutation {
    case .setCryptoInfo(let cryptoCellInfo):
      newState.cryptoCellInfo = cryptoCellInfo
    case .setOrderBookInfo(let obTicker):
      newState.obTicker = obTicker
	case .setCryptoInformation(let cryptoQuotesResponse):
	  newState.cryptoQuotesInfo = cryptoQuotesResponse
	case .setCandleListMinutes(let minuteResponseModelList):
	  newState.candleMinuteResponse = minuteResponseModelList
	case .setCandleList(let dayResponseModelList):
	  newState.candleResponse = dayResponseModelList
	case .setSelectedWholeTab(let tab):
	  newState.selectedWholeTab = tab
	case .setUserCrypto(let cryptoTransactionDatas):
	  newState.cryptoTransactionDatas = cryptoTransactionDatas ?? []
    }
    
    return newState
  }
}

extension TradeReactor {
  // WebSocket Ticker
  private func connectTickerSocket(crypto: CryptoCellInfo) -> Observable<TradeMutation> {
    
    let socketObservable = Observable<TradeMutation>.create { observer in
	  
	  self.tickerSocketManager = NewWebSocketManager(socketType: .ticker)
	  guard let tickerSocketManager = self.tickerSocketManager else {
		return Disposables.create {
		  self.tickerSocketManager?.disconnect()
		  self.tickerSocketManager = nil
		}
	  }
	  tickerSocketManager.connect()
	  tickerSocketManager.onConnected = {
		tickerSocketManager.sendMessage(
          codes: [self.transformMarketForm(market: crypto.market)],
          socketType: .ticker
        )
      }
      
	  tickerSocketManager.observeReceivedData()
        .observe(on: MainScheduler.instance)
        .subscribe { [weak self] data in
          guard let self = self else { return }

          do {
            let decodeTarget = CryptoSocketTickerDTO.self
            let cryptoTickerDTO = try JSONDecoder().decode(decodeTarget, from: data)
            let ticker = cryptoTickerDTO.toDomain()
            
            var updatedCryptoCellInfo: CryptoCellInfo = self.selectCrypto
            updatedCryptoCellInfo.tradePrice = ticker.tradePrice
            updatedCryptoCellInfo.change = ticker.change
            updatedCryptoCellInfo.changePrice = ticker.changePrice
            updatedCryptoCellInfo.signedChangeRate = ticker.signedChangeRate
            
            observer.onNext(.setCryptoInfo(cryptoInfo: updatedCryptoCellInfo))
          } catch {
			Log.error("Crypto Detail Ticker websocket receive decoding error : \(error.localizedDescription)")
          }
        } onError: { error in
          observer.onError(error)
        } onCompleted: {
          observer.onCompleted()
        }.disposed(by: self.disposeBag)
      
      return Disposables.create {
        self.tickerSocketManager?.disconnect()
		self.tickerSocketManager = nil
      }
    }
    
    return socketObservable
  }
  
  // 호가창 WebSocket 통신
  private func connectOrderBookTicker(crypto: CryptoCellInfo) -> Observable<TradeMutation> {
    let socketObservable = Observable<TradeMutation>.create { observer in
	  
	  self.orderBookSocketManager = NewWebSocketManager(socketType: .orderbook)
	  
	  guard let orderBookSocketManager = self.orderBookSocketManager else {
		return Disposables.create {
		  self.orderBookSocketManager?.disconnect()
		  self.orderBookSocketManager = nil
		}
	  }
	  
      orderBookSocketManager.connect()
	  orderBookSocketManager.onConnected = {
        orderBookSocketManager.sendMessage(
          codes: [
            self.transformMarketForm(
              market: self.selectCrypto.market
            )
          ],
          socketType: .orderbook
        )
      }
      
      orderBookSocketManager.observeReceivedData()
        .observe(on: MainScheduler.instance)
		.subscribe { [weak self] data in
		  guard let self = self else { return }

          do {
            let decodeTarget = OrderbookDTO.self
            let orderBookDTO = try JSONDecoder().decode(decodeTarget, from: data)
            let obTicker = orderBookDTO.toDomain()
            observer.onNext(.setOrderBookInfo(obTicker: obTicker))
          } catch {
			Log.error("orderbook websocket receive decoding error : \(error.localizedDescription)")
          }
        } onError: { error in
          observer.onError(error)
        } onCompleted: {
          observer.onCompleted()
        }.disposed(by: self.disposeBag)
      
      return Disposables.create {
        self.orderBookSocketManager?.disconnect()
		self.orderBookSocketManager = nil
      }
    }
    
    return socketObservable
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
	  return .setCandleList(candleResponseModelList: dayResponseModelList)
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
