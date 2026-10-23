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
import FirebaseMessaging
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  // 푸시 화면 이동과 등록한 독립 액션을 Scene 준비 이후 실행한다.
  let pushNotificationOpenHandler = PushNotificationOpenHandler()
  // 최초 ATT 요청이 끝나기 전에 알림 권한 팝업이 겹치지 않도록 한다.
  private var hasCompletedTrackingAuthorization = false
  // ATT 완료와 Scene 활성화가 동시에 이어져도 알림 권한은 한 번만 확인한다.
  private var isCheckingPushAuthorization = false
  
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
	NetworkMonitor.shared.startNetworkMonitoring()
	
	FirebaseApp.configure()
	UNUserNotificationCenter.current().delegate = self
	Messaging.messaging().delegate = self
	
	MobileAds.shared.start(completionHandler: nil)
	#if DEBUG
	// 순서대로, 13mini(H), 13mini(C), 17pro_SJ
	MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [
	  "B9169A22-1CEE-40F7-8128-976F17201053",
	  "7271EAFB-AA2B-4C34-81C5-26499236950A",
	  "14D61EB7-AB38-44EF-943A-E35E1DCC4A0A",
	  "EE77D6AF-5683-4761-A1A7-20521EFC96C9"
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
	  ATTrackingManager.requestTrackingAuthorization { [weak self] status in
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
		DispatchQueue.main.async {
		  self?.hasCompletedTrackingAuthorization = true
		  self?.registerForPushNotificationsIfNeeded()
		}
	  }
	}
  }

  func registerForPushNotificationsIfNeeded() {
	guard hasCompletedTrackingAuthorization,
	  !isCheckingPushAuthorization,
	  UIApplication.shared.applicationState == .active else { return }
	isCheckingPushAuthorization = true
	Task { @MainActor [weak self] in
	  guard let self else { return }
	  defer { self.isCheckingPushAuthorization = false }
	  // 기기 설정에서 변경한 알림 권한도 복귀할 때 다시 읽는다.
	  let notificationCenter = UNUserNotificationCenter.current()
	  // 거부된 권한을 반복 요청하지 않고 허용된 경우에만 APNs에 등록한다.
	  let settings = await notificationCenter.notificationSettings()
	  guard UIApplication.shared.applicationState == .active else { return }
	  do {
		switch settings.authorizationStatus {
		case .notDetermined:
		  guard try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) else { return }
		case .authorized, .provisional, .ephemeral:
		  break
		case .denied:
		  return
		@unknown default:
		  return
		}
		UIApplication.shared.registerForRemoteNotifications()
	  } catch {
		Log.error("푸시 알림 권한 요청에 실패했습니다. code=\((error as NSError).code)", tag: "Push")
	  }
	}
  }

  func application(
	_ application: UIApplication,
	didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
	Messaging.messaging().apnsToken = deviceToken
  }

  func application(
	_ application: UIApplication,
	didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
	Log.error("APNs 기기 등록에 실패했습니다. code=\((error as NSError).code)", tag: "Push")
  }
}

extension AppDelegate: MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
	guard fcmToken?.isEmpty == false else {
	  Log.warning("FCM 기기 등록 토큰이 없습니다.", tag: "Push")
	  return
	}
	Log.info("FCM 기기 등록이 갱신되었습니다.", tag: "Push")
  }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
  func userNotificationCenter(
	_ center: UNUserNotificationCenter,
	willPresent notification: UNNotification,
	withCompletionHandler callBack: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
	callBack([.banner, .list, .sound])
  }

  func userNotificationCenter(
	_ center: UNUserNotificationCenter,
	didReceive response: UNNotificationResponse,
	withCompletionHandler callBack: @escaping () -> Void
  ) {
	// 알림 응답 큐와 관계없이 화면 전환과 완료 처리는 메인 큐에서 이어간다.
	DispatchQueue.main.async { [weak self] in
	  self?.pushNotificationOpenHandler.handle(response)
	  callBack()
	}
  }
}
