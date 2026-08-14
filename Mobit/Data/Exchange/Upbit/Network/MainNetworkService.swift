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
  case getCryptoTicker(markets: [String])
  case getCryptoInformation(market: String, currency: String = "KRW")
  case getFearAndGreedIndex
}

extension MainNetworkService: TargetType {
  var baseURL: URL {
    switch self {
    case .getCryptoList:
      return URL(string: "https://api.upbit.com/v1/market/all")!
    case .getCryptoTicker:
      return URL(string: "https://api.upbit.com/v1/ticker")!
    case .getCryptoInformation:
      return URL(string: "https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest")!
    case .getFearAndGreedIndex:
      return URL(string: "https://pro-api.coinmarketcap.com/v3/fear-and-greed/latest")!
    }
  }

  var path: String {
    switch self {
    case .getCryptoList:
      return ""
    case .getCryptoTicker:
      return ""
    case .getCryptoInformation:
      return ""
    case .getFearAndGreedIndex:
      return ""
    }
  }

  var method: Moya.Method {
    switch self {
    case .getCryptoList:
      return .get
    case .getCryptoTicker:
      return .get
    case .getCryptoInformation:
      return .get
    case .getFearAndGreedIndex:
      return .get
    }
  }

  var task: Moya.Task {
    switch self {
    case .getCryptoList:
      let param = ["isDetails": true]
      return .requestParameters(parameters: param, encoding: URLEncoding.queryString)
    case .getCryptoTicker(let markets):
      // URL 길이 제한을 초과하면 400 Error가 발생할 수 있다.
      let markets = markets.joined(separator: ",")
      let param = ["markets": markets]
      return .requestParameters(parameters: param, encoding: URLEncoding.queryString)
    case .getCryptoInformation(let market, let currency):
      let param = ["symbol": market, "convert": currency]
      return .requestParameters(parameters: param, encoding: URLEncoding.queryString)
    case .getFearAndGreedIndex:
      return .requestPlain
    }
  }

  var headers: [String : String]? {
    switch self {
    case .getCryptoInformation, .getFearAndGreedIndex:
      guard let apiKey = Environment.coinMarketCapApiKey else { return nil }
      return ["X-CMC_PRO_API_KEY": apiKey]
    default:
      return ["Accept":"application/json",
              "Content-type":"application/json"]
    }
  }
}
