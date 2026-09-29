import Foundation
import Moya

struct DomesticFuturesNetworkService: TargetType {
  enum Query {
    case ticker
    case candles(seconds: Bool, to: Int64, count: Int)
    case trades(to: String?, daysAgo: Int?, cursor: String?)
  }

  let exchange: Exchange
  let market: String
  let query: Query

  var baseURL: URL {
    URL(string: exchange == .upbit ? "https://api.upbit.com" : "https://api.bithumb.com")!
  }
  var method: Moya.Method { .get }
  var headers: [String: String]? { ["Accept": "application/json"] }
  var path: String {
    switch query {
    case .ticker: return "/v1/ticker"
    case .candles(let seconds, _, _): return seconds ? "/v1/candles/seconds" : "/v1/candles/minutes/1"
    case .trades: return "/v1/trades/ticks"
    }
  }
  var task: Moya.Task {
    var values: [String: Any] = ["market": market]
    switch query {
    case .ticker: values = ["markets": market]
    case .candles(_, let to, let count):
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: exchange == .upbit ? 0 : 9 * 3600)
      formatter.dateFormat = exchange == .upbit ? "yyyy-MM-dd'T'HH:mm:ss'Z'" : "yyyy-MM-dd'T'HH:mm:ss"
      values["to"] = formatter.string(from: Date(timeIntervalSince1970: Double(to) / 1000))
      values["count"] = count
    case .trades(let to, let daysAgo, let cursor):
      values["count"] = 500
      if let to { values["to"] = to }
      if let daysAgo { values[exchange == .upbit ? "days_ago" : "daysAgo"] = daysAgo }
      if let cursor { values["cursor"] = cursor }
    }
    return .requestParameters(parameters: values, encoding: URLEncoding.queryString)
  }
}
