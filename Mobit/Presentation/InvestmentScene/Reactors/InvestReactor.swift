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
  private let mainUseCase: MainUseCase
  let initialState: InvestReactorState = InvestReactorState()

  init(mainUseCase: MainUseCase) {
	self.mainUseCase = mainUseCase
	UserDataManager.userCryptoListObservable
      .observe(on: MainScheduler.asyncInstance)
	  .map { InvestMutation.setUserCrypto($0) }
	  .bind(to: mutationSubject)
	  .disposed(by: disposeBag)
	
	UserDataManager.userAvailableBalanceObservable
      .observe(on: MainScheduler.asyncInstance)
	  .map { InvestMutation.setUserAvailableBalance($0 ?? 0) }
	  .bind(to: mutationSubject)
	  .disposed(by: disposeBag)
  }
  
}

// 기본 설정
extension InvestReactor {
  enum InvestAction {
	case loadTransactions
//	case updateUserAvailableBalance
	case prepareDetailCrypto(marketName: String, cryptoName: String)
  }

  /// 상태 변경 단위, 작업 단위
  enum InvestMutation {
	case setUserCrypto([CryptoTransactionDataModel]?)
	case setUserAvailableBalance(Double)
	case setDetailCrypto(CryptoCellInfo?)
  }

  struct InvestReactorState {
	var cryptos: [CryptoTransactionDataModel] = []
	var userAvailableBalance: Double = UserDataManager.userInformation?.userAvailableBalance ?? 0
	var detailCrypto: CryptoCellInfo?
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

	case let .prepareDetailCrypto(marketName, cryptoName):
	  // 보유코인 상세 진입: 티커를 조회해 정보 탭에 필요한 필드까지 채운다.
	  // 실패해도 이동은 하되(정보 탭만 비활성) 기존 동작을 유지한다.
	  let apiMarket = MarketFormat.apiMarket(fromDisplayMarket: marketName)
	  let fallback = CryptoCellInfo(cryptoName: cryptoName, market: marketName)
	  return self.mainUseCase.loadCryptoTicker(markets: [apiMarket])
		.map { tickers -> InvestMutation in
		  guard let ticker = tickers.first else { return .setDetailCrypto(fallback) }
		  var info = fallback
		  info.prevPrice = ticker.prevClosingPrice
		  info.tradePrice = ticker.tradePrice
		  info.accTradePrice24h = ticker.accTradePrice24h
		  info.accTradeVolume24h = ticker.accTradeVolume24h
		  info.highest52WeekPrice = ticker.highest52WeekPrice
		  info.lowest52WeekPrice = ticker.lowest52WeekPrice
		  return .setDetailCrypto(info)
		}
		.catch { _ in .just(.setDetailCrypto(fallback)) }
	}
  }
  
  // View 업데이트
  func reduce(state: InvestReactorState, mutation: InvestMutation) -> InvestReactorState {
	var newState = state
	switch mutation {
	case .setUserCrypto(let cryptos):
	  newState.cryptos = cryptos ?? []
	case .setUserAvailableBalance(let userAvailableBalance):
	  newState.userAvailableBalance = userAvailableBalance
	case .setDetailCrypto(let detailCrypto):
	  newState.detailCrypto = detailCrypto
	}
	return newState
  }
}
