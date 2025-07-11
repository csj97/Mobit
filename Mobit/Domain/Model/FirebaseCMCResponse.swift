//
//  FirebaseCMCResponse.swift
//  Mobit
//
//  Created by 조성재 on 7/10/25.
//

import Foundation

struct FirebaseCMCResponse: Codable {
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
}
