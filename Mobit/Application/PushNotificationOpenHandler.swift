import UserNotifications

enum PushNotificationDestination: String, CaseIterable {
  case exchange, investment, news, more
}

private enum PushNotificationCommand {
  case route(PushNotificationDestination)
  case action(identifier: String, data: [String: String])

  init?(userInfo: [AnyHashable: Any], registeredActions: Set<String>) {
    // type을 생략한 기존 destination 메시지는 화면 이동으로 해석한다.
    let type = (userInfo["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard userInfo["type"] == nil || type != nil else { return nil }
    switch type {
    case nil, "route":
      guard let value = userInfo["destination"] as? String,
            let destination = PushNotificationDestination(
              rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            ) else { return nil }
      self = .route(destination)
    case "action":
      guard let value = userInfo["action"] as? String else { return nil }
      // 앱에 등록한 이름만 실행하며 분석에도 같은 식별자를 사용한다.
      let identifier = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard identifier.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) != nil,
            registeredActions.contains(identifier) else { return nil }
      // 실행 제어 키와 FCM 메타데이터를 제외한 커스텀 문자열만 액션에 전달한다.
      let data = userInfo.reduce(into: [String: String]()) { result, item in
        guard let key = item.key as? String, let value = item.value as? String,
              !["type", "action", "destination", "campaign_id", "aps", "from", "collapse_key", "message_type"].contains(key),
              !key.hasPrefix("gcm."), !key.hasPrefix("google.") else { return }
        result[key] = value
      }
      self = .action(identifier: identifier, data: data)
    default:
      return nil
    }
  }
}

@MainActor
final class PushNotificationOpenHandler {
  // Scene 연결과 알림 응답이 같은 메시지를 전달해도 한 번만 처리한다.
  private var openedNotificationIDs = Set<String>()
  // 화면 이동은 최신 클릭을 따르고, 독립 액션은 클릭 순서대로 보관한다.
  private var pendingCommands: [PushNotificationCommand] = []
  // 기능별 액션을 이름과 처리 함수로 등록해 화면 라우팅과 독립적으로 실행한다.
  private let actionHandlers: [String: ([String: String]) -> Void]
  // 화면 전환과 별개로 실제 알림 클릭만 분석에 전달한다.
  private let trackOpen: (String, String?, String?) -> Void
  // Scene 준비·활성 상태가 충족된 실행 구간에서만 연결한다.
  private var routeCallBack: ((PushNotificationDestination) -> Void)?

  init(
    actionHandlers: [String: ([String: String]) -> Void] = [:],
    trackOpen: @escaping (String, String?, String?) -> Void = {
      MobitAnalyticsUtil.sendPushOpenEvent(destination: $0, action: $1, campaignID: $2)
    }
  ) {
    self.actionHandlers = actionHandlers
    self.trackOpen = trackOpen
  }

  func resume(routeCallBack: @escaping (PushNotificationDestination) -> Void) {
    self.routeCallBack = routeCallBack
    performPendingCommands()
  }

  func suspend() {
    routeCallBack = nil
  }

  func handle(_ response: UNNotificationResponse) {
    handle(
      userInfo: response.notification.request.content.userInfo,
      notificationID: response.notification.request.identifier,
      actionIdentifier: response.actionIdentifier,
      isRemoteNotification: response.notification.request.trigger is UNPushNotificationTrigger
    )
  }

  func handle(
    userInfo: [AnyHashable: Any],
    notificationID: String,
    actionIdentifier: String,
    isRemoteNotification: Bool
  ) {
    guard isRemoteNotification, actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
    // 시스템의 요청 ID 대신 FCM 메시지 ID가 있으면 두 진입 경로에서 공유한다.
    let messageID = (userInfo["gcm.message_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? notificationID
    guard !messageID.isEmpty, openedNotificationIDs.insert(messageID).inserted else { return }
    // payload 해석은 실행과 분리하며 등록하지 않은 명령은 일반 앱 열기로 처리한다.
    let command = PushNotificationCommand(userInfo: userInfo, registeredActions: Set(actionHandlers.keys))
    switch command {
    case .route(let destination):
      trackOpen(destination.rawValue, nil, userInfo["campaign_id"] as? String)
    case .action(let identifier, _):
      trackOpen("app", identifier, userInfo["campaign_id"] as? String)
    case nil:
      trackOpen("app", nil, userInfo["campaign_id"] as? String)
    }
    pendingCommands.removeAll {
      if case .route = $0 { return true }
      return false
    }
    if let command { pendingCommands.append(command) }
    performPendingCommands()
  }

  private func performPendingCommands() {
    while let routeCallBack, !pendingCommands.isEmpty {
      // 실행 전에 소비해 재진입하거나 Scene이 다시 활성화돼도 중복 실행하지 않는다.
      let command = pendingCommands.removeFirst()
      switch command {
      case .route(let destination):
        routeCallBack(destination)
      case .action(let identifier, let data):
        actionHandlers[identifier]?(data)
      }
    }
  }
}
