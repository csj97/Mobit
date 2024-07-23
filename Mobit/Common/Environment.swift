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
  }
  
  private static let infoDictionary: [String: Any] = {
    guard let dict = Bundle.main.infoDictionary else {
      fatalError("plist file not found")
    }
    return dict
  }()
  
  static let accessKey: String = {
    guard let accessKeyString = Environment.infoDictionary[Keys.accessKey] as? String else {
      fatalError("Upbit Access Key not set in plist")
    }
    return accessKeyString
  }()
  
  static let secretKey: String = {
    guard let secretKeyString = Environment.infoDictionary[Keys.secretKey] as? String else {
      fatalError("Upbit Secret Key not set in plist")
    }
    return secretKeyString
  }()
}
