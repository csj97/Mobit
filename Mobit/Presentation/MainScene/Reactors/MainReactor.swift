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
  }
  
  /// 상태 변경 단위, 작업 단위
  enum MainMutation {
    case loadCrypto(list: [CryptoMarket])
  }
  
  struct MainReactorState {
    // krw, btc, usdt
    var cryptoList: CryptoList = []
  }
  
  let initialState: MainReactorState = MainReactorState()
  private let mainUseCase: MainUseCase
  
  init(mainUseCase: MainUseCase) {
    self.mainUseCase = mainUseCase
  }
  
}

extension MainReactor {
  // Observable 방출
  func mutate(action: MainAction) -> Observable<MainMutation> {
    switch action {
    case .loadCrypto:
//      return Observable.concat([
//        self.mainUseCase.loadCryptoList()
//          .map { cryptoList in
//            MainMutation.loadCrypto(list: cryptoList)
//          }
//      ])
      return self.mainUseCase.loadCryptoList()
        .map { cryptoList in
          return MainMutation.loadCrypto(list: cryptoList)
        }
            
//      return Observable.concat([self.mainUseCase.loadCryptoList()
//        .map { MainMutation.loadCrypto(list: $0) }]) 
    }
  }
  
  // View 업데이트
  func reduce(state: MainReactorState, mutation: MainMutation) -> MainReactorState {
    var newState = state
    switch mutation {
    case .loadCrypto(let cryptoList):
      newState.cryptoList = cryptoList
    }
    return newState
  }
}
