import Foundation
import UserNotifications

enum PushCategory: String, CaseIterable {
  case announcement = "mobit_announcements"
  case priceAlert = "mobit_price_alerts"

  // 사용자가 변경한 항목만 저장해 최초 권한 허용 시 두 토픽을 기본 선택한다.
  var isEnabled: Bool {
    get { UserDefaults.standard.object(forKey: "push.enabled." + rawValue) as? Bool ?? true }
    nonmutating set { UserDefaults.standard.set(newValue, forKey: "push.enabled." + rawValue) }
  }

  // 이전 버전의 공지 구독도 권한 철회나 스위치 변경 때 해제할 수 있게 한다.
  private var subscriptionKey: String {
    self == .announcement ? "mobitPushAnnouncementSubscriptionRequested" : "mobitPushPriceAlertSubscriptionRequested"
  }

  // 구독 요청 직후 앱이 종료되어도 다음 실행 때 서버와 설정을 동기화한다.
  var hasRequestedSubscription: Bool {
    get { UserDefaults.standard.bool(forKey: subscriptionKey) }
    nonmutating set { UserDefaults.standard.set(newValue, forKey: subscriptionKey) }
  }
}

extension UNAuthorizationStatus {
  // iOS가 알림 전달을 허용한 상태에서만 토픽 구독과 스위치를 활성화한다.
  var allowsPush: Bool {
    self == .authorized || self == .provisional || self == .ephemeral
  }
}

enum PushSettingFailure {
  case enable, disable
}

extension Notification.Name {
  // 알림 설정 변경과 기기별 동기화 오류를 열린 설정 화면에 전달한다.
  static let pushSettingsChanged = Notification.Name("pushSettingsChanged")
}
