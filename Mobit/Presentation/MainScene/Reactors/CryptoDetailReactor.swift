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
    case connectTickerSocket(cryptoCellInfo: CryptoCellInfo)
    case connectOrderBookSocket
  }
  
  enum CryptoDetailMutation {
    case setCryptoInfo(cryptoInfo: CryptoCellInfo?)
  }
  
  struct CryptoDetailState {
    var cryptoInfo: CryptoCellInfo? = nil
  }
}

extension CryptoDetailReactor {
  func mutate(action: CryptoDetailAction) -> Observable<CryptoDetailMutation> {
    switch action {
    case .connectTickerSocket(let cryptoCellInfo):
      return self.loadSocketTicker(crypto: cryptoCellInfo)
      
    case .connectOrderBookSocket:
      return Observable.concat([])
    }
  }
  
  func reduce(state: CryptoDetailState, mutation: CryptoDetailMutation) -> CryptoDetailState {
    var newState = state
    
    switch mutation {
    case .setCryptoInfo(let cryptoInfo):
      if let cryptoInfo = cryptoInfo {
        newState.cryptoInfo = cryptoInfo
      }
    }
    
    return newState
  }
}

extension CryptoDetailReactor {
  // WebSocket Ticker
  private func loadSocketTicker(crypto: CryptoCellInfo) -> Observable<CryptoDetailMutation> {
    
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
            print("websocket receive decoding error : \(error.localizedDescription)")
          }
        } onError: { error in
          observer.onError(error)
        } onCompleted: {
          observer.onCompleted()
        }.disposed(by: self.disposeBag)
      
      return Disposables.create {
        WebSocketManager.shared.disconnect()
      }
    }
    
    return socketObservable
  }
}

extension CryptoDetailReactor {
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
