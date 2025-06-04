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

class MoreViewController: UIViewController, ViewRule, MobitAlertDelegate {
  
  @IBOutlet weak var chargeMoneyButton: UIButton!
  @IBOutlet weak var loadingIndicator: UIActivityIndicatorView!
  @IBOutlet weak var loadingView: UIView!
  
  weak var coordinator: MoreCoordinator?
  private var rewardedAd: RewardedAd?

  override func viewDidLoad() {
	super.viewDidLoad()
	
	self.setUI()
	self.setData()
  }
  
  override func viewDidLayoutSubviews() {
	super.viewDidLayoutSubviews()
  }
  
  func setUI() {
    self.chargeMoneyButton.layer.borderWidth = 1
	self.chargeMoneyButton.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.4).cgColor
	self.chargeMoneyButton.layer.cornerRadius = 10
    self.loadingView.isHidden = true
  }
  
  func setData() {
    
  }
  
  @IBAction func tapOnChargeMoney(_ sender: UIButton) {
	self.show(
	  alertType: .canCancel,
	  title: "안내",
	  content: "본 광고를 시청하시면 모의투자 금액\n1천만원이 보유 금액으로 추가됩니다."
	) { isOk in
	  if isOk {
		Task {
		  await self.loadRewardedAd()
		}
	  } else {
		
	  }
	}
  }
  
  /// Google 보상형 광고 load
  func loadRewardedAd() async {
	do {
      self.loadingIndicator.startAnimating()
      self.loadingView.isHidden = false
	  rewardedAd = try await RewardedAd.load(
		with: "ca-app-pub-3498168241675848/9517873690",
		request: Request()
	  )
	  rewardedAd?.fullScreenContentDelegate = self
	  rewardedAd?.present(from: nil, userDidEarnRewardHandler: {
		print("did earn reward")
	  })
	} catch {
	  print("Rewarded ad failed to load with error: \(error.localizedDescription)")
	}
  }
}

extension MoreViewController: FullScreenContentDelegate {
  /// Tells the delegate that the ad failed to present full screen content.
  func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
	print("Ad did fail to present full screen content.")
	self.show(
	  alertType: .onlyConfirm,
	  content: "Google AD load에 실패하였습니다.\n다시 시도 해주세요.",
	  callBack: nil
	)
  }
  
  /// Tells the delegate that the ad will present full screen content.
  func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
	print("Ad will present full screen content.")
	
	self.loadingIndicator.stopAnimating()
	self.loadingView.isHidden = true
  }
  
  /// Tells the delegate that the ad dismissed full screen content.
  func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
	print("광고 끝! 돈 충전해줄게요!!")
	UserDataManager.userInformation?.userAvailableBalance += 10000000
  }
}
