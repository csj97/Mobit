//
//  BithumbCryptoDTO.swift
//  Mobit
//
//  Created by 조성재 on 7/9/26.
//

import Foundation

struct BithumbCryptoDTO: Decodable {
  let market: String
  let koreanName: String
  let englishName: String
  let marketWarning: String?

  enum CodingKeys: String, CodingKey {
    case market
    case koreanName = "korean_name"
    case englishName = "english_name"
    case marketWarning = "market_warning"
  }
}

typealias BithumbCryptoListDTO = [BithumbCryptoDTO]

extension BithumbCryptoDTO {
  func toDomain() -> Crypto {
    let isWarning = marketWarning == "CAUTION"
    return .init(
      market: market,
      koreanName: koreanName,
      englishName: englishName,
      marketEvent: .init(
        warning: isWarning,
        caution: .init(
          priceFluctuations: false,
          tradingVolumeSoaring: false,
          depositAmountSoaring: false,
          globalPriceDifferences: false,
          concentrationOfSmallAccounts: false
        )
      )
    )
  }
}

extension Array where Element == BithumbCryptoDTO {
  func toDomain() -> CryptoList {
    map { $0.toDomain() }
  }
}

