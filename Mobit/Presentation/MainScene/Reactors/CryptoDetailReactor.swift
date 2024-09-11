//
//  CryptoDetailReactor.swift
//  Mobit
//
//  Created by 조성재 on 8/19/24.
//

import Foundation
import UIKit
import RxSwift
import ReactorKit
import RxRelay

class CryptoDetailReactor: Reactor {
  let selectCrypto: CryptoCellInfo
  private let cryptoDetailUseCase: CryptoDetailUseCase
  private let disposeBag = DisposeBag()
  
  let initialState: CryptoDetailState = CryptoDetailState()
  
  init(selectCrypto: CryptoCellInfo, cryptoDetailUseCase: CryptoDetailUseCase) {
    self.selectCrypto = selectCrypto
    self.cryptoDetailUseCase = cryptoDetailUseCase
  }
}

extension CryptoDetailReactor {
  enum CryptoDetailAction {
    case connectTickerSocket
    case connectOrderBookSocket
  }
  
  enum CryptoDetailMutation {
    case setCryptoInfo(cryptoInfo: CryptoCellInfo?)
    case setOrderBookInfo(obTicker: Orderbook)
  }
  
  struct CryptoDetailState {
    var cryptoInfo: CryptoCellInfo? = nil
    var obTicker: Orderbook?
  }
}

extension CryptoDetailReactor {
  func mutate(action: CryptoDetailAction) -> Observable<CryptoDetailMutation> {
    switch action {
    case .connectTickerSocket:
      return self.connectTickerSocket(crypto: self.selectCrypto)
      
    case .connectOrderBookSocket:
      return self.connectOrderBookTicker(crypto: self.selectCrypto)
    }
  }
  
  func reduce(state: CryptoDetailState, mutation: CryptoDetailMutation) -> CryptoDetailState {
    var newState = state
    
    switch mutation {
    case .setCryptoInfo(let cryptoInfo):
      if let cryptoInfo = cryptoInfo {
        newState.cryptoInfo = cryptoInfo
      }
    case .setOrderBookInfo(let obTicker):
      print(obTicker)
      newState.obTicker = obTicker
    }
    
    return newState
  }
}

extension CryptoDetailReactor {
  // WebSocket Ticker
  private func connectTickerSocket(crypto: CryptoCellInfo) -> Observable<CryptoDetailMutation> {
    
    let socketObservable = Observable<CryptoDetailMutation>.create { observer in
      WebSocketManager.shared
        .connect(
          codes: [self.transformMarketForm(market: crypto.market)],
          socketType: .ticker
        )
      WebSocketManager.shared.observeReceivedData()
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
        WebSocketManager.shared.disconnect(socketType: .ticker)
      }
    }
    
    return socketObservable
  }
  
  // 호가창 WebSocket 통신
  private func connectOrderBookTicker(crypto: CryptoCellInfo) -> Observable<CryptoDetailMutation> {
    let socketObservable = Observable<CryptoDetailMutation>.create { observer in
      WebSocketManager.shared
        .connectOrderBook(
          codes: [self.transformMarketForm(market: self.selectCrypto.market)],
          socketType: .orderbook
        )
      WebSocketManager.shared.observeReceivedData()
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
        WebSocketManager.shared.disconnect(socketType: .orderbook)
      }
    }
    
    return socketObservable
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
