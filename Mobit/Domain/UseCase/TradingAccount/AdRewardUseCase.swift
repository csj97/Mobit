import Foundation

final class AdRewardUseCase {
  static let shared = AdRewardUseCase(store: LocalAdRewardPendingStore())
  private static let lock = NSRecursiveLock()
  private let store: AdRewardPendingStore
  // 광고를 시작할 선물 계좌를 기존 저장소에 준비한다.
  private let prepareFuturesAccount: (TradingAccountID) throws -> Void
  private let apply: (AdRewardClaim) throws -> Void
  private var unsavedClaims: [UUID: AdRewardClaim] = [:]

  init(
    store: AdRewardPendingStore,
    prepareFuturesAccount: @escaping (TradingAccountID) throws -> Void = {
      try LocalFuturesAccountRepository.applicationStore().ensureAccount($0)
    },
    apply: @escaping (AdRewardClaim) throws -> Void = { claim in
      switch claim.account.product {
      case .spot: try UserDataManager.applyAdvertisementReward(claim)
      case .perpetual: try LocalFuturesAccountRepository.applicationStore().applyAdvertisementReward(claim)
      }
    }
  ) {
    self.store = store
    self.prepareFuturesAccount = prepareFuturesAccount
    self.apply = apply
  }

  func prepareAccount(_ account: TradingAccountID) throws {
	guard account.availability == .available else { throw AdRewardError.invalidClaim }
	if account.product == .perpetual {
      try prepareFuturesAccount(account)
	}
  }

  func receive(_ claim: AdRewardClaim) throws {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    try claim.validate()
    if let existing = unsavedClaims[claim.id], existing != claim { throw AdRewardError.conflictingClaim }
    unsavedClaims[claim.id] = claim
    try retryPendingRewards()
  }

  @discardableResult
  func retryPendingRewards() throws -> [AdRewardClaim] {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    var pending = try store.fetchClaims()
    for claim in unsavedClaims.values {
      if let existing = pending.first(where: { $0.id == claim.id }) {
        guard existing == claim else { throw AdRewardError.conflictingClaim }
      } else {
        pending.append(claim)
      }
    }
    if !unsavedClaims.isEmpty {
      try store.save(pending)
      unsavedClaims.removeAll()
    }
    var completed: [AdRewardClaim] = []
    var firstError: Error?
    for claim in pending.sorted(by: { $0.earnedAt < $1.earnedAt }) {
      do {
        try apply(claim)
        let remaining = pending.filter { $0.id != claim.id }
        try store.save(remaining)
        pending = remaining
        completed.append(claim)
      } catch {
        firstError = firstError ?? error
      }
    }
    if let firstError { throw firstError }
    return completed
  }

  func resetSpotInvestment() throws {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    guard unsavedClaims.isEmpty, try store.fetchClaims().isEmpty else { throw AdRewardError.pendingReward }
    guard UserDataManager.resetInvestmentData() else { throw AdRewardError.invalidStoredData }
  }
}
