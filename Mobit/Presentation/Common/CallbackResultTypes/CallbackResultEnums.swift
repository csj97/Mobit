//
//  CallbackResultEnums.swift
//  Mobit
//
//  Created by 조성재 on 3/3/25.
//

import Foundation

enum OrderResult {
  case alert(title: String, message: String)
}

enum BidResult {
  case updateHistory
  case alert(title: String, message: String)
}

enum AskResult {
  case updateHistory
  case alert(title: String, message: String)
}

enum HistoryResult {
  
}
