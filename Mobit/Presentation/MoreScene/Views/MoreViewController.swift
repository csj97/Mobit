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
  
  @IBOutlet weak var naviBar: UIView!
  @IBOutlet weak var chargeMoneyButton: NeumorphicButton!
  @IBOutlet weak var userNoticeButton: NeumorphicButton!
  @IBOutlet weak var investInitButton: NeumorphicButton!
  @IBOutlet weak var loadingIndicator: UIActivityIndicatorView!
  @IBOutlet weak var loadingView: UIView!
  @IBOutlet weak var versionLabel: UILabel!
  
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
	self.navigationController?.navigationBar.isHidden = true
    self.naviBar.layer.applyShadow(color: .lightGray, alpha: 0.3, x: 0, y: 3, blur: 12)
    
	self.makeBorderLine(self.chargeMoneyButton)
	self.makeBorderLine(self.userNoticeButton)
	self.makeBorderLine(self.investInitButton)
	self.loadingView.isHidden = true
  }
  
  func setData() {
	self.updateVersionLabel()
  }
  
  func makeBorderLine(_ button: UIButton) {
	button.layer.borderWidth = 1
    button.layer.borderColor = UIColor.clear.cgColor
	button.layer.cornerRadius = 16
  }
  
  @IBAction func tapOnChargeMoney(_ sender: NeumorphicButton) {
	
	MobitAnalyticsUtil.sendScreen(event: .more_charge)
	
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
  
  @IBAction func tapOnUserNoticeButton(_ sender: NeumorphicButton) {
	let noticeContent = """
   사용자는 이 앱에서 실제 금전적인 자산을 입금하거나 출금할 수 없으며,
   모든 거래 및 수익/손실은 가상의 수치일 뿐, 
   
   ⭐️ 현실의 자산에 어떤 영향도 미치지 않습니다.
   
   앱 내 정보 및 결과는 학습 또는 참고 목적으로 제공되며,
   실제 투자 판단의 근거로 삼을 수 없으며, 
   
   ⭐️ 그로 인해 발생한 어떠한 손실에 대해서도 본 앱은 책임지지 않습니다.
   """
	
	MobitAnalyticsUtil.sendScreen(event: .more_notice)
	
	self.show(
	  alertType: .onlyConfirm,
	  titleAlignment: .center,
	  title: "🚨 사용자 안내사항 🚨",
	  content: noticeContent,
	  callBack: nil
	)
  }
  
  @IBAction func tapOnInvestInitButton(_ sender: NeumorphicButton) {
	
	let noticeContent = """
	투자하신 거래 내역이 모두 초기화되며,
	보유 금액도 0원이 됩니다.
	"""
	
	MobitAnalyticsUtil.sendScreen(event: . more_init_data)
	
	self.show(
	  alertType: .canCancel,
	  titleAlignment: .center,
	  title: "🚨 투자내역 초기화 안내 🚨",
	  content: noticeContent
	) { isPositive in
	  if isPositive {
		UserDataManager.userInformation?.userAvailableBalance = 0
		UserDataManager.userCryptoList = []
		UserDataManager.userTransactionList = []
		UserDataManager.userValidTransactionList = []
		
		self.show(alertType: .onlyConfirm, content: "초기화 되었습니다.", callBack: nil)
	  }
	}
  }
  
  /// 현재 사용 중인 앱 버전
  func updateVersionLabel() {
	let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    let versionParts = currentVersion.split(separator: ".")
    var fixedVersion = currentVersion
    
    if versionParts.count == 2 {
        // 1.2 → 1.2.0 으로 변환
        fixedVersion = currentVersion + ".0"
    }
    
    self.versionLabel.text = "앱 버전: \(fixedVersion)"
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
	self.show(alertType: .onlyConfirm, content: "충전이 완료 되었습니다.", callBack: nil)
	UserDataManager.userInformation?.userAvailableBalance += 10000000
  }
}
