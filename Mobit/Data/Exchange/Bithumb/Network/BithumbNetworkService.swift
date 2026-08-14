//
//  BithumbNetworkService.swift
//  Mobit
//
//  Created by Codex on 7/9/26.
//

import Foundation
import Moya

enum BithumbMainNetworkService {
  case getCryptoList
  case getCryptoTicker(markets: [String])
  case getCryptoInformation(market: String, currency: String = "KRW")
  case getFearAndGreedIndex
}


extension BithumbMainNetworkService: TargetType {
  var baseURL: URL {
    switch self {
    case .getCryptoList:
      return URL(string: "https://api.bithumb.com/v1/market/all")!
    case .getCryptoTicker:
      return URL(string: "https://api.bithumb.com/v1/ticker")!
    case .getCryptoInformation:
      return URL(string: "https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest")!
    case .getFearAndGreedIndex:
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
    case .getCryptoList:
      return .requestParameters(
        parameters: ["isDetails": true],
        encoding: URLEncoding.queryString
      )

    case .getCryptoTicker(let markets):
      return .requestParameters(
        parameters: ["markets": markets.joined(separator: ",")],
        encoding: URLEncoding.queryString
      )

    case .getCryptoInformation(let market, let currency):
      return .requestParameters(
        parameters: ["symbol": market, "convert": currency],
        encoding: URLEncoding.queryString
      )

    case .getFearAndGreedIndex:
      return .requestPlain
    }
  }

  var headers: [String: String]? {
    switch self {
    case .getCryptoInformation, .getFearAndGreedIndex:
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
  case getCandleListMinutes(market: String, unit: Int32, to: String?, count: Int?)
  case getCandleListDays(market: String, to: String?, count: Int?, convertingPriceUnit: String?)
}

extension BithumbTradeNetworkService: TargetType {
  var baseURL: URL {
    URL(string: "https://api.bithumb.com/v1/candles")!
  }

  var path: String {
    switch self {
    case .getCandleListMinutes(_, let unit, _, _):
      return "/minutes/\(unit)"
    case .getCandleListDays:
      return "/days"
    }
  }

  var method: Moya.Method {
    .get
  }

  var task: Moya.Task {
    switch self {
    case .getCandleListMinutes(let market, _, let to, let count):
      var parameters: [String: Any] = ["market": market]
      if let to {
        parameters["to"] = Self.candleToParameter(from: to)
      }
      if let count {
        parameters["count"] = count
      }
      return .requestParameters(parameters: parameters, encoding: URLEncoding.queryString)

    case .getCandleListDays(let market, let to, let count, let convertingPriceUnit):
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

