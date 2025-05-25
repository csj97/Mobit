//
//  CryptoInfoQuotesResponse.swift
//  Mobit
//
//  Created by 조성재 on 5/25/25.
//

import Foundation

struct CryptoQuoteResponse: Hashable {
  let id: Int                         // 고유 ID
  let name: String                    // 코인명
  let symbol: String                  // 코인 심볼 (예: BTC)
  let iconURL: URL?                   // 아이콘 URL (별도 처리 필요)
  let marketCap: Double               // 시가총액
  let circulatingSupply: Double       // 현재 유통량
  let totalSupply: Double             // 총 발행량
  let maxSupply: Double?              // 최대 공급량
  let lastUpdated: Date               // 마지막 시세 업데이트
  let price: Double                   // 현재 가격
  let marketCapRank: Int              // 시가총액 순위
  let platformName: String?           // 플랫폼 이름 (예: Ethereum)
  let tokenAddress: String?           // 토큰 주소
  let updatedAtString: String         // "코인마켓캡 기준: 2025-05-25 17:19" 등 표시용
}
