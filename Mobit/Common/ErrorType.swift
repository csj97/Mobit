//
//  ErrorType.swift
//  Mobit
//
//  Created by 조성재 on 7/16/24.
//

import Foundation

enum ErrorType: Error {
  case invalidURL
  case invalidResponse
  case badRequest
  case requestURITooLong
  case tooManyRequests
  case serverError
  case networkConnection
  case decodingFailed
  case unknown
  case socketError
}

extension ErrorType: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "잘못된 요청입니다."
    case .invalidResponse:
      return "응답 정보를 확인할 수 없습니다."
    case .badRequest:
      return "잘못된 요청입니다."
    case .requestURITooLong:
      return "요청 대상이 너무 많습니다."
    case .tooManyRequests:
      return "요청이 많습니다. 잠시 후 다시 시도해 주세요."
    case .serverError:
      return "시스템이 원활하지 않습니다. 잠시 후 다시 시도해 주세요."
    case .networkConnection:
      return "네트워크 연결을 확인해 주세요."
    case .decodingFailed:
      return "데이터를 처리하는 중 문제가 발생했습니다."
    case .unknown:
      return "알 수 없는 오류가 발생했습니다."
    case .socketError:
      return "소켓(실시간 통신) 에러가 발생하였습니다."
    }
  }
}
