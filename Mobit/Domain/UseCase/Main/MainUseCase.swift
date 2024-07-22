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
  func loadCryptoList() -> Observable<CryptoList>
}

class MainUseCase: MainUseCaseProtocol {
  let cryptoList = PublishSubject<CryptoMarket>()
  private var disposeBag: DisposeBag = DisposeBag()
  private let mainRepository: MainRepository
  
  init(mainRepository: MainRepository) {
    self.mainRepository = mainRepository
  }
  
  func loadCryptoList() -> Observable<CryptoList> {
    return self.mainRepository.fetchCoinList()
  }
}
