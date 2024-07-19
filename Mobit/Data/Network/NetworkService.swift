//
//  NetworkService.swift
//  Mobit
//
//  Created by openobject on 2024/07/18.
//

import Foundation
import Moya
import RxSwift

enum NetworkService {
  case getCoinList
}

extension NetworkService: TargetType {
  var baseURL: URL {
    switch self {
    case .getCoinList:
      return URL(string: "https://api.upbit.com/v1/market/all")!
    }
  }
  
  var path: String {
    switch self {
    case .getCoinList:
      return ""
    }
  }
  
  var method: Moya.Method {
    return .get
  }
  
  var task: Moya.Task {
    switch self {
    case .getCoinList:
      let param = ["isDetails": true]
      return .requestParameters(parameters: ["isDetails": true], encoding: URLEncoding.queryString)
    }
  }
  
  var headers: [String : String]? {
    return ["Accept":"application/json",
            "Content-type":"application/json"]
  }
  
  
}
