import GoogleMobileAds
import RxSwift
import UIKit

// SDK의 실제 표시·보상·종료 콜백을 테스트에서도 같은 경로로 전달한다.
protocol RewardedAdPresenting: FullScreenPresentingAd {
  @MainActor func present(from viewController: UIViewController?, userDidEarnRewardHandler: @escaping () -> Void)
}

extension RewardedAd: RewardedAdPresenting {}

@MainActor
final class RewardedAdManager: NSObject {
  static let shared = RewardedAdManager()
  // 광고 준비도 기존 전체 화면 대기 기준과 동일하게 20초까지만 앱을 잠근다.
  static let preparationTimeout: RxTimeInterval = .seconds(20)

  private final class Presentation {
    // 닫힘 뒤 늦은 보상은 허용하되 취소·실패한 요청의 보상은 받지 않는다.
    enum Phase { case preparing, showing, dismissed, cancelled }
    // 광고를 시작한 계좌와 한 번의 지급 ID를 보존한다.
    let session: RewardedAdSession
    // 화면이 해제돼도 광고 요청이 화면을 계속 붙잡지 않는다.
    weak var viewController: MobitBaseViewController?
    // SDK 콜백이 어느 요청 단계에 속하는지 구분한다.
    var phase = Phase.preparing

    init(session: RewardedAdSession, viewController: MobitBaseViewController) {
      self.session = session
      self.viewController = viewController
    }
  }

  // 현재 표시 요청에 연결된 SDK 광고만 콜백을 받을 수 있다.
  private var rewardedAd: RewardedAdPresenting?
  // 중복 탭을 하나의 준비·표시 요청으로 제한한다.
  private var presentation: Presentation?
  // 준비를 중단하면 대기 중인 SDK 로드를 취소한다.
  private var loadTask: Task<Void, Never>?
  // 로드·표시 콜백이 오지 않아도 인디케이터를 자동 해제한다.
  private var preparationTimer: Disposable?
  // 앱 백그라운드 전환을 한 번만 구독한다.
  private let disposeBag = DisposeBag()
  // 기존 지급 기록·재시도·원자적 저장을 광고 UI와 연결한다.
  private let useCase: AdRewardUseCase
  // 실제 SDK 로더이며 테스트에서는 완료·실패·지연을 제어한다.
  private let loadAd: @MainActor () async throws -> RewardedAdPresenting
  // 대기 상한을 SDK 응답과 독립적으로 동작시킨다.
  private let scheduler: SchedulerType

  init(
    useCase: AdRewardUseCase = .shared,
    loadAd: @escaping @MainActor () async throws -> RewardedAdPresenting = {
      try await RewardedAd.load(with: MobitConstants.rewardAdType, request: Request())
    },
    scheduler: SchedulerType = MainScheduler.instance
  ) {
    self.useCase = useCase
    self.loadAd = loadAd
    self.scheduler = scheduler
    super.init()
    NotificationCenter.default.rx.notification(UIApplication.didEnterBackgroundNotification)
      .observe(on: MainScheduler.instance)
      .subscribe(onNext: { [weak self] _ in
        guard let self, let context = self.presentation, context.phase == .preparing else { return }
        context.phase = .cancelled
        MobitAnalyticsUtil.sendAdEvent(
          event: .reward_failed,
          account: context.session.account,
          extraParameters: ["failure_reason": "광고_준비_백그라운드취소"]
        )
        self.finish(context)
      }).disposed(by: disposeBag)
  }

  func showAd(from viewController: MobitBaseViewController, account: TradingAccountID) {
    guard presentation == nil, viewController.viewIfLoaded?.window != nil,
      UIApplication.shared.applicationState != .background else { return }
    guard account.availability == .available else {
      MobitAnalyticsUtil.sendAdEvent(
        event: .reward_failed,
        account: account,
        extraParameters: ["failure_reason": "지원하지_않는_계좌"]
      )
      showMessage("ad_reward_unavailable", in: viewController)
      return
    }
    do {
      try useCase.prepareAccount(account)
      // 미완료 지급을 먼저 복구한 경우 새 광고를 시작하지 않는다.
      let recovered = try useCase.retryPendingRewards()
      if !recovered.isEmpty {
        sendRecoveredRewardEvents(recovered)
        NotificationCenter.default.post(name: .futuresAccountDidChange, object: nil)
        showMessage("ad_reward_recovered", in: viewController)
        return
      }
      // 비동기 로드가 끝날 때까지 충전 대상을 현재 선택과 분리한다.
      let context = Presentation(session: try RewardedAdSession(account: account), viewController: viewController)
      presentation = context
      viewController.showLoadingIndicator()
      preparationTimer = Observable<Int>.timer(Self.preparationTimeout, scheduler: scheduler)
        .observe(on: MainScheduler.instance)
        .subscribe(onNext: { [weak self, context] _ in
          guard let self, self.presentation === context, context.phase == .preparing else { return }
          context.phase = .cancelled
          MobitAnalyticsUtil.sendAdEvent(
            event: .reward_failed,
            account: context.session.account,
            extraParameters: ["failure_reason": "광고_준비_시간초과"]
          )
          self.finish(context)
          if let presenter = context.viewController { self.showMessage("ad_reward_load_failed", in: presenter) }
        })
      loadTask = Task { @MainActor [weak self, loadAd, context] in
        do {
          // SDK가 취소 후 응답하더라도 이전 요청의 광고를 표시하지 않는다.
          let ad = try await loadAd()
          guard let self, self.presentation === context, context.phase == .preparing else { return }
          guard let presenter = context.viewController, presenter.viewIfLoaded?.window != nil else {
            context.phase = .cancelled
            MobitAnalyticsUtil.sendAdEvent(
              event: .reward_failed,
              account: context.session.account,
              extraParameters: ["failure_reason": "광고_표시화면_이탈"]
            )
            self.finish(context)
            return
          }
          self.rewardedAd = ad
          ad.fullScreenContentDelegate = self
          ad.present(from: presenter) { [weak self, context] in
            Task { @MainActor in
              guard let self, context.phase == .showing || context.phase == .dismissed,
                context.session.earned(using: self.useCase) else { return }
              NotificationCenter.default.post(name: .futuresAccountDidChange, object: nil)
              MobitAnalyticsUtil.sendAdEvent(event: .reward_finish, account: context.session.account)
              self.showResultIfReady(context)
            }
          }
        } catch {
          guard let self, self.presentation === context else { return }
          context.phase = .cancelled
          MobitAnalyticsUtil.sendAdEvent(
            event: .reward_failed,
            account: context.session.account,
            extraParameters: ["failure_reason": "광고_로드_실패"]
          )
          self.finish(context)
          if let presenter = context.viewController { self.showMessage("ad_reward_load_failed", in: presenter) }
        }
      }
    } catch {
      MobitAnalyticsUtil.sendClickEvent(
        location: "광고_보상",
        stepDepth01: "광고_충전",
        stepDepth02: "광고_충전_준비_실패",
        account: account,
        extraParameters: ["failure_reason": rewardFailureReason(error)]
      )
      showMessage("ad_reward_pending", in: viewController)
    }
  }

  func retryPendingRewards() {
    guard presentation == nil else { return }
    do {
      // 기존 보상은 원래 계좌에만 재시도하며 새 광고 보상을 만들지 않는다.
      let recovered = try useCase.retryPendingRewards()
      sendRecoveredRewardEvents(recovered)
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
      try useCase.resetSpotInvestment()
      showMessage("ad_reward_reset_complete", in: viewController)
    } catch {
      showMessage("ad_reward_reset_pending", in: viewController)
    }
  }

  func resetInvestment(for account: TradingAccountID, from viewController: MobitBaseViewController) {
    guard presentation == nil else {
      MobitAnalyticsUtil.sendClickEvent(
        location: "더보기_화면",
        stepDepth01: "더보기_탭",
        stepDepth02: "더보기_초기화_차단",
        account: account,
        extraParameters: ["failure_reason": "광고_진행중"]
      )
      showMessage("ad_reward_reset_pending", in: viewController)
      return
    }
    do {
      try useCase.resetInvestment(for: account)
      MobitAnalyticsUtil.sendClickEvent(
        location: "더보기_화면",
        stepDepth01: "더보기_탭",
        stepDepth02: "더보기_초기화_성공",
        account: account
      )
      NotificationCenter.default.post(name: .futuresAccountDidChange, object: nil)
      showMessage("ad_reward_reset_complete", in: viewController)
    } catch AdRewardError.pendingReward {
      MobitAnalyticsUtil.sendClickEvent(
        location: "더보기_화면",
        stepDepth01: "더보기_탭",
        stepDepth02: "더보기_초기화_차단",
        account: account,
        extraParameters: ["failure_reason": "보상_정산_대기"]
      )
      showMessage("ad_reward_reset_pending", in: viewController)
    } catch {
      MobitAnalyticsUtil.sendClickEvent(
        location: "더보기_화면",
        stepDepth01: "더보기_탭",
        stepDepth02: "더보기_초기화_실패",
        account: account,
        extraParameters: ["failure_reason": rewardFailureReason(error)]
      )
      showMessage("ad_reward_reset_pending", in: viewController)
    }
  }

  private func stopPreparationTimer() {
    preparationTimer?.dispose()
    preparationTimer = nil
  }

  private func finish(_ context: Presentation) {
    // 이전 콜백이 새 요청의 인디케이터나 작업을 종료하지 못하게 한다.
    guard presentation === context else { return }
    stopPreparationTimer()
    loadTask?.cancel()
    loadTask = nil
    context.viewController?.hideLoadingIndicator()
    presentation = nil
    rewardedAd = nil
  }

  private func showResultIfReady(_ context: Presentation) {
    guard let result = context.session.takeResultIfReady() else { return }
    // 보상 획득과 구분해 지급·대기 정리가 모두 끝난 1회 결과만 기록한다.
    switch result {
    case .success:
      MobitAnalyticsUtil.sendClickEvent(
        location: "광고_보상",
        stepDepth01: "광고_충전",
        stepDepth02: "광고_충전_지급_완료",
        account: context.session.account
      )
    case .failure(let error):
      MobitAnalyticsUtil.sendClickEvent(
        location: "광고_보상",
        stepDepth01: "광고_충전",
        stepDepth02: "광고_충전_지급_대기",
        account: context.session.account,
        extraParameters: ["failure_reason": rewardFailureReason(error)]
      )
    }
    // 광고가 닫힌 뒤에도 보이는 계좌 목록이 확정 잔고를 바로 다시 읽는다.
    NotificationCenter.default.post(name: .futuresAccountDidChange, object: nil)
    guard presentation == nil, let viewController = context.viewController,
      viewController.viewIfLoaded?.window != nil else { return }
    switch result {
    case .success: showMessage("ad_reward_complete", in: viewController)
    case .failure: showMessage("ad_reward_pending", in: viewController)
    }
  }

  private func sendRecoveredRewardEvents(_ claims: [AdRewardClaim]) {
    // 복구가 확정된 보상마다 현재 선택이 아닌 원래 지급 계좌를 기록한다.
    for claim in claims {
      MobitAnalyticsUtil.sendClickEvent(
        location: "광고_보상",
        stepDepth01: "광고_충전",
        stepDepth02: "광고_충전_보상_복구",
        account: claim.account
      )
    }
  }

  private func rewardFailureReason(_ error: Error) -> String {
    switch error {
    case AdRewardError.invalidClaim: return "지원하지_않는_보상요청"
    case AdRewardError.conflictingClaim: return "보상_기록_충돌"
    case AdRewardError.pendingReward: return "보상_정산_대기"
    case AdRewardError.invalidStoredData: return "저장_확인_실패"
    default: return "저장_처리_실패"
    }
  }

  private func showMessage(_ key: String, in viewController: MobitBaseViewController) {
    guard viewController.viewIfLoaded?.window != nil,
      UIApplication.shared.applicationState != .background else { return }
    // 화면의 기존 다국어 테이블과 실제 오류 안내를 유지한다.
    let table = Locale.preferredLanguages.first?.hasPrefix("ko") == true ? "Localizable(KO)" : "Localizable(EN)"
    // 광고 SDK 오류 원문이나 계좌 저장 원본을 사용자에게 노출하지 않는다.
    let message = NSLocalizedString(key, tableName: table, bundle: .main, value: key, comment: "")
    viewController.show(alertType: .onlyConfirm, title: FuturesText.text("common_notice"), content: message, callBack: nil)
  }
}

extension RewardedAdManager: FullScreenContentDelegate {
  func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
    guard let context = presentation, (ad as AnyObject) === rewardedAd, context.phase == .preparing else { return }
    context.phase = .showing
    stopPreparationTimer()
    MobitAnalyticsUtil.sendAdEvent(event: .reward_present, account: context.session.account)
    context.viewController?.hideLoadingIndicator()
  }

  func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
    guard let context = presentation, (ad as AnyObject) === rewardedAd, context.phase == .showing else { return }
    context.phase = .dismissed
    MobitAnalyticsUtil.sendAdEvent(event: .reward_close, account: context.session.account)
    context.session.dismissed()
    finish(context)
    showResultIfReady(context)
  }

  func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
    guard let context = presentation, (ad as AnyObject) === rewardedAd else { return }
    context.phase = .cancelled
    MobitAnalyticsUtil.sendAdEvent(
      event: .reward_failed,
      account: context.session.account,
      extraParameters: ["failure_reason": "광고_표시_실패"]
    )
    finish(context)
    if let viewController = context.viewController { showMessage("ad_reward_load_failed", in: viewController) }
  }
}
