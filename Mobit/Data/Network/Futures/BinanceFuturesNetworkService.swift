import Foundation
import Moya

enum BinanceFuturesNetworkService: TargetType {
  case mark(String)
  case exchangeInfo
  case serverTime
  case candles(String, Int64, Int64)
  case funding(String, Int64, Int64)

  var baseURL: URL { URL(string: "https://fapi.binance.com")! }
  var method: Moya.Method { .get }
  var headers: [String: String]? { ["Accept": "application/json"] }
  var path: String {
    switch self {
    case .mark: return "/fapi/v1/premiumIndex"
    case .exchangeInfo: return "/fapi/v1/exchangeInfo"
    case .serverTime: return "/fapi/v1/time"
    case .candles: return "/fapi/v1/markPriceKlines"
    case .funding: return "/fapi/v1/fundingRate"
    }
  }
  var task: Moya.Task {
    let parameters: [String: Any]
    switch self {
    case .mark(let symbol): parameters = ["symbol": symbol]
    case .exchangeInfo, .serverTime: return .requestPlain
    case .candles(let symbol, let start, let end):
      parameters = ["symbol": symbol, "interval": "1m", "startTime": start, "endTime": end - 1, "limit": 499]
    case .funding(let symbol, let start, let end):
      parameters = ["symbol": symbol, "startTime": start, "endTime": end - 1, "limit": 1000]
    }
    return .requestParameters(parameters: parameters, encoding: URLEncoding.queryString)
  }
}
