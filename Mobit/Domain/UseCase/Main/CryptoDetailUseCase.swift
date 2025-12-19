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
  
  /// crypto 정보 가져오기
  func getCryptoInformation(market: String) -> Observable<CryptoQuoteResponse> {
	self.cryptoDetailRepository.getCryptoInformation(market: market)
  }
  
  /// crypto candle 분봉 데이터 가져오기
  func getCandleMinutes(market: String, unit: Int32, to: String?, count: Int?) -> Observable<[MinuteResponseModel]> {
	self.cryptoDetailRepository.getCandleListMinutes(market: market, unit: unit, to: to, count: count)
  }
  
  /// crypto candle 일봉 데이터 가져오기
  func getCandleDays(market: String, to: String?, count: Int?, convertingPriceUnit: String?) -> Observable<[DayResponseModel]> {
	self.cryptoDetailRepository.getCandleListDays(
	  market: market,
	  to: to,
	  count: count,
	  convertingPriceUnit: convertingPriceUnit
	)
  }
}
