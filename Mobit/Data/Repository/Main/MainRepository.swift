//
//  MainRepository.swift
//  Mobit
//
//  Created by openobject on 2024/07/18.
//

import Foundation
import Moya
import RxMoya
import RxSwift

protocol MainRepositoryProtocol {
  func fetchCoinList() -> Observable<CryptoList>
  func loadTicker(markets: [String]) -> Observable<CryptoTickerList>
}

class MainRepository: MainRepositoryProtocol {
  let provider = MoyaProvider<MainNetworkService>()
  private var disposeBag = DisposeBag()
  
  func fetchCoinList() -> Observable<CryptoList> {
    let decodeTarget = CryptoListDTO.self
    
    return Observable.create { observer in
      let disposable = self.provider.rx.request(.getCryptoList)
        .subscribe { event in
          switch event {
          case .success(let response):
            switch response.statusCode {
            case 200..<300:
              guard let cryptoListDTO = try? JSONDecoder().decode(decodeTarget, from: response.data) else {
                observer.onError(ErrorType.dataMappingError)
                return
              }
              observer.onNext(cryptoListDTO.toDomain())
              observer.onCompleted()
            case 400..<500:
              observer.onError(ErrorType.badRequest)
            default:
              observer.onError(ErrorType.unknownError)
            }
          case .failure(let error):
            print(error.localizedDescription)
          }
        }
      return Disposables.create {
        disposable.disposed(by: self.disposeBag)
      }
    }
  }
  
    // ticker 리스트 조회
  func loadTicker(markets: [String]) -> Observable<CryptoTickerList> {
    let decodeTarget = CryptoTickerListDTO.self

    return Observable.create { observer in
      let disposable = self.provider.rx.request(.getTicker(markets: markets))
        .subscribe { event in
          switch event {
          case .success(let response):
            switch response.statusCode {
            case 200..<300:
			  
			  do {
				if let jsonString = String(data: response.data, encoding: .utf8) {
					// print("📦 JSON 응답 문자열:\n\(jsonString)")
				}
				let cryptoTickerList = try JSONDecoder().decode(decodeTarget, from: response.data)
				observer.onNext(cryptoTickerList.toDomain())
				observer.onCompleted()
			  } catch {
				print("❌ 디코딩 실패: \(error)")
				observer.onError(ErrorType.dataMappingError)
			  }
			  
            case 400..<500:
              observer.onError(ErrorType.badRequest)
            default:
              observer.onError(ErrorType.unknownError)

            }
            
          case .failure(let error):
            print(error.localizedDescription)
			observer.onError(error)
          }
        }
      
      return Disposables.create {
        disposable.dispose()
      }
    }
  }
}
