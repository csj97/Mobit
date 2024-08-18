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
  let selectCrypto: String
  private let cryptoDetailUseCase: CryptoDetailUseCase
  private let disposeBag = DisposeBag()
  
  let initialState: CryptoDetailState = CryptoDetailState()
  
  init(selectCrypto: String, cryptoDetailUseCase: CryptoDetailUseCase) {
    self.selectCrypto = selectCrypto
    self.cryptoDetailUseCase = cryptoDetailUseCase
  }
}

extension CryptoDetailReactor {
  enum CryptoDetailAction {
    
  }
  
  enum CryptoDetailMutation {
    
  }
  
  struct CryptoDetailState {
    
  }
}

extension CryptoDetailReactor {
  func mutate(action: CryptoDetailAction) -> Observable<CryptoDetailMutation> {
    switch action {
      
    default:
      break
    }
  }
  
  func reduce(state: CryptoDetailState, mutation: CryptoDetailMutation) -> CryptoDetailState {
    var newState = state
    
    switch mutation {
    
    default:
      break
    }
    
    return newState
  }
}
