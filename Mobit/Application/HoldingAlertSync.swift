import CryptoKit
import FirebaseMessaging
import UIKit
import UserNotifications

@MainActor
final class HoldingAlertSync {
  // 앱 실행 중 하나의 순차 전송 작업만 유지한다.
  static let shared = HoldingAlertSync()
  // 사용자가 개인 보유 건의 서버 감시를 직접 선택한 상태다.
  static var enabled: Bool {
    get { UserDefaults.standard.bool(forKey: "holdingAlerts.enabled") }
    set { UserDefaults.standard.set(newValue, forKey: "holdingAlerts.enabled") }
  }
  // 등록 실패는 해제 요청이 성공한 뒤에도 사용자가 다시 선택할 때까지 안내한다.
  private(set) var failure: PushSettingFailure? {
    didSet { NotificationCenter.default.post(name: .pushSettingsChanged, object: nil) }
  }
  // 이전 설정으로 시작한 요청의 실패가 더 최근 선택을 취소하지 않게 한다.
  private var selectionRevision = 0
  // 앱 시작 시 토큰을 기다리는 경우와 사용자가 방금 켠 경우를 구분한다.
  private var awaitingActivation = false
  // 운영에서는 한 API 인스턴스가 설치별 익명 세션을 재사용한다.
  private let sendRPC: (String, UUID, Data) async throws -> Void
  // 이전 설치의 익명 세션으로 해당 설치의 개인 알림만 해제한다.
  private let retirePreviousInstallations: () async throws -> Void
  // 거래 때마다 키체인을 검색하지 않고, 실패한 정리만 다시 시도한다.
  private var checkedPreviousInstallations = false
  // APNs 등록까지 끝난 기기의 최신 FCM 토큰만 사용한다.
  private let registeredToken: () -> String?
  // 전송할 기준은 커밋된 현물·선물 원장에서 다시 읽는다.
  private let loadHoldings: () async throws -> [HoldingAlertSnapshot]
  // 실행 중 요청과 새 체결의 재검토 여부를 분리한다.
  private(set) var syncTask: Task<Void, Never>?
  // 현재 요청을 마친 뒤 최신 원장을 다시 비교할지 기록한다.
  private var requested = false
  // 일시적인 통신 오류 뒤 포그라운드에서 다시 전달한다.
  private var retry: Task<Void, Never>?
  // 포그라운드 복귀 후 앱이 검증한 선물 이력을 다시 전달할 기회다.
  private var verificationSince = Date()

  // 원장 파일의 보호 속성을 유지하면서 테스트용 저장 위치를 격리한다.
  private let journalFolder: () throws -> URL
  // 권한 거부나 철회를 기기 등록 전에 확인한다.
  private let notificationPermission: () async -> UNAuthorizationStatus

  init(
    journalFolder: @escaping () throws -> URL = {
      try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    },
    notificationPermission: @escaping () async -> UNAuthorizationStatus = {
      await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    },
    registeredToken: @escaping () -> String? = {
      Messaging.messaging().apnsToken == nil ? nil : Messaging.messaging().fcmToken
    },
    loadHoldings: @escaping () async throws -> [HoldingAlertSnapshot] = {
      try await Task.detached(priority: .utility) {
        let spot = try UserDataManager.holdingAlertSnapshots()
        let futures = try LocalFuturesAccountRepository.applicationStore().snapshot()
        return try spot + HoldingAlertSnapshot.futures(futures)
      }.value
    },
    retirePreviousInstallations: @escaping () async throws -> Void = HoldingAlertAPI.shared.retirePreviousInstallations,
    sendRPC: @escaping (String, UUID, Data) async throws -> Void = HoldingAlertAPI.shared.rpc
  ) {
    self.journalFolder = journalFolder
    self.notificationPermission = notificationPermission
    self.registeredToken = registeredToken
    self.loadHoldings = loadHoldings
    self.retirePreviousInstallations = retirePreviousInstallations
    self.sendRPC = sendRPC
  }

  private struct DeviceRemovalError: Error {
    // 기기 권한 철회 후 서버 해제 실패는 재시도하되 앱 안의 선택은 보존한다.
    let cause: Error
  }

  struct Entry: Codable {
    // 서버가 비교할 단조 증가 순번과 해당 순번의 체결 시각이다.
    var revision: Int64, date: Date
    // nil은 서버에서 종료해야 하는 보유 건이다.
    var snapshot: HoldingAlertSnapshot?
    // 응답 전에 종료된 앱은 같은 순번으로 재시도한다.
    var pending: Bool
  }

  struct Journal: Codable {
    // 재설치하면 이전 기기의 익명 세션이나 감시 건을 재사용하지 않는다.
    var installation = UUID()
    // 기기 요청과 보유 건 요청 모두 더 큰 순번으로만 갱신한다.
    var revision: Int64 = 0
    // FCM 토큰 원문 대신 변경 감지용 해시만 보관한다.
    var deviceHash: String?
    // 네트워크 요청 전에 예약한 기기 상태와 순번이다.
    var deviceRevision: Int64 = 0
    // 응답 전 종료된 토큰 변경 요청의 재전송 여부다.
    var devicePending = false
    // 전체 원장과 비교해 오프라인 매도와 계좌 초기화도 복구한다.
    var entries: [UUID: Entry] = [:]

    mutating func next() -> Int64 {
      revision = max(revision + 1, TradeTimestampFormatter.timestamp(from: Date()))
      return revision
    }

    mutating func reconcile(_ rows: [HoldingAlertSnapshot], verificationSince: Date?) -> Bool {
      // 원장에서 사라진 UUID를 종료 요청으로 바꾼다.
      let live = Set(rows.map(\.id))
      // 새 순번을 발급한 경우에만 파일을 기록한다.
      var changed = false
      for row in rows {
        if let previous = entries[row.id]?.snapshot, previous.hasSameBasis(as: row) {
          // 분할 매도만으로 새 단계가 발송된 것처럼 리셋하지 않는다.
          guard row.side != "spot", let verificationSince, previous.effectiveAt < verificationSince,
                row.effectiveAt >= verificationSince else { continue }
        }
        let revision = next()
        entries[row.id] = Entry(revision: revision, date: row.effectiveAt, snapshot: row, pending: true)
        changed = true
      }
      for (id, entry) in entries where entry.snapshot != nil && !live.contains(id) {
        let revision = next()
        entries[id] = Entry(revision: revision, date: Date(), snapshot: nil, pending: true)
        changed = true
      }
      return changed
    }
  }

  func setEnabled(_ enabled: Bool) {
    selectionRevision += 1
    Self.enabled = enabled
    awaitingActivation = enabled
    failure = nil
    request(immediate: true)
  }

  func start() {
    for name in [Notification.Name.holdingLedgerChanged, .networkStatusChanged, UIApplication.didBecomeActiveNotification] {
      NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: name, object: nil)
    }
    request(immediate: true)
  }

  @objc private func changed(_ notification: Notification) {
    if notification.name == UIApplication.didBecomeActiveNotification { verificationSince = Date() }
    request(immediate: notification.name != .holdingLedgerChanged)
  }

  func request(immediate: Bool = false) {
    guard immediate || retry == nil else { return }
    requested = true
    retry?.cancel()
    retry = nil
    guard syncTask == nil else { return }
    syncTask = Task {
      defer { syncTask = nil }
      while requested {
        requested = false
        // 비동기 처리 중 사용자가 변경한 설정은 다음 반복에서 반영한다.
        let revision = selectionRevision
        do { try await synchronize() }
        catch {
          guard revision == selectionRevision else { continue }
          // 서버 해제가 실패한 경우에도 원래의 네트워크 오류 코드만 기록한다.
          let cause = (error as? DeviceRemovalError)?.cause ?? error
          Log.warning("개인 알림 동기화 실패: \((cause as? HoldingAlertAPI.ResponseError)?.status ?? (cause as NSError).code)", tag: "Push")
          if Self.enabled && !(error is DeviceRemovalError) {
            Self.enabled = false
            awaitingActivation = false
            failure = .enable
            // 등록 응답이 유실된 경우에도 서버에는 더 높은 순번으로 해제를 전달한다.
            requested = true
            continue
          }
          if failure != .enable { failure = .disable }
          requested = false
          retry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.retry = nil
            if UIApplication.shared.applicationState == .active { self.request() }
          }
        }
      }
    }
  }

  private func synchronize() async throws {
    // 개인 알림을 켜 본 적이 없는 기기는 계정 생성이나 서버 접근을 하지 않는다.
    let folder = try journalFolder()
    // 네트워크 요청 전 보호된 파일에 보유 건과 전송 순번을 보존한다.
    var file = folder.appendingPathComponent("holding-alert-sync.json")
    // 파일 부재만 재설치 후보로 취급한다. 보호된 파일이나 디코딩 실패로 세션을 해제하지 않는다.
    var journal: Journal
    do {
      journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: file))
    } catch CocoaError.fileReadNoSuchFile {
      if !checkedPreviousInstallations {
        try await retirePreviousInstallations()
        checkedPreviousInstallations = true
      }
      guard Self.enabled else {
        if failure == .disable { failure = nil }
        return
      }
      journal = Journal()
    }
    func persist() throws {
      try JSONEncoder().encode(journal).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try file.setResourceValues(values)
    }

    // 앱의 선택과 OS 알림 권한을 함께 확인한다.
    let permission = await notificationPermission()
    // OS에서 알림을 철회하면 서버 등록도 해제한다.
    let active = Self.enabled && permission.allowsPush
    if awaitingActivation && !active { throw URLError(.userAuthenticationRequired) }
    // 활성화하는 동안에만 Firebase 등록 토큰을 사용한다.
    let token = active ? registeredToken() : nil
    if active && token?.isEmpty != false {
      if awaitingActivation { throw URLError(.resourceUnavailable) }
      return
    }
    // 해시가 바뀌면 토큰 교체 또는 해제를 새 순번으로 등록한다.
    let hash = token.map { Data(SHA256.hash(data: Data($0.utf8))).base64EncodedString() }
    if hash != journal.deviceHash {
      journal.deviceHash = hash
      journal.deviceRevision = journal.next()
      journal.devicePending = true
      try persist()
    }
    if active {
      // 계좌 파일 검증과 원장 디코딩은 UI 스레드 밖에서 처리한다.
      let rows = try await loadHoldings()
      if journal.reconcile(rows, verificationSince: verificationSince) { try persist() }
      for (id, entry) in journal.entries.filter({ $0.value.pending }).sorted(by: { $0.value.revision < $1.value.revision }) {
        guard Self.enabled else { return }
        var payload: [String: Any] = ["p_holding": id.uuidString, "p_revision": entry.revision,
                                      "p_closed": entry.snapshot == nil, "p_effective_at": Self.timestamp(entry.date)]
        if let row = entry.snapshot {
          payload["p_exchange"] = row.exchange
          payload["p_market"] = row.market
          payload["p_side"] = row.side
          payload["p_fill_price"] = row.fill
          payload["p_average"] = row.average
          payload["p_units"] = row.units
          payload["p_cost"] = row.cost
          payload["p_margin"] = row.margin
        }
        try await sendRPC("mobit_sync_holding", journal.installation, JSONSerialization.data(withJSONObject: payload))
        if entry.snapshot == nil { journal.entries.removeValue(forKey: id) }
        else { journal.entries[id]?.pending = false }
        try persist()
      }
    }
    // 보유 상태가 최신인 경우에만 기기 토큰을 활성화한다. 해제 요청은 원장 읽기 전에 처리된다.
    if journal.devicePending && (!active || Self.enabled) {
      let target: Any = token.map { $0 as Any } ?? NSNull()
      let payload: [String: Any] = ["p_revision": journal.deviceRevision, "p_token": target]
      do {
        try await sendRPC("mobit_set_push_device", journal.installation, JSONSerialization.data(withJSONObject: payload))
        journal.devicePending = false
        try persist()
      } catch {
        if !active { throw DeviceRemovalError(cause: error) }
        throw error
      }
    }
    if !requested {
      awaitingActivation = false
      if failure == .disable { failure = nil }
    }
  }

  private static func timestamp(_ date: Date) -> String {
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return format.string(from: date)
  }
}

extension Notification.Name {
  // 거래 저장에 성공한 시점만 서버 동기화 대상으로 삼는다.
  static let holdingLedgerChanged = Notification.Name("holdingLedgerChanged")
}
