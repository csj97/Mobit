//
//  AppDelegate.swift
//  Mobit
//
//  Created by 조성재 on 7/10/24.
//

import AdSupport
import AppTrackingTransparency
import UIKit
import GoogleMobileAds

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    
	MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [ "26842ce77d193c02e94e1e2826d0121f", "9c171ef9b1742b705cca840364271e44" ]
	MobileAds.shared.start(completionHandler: nil)
	
	requestATT()
    checkFirstLaunch()
    return true
  }

  // MARK: UISceneSession Lifecycle

  func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
  }

  func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
  }

  /// App의 첫 실행 여부
  func checkFirstLaunch() {
    // 첫 실행이면 천만원 설정
    if UserDataManager.isFirstLaunch {
	  UserDataManager.isFirstLaunch = false
	  UserDataManager.userInformation = MobitUserInformation(
		userAvailableBalance: 10_000_000
	  )
	} else {
	  guard let userInfo = UserDataManager.userInformation else { return }
	  print("지금 내돈 : \(userInfo.userAvailableBalance)")
	}
  }
  
  func requestATT() {
	// 앱 추적 권한 요청
	DispatchQueue.main.async {
	  ATTrackingManager.requestTrackingAuthorization { status in
		switch status {
		case .authorized:           // 허용됨
		  print("Authorized")
		  print("IDFA = \(ASIdentifierManager.shared().advertisingIdentifier)")
		case .denied:               // 거부됨
		  print("Denied")
		case .notDetermined:        // 결정되지 않음
		  print("Not Determined")
		case .restricted:           // 제한됨
		  print("Restricted")
		@unknown default:           // 알려지지 않음
		  print("Unknow")
		}
	  }
	}
  }
}

