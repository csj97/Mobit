//
//  FearGreedIndexResponseDTO.swift
//  Mobit
//
//  Created by 조성재 on 7/1/26.
//

import Foundation

// CoinMarketCap /v3/fear-and-greed/latest 응답
struct FearGreedIndexResponseDTO: Decodable {
  let data: FearGreedIndexDataDTO

  struct FearGreedIndexDataDTO: Decodable {
    // CMC가 정수/실수 어느 쪽으로 내려도 안전하도록 Double로 받아 반올림한다.
    let value: Double
  }

  func toDomain() -> FearGreedIndex {
    return FearGreedIndex(value: Int(data.value.rounded()))
  }
}
