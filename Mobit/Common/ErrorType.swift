//
//  ErrorType.swift
//  Mobit
//
//  Created by 조성재 on 7/16/24.
//

import Foundation

enum ErrorType: Error {
  case badRequest
  case rateLimited
  case unknownError
  case dataMappingError
  case socketError
}

extension ErrorType: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .badRequest:
      return "잘못된 접근입니다."
    case .rateLimited:
      return "요청이 많아 잠시 후 다시 시도해주세요."
    case .dataMappingError:
      return "Data의 맵핑이 잘못됐습니다."
    case .unknownError:
      return "알 수 없는 오류가 발생하였습니다."
	case .socketError:
	  return "소켓(실시간 통신) 에러가 발생하였습니다."
    }
  }
}
