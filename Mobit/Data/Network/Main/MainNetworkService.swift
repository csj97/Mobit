//
//  MainNetworkService.swift
//  Mobit
//
//  Created by openobject on 2024/07/18.
//

import Foundation
import Moya
import RxSwift

enum MainNetworkService {
  case getCryptoList
  case getTicker(markets: [String])
}

extension MainNetworkService: TargetType {
  var baseURL: URL {
    switch self {
    case .getCryptoList:
      return URL(string: "https://api.upbit.com/v1/market/all")!
    case .getTicker:
      return URL(string: "https://api.upbit.com/v1/ticker")!
    }
  }
  
  var path: String {
    switch self {
    case .getCryptoList:
      return ""
    case .getTicker:
      return ""
    }
  }
  
  var method: Moya.Method {
    switch self {
    case .getCryptoList:
      return .get
    case .getTicker:
      return .get
    }
  }
  
  var task: Moya.Task {
    switch self {
    case .getCryptoList:
      let param = ["isDetails": true]
      return .requestParameters(parameters: param, encoding: URLEncoding.queryString)
    case .getTicker(let markets):
      // URL 길이 제한을 초과하면 400 Error가 발생할 수 있다.
      let markets = markets.joined(separator: ",")
      let param = ["markets": markets]
      return .requestParameters(parameters: param, encoding: URLEncoding.queryString)
    }
  }
  
  var headers: [String : String]? {
    return ["Accept":"application/json",
            "Content-type":"application/json"]
  }
  
  
}
