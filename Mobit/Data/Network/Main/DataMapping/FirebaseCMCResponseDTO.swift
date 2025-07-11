//
//  FirebaseCMCResponseDTO.swift
//  Mobit
//
//  Created by 조성재 on 7/11/25.
//

import Foundation

struct FirebaseCMCResponseDTO: Decodable {
  let id: Int
  let name: String
  let symbol: String
  let slug: String
  let iconURL: String
  let marketCap: Double
  let marketCapRank: Int
  let circulatingSupply: Double
  let totalSupply: Double
  let maxSupply: Double?
  let selfReportedCirculatingSupply: Double?
  let selfReportedMarketCap: Double?
  let price: Double
  let platformName: String?
  let tokenAddress: String?
  let dateAdded: String
  let lastUpdated: String
  let updatedAtString: String
  let percentChange1h: Double
  let percentChange24h: Double
  let percentChange7d: Double
  let percentChange30d: Double
  let percentChange60d: Double
  let percentChange90d: Double
  let volume24h: Double
  let volumeChange24h: Double
  let tags: [String]?
  
  enum CodingKeys: String, CodingKey {
	case id, name, symbol, slug, iconURL
	case marketCap = "market_cap"
	case marketCapRank = "market_cap_rank"
	case circulatingSupply = "circulating_supply"
	case totalSupply = "total_supply"
	case maxSupply = "max_supply"
	case selfReportedCirculatingSupply = "self_reported_circulating_supply"
	case selfReportedMarketCap = "self_reported_market_cap"
	case price
	case platformName = "platform_name"
	case tokenAddress = "token_address"
	case dateAdded = "date_added"
	case lastUpdated = "last_updated"
	case updatedAtString = "updated_at_string"
	case percentChange1h = "percent_change_1h"
	case percentChange24h = "percent_change_24h"
	case percentChange7d = "percent_change_7d"
	case percentChange30d = "percent_change_30d"
	case percentChange60d = "percent_change_60d"
	case percentChange90d = "percent_change_90d"
	case volume24h = "volume_24h"
	case volumeChange24h = "volume_change_24h"
	case tags
  }
}

extension FirebaseCMCResponseDTO {
  func toDomain() -> FirebaseCMCResponse {
	return FirebaseCMCResponse(
	  id: id,
	  name: name,
	  symbol: symbol,
	  slug: slug,
	  iconURL: iconURL,
	  marketCap: marketCap,
	  marketCapRank: marketCapRank,
	  circulatingSupply: circulatingSupply,
	  totalSupply: totalSupply,
	  maxSupply: maxSupply,
	  selfReportedCirculatingSupply: selfReportedCirculatingSupply,
	  selfReportedMarketCap: selfReportedMarketCap,
	  price: price,
	  platformName: platformName,
	  tokenAddress: tokenAddress,
	  dateAdded: dateAdded,
	  lastUpdated: lastUpdated,
	  updatedAtString: updatedAtString,
	  percentChange1h: percentChange1h,
	  percentChange24h: percentChange24h,
	  percentChange7d: percentChange7d,
	  percentChange30d: percentChange30d,
	  percentChange60d: percentChange60d,
	  percentChange90d: percentChange90d,
	  volume24h: volume24h,
	  volumeChange24h: volumeChange24h,
	  tags: tags
	)
  }
}

