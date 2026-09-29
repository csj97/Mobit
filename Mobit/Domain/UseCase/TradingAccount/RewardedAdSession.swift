import Foundation

@MainActor
final class RewardedAdSession {
  private let offer: AdRewardClaim
  private var earnedClaim: AdRewardClaim?
  private var result: Result<Void, Error>?
  private var isDismissed = false
  private var didNotify = false

  init(account: TradingAccountID) throws {
    offer = try AdRewardClaim(account: account)
  }

  func earned(using useCase: AdRewardUseCase, at date: Date = Date()) {
    guard earnedClaim == nil else { return }
    do {
      let claim = try AdRewardClaim(id: offer.id, account: offer.account, earnedAt: date)
      earnedClaim = claim
      try useCase.receive(claim)
      result = .success(())
    } catch {
      result = .failure(error)
    }
  }

  func dismissed() { isDismissed = true }

  func takeResultIfReady() -> Result<Void, Error>? {
    guard isDismissed, !didNotify, let result else { return nil }
    didNotify = true
    return result
  }
}
