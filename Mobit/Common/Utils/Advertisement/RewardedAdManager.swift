//
//  RewardedAdManager.swift
//  Mobit
//
//  Created by 조성재 on 7/21/25.
//

import GoogleMobileAds
import UIKit

final class RewardedAdManager: NSObject {	// NSObject 상속 이유 : Obj-C 호환, NSObject 기본 제공 기능 사용
  static let shared = RewardedAdManager()
  
  private var rewardedAd: RewardedAd?
  private var rewardCompletion: (() -> Void)?	// 광고 종료 시점
  private var presentingVC: MobitBaseViewController?		// 광고를 띄우기 위한 VC

  /// 클래스의 생성자를 외부에서 호출 못하도록 방어 (싱글톤이므로 내부에서만 초기화 가능하게)
  private override init() {}

  /// 광고 보여주는 메소드
  func showAd(from viewController: MobitBaseViewController, onSuccess: @escaping () -> Void) {
	self.rewardCompletion = onSuccess
	self.presentingVC = viewController

	Task {
	  do {
		self.showLoadingIndicator(in: viewController)
		
		rewardedAd = try await RewardedAd.load(
		  with: MobitConstants.rewardAdType,
		  request: Request()
		)
		rewardedAd?.fullScreenContentDelegate = self
		await rewardedAd?.present(from: viewController, userDidEarnRewardHandler: {
		  Log.info("광고 끝! 돈 충전해줄게요!!")
		  MobitAnalyticsUtil.sendAdEvent(event: .reward_finish)
		})
	  } catch {
		Log.info("Rewarded ad load error: \(error.localizedDescription)")
		self.hideLoadingIndicator(in: viewController)
		self.showFailAlert(in: viewController)
	  }
	}
  }
  
  /// 광고 로드 실패
  private func showFailAlert(in vc: MobitBaseViewController) {
	vc.show(
	  alertType: .onlyConfirm,
	  content: "광고를 불러오는 데 실패했습니다.\n다시 시도해 주세요.",
	  callBack: nil
	)
  }
  
  /// 광고 띄우기 전 로드 시점 > 인디케이터 화면 노출 (광고 보여주는 화면에서 구현되어 있어야 함)
  private func showLoadingIndicator(in vc: MobitBaseViewController) {
	vc.showLoadingIndicator()
  }
  
  private func hideLoadingIndicator(in vc: MobitBaseViewController) {
	vc.hideLoadingIndicator()
  }
}

// MARK: - FullScreenContentDelegate
extension RewardedAdManager: FullScreenContentDelegate {
  func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
	Log.info("Ad will present")
	MobitAnalyticsUtil.sendAdEvent(event: .reward_present)
	guard let presentingVC = self.presentingVC else { return }
	self.hideLoadingIndicator(in: presentingVC)
  }
  
  // 광고 닫힘 후 처리
  func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
	Log.info("Ad dismissed")
	MobitAnalyticsUtil.sendAdEvent(event: .reward_close)
	self.rewardCompletion?()
  }

  /// 광고 로드 실패
  func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
	Log.info("Ad failed to present: \(error.localizedDescription)")
	MobitAnalyticsUtil.sendAdEvent(event: .reward_failed)
	guard let presentingVC = self.presentingVC else { return }
	self.hideLoadingIndicator(in: presentingVC)
	self.showFailAlert(in: presentingVC)
  }
}
