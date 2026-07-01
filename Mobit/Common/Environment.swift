//
//  Environment.swift
//  Mobit
//
//  Created by openobject on 2024/07/23.
//

import Foundation

public enum Environment {
  enum Keys {
    static let accessKey = "UPBIT_ACCESS_KEY"
    static let secretKey = "UPBIT_SECRET_KEY"
    static let coinMarketCapApiKey = "COIN_MARKET_CAP_API_KEY"
  }

  private static let infoDictionary: [String: Any] = {
    Bundle.main.infoDictionary ?? [:]
  }()

  static let accessKey = string(for: Keys.accessKey)
  static let secretKey = string(for: Keys.secretKey)
  static let coinMarketCapApiKey = string(for: Keys.coinMarketCapApiKey)

  private static func string(for key: String) -> String? {
    guard let value = infoDictionary[key] as? String else { return nil }
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.isEmpty, !trimmedValue.hasPrefix("$(") else { return nil }
    return trimmedValue
  }
}
