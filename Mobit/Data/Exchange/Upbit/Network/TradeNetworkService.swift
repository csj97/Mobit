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
  // 종목·봉 간격·조회 범위를 지정한 업비트 분봉 요청을 정의한다.
  case fetchCandleListMinutes(market: String, unit: Int32, to: String?, count: Int?)
  // 종목과 조회 범위를 지정한 업비트 일봉 요청을 정의한다.
  case fetchCandleListDays(market: String, to: String?, count: Int?, convertingPriceUnit: String?)
}

extension TradeNetworkService: TargetType {
  var baseURL: URL {
	switch self {
	case .fetchCandleListMinutes:
	  return URL(string: "https://api.upbit.com/v1/candles")!
	case .fetchCandleListDays:
	  return URL(string: "https://api.upbit.com/v1/candles")!
	}
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
	switch self {
	case .fetchCandleListMinutes:
	  return .get
	case .fetchCandleListDays:
	  return .get
	}
  }
  
  var task: Moya.Task {
	switch self {
	case .fetchCandleListMinutes(let market, _, let to, let count):
	  let param: [String: Any] = [
		"market": market,
		"to": to ?? "",
		"count": count ?? ""
	  ]
	  return .requestParameters(parameters: param, encoding: URLEncoding.queryString)
	  
	case .fetchCandleListDays(let market, let to, let count, let convertingPriceUnit):
	  var param: [String: Any] = [
		"market": market
	  ]
	  if let to {
		param["to"] = to
	  }

	  if let count {
		param["count"] = count
	  }

	  if let convertingPriceUnit {
		param["convertingPriceUnit"] = convertingPriceUnit
	  }
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
