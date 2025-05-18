//
//  MoreViewController.swift
//  Mobit
//
//  Created by 조성재 on 5/18/25.
//

import GoogleMobileAds
import RxCocoa
import RxSwift
import UIKit

class MoreViewController: UIViewController, MobitAlertDelegate {
  
  weak var coordinator: MoreCoordinator?
  private var rewardedAd: RewardedAd?

  override func viewDidLoad() {
	super.viewDidLoad()
	self.view.backgroundColor = .gray
  }
  
  override func viewDidLayoutSubviews() {
	super.viewDidLayoutSubviews()
  }
  
  @IBAction func tapOnChargeMoney(_ sender: UIButton) {
	Task {
	  await loadRewardedAd()
	}
  }
  
  /// Google 보상형 광고 load
  func loadRewardedAd() async {
	do {
	  print("로딩 시도 시작")
	  rewardedAd = try await RewardedAd.load(
		with: "ca-app-pub-3498168241675848/9517873690", request: Request())
	  rewardedAd?.fullScreenContentDelegate = self
	} catch {
	  print("Rewarded ad failed to load with error: \(error.localizedDescription)")
	}
  }
}

extension MoreViewController: FullScreenContentDelegate {
  /// Tells the delegate that the ad failed to present full screen content.
  func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
	print("Ad did fail to present full screen content.")
	show(alertType: .onlyConfirm, content: "Google AD load에 실패하였습니다.\n다시 시도 해주세요.")
  }
  
  /// Tells the delegate that the ad will present full screen content.
  func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
	print("Ad will present full screen content.")
  }
  
  /// Tells the delegate that the ad dismissed full screen content.
  func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
	print("광고 끝! 돈 충전해줄게요!!")
	UserDataManager.userInformation?.userAvailableBalance += 10000000
  }
}
