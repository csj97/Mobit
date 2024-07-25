//
//  MainViewModel.swift
//  Mobit
//
//  Created by openobject on 2024/07/19.
//

import Foundation
import UIKit
import RxSwift
import ReactorKit
import RxRelay

class MainReactor: Reactor {
  private let mainUseCase: MainUseCase
  private let disposeBag = DisposeBag()
  let initialState: MainReactorState = MainReactorState()
  var currentPriceRelay = PublishRelay<CurrentPrice>() // 구독한 시점 이후부터 방출
  lazy var cryptoTickerObservable: Observable<CurrentPrice> = currentPriceRelay.asObservable()
  
  init(mainUseCase: MainUseCase) {
    self.mainUseCase = mainUseCase
    self.action.onNext(.loadCrypto)
  }
  
}

// 기본 설정
extension MainReactor {
  enum MainAction {
    case loadCrypto
    case classifyCrypto(list: CryptoList)
  }
  
  /// 상태 변경 단위, 작업 단위
  enum MainMutation {
    case loadCrypto(list: CryptoList)
    case addToKRWArray(crypto: CryptoList)
    case addToBTCArray(crypto: CryptoList)
    case setCryptoTricket(CurrentPrice)
  }
  
  struct MainReactorState {
    // krw, btc, usdt
    var cryptoList: CryptoList = []
    var krwCryptoList: CryptoList = []
    var btcCryptoList: CryptoList = []
    var favoriteCryptoList: CryptoList = []
    var cryptoTricker: CurrentPriceList = []
  }
}

extension MainReactor {
  // Observable 방출
  func mutate(action: MainAction) -> Observable<MainMutation> {
    switch action {
    case .loadCrypto:
      return self.mainUseCase.loadCryptoList()
        .flatMap({ cryptoList -> Observable<MainMutation> in
          return Observable.concat([
            self.classifyCrypto(cryptoList: cryptoList),
            self.ticker(cryptoList: cryptoList.filter { $0.market.contains("KRW-") })
              .map { cryptoTrickerList in
                  .setCryptoTricket(cryptoTrickerList)
              }
          ])
        })
    case .classifyCrypto(let cryptoList):
      return self.classifyCrypto(cryptoList: cryptoList)
    }
  }
  
  // View 업데이트
  func reduce(state: MainReactorState, mutation: MainMutation) -> MainReactorState {
    var newState = state
    switch mutation {
    case .loadCrypto(let cryptoList):
      newState.cryptoList = cryptoList
    case .addToKRWArray(let krwList):
      newState.krwCryptoList = krwList
    case .addToBTCArray(let btcList):
      newState.btcCryptoList = btcList
    case .setCryptoTricket(let cryptoTricker):
      newState.cryptoTricker = [cryptoTricker]
    }
    return newState
  }
  
  func classifyCrypto(cryptoList: CryptoList) -> Observable<MainMutation> {
    let krwCrypto = cryptoList.filter { $0.market.contains("KRW-") }
      .map { self.transformCrypto(crypto: $0) }
    
//    self.ticker(cryptoList: cryptoList.filter { $0.market.contains("KRW-") })
//      .observe(on: MainScheduler.instance)
//      .subscribe(onNext: { curPrice in
//        print(curPrice)
//      }).disposed(by: self.disposeBag)
    
    let btcCrypto = cryptoList.filter { $0.market.contains("BTC-") }
      .map { self.transformCrypto(crypto: $0) }
    
    let krwObservable = Observable<MainMutation>.create { observer in
      observer.onNext(.addToKRWArray(crypto: krwCrypto))
      observer.onCompleted()
      return Disposables.create()
    }
    
    let btcObservable = Observable<MainMutation>.create { observer in
      observer.onNext(.addToBTCArray(crypto: btcCrypto))
      observer.onCompleted()
      return Disposables.create()
    }
    
    // 2개의 이벤트를 순서대로 실행하기 위함
    return Observable.concat([krwObservable, btcObservable])
  }
  
  func transformCrypto(crypto: Crypto) -> Crypto {
    var transformedCrypto = crypto
    let components = crypto.market.split(separator: "-")
    if components.count == 2 {
      transformedCrypto.market = "\(components[1])/\(components[0])"
    } else {
      // 기본값 유지
      transformedCrypto.market = crypto.market
    }
    return transformedCrypto
  }
  
  private func ticker(cryptoList: CryptoList) -> Observable<CurrentPrice> {
    let cryptoJoined = cryptoList.map { $0.market }
    WebSocketManager.shared.connect(codes: cryptoJoined)
    WebSocketManager.shared.observeReceivedData()
      .observe(on: MainScheduler.instance)
      .subscribe { [weak self] data in
        let decodeTarget = CurrentPriceDTO.self
        
        do {
          let currentPriceDTO = try JSONDecoder().decode(decodeTarget, from: data)
          self?.currentPriceRelay.accept(currentPriceDTO.toDomain())
        } catch {
          print("websocket receive decoding error : \(error.localizedDescription)")
        }
      }.disposed(by: self.disposeBag)
    
    return self.cryptoTickerObservable
  }

}
