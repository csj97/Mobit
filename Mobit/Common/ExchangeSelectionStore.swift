//
//  ExchangeSelectionStore.swift
//  Mobit
//
//  Created by 조성재 on 7/9/26.
//

import Foundation

enum ExchangeSelectionStore {
  private static let key = "selected-exchange"

  static var currentExchange: Exchange {
    get {
      guard let rawValue = UserDefaults.standard.string(forKey: key),
            let exchange = Exchange(rawValue: rawValue) else {
        return .upbit
      }
      return exchange
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: key)
    }
  }
}
