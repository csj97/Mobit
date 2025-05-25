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
  case getCryptoInfo(market: String)
}

extension MainNetworkService: TargetType {
  var baseURL: URL {
    switch self {
    case .getCryptoList:
      return URL(string: "https://api.upbit.com/v1/market/all")!
    case .getTicker:
      return URL(string: "https://api.upbit.com/v1/ticker")!
	case .getCryptoInfo:
	 return URL(string: "https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest")!
    }
  }
  
  var path: String {
    switch self {
    case .getCryptoList:
      return ""
    case .getTicker:
      return ""
	case .getCryptoInfo:
	  return ""
    }
  }
  
  var method: Moya.Method {
    switch self {
    case .getCryptoList:
      return .get
    case .getTicker:
      return .get
	case .getCryptoInfo:
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
    case .getCryptoInfo(let market):
	 let param = ["symbol": market]
	 return .requestParameters(parameters: param, encoding: URLEncoding.queryString)
    }
  }
  
  var headers: [String : String]? {
    switch self {
    case .getCryptoInfo:
	 return ["X-CMC_PRO_API_KEY": "101fdf9b-56b2-4600-ae1c-1a7947b55dfd"]
    default:
	 return ["Accept":"application/json",
		    "Content-type":"application/json"]
    }
  }
  
  
}
