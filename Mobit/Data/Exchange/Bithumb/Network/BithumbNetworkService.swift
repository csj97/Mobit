//
//  BithumbNetworkService.swift
//  Mobit
//
//  Created by 조성재 on 7/9/26.
//

import Foundation
import Moya

enum BithumbMainNetworkService {
  // 빗썸의 거래 가능한 마켓 목록 요청을 정의한다.
  case fetchCryptoList
  // 지정한 빗썸 마켓들의 현재 시세 요청을 정의한다.
  case fetchCryptoTicker(markets: [String])
  // CoinMarketCap의 종목 시세·시가총액 요청을 정의한다.
  case fetchCryptoInformation(market: String, currency: String = "KRW")
  // CoinMarketCap의 시장 공포·탐욕 지수 요청을 정의한다.
  case fetchFearAndGreedIndex
}


extension BithumbMainNetworkService: TargetType {
  var baseURL: URL {
    switch self {
    case .fetchCryptoList:
      return URL(string: "https://api.bithumb.com/v1/market/all")!
    case .fetchCryptoTicker:
      return URL(string: "https://api.bithumb.com/v1/ticker")!
    case .fetchCryptoInformation:
      return URL(string: "https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest")!
    case .fetchFearAndGreedIndex:
      return URL(string: "https://pro-api.coinmarketcap.com/v3/fear-and-greed/latest")!
    }
  }

  var path: String {
    ""
  }

  var method: Moya.Method {
    .get
  }

  var task: Moya.Task {
    switch self {
    case .fetchCryptoList:
      return .requestParameters(
        parameters: ["isDetails": true],
        encoding: URLEncoding.queryString
      )

    case .fetchCryptoTicker(let markets):
      return .requestParameters(
        parameters: ["markets": markets.joined(separator: ",")],
        encoding: URLEncoding.queryString
      )

    case .fetchCryptoInformation(let market, let currency):
      return .requestParameters(
        parameters: ["symbol": market, "convert": currency],
        encoding: URLEncoding.queryString
      )

    case .fetchFearAndGreedIndex:
      return .requestPlain
    }
  }

  var headers: [String: String]? {
    switch self {
    case .fetchCryptoInformation, .fetchFearAndGreedIndex:
      guard let apiKey = Environment.coinMarketCapApiKey else { return nil }
      return ["X-CMC_PRO_API_KEY": apiKey]
    default:
      return [
        "Accept": "application/json",
        "Content-type": "application/json"
      ]
    }
  }
}

enum BithumbTradeNetworkService {
  // 종목·봉 간격·조회 범위를 지정한 빗썸 분봉 요청을 정의한다.
  case fetchCandleListMinutes(market: String, unit: Int32, to: String?, count: Int?)
  // 종목과 조회 범위를 지정한 빗썸 일봉 요청을 정의한다.
  case fetchCandleListDays(market: String, to: String?, count: Int?, convertingPriceUnit: String?)
}

extension BithumbTradeNetworkService: TargetType {
  var baseURL: URL {
    URL(string: "https://api.bithumb.com/v1/candles")!
  }

  var path: String {
    switch self {
    case .fetchCandleListMinutes(_, let unit, _, _):
      return "/minutes/\(unit)"
    case .fetchCandleListDays:
      return "/days"
    }
  }

  var method: Moya.Method {
    .get
  }

  var task: Moya.Task {
    switch self {
    case .fetchCandleListMinutes(let market, _, let to, let count):
      var parameters: [String: Any] = ["market": market]
      if let to {
        parameters["to"] = Self.candleToParameter(from: to)
      }
      if let count {
        parameters["count"] = count
      }
      return .requestParameters(parameters: parameters, encoding: URLEncoding.queryString)

    case .fetchCandleListDays(let market, let to, let count, let convertingPriceUnit):
      var parameters: [String: Any] = ["market": market]
      if let to {
        parameters["to"] = Self.candleToParameter(from: to)
      }
      if let count {
        parameters["count"] = count
      }
      if let convertingPriceUnit {
        parameters["convertingPriceUnit"] = convertingPriceUnit
      }
      return .requestParameters(parameters: parameters, encoding: URLEncoding.queryString)
    }
  }

  var headers: [String: String]? {
    [
      "Accept": "application/json",
      "Content-type": "application/json"
    ]
  }

  // 빗썸 캔들 API는 타임존 suffix(Z/offset)와 소수초를 거부하고, tz 없는 시각을 KST로 해석한다.
  // 앱은 to를 UTC ISO8601로 넘기므로, 같은 순간의 KST 벽시계(yyyy-MM-dd'T'HH:mm:ss)로 변환해 전달한다.
  // (Z만 떼면 UTC 값이 KST로 오해돼 9시간 과거 캔들이 조회된다.)
  private static func candleToParameter(from to: String) -> String {
    let isoWithFraction = ISO8601DateFormatter()
    isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let isoPlain = ISO8601DateFormatter()
    isoPlain.formatOptions = [.withInternetDateTime]
    guard let date = isoWithFraction.date(from: to) ?? isoPlain.date(from: to) else {
      return to
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter.string(from: date)
  }
}

