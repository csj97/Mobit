//
//  InvestReactor.swift
//  Mobit
//
//  Created by 조성재 on 4/8/25.
//

import Foundation
import UIKit
import ReactorKit
import RxSwift

class InvestReactor: Reactor {
  // ReactorKit 외부에서 mutation을 주입하려면 이게 필요
  private let mutationSubject = PublishSubject<InvestMutation>()
  private let disposeBag = DisposeBag()
  let initialState: InvestReactorState = InvestReactorState()
  
  init() {
	UserDataManager.userCryptoListObservable
		.map { InvestMutation.setUserCrypto($0) }
		.bind(to: mutationSubject)
		.disposed(by: disposeBag)
  }
  
}

// 기본 설정
extension InvestReactor {
  enum InvestAction {
	case loadTransactions
  }
  
  /// 상태 변경 단위, 작업 단위
  enum InvestMutation {
	case setUserCrypto([CryptoTransactionDataModel]?)
  }
  
  struct InvestReactorState {
	var cryptos: [CryptoTransactionDataModel]? = []
  }
}

extension InvestReactor {
  func transform(mutation: Observable<InvestMutation>) -> Observable<InvestMutation> {
	return Observable.merge(
	  mutation,                      // 원래 액션 기반의 내부 스트림
	  mutationSubject.asObservable() // 외부 이벤트 기반의 스트림
	)
  }
  
  // Observable 방출
  func mutate(action: InvestAction) -> Observable<InvestMutation> {
	switch action {
	case .loadTransactions:
	  return .just(.setUserCrypto(UserDataManager.userCryptoList))
	}
  }
  
  // View 업데이트
  func reduce(state: InvestReactorState, mutation: InvestMutation) -> InvestReactorState {
	var newState = state
	switch mutation {
	case .setUserCrypto(let crypto):
	  newState.cryptos = crypto
	}
	return newState
  }
}
