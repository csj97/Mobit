//
//  CryptoDetailUseCase.swift
//  Mobit
//
//  Created by 조성재 on 8/19/24.
//

import Foundation
import RxSwift

protocol CryptoDetailUseCaseProtocol {
  func getCryptoInformation(market: String) -> Observable<CryptoQuoteResponse>
}

class CryptoDetailUseCase: CryptoDetailUseCaseProtocol {
  let cryptoList = PublishSubject<Crypto>()
  private var disposeBag: DisposeBag = DisposeBag()
  private let cryptoDetailRepository: CryptoDetailRepository
  
  init(cryptoDetailRepository: CryptoDetailRepository) {
    self.cryptoDetailRepository = cryptoDetailRepository
  }
  
  func getCryptoInformation(market: String) -> Observable<CryptoQuoteResponse> {
	self.cryptoDetailRepository.getCryptoInformation(market: market)
  }
}
