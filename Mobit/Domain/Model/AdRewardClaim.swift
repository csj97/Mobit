import Foundation

struct AdRewardClaim: Codable, Equatable {
  let id: UUID
  let account: TradingAccountID
  let amount: Decimal
  let policyVersion: Int
  let earnedAt: Date

  init(id: UUID = UUID(), account: TradingAccountID, earnedAt: Date = Date()) throws {
    guard let amount = TradingFundingPolicy.advertisementReward(for: account) else {
      throw AdRewardError.invalidClaim
    }
    self.id = id
    self.account = account
    self.amount = amount
    self.policyVersion = 1
    self.earnedAt = earnedAt
    try validate()
  }

  func validate() throws {
    guard policyVersion == 1, !amount.isNaN, amount > 0,
          amount == TradingFundingPolicy.advertisementReward(for: account),
          earnedAt.timeIntervalSince1970.isFinite, earnedAt.timeIntervalSince1970 > 0,
          account.availability != .unsupported else { throw AdRewardError.invalidClaim }
  }

  static func validateCollection(_ claims: [Self]) throws {
    guard Set(claims.map(\.id)).count == claims.count else { throw AdRewardError.invalidClaim }
    try claims.forEach { try $0.validate() }
  }
}

enum AdRewardError: Error {
  case invalidClaim
  case conflictingClaim
  case pendingReward
  case invalidStoredData
}

protocol AdRewardPendingStore {
  // 로컬 저장소에서 지급 대기 중인 광고 보상 요청을 읽는다.
  func fetchClaims() throws -> [AdRewardClaim]
  func save(_ claims: [AdRewardClaim]) throws
}
