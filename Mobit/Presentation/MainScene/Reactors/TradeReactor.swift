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
  
  let selectCrypto: CryptoCellInfo
  private let cryptoDetailUseCase: CryptoDetailUseCase
  private let disposeBag = DisposeBag()
  
  let initialState: TradeState = TradeState()
  var tickerSocketManager: NewWebSocketManager? = nil
  var orderBookSocketManager: NewWebSocketManager? = nil
  var cmcInformation: FirebaseCMCResponse
  private var firebaseDB = Database.database().reference()
  
  init(
    selectCrypto: CryptoCellInfo,
	cmcInformation: FirebaseCMCResponse,
    cryptoDetailUseCase: CryptoDetailUseCase
  ) {
    self.selectCrypto = selectCrypto
	self.cmcInformation = cmcInformation
    self.cryptoDetailUseCase = cryptoDetailUseCase
  }
}

extension TradeReactor {
  enum TradeAction {
    case connectTickerSocket
    case connectOrderBookSocket
	case getCryptoInformation
	case setSelectedWholeTab(selectedWholeTab: SelectedWholeTab)
  }
  
  enum TradeMutation {
    case setCryptoInfo(cryptoInfo: CryptoCellInfo)
    case setOrderBookInfo(obTicker: Orderbook)
	case setCryptoInformation(cryptoQuoteResponse: CryptoQuoteResponse)
	case setSelectedWholeTab(tab: SelectedWholeTab)
  }
  
  struct TradeState {
    var cryptoCellInfo: CryptoCellInfo? = nil
    var obTicker: Orderbook?
	var cryptoQuotesInfo: CryptoQuoteResponse? = nil
	var selectedWholeTab: SelectedWholeTab = .trade
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
	  
	case .setSelectedWholeTab(let tab):
	  return self.setSelectedWholeTab(tab: tab)
    }
  }
  
  func reduce(state: TradeState,
              mutation: TradeMutation) -> TradeState {
    var newState = state
    
    switch mutation {
    case .setCryptoInfo(let cryptoCellInfo):
      newState.cryptoCellInfo = cryptoCellInfo
    case .setOrderBookInfo(let obTicker):
      newState.obTicker = obTicker
	case .setCryptoInformation(let cryptoQuotesResponse):
	  newState.cryptoQuotesInfo = cryptoQuotesResponse
	case .setSelectedWholeTab(let tab):
	  newState.selectedWholeTab = tab
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
            print("Crypto Detail Ticker websocket receive decoding error : \(error.localizedDescription)")
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
            print("orderbook websocket receive decoding error : \(error.localizedDescription)")
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
  
}
