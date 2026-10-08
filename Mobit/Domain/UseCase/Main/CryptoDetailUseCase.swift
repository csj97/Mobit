//
//  CryptoDetailUseCase.swift
//  Mobit
//
//  Created by 조성재 on 8/19/24.
//

import Foundation
import RxSwift

protocol CryptoDetailUseCaseProtocol {
  // 종목의 시세·시가총액 정보를 조회한다.
  func fetchCryptoInformation(market: String) -> Observable<CryptoQuoteResponse>
}

class CryptoDetailUseCase: CryptoDetailUseCaseProtocol {
  let cryptoList = PublishSubject<Crypto>()
  private var disposeBag: DisposeBag = DisposeBag()
  private let cryptoDetailRepository: CryptoDetailRepository
  
  init(cryptoDetailRepository: CryptoDetailRepository) {
    self.cryptoDetailRepository = cryptoDetailRepository
  }
  
  /// 종목의 시세·시가총액 정보를 조회한다.
  func fetchCryptoInformation(market: String) -> Observable<CryptoQuoteResponse> {
	self.cryptoDetailRepository.fetchCryptoInformation(market: market)
  }
  
  /// 지정한 종목의 분봉 데이터를 조회한다.
  func fetchCandleMinutes(market: String, unit: Int32, to: String?, count: Int?) -> Observable<[MinuteResponseModel]> {
	self.cryptoDetailRepository.fetchCandleListMinutes(market: market, unit: unit, to: to, count: count)
  }
  
  /// 지정한 종목의 일봉 데이터를 조회한다.
  func fetchCandleDays(market: String, to: String?, count: Int?, convertingPriceUnit: String?) -> Observable<[DayResponseModel]> {
	self.cryptoDetailRepository.fetchCandleListDays(
	  market: market,
	  to: to,
	  count: count,
	  convertingPriceUnit: convertingPriceUnit
	)
  }
}
