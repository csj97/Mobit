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
  func fetchCoinList() -> Observable<[CryptoMarket]>
}

class MainRepository: MainRepositoryProtocol {
  let provider = MoyaProvider<NetworkService>()
  private var disposeBag = DisposeBag()
  
  func fetchCoinList() -> Observable<CryptoList> {
    let decodeTarget = CryptoListDTO.self
    
    return Observable.create { observer in
      let disposable = self.provider.rx.request(.getCoinList)
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
}
