//
//  ErrorType.swift
//  Mobit
//
//  Created by 조성재 on 7/16/24.
//

import Foundation

enum ErrorType: Error {
  case badRequest
  case unknownError
  case dataMappingError
}

extension ErrorType: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .badRequest:
      return "잘못된 접근입니다."
    case .dataMappingError:
      return "Data의 맵핑이 잘못됐습니다."
    case .unknownError:
      return "알 수 없는 오류가 발생하였습니다."
    }
  }
}
