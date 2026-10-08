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
  // 업비트의 거래 가능한 마켓 목록 요청을 정의한다.
  case fetchCryptoList
  // 지정한 업비트 마켓들의 현재 시세 요청을 정의한다.
  case fetchCryptoTicker(markets: [String])
  // CoinMarketCap의 종목 시세·시가총액 요청을 정의한다.
  case fetchCryptoInformation(market: String, currency: String = "KRW")
  // CoinMarketCap의 시장 공포·탐욕 지수 요청을 정의한다.
  case fetchFearAndGreedIndex
}

extension MainNetworkService: TargetType {
  var baseURL: URL {
    switch self {
    case .fetchCryptoList:
      return URL(string: "https://api.upbit.com/v1/market/all")!
    case .fetchCryptoTicker:
      return URL(string: "https://api.upbit.com/v1/ticker")!
    case .fetchCryptoInformation:
      return URL(string: "https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest")!
    case .fetchFearAndGreedIndex:
      return URL(string: "https://pro-api.coinmarketcap.com/v3/fear-and-greed/latest")!
    }
  }

  var path: String {
    switch self {
    case .fetchCryptoList:
      return ""
    case .fetchCryptoTicker:
      return ""
    case .fetchCryptoInformation:
      return ""
    case .fetchFearAndGreedIndex:
      return ""
    }
  }

  var method: Moya.Method {
    switch self {
    case .fetchCryptoList:
      return .get
    case .fetchCryptoTicker:
      return .get
    case .fetchCryptoInformation:
      return .get
    case .fetchFearAndGreedIndex:
      return .get
    }
  }

  var task: Moya.Task {
    switch self {
    case .fetchCryptoList:
      let param = ["isDetails": true]
      return .requestParameters(parameters: param, encoding: URLEncoding.queryString)
    case .fetchCryptoTicker(let markets):
      // URL 길이 제한을 초과하면 400 Error가 발생할 수 있다.
      let markets = markets.joined(separator: ",")
      let param = ["markets": markets]
      return .requestParameters(parameters: param, encoding: URLEncoding.queryString)
    case .fetchCryptoInformation(let market, let currency):
      let param = ["symbol": market, "convert": currency]
      return .requestParameters(parameters: param, encoding: URLEncoding.queryString)
    case .fetchFearAndGreedIndex:
      return .requestPlain
    }
  }

  var headers: [String : String]? {
    switch self {
    case .fetchCryptoInformation, .fetchFearAndGreedIndex:
      guard let apiKey = Environment.coinMarketCapApiKey else { return nil }
      return ["X-CMC_PRO_API_KEY": apiKey]
    default:
      return ["Accept":"application/json",
              "Content-type":"application/json"]
    }
  }
}
