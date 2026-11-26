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
  
  // 권한·설정·토큰 변경이 겹치면 순서대로 최신 설정을 반영한다.
  private var topicUpdate: Task<Void, Never>?
  // 같은 토큰으로 이미 완료한 구독은 앱 실행 중 반복하지 않는다.
  private var subscribedTokens: [PushCategory: String] = [:]

  // 같은 항목의 구독 변경이 끝날 때까지 두 번째 입력을 막는다.
  private var topicAttempts: [PushCategory: UUID] = [:]
  // 진행 중인 사용자 요청만 설정 화면에서 잠시 비활성화한다.
  var changingTopics: Set<PushCategory> { Set(topicAttempts.keys) }
  // 실패한 항목의 안내는 해당 사용자가 재시도하거나 해제가 확인될 때 갱신한다.
  private(set) var topicFailures: [PushCategory: PushSettingFailure] = [:]

  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
	NetworkMonitor.shared.startNetworkMonitoring()
	
	FirebaseApp.configure()
    HoldingAlertSync.shared.start()
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
	  // 거부된 권한은 다시 요청하지 않고 이전 구독 해제만 처리한다.
	  let settings = await notificationCenter.notificationSettings()
	  guard UIApplication.shared.applicationState == .active else { return }
	  do {
		switch settings.authorizationStatus {
		case .notDetermined:
		  guard try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) else { return }
		case .authorized, .provisional, .ephemeral:
		  break
		case .denied:
		  guard PushCategory.allCases.contains(where: { $0.hasRequestedSubscription }) else { return }
		@unknown default:
		  return
		}
		UIApplication.shared.registerForRemoteNotifications()
		updatePushSubscriptions()
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
	updatePushSubscriptions()
  }

  func setPushCategory(_ category: PushCategory, enabled: Bool) {
    guard topicAttempts[category] == nil else { return }
    // SDK가 오프라인 구독을 계속 재시도해도 화면은 한 번의 선택에만 응답한다.
    let attempt = UUID()
    topicAttempts[category] = attempt
    category.isEnabled = enabled
    topicFailures[category] = nil
    NotificationCenter.default.post(name: .pushSettingsChanged, object: nil)
    updateTopics(for: category, attempt: attempt)
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 15_000_000_000)
      guard topicAttempts[category] == attempt else { return }
      topicAttempts[category] = nil
      recordTopicFailure(category, enabling: enabled)
      if !enabled && category.hasRequestedSubscription { updateTopics(for: category) }
      NotificationCenter.default.post(name: .pushSettingsChanged, object: nil)
    }
  }

  func updatePushSubscriptions() {
    HoldingAlertSync.shared.request(immediate: true)
    updateTopics()
  }

  private func updateTopics(for target: PushCategory? = nil, attempt: UUID? = nil) {
    // 기기 등록 콜백과 사용자 선택을 같은 순서로 서버에 반영한다.
    let previous = topicUpdate
    topicUpdate = Task { @MainActor in
      await previous?.value
      if let target, topicAttempts[target] != attempt { return }
      defer {
        if let target, topicAttempts[target] == attempt { topicAttempts[target] = nil }
        NotificationCenter.default.post(name: .pushSettingsChanged, object: nil)
      }
      // 기기 설정 복귀 또는 FCM 토큰 교체 후에도 현재 권한을 확인한다.
      let permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
      for category in target.map({ [$0] }) ?? PushCategory.allCases {
        guard topicAttempts[category] == attempt else { continue }
        // 비동기 응답이 도착하기 전의 구독 의도를 보존한다.
        let subscribe = permission.allowsPush && category.isEnabled
        do {
          guard Messaging.messaging().apnsToken != nil, let token = Messaging.messaging().fcmToken,
                !token.isEmpty else {
            if attempt != nil { throw URLError(.resourceUnavailable) }
            continue
          }
          if attempt != nil && (!permission.allowsPush && category.isEnabled || NetworkMonitor.shared.currentAvailability == false) {
            throw URLError(.cannotConnectToHost)
          }
          if subscribe {
            guard subscribedTokens[category] != token else { continue }
            category.hasRequestedSubscription = true
            try await Messaging.messaging().subscribe(toTopic: category.rawValue)
            subscribedTokens[category] = token
          } else if category.hasRequestedSubscription {
            subscribedTokens[category] = nil
            try await Messaging.messaging().unsubscribe(fromTopic: category.rawValue)
            category.hasRequestedSubscription = false
          }
          if !subscribe && !category.isEnabled && topicFailures[category] == .disable { topicFailures[category] = nil }
        } catch {
          Log.warning("푸시 구독 상태 갱신 실패: \((error as NSError).code)", tag: "Push")
          guard topicAttempts[category] == attempt else { continue }
          recordTopicFailure(category, enabling: category.isEnabled && (subscribe || attempt != nil))
        }
      }
    }
  }

  private func recordTopicFailure(_ category: PushCategory, enabling: Bool) {
    if enabling {
      category.isEnabled = false
      subscribedTokens[category] = nil
      topicFailures[category] = .enable
      // Firebase에 이미 전달된 구독도 연결이 돌아오면 해제한다.
      if category.hasRequestedSubscription { updateTopics(for: category) }
    } else if topicFailures[category] != .enable {
      topicFailures[category] = .disable
    }
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
	updatePushSubscriptions()
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
