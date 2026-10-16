import Foundation

@MainActor
final class RewardedAdSession {
  private let offer: AdRewardClaim
  // 비동기 광고 콜백에도 요청 당시의 지급 계좌를 그대로 제공한다.
  var account: TradingAccountID { offer.account }
  private var earnedClaim: AdRewardClaim?
  private var result: Result<Void, Error>?
  private var isDismissed = false
  private var didNotify = false

  init(account: TradingAccountID) throws {
    offer = try AdRewardClaim(account: account)
  }

  @discardableResult
  func earned(using useCase: AdRewardUseCase, at date: Date = Date()) -> Bool {
    guard earnedClaim == nil else { return false }
    do {
      let claim = try AdRewardClaim(id: offer.id, account: offer.account, earnedAt: date)
      earnedClaim = claim
      try useCase.receive(claim)
      result = .success(())
    } catch {
      result = .failure(error)
    }
    return true
  }

  func dismissed() { isDismissed = true }

  func takeResultIfReady() -> Result<Void, Error>? {
    guard isDismissed, !didNotify, let result else { return nil }
    didNotify = true
    return result
  }
}
