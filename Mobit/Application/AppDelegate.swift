//
//  AppDelegate.swift
//  Mobit
//
//  Created by 조성재 on 7/10/24.
//

import AdSupport
import AppTrackingTransparency
import GoogleMobileAds
import UIKit
import FirebaseCore

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
	NetworkMonitor.shared.startNetworkMonitoring()
	
	FirebaseApp.configure()
	
	MobileAds.shared.start(completionHandler: nil)
	#if DEBUG
	// 순서대로, 13mini(H), 13mini(C), 17pro_SJ
	MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [
	  "B9169A22-1CEE-40F7-8128-976F17201053",
	  "7271EAFB-AA2B-4C34-81C5-26499236950A",
	  "14D61EB7-AB38-44EF-943A-E35E1DCC4A0A"
	]
	#endif
	
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
  
  /// 세로 방향 고정
  func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
	return UIInterfaceOrientationMask.portrait
  }
  
  /// App의 첫 실행 여부
  func checkFirstLaunch() {
	UserDataManager.seedInitialUserInformationIfNeeded()
  }
  
  func requestATT() {
	// 앱 추적 권한 요청
	DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
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
