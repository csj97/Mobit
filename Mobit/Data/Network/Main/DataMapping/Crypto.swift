//
//  Crypto.swift
//  Mobit
//
//  Created by openobject on 2024/07/18.
//

import Foundation

typealias CryptoList = [Crypto]

struct Crypto: Hashable {
  let identifier = UUID()
  var market: String  // KRW-BTC 형태
  let koreanName: String
  let englishName: String
  let marketWarning: String
  let marketEvent: MarketEvent
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(identifier)
  }
  
  static func == (lhs: Crypto, rhs: Crypto) -> Bool {
    return lhs.identifier == rhs.identifier
  }
}

struct MarketEvent: Hashable {
  let warning: Bool   // 유의 종목 지정 여부
  let caution: CautionEvents
}

struct CautionEvents: Hashable {
  let priceFluctuations: Bool     // 가격 급등락 경보 발령 여부
  let tradingVolumeSoaring: Bool  // 거래량 급등 경보 발령 여부
  let depositAmountSoaring: Bool  // 입금량 급등 경보 발령 여부
  let globalPriceDifferences: Bool  // 가격 차이 경보 발령 여부
  let concentrationOfSmallAccounts: Bool  // 소수 계정 집중 경보 발령 여부
}

