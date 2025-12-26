//
//  CryptoDetailRepository.swift
//  Mobit
//
//  Created by 조성재 on 8/19/24.
//

import Foundation
import Moya
import RxMoya
import RxSwift

protocol CryptoDetailRepositoryProtocol {
  func getCryptoInformation(market: String) -> Observable<CryptoQuoteResponse>
}

class CryptoDetailRepository: CryptoDetailRepositoryProtocol {
  let mainProvider = MoyaProvider<MainNetworkService>()
  let tradeProvider = MoyaProvider<TradeNetworkService>()
  private var disposeBag = DisposeBag()
  
  func getCryptoInformation(market: String) -> Observable<CryptoQuoteResponse> {
	let decodeTarget = CryptoQuoteResponseDTO.self
	
	return Observable.create { observer in
	  let disposable = self.mainProvider.rx.request(.getCryptoInformation(market: market))
		.subscribe { event in
		  switch event {
		  case .success(let response):
			switch response.statusCode {
			case 200..<300:
			  guard let cryptoQuotesResponseDTO = try? JSONDecoder().decode(
				decodeTarget,
				from: response.data
			  ) else {
				observer.onError(ErrorType.dataMappingError)
				return
			  }
			  observer.onNext(cryptoQuotesResponseDTO.toDomain(symbol: market))
			  observer.onCompleted()
			case 400..<500:
			  observer.onError(ErrorType.badRequest)
			default:
			  observer.onError(ErrorType.unknownError)
			}
		  case .failure(let error):
			Log.error(error.localizedDescription)
		  }
		}
	  return Disposables.create {
		disposable.disposed(by: self.disposeBag)
	  }
	}
  }
  
  /// market: KRW-BTC
  /// to : 조회 기간의 종료 시작 (ex. 2025-06-24T13:56:53+09:00)
  /// count : 조회할 캔들의 개수
  func getCandleListMinutes(market: String, unit: Int32, to: String?, count: Int?) -> Observable<[MinuteResponseModel]> {
	let decodeTarget = [MinuteResponseModelDTO].self
	
	return Observable.create { observer in
	  let disposable = self.tradeProvider.rx.request(
		.getCandleListMinutes(
		  market: market,
		  unit: unit,
		  to: to,
		  count: count
		)
	  ).subscribe { event in
		switch event {
		case .success(let response):
		  switch response.statusCode {
		  case 200..<300:
			guard let candleMinuteResponseDTO = try? JSONDecoder().decode(
			  decodeTarget,
			  from: response.data
			) else {
			  observer.onError(ErrorType.dataMappingError)
			  return
			}
			observer.onNext(candleMinuteResponseDTO.toDomainList())
			observer.onCompleted()
		  case 400..<500:
			observer.onError(ErrorType.badRequest)
		  default:
			observer.onError(ErrorType.unknownError)
		  }
		case .failure(let error):
		  Log.error(error.localizedDescription)
		}
	  }
	  return Disposables.create {
		disposable.disposed(by: self.disposeBag)
	  }
	}
  }
  
  func getCandleListDays(
  market: String,
  to: String?,
  count: Int?,
  convertingPriceUnit: String?
  ) -> Observable<[DayResponseModel]> {
	let decodeTarget = [DayResponseModelDTO].self
	
	return Observable.create { observer in
	  let disposable = self.tradeProvider.rx.request(
		.getCandleListDays(
		  market: market,
		  to: to,
		  count: count,
		  convertingPriceUnit: convertingPriceUnit
		)
	  ).subscribe { event in
		switch event {
		case .success(let response):
		  switch response.statusCode {
		  case 200..<300:
			guard let candleDayResponseDTO = try? JSONDecoder().decode(
			  decodeTarget,
			  from: response.data
			) else {
			  observer.onError(ErrorType.dataMappingError)
			  return
			}
			observer.onNext(candleDayResponseDTO.toDomainList())
			observer.onCompleted()
		  case 400..<500:
			observer.onError(ErrorType.badRequest)
		  default:
			observer.onError(ErrorType.unknownError)
		  }
		case .failure(let error):
		  Log.error(error.localizedDescription)
		}
	  }
	  return Disposables.create {
		disposable.disposed(by: self.disposeBag)
	  }
	}
  }
}
