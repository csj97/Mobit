//
//  CryptoQuoteResponseDTO.swift
//  Mobit
//
//  Created by 조성재 on 5/25/25.
//

import Foundation

/// 전체 응답을 감싸는 최상위 구조체
struct CryptoQuoteResponseDTO: Codable {
  let status: Status                      // 응답 상태에 대한 메타 정보
  let data: [String: CryptoData]          // 코인 심볼(BTC 등)을 키로 갖는 실제 데이터
}

/// 응답 상태를 설명하는 구조체
struct Status: Codable {
  let timestamp: String                   // 응답이 생성된 시각 (ISO 8601 포맷)
  let errorCode: Int                      // 에러 코드 (0이면 성공)
  let errorMessage: String?               // 에러 메시지 (에러 발생 시 설명)
  let elapsed: Int                        // 응답 생성까지 걸린 시간 (밀리초)
  let creditCount: Int                    // 사용된 API 크레딧 수
  let notice: String?                     // 참고 메시지
  
  enum CodingKeys: String, CodingKey {
	case timestamp
	case errorCode = "error_code"
	case errorMessage = "error_message"
	case elapsed
	case creditCount = "credit_count"
	case notice
  }
}

/// 특정 코인에 대한 상세 정보
struct CryptoData: Codable {
  let id: Int                             // 고유 ID
  let name: String                        // 코인 이름 (예: Bitcoin)
  let symbol: String                      // 코인 심볼 (예: BTC)
  let slug: String                        // URL-friendly 이름
  let numMarketPairs: Int                 // 거래 가능한 마켓 쌍 개수
  let dateAdded: String                   // CoinMarketCap에 추가된 날짜
  let tags: [String]                      // 태그 목록 (예: "mineable", "pow")
  let maxSupply: Double?                  // 발행 최대 공급량 (없을 경우 nil)
  let circulatingSupply: Double           // 현재 유통 중인 코인 수량
  let totalSupply: Double                 // 총 발행 수량
  let isActive: Int                       // 활성 상태 (1: 활성, 0: 비활성)
  let infiniteSupply: Bool                // 무한 공급 여부
  let platform: Platform?                 // 플랫폼 정보 (예: Ethereum 위 토큰)
  let cmcRank: Int                        // CoinMarketCap 순위
  let isFiat: Int                         // 법정화폐 여부 (0: 아님, 1: 맞음)
  let selfReportedCirculatingSupply: Double? // 코인 프로젝트에서 직접 보고한 유통량
  let selfReportedMarketCap: Double?      // 자체 보고한 시가총액
  let tvlRatio: Double?                   // TVL 대비 시가총액 비율 (DeFi용)
  let lastUpdated: String                 // 마지막 업데이트 시각
  let quote: [String: Quote]              // 통화 단위(예: USD)에 따른 시세 정보
  
  enum CodingKeys: String, CodingKey {
	case id, name, symbol, slug
	case numMarketPairs = "num_market_pairs"
	case dateAdded = "date_added"
	case tags
	case maxSupply = "max_supply"
	case circulatingSupply = "circulating_supply"
	case totalSupply = "total_supply"
	case isActive = "is_active"
	case infiniteSupply = "infinite_supply"
	case platform
	case cmcRank = "cmc_rank"
	case isFiat = "is_fiat"
	case selfReportedCirculatingSupply = "self_reported_circulating_supply"
	case selfReportedMarketCap = "self_reported_market_cap"
	case tvlRatio = "tvl_ratio"
	case lastUpdated = "last_updated"
	case quote
  }
}

/// 토큰이 소속된 플랫폼 정보 (예: 이더리움, 바이낸스 스마트체인 등)
struct Platform: Codable {
  let id: Int                             // 플랫폼의 고유 ID (예: Ethereum의 ID)
  let name: String                        // 플랫폼 이름 (예: Ethereum)
  let symbol: String                      // 플랫폼 심볼 (예: ETH)
  let slug: String                        // URL-friendly 이름 (예: ethereum)
  let tokenAddress: String                // 해당 플랫폼 내 토큰 주소
  
  enum CodingKeys: String, CodingKey {
	case id
	case name
	case symbol
	case slug
	case tokenAddress = "token_address"
  }
}

/// 실시간 시세 정보 (예: USD 기준)
struct Quote: Codable {
  let price: Double                       // 현재 가격
  let volume24h: Double                   // 24시간 거래량
  let volumeChange24h: Double             // 전일 대비 거래량 변화율
  let percentChange1h: Double             // 1시간 전 대비 가격 변화율
  let percentChange24h: Double            // 24시간 전 대비 가격 변화율
  let percentChange7d: Double             // 7일 전 대비 가격 변화율
  let percentChange30d: Double            // 30일 전 대비 가격 변화율
  let percentChange60d: Double            // 60일 전 대비 가격 변화율
  let percentChange90d: Double            // 90일 전 대비 가격 변화율
  let marketCap: Double                   // 시가총액
  let marketCapDominance: Double          // 전체 시장에서 해당 코인의 점유율
  let fullyDilutedMarketCap: Double       // 최대 공급 기준 시가총액
  let tvl: Double?                        // Total Value Locked (DeFi 관련)
  let lastUpdated: String                 // 마지막 업데이트 시각
  
  enum CodingKeys: String, CodingKey {
	case price
	case volume24h = "volume_24h"
	case volumeChange24h = "volume_change_24h"
	case percentChange1h = "percent_change_1h"
	case percentChange24h = "percent_change_24h"
	case percentChange7d = "percent_change_7d"
	case percentChange30d = "percent_change_30d"
	case percentChange60d = "percent_change_60d"
	case percentChange90d = "percent_change_90d"
	case marketCap = "market_cap"
	case marketCapDominance = "market_cap_dominance"
	case fullyDilutedMarketCap = "fully_diluted_market_cap"
	case tvl
	case lastUpdated = "last_updated"
  }
}

extension CryptoQuoteResponseDTO {
  func toDomain(symbol: String) -> CryptoQuoteResponse {
	let cryptoData = data[symbol]
	let quoteData = cryptoData?.quote["USD"]
	guard let id = cryptoData?.id,
		  let name = cryptoData?.name,
		  let marketCap = quoteData?.marketCap,
		  let circulatingSupply = cryptoData?.circulatingSupply,
		  let totalSupply = cryptoData?.totalSupply,
		  let lastUpdated = quoteData?.lastUpdated,
		  let price = quoteData?.price,
		  let marketCapRank = cryptoData?.cmcRank,
		  let updatedAtString = quoteData?.lastUpdated
	else {
	  fatalError("Could not parse CryptoQuoteResponseDTO to CryptoQuoteResponse")
	}
		  
	return .init(
	  id: id,
	  name: name,
	  symbol: symbol,
	  iconURL: URL(string: "https://s2.coinmarketcap.com/static/img/coins/64x64/\(id).png"),
	  marketCap: marketCap,
	  circulatingSupply: circulatingSupply,
	  totalSupply: totalSupply,
	  maxSupply: cryptoData?.maxSupply,
	  lastUpdated: Self.date(from: lastUpdated),
	  price: price,
	  marketCapRank: marketCapRank,
	  platformName: cryptoData?.platform?.name,
	  tokenAddress: cryptoData?.platform?.tokenAddress,
	  updatedAtString: updatedAtString
	)
  }
  private static func date(from string: String) -> Date {
	let formatter = ISO8601DateFormatter()
	return formatter.date(from: string) ?? Date()
  }
  
  private static func formattedDate(from string: String) -> String {
	let formatter = ISO8601DateFormatter()
	guard let date = formatter.date(from: string) else { return "" }
	
	let displayFormatter = DateFormatter()
	displayFormatter.locale = Locale(identifier: "ko_KR")
	displayFormatter.dateFormat = "yyyy-MM-dd HH:mm"
	
	return "코인마켓캡 기준: \(displayFormatter.string(from: date))"
  }
}

//extension CryptoQuoteResponseDTO {
//  init?(symbol: String, data: CryptoData) {
//	guard let usdQuote = data.quote["USD"] else { return nil }
//	
//	self.id = data.id
//	self.name = data.name
//	self.symbol = data.symbol
//	self.iconURL = URL(
//	  string: "https://s2.coinmarketcap.com/static/img/coins/64x64/\(data.id).png"
//	)
//	
//	self.marketCap = usdQuote.marketCap
//	self.circulatingSupply = data.circulatingSupply
//	self.totalSupply = data.totalSupply
//	self.maxSupply = data.maxSupply
//	self.lastUpdated = Self.date(from: usdQuote.lastUpdated)
//	self.price = usdQuote.price
//	self.marketCapRank = data.cmcRank
//	
//	self.platformName = data.platform?.name
//	self.tokenAddress = data.platform?.tokenAddress
//	
//	self.updatedAtString = Self.formattedDate(from: usdQuote.lastUpdated)
//  }
//  
//  private static func date(from string: String) -> Date {
//	let formatter = ISO8601DateFormatter()
//	return formatter.date(from: string) ?? Date()
//  }
//  
//  private static func formattedDate(from string: String) -> String {
//	let formatter = ISO8601DateFormatter()
//	guard let date = formatter.date(from: string) else { return "" }
//	
//	let displayFormatter = DateFormatter()
//	displayFormatter.locale = Locale(identifier: "ko_KR")
//	displayFormatter.dateFormat = "yyyy-MM-dd HH:mm"
//	
//	return "코인마켓캡 기준: \(displayFormatter.string(from: date))"
//  }
//}
