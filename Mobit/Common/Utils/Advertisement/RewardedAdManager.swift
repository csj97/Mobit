import GoogleMobileAds
import UIKit

@MainActor
final class RewardedAdManager: NSObject {
  static let shared = RewardedAdManager()

  private final class Presentation {
    let session: RewardedAdSession
    weak var viewController: MobitBaseViewController?

    init(session: RewardedAdSession, viewController: MobitBaseViewController) {
      self.session = session
      self.viewController = viewController
    }
  }

  private var rewardedAd: RewardedAd?
  private var presentation: Presentation?
  private override init() {}

  func showAd(from viewController: MobitBaseViewController, account: TradingAccountID) {
    guard presentation == nil else { return }
    guard account.availability == .available else {
      showMessage("ad_reward_unavailable", in: viewController)
      return
    }
    do {
      try AdRewardUseCase.shared.prepareAccount(account)
      let recovered = try AdRewardUseCase.shared.retryPendingRewards()
      if !recovered.isEmpty {
        NotificationCenter.default.post(name: .futuresAccountDidChange, object: nil)
        showMessage("ad_reward_recovered", in: viewController)
        return
      }
      let context = Presentation(session: try RewardedAdSession(account: account), viewController: viewController)
      presentation = context
      viewController.showLoadingIndicator()
      Task { @MainActor in
        do {
          let ad = try await RewardedAd.load(with: MobitConstants.rewardAdType, request: Request())
          guard self.presentation === context else { return }
          guard let presenter = context.viewController, presenter.viewIfLoaded?.window != nil else {
            self.finish(context)
            return
          }
          self.rewardedAd = ad
          ad.fullScreenContentDelegate = self
          ad.present(from: presenter) { [weak self, context] in
            Task { @MainActor in
              context.session.earned(using: AdRewardUseCase.shared)
              NotificationCenter.default.post(name: .futuresAccountDidChange, object: nil)
              MobitAnalyticsUtil.sendAdEvent(event: .reward_finish)
              self?.showResultIfReady(context)
            }
          }
        } catch {
          self.finish(context)
          if let presenter = context.viewController { self.showMessage("ad_reward_load_failed", in: presenter) }
        }
      }
    } catch {
      showMessage("ad_reward_pending", in: viewController)
    }
  }

  func retryPendingRewards() {
    guard presentation == nil else { return }
    do {
      let recovered = try AdRewardUseCase.shared.retryPendingRewards()
      if !recovered.isEmpty { NotificationCenter.default.post(name: .futuresAccountDidChange, object: nil) }
    }
    catch { Log.info("광고 보상 정산 대기: 로컬 기록을 유지합니다.") }
  }

  func resetSpotInvestment(from viewController: MobitBaseViewController) {
    guard presentation == nil else {
      showMessage("ad_reward_reset_pending", in: viewController)
      return
    }
    do {
      try AdRewardUseCase.shared.resetSpotInvestment()
      showMessage("ad_reward_reset_complete", in: viewController)
    } catch {
      showMessage("ad_reward_reset_pending", in: viewController)
    }
  }

  private func finish(_ context: Presentation) {
    context.viewController?.hideLoadingIndicator()
    guard presentation === context else { return }
    presentation = nil
    rewardedAd = nil
  }

  private func showResultIfReady(_ context: Presentation) {
    guard let result = context.session.takeResultIfReady(),
          let viewController = context.viewController, viewController.viewIfLoaded?.window != nil else { return }
    switch result {
    case .success: showMessage("ad_reward_complete", in: viewController)
    case .failure: showMessage("ad_reward_pending", in: viewController)
    }
  }

  private func showMessage(_ key: String, in viewController: MobitBaseViewController) {
    let table = Locale.preferredLanguages.first?.hasPrefix("ko") == true ? "Localizable(KO)" : "Localizable(EN)"
    let message = NSLocalizedString(key, tableName: table, bundle: .main, value: key, comment: "")
    viewController.show(alertType: .onlyConfirm, content: message, callBack: nil)
  }
}

extension RewardedAdManager: FullScreenContentDelegate {
  func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
    guard (ad as AnyObject) === rewardedAd else { return }
    MobitAnalyticsUtil.sendAdEvent(event: .reward_present)
    presentation?.viewController?.hideLoadingIndicator()
  }

  func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
    guard let context = presentation, (ad as AnyObject) === rewardedAd else { return }
    MobitAnalyticsUtil.sendAdEvent(event: .reward_close)
    context.session.dismissed()
    finish(context)
    showResultIfReady(context)
  }

  func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
    guard let context = presentation, (ad as AnyObject) === rewardedAd else { return }
    MobitAnalyticsUtil.sendAdEvent(event: .reward_failed)
    finish(context)
    if let viewController = context.viewController { showMessage("ad_reward_load_failed", in: viewController) }
  }
}
