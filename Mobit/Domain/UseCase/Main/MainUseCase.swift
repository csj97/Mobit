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
  // 첫 메인 화면에서 인트로 중 시작한 요청을 한 번만 이어받는다.
  private var launchMarketList: Observable<CryptoList>?
  private let mainRepository: MainRepository
  
  init(mainRepository: MainRepository) {
    self.mainRepository = mainRepository
  }
  
  func prefetchLaunchMarketList() {
    guard launchMarketList == nil else { return }
    // 메인 화면이 늦게 구독해도 완료된 목록 또는 오류를 전달한다.
    let result = AsyncSubject<CryptoList>()
    // 화면의 타임아웃·이탈도 인트로에서 시작한 원래 HTTP 요청을 취소한다.
    let connection = mainRepository.fetchCryptoList().subscribe(result)
    launchMarketList = result.do(onDispose: connection.dispose)
    connection.disposed(by: disposeBag)
  }

  // 첫 요청 이후 재시도와 새로고침은 거래소에서 다시 읽는다.
  func fetchCryptoList() -> Observable<CryptoList> {
    if let result = launchMarketList {
      launchMarketList = nil
      return result
    }
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
