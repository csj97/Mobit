//
//  NetworkResponseValidator.swift
//  Mobit
//
//  Created by 조성재 on 8/18/26.
//

import Foundation
import Moya

enum NetworkResponseValidator {
  static func validate(response: Response) throws {
    guard (200..<300).contains(response.statusCode) else {
      throw self.mapHTTPError(statusCode: response.statusCode, data: response.data)
    }
  }

  static func mapHTTPError(statusCode: Int, data: Data = Data()) -> ErrorType {
    let apiError = try? JSONDecoder().decode(NetworkErrorResponse.self, from: data)
    let errorName = apiError?.error?.name ?? "nil"
    Log.error("서버 에러 매핑 status=\(statusCode), name=\(errorName)")

    switch statusCode {
    case 400, 401, 403, 404, 422:
      return .badRequest
    case 414:
      return .requestURITooLong
    case 429:
      return .tooManyRequests
    case 500..<600:
      return .serverError
    default:
      return .unknown
    }
  }

  static func mapRequestError(_ error: Error) -> ErrorType {
    if let errorType = error as? ErrorType {
      return errorType
    }

    if let moyaError = error as? MoyaError {
      return self.mapMoyaError(moyaError)
    }

    if let urlError = error as? URLError {
      return self.mapURLError(urlError)
    }

    return .unknown
  }

  static func bodyPreview(from data: Data, maxLength: Int = 500) -> String {
    guard let body = String(data: data, encoding: .utf8), !body.isEmpty else {
      return "N/A"
    }

    guard body.count > maxLength else { return body }
    return String(body.prefix(maxLength)) + "...<truncated>"
  }

  private static func mapMoyaError(_ error: MoyaError) -> ErrorType {
    switch error {
    case .imageMapping, .jsonMapping, .stringMapping, .objectMapping:
      return .decodingFailed
    case .statusCode(let response):
      return self.mapHTTPError(statusCode: response.statusCode, data: response.data)
    case .underlying(let error, _):
      if let urlError = error as? URLError {
        return self.mapURLError(urlError)
      }
      return .unknown
    case .requestMapping, .parameterEncoding, .encodableMapping:
      return .badRequest
    }
  }

  private static func mapURLError(_ error: URLError) -> ErrorType {
    switch error.code {
    case .notConnectedToInternet, .networkConnectionLost, .timedOut:
      return .networkConnection
    case .badURL, .unsupportedURL:
      return .invalidURL
    default:
      return .unknown
    }
  }
}

/// bithumb network error response
struct NetworkErrorResponse: Decodable {
  let error: ErrorMessage?

  struct ErrorMessage: Decodable {
    let name: String?
    let message: String?
  }
}
