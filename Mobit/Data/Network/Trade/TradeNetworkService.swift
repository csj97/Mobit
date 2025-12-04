//
//  TradeNetworkService.swift
//  Mobit
//
//  Created by 조성재 on 12/3/25.
//

import Foundation
import Moya
import RxSwift

/// 캔들 조회 타입 (초, 분, 날, 주, 월, 연)
enum CandleTimeType {
  case second
  case minute
  case day
  case week
  case month
  case year
}

enum TradeNetworkService {
  // market (KRW-BTC), to (조회 종료 시각), count (조회 캔들 개수)
  case getCandleList(market: String, unit: Int32, to: String?, count: Int?)
}

extension TradeNetworkService: TargetType {
  var baseURL: URL {
	switch self {
	case .getCandleList:
	  return URL(string: "https://api.upbit.com/v1/candles")!
	}
  }
  
  var path: String {
	switch self {
	case .getCandleList(_, let unit, _, _):
	  return "/minutes/\(unit)"
	}
  }
  
  var method: Moya.Method {
	switch self {
	case .getCandleList:
	  return .get
	}
  }
  
  var task: Moya.Task {
	switch self {
	case .getCandleList(let market, _, let to, let count):
	  let param: [String: Any] = [
		"market": market,
		"to": to ?? "",
		"count": count ?? ""
	  ]
	  return .requestParameters(parameters: param, encoding: URLEncoding.queryString)
	}
  }
  
  var headers: [String : String]? {
	return [
	  "Accept":"application/json",
	  "Content-type":"application/json"
	]
  }
}
