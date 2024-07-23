//
//  CryptoDTO.swift
//  Mobit
//
//  Created by openobject on 2024/07/18.
//

import Foundation

typealias CryptoListDTO = [CryptoDTO]

struct CryptoDTO: Hashable, Codable {
  let market: String  // KRW-BTC 형태
  let koreanName: String
  let englishName: String
  let marketWarning: String
  let marketEvent: MarketEventDTO
  
  enum CodingKeys: String, CodingKey {
    case market
    case koreanName = "korean_name"
    case englishName = "english_name"
    case marketWarning = "market_warning" // 유의 종목 여부 (NONE, CAUTION-투자유의)
    case marketEvent = "market_event"
  }
}

struct MarketEventDTO: Hashable, Codable {
  let warning: Bool   // 유의 종목 지정 여부
  let caution: CautionEventsDTO
}

struct CautionEventsDTO: Hashable, Codable {
  let priceFluctuations: Bool     // 가격 급등락 경보 발령 여부
  let tradingVolumeSoaring: Bool  // 거래량 급등 경보 발령 여부
  let depositAmountSoaring: Bool  // 입금량 급등 경보 발령 여부
  let globalPriceDifferences: Bool  // 가격 차이 경보 발령 여부
  let concentrationOfSmallAccounts: Bool  // 소수 계정 집중 경보 발령 여부
  
  enum CodingKeys: String, CodingKey {
    case priceFluctuations = "PRICE_FLUCTUATIONS"
    case tradingVolumeSoaring = "TRADING_VOLUME_SOARING"
    case depositAmountSoaring = "DEPOSIT_AMOUNT_SOARING"
    case globalPriceDifferences = "GLOBAL_PRICE_DIFFERENCES"
    case concentrationOfSmallAccounts = "CONCENTRATION_OF_SMALL_ACCOUNTS"
  }
}

extension CryptoDTO {
  func toDomain() -> Crypto {
    return .init(market: market,
                 koreanName: koreanName,
                 englishName: englishName,
                 marketWarning: marketWarning,
                 marketEvent: marketEvent.toDomain())
  }
}

extension MarketEventDTO {
  func toDomain() -> MarketEvent {
    return .init(warning: warning, caution: caution.toDomain())
  }
}

extension CautionEventsDTO {
  func toDomain() -> CautionEvents {
    return .init(priceFluctuations: priceFluctuations,
                 tradingVolumeSoaring: tradingVolumeSoaring,
                 depositAmountSoaring: depositAmountSoaring,
                 globalPriceDifferences: globalPriceDifferences,
                 concentrationOfSmallAccounts: concentrationOfSmallAccounts)
  }
}

extension CryptoListDTO {
  // Crypto toDomain을 map을 사용해 배열로 return
  func toDomain() -> [Crypto] {
    return self.map { $0.toDomain() }
  }
}

