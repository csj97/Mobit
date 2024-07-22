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

class MainReactor: Reactor {
  enum MainAction {
    case loadCrypto
    case classifyCrypto(list: CryptoList)
  }
  
  /// 상태 변경 단위, 작업 단위
  enum MainMutation {
    case loadCrypto(list: CryptoList)
    case addToKRWArray(crypto: CryptoList)
    case addToBTCArray(crypto: CryptoList)
  }
  
  struct MainReactorState {
    // krw, btc, usdt
    var cryptoList: CryptoList = []
    var krwCryptoList: CryptoList = []
    var btcCryptoList: CryptoList = []
    var favoriteCryptoList: CryptoList = []
  }
  
  let initialState: MainReactorState = MainReactorState()
  private let mainUseCase: MainUseCase
  
  init(mainUseCase: MainUseCase) {
    self.mainUseCase = mainUseCase
    self.action.onNext(.loadCrypto)
  }
  
}

extension MainReactor {
  // Observable 방출
  func mutate(action: MainAction) -> Observable<MainMutation> {
    switch action {
    case .loadCrypto:
      return self.mainUseCase.loadCryptoList()
        .flatMap({ cryptoList -> Observable<MainMutation> in
          return self.classifyCrypto(cryptoList: cryptoList)
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
    }
    return newState
  }
  
  func classifyCrypto(cryptoList: CryptoList) -> Observable<MainMutation> {
    let krwCrypto = cryptoList.filter { $0.market.contains("KRW-") }
    let btcCrypto = cryptoList.filter { $0.market.contains("BTC-") }
    
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
  
}
