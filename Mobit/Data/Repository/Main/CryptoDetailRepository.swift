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
  let provider = MoyaProvider<MainNetworkService>()
  private var disposeBag = DisposeBag()
  
  func getCryptoInformation(market: String) -> Observable<CryptoQuoteResponse> {
	let decodeTarget = CryptoQuoteResponseDTO.self
	
	return Observable.create { observer in
	  let disposable = self.provider.rx.request(.getCryptoInformation(market: market))
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
}
