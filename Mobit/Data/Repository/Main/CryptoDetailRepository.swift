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
}

class CryptoDetailRepository: CryptoDetailRepositoryProtocol {
  let provider = MoyaProvider<MainNetworkService>()
  private var disposeBag = DisposeBag()
}
