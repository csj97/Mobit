//
//  ExchangeSelectionStore.swift
//  Mobit
//
//  Created by 조성재 on 7/9/26.
//

import Foundation

enum ExchangeSelectionStore {
  static var currentProduct: TradingProduct {
    get { TradingProduct(rawValue: UserDefaults.standard.string(forKey: "selected-trading-product") ?? "") ?? .spot }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: "selected-trading-product") }
  }

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
