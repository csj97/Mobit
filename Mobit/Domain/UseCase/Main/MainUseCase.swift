//
//  HomeUseCase.swift
//  Mobit
//
//  Created by 조성재 on 7/11/24.
//

import Foundation
import RxSwift

// Observing할 함수나 프로퍼티 정의
protocol MainUseCaseProtocol {
  // 거래소에서 거래 가능한 마켓 목록을 조회한다.
  func fetchCryptoList() -> Observable<CryptoList>
  // 지정한 마켓들의 현재 시세를 조회한다.
  func fetchCryptoTicker(markets: [String]) -> Observable<CryptoTickerList>
  // CoinMarketCap에서 시장 공포·탐욕 지수를 조회한다.
  func fetchFearGreedIndex() -> Observable<FearGreedIndex>
}

class MainUseCase: MainUseCaseProtocol {
  let cryptoList = PublishSubject<Crypto>()
  private var disposeBag: DisposeBag = DisposeBag()
  private let mainRepository: MainRepository
  
  init(mainRepository: MainRepository) {
    self.mainRepository = mainRepository
  }
  
  // 거래소에서 거래 가능한 마켓 목록을 조회한다.
  func fetchCryptoList() -> Observable<CryptoList> {
	return self.mainRepository.fetchCryptoList()
  }
  // 지정한 마켓들의 현재 시세를 조회한다.
  func fetchCryptoTicker(markets: [String]) -> Observable<CryptoTickerList> {
    return self.mainRepository.fetchCryptoTicker(markets: markets)
  }
  // CoinMarketCap에서 시장 공포·탐욕 지수를 조회한다.
  func fetchFearGreedIndex() -> Observable<FearGreedIndex> {
    return self.mainRepository.fetchFearGreedIndex()
  }
}
