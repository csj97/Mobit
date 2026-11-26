import Foundation
import Security

/// 사용자 로그인 화면 없이 이 설치의 인증 세션으로만 개인 알림 RPC를 호출한다.
actor HoldingAlertAPI {
  // 설치 확인과 보유 건 전송이 같은 운영 인증 저장소를 사용한다.
  static let shared = HoldingAlertAPI()
  // 운영은 앱 기본 세션, 테스트는 외부 통신을 차단한 세션으로 실행한다.
  private let transport: URLSession

  // 테스트 세션과 운영 세션을 서로 다른 키체인 서비스에 보관한다.
  private let keychainService: String

  init(transport: URLSession = .shared, keychainService: String = "bxuirfkxptypevhfnqrx.supabase.co") {
    self.transport = transport
    self.keychainService = keychainService
  }
  // 이 키는 앱 배포용 공개 키이며 데이터 접근 범위는 세션과 서버 RPC가 결정한다.
  private let publicKey = "sb_publishable_PoLwzRMq07B2k-fqabcClA_T-omdkIj"
  // 익명 세션은 프로젝트별로 구분하고 기기 백업에 포함하지 않는다.
  private let host = "bxuirfkxptypevhfnqrx.supabase.co"

  private struct Session: Codable {
    // 서버 RPC를 인증하는 단기 JWT다.
    let access_token: String
    // 같은 익명 사용자로 세션을 연장한다.
    let refresh_token: String
    // 만료 직전 갱신할 기준 시각이다.
    let expires_at: TimeInterval
  }

  struct ResponseError: Error {
    // 운영 로그에는 토큰과 요청 본문 대신 상태 코드만 남긴다.
    let status: Int
  }

  private func sessionQuery(_ installation: UUID) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService,
     kSecAttrAccount as String: installation.uuidString]
  }

  private func storedSession(_ installation: UUID) throws -> Session? {
    // 동일 앱의 동일 프로젝트 토큰만 읽는다.
    var query = sessionQuery(installation)
    query[kSecReturnData as String] = true
    // 잠금 등 Keychain 오류를 새 익명 사용자로 해석하지 않는다.
    var value: CFTypeRef?
    let result = SecItemCopyMatching(query as CFDictionary, &value)
    if result == errSecItemNotFound { return nil }
    guard result == errSecSuccess, let bytes = value as? Data else { throw URLError(.userAuthenticationRequired) }
    return try JSONDecoder().decode(Session.self, from: bytes)
  }

  private func save(_ session: Session, installation: UUID) throws {
    // 회전한 refresh token을 기존 항목에 원자적으로 덮어쓴다.
    let query = sessionQuery(installation)
    let data = try JSONEncoder().encode(session)
    let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecSuccess { return }
    guard status == errSecItemNotFound else { throw URLError(.cannotWriteToFile) }
    var item = query
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    item[kSecValueData as String] = data
    guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw URLError(.cannotWriteToFile) }
  }

  private struct ExpiredSession: Error {}

  private func post(_ path: String, data: Data, token: String? = nil) async throws -> Data {
    guard let url = URL(string: "https://" + host + path) else { throw URLError(.badURL) }
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.httpMethod = "POST"
    request.httpBody = data
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(publicKey, forHTTPHeaderField: "apikey")
    if path.hasPrefix("/auth/v1/") { request.setValue("2024-01-01", forHTTPHeaderField: "X-Supabase-Api-Version") }
    if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
    let (responseData, response) = try await transport.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    guard (200..<300).contains(http.statusCode) else {
      if path.hasPrefix("/auth/v1/token"), [400, 401, 403, 404].contains(http.statusCode),
         let fields = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any],
         let code = (fields["error_code"] ?? fields["code"]) as? String,
         ["refresh_token_not_found", "refresh_token_already_used", "session_not_found", "session_expired", "user_not_found"].contains(code) {
        throw ExpiredSession()
      }
      throw ResponseError(status: http.statusCode)
    }
    return responseData
  }

  private func accessToken(_ installation: UUID, session stored: Session?, refresh: Bool) async throws -> String {
    if let stored, !refresh, stored.expires_at > Date().timeIntervalSince1970 + 60 { return stored.access_token }
    let path = stored == nil ? "/auth/v1/signup" : "/auth/v1/token?grant_type=refresh_token"
    let body = stored.map { ["refresh_token": $0.refresh_token] } ?? [:]
    let response = try await post(path, data: JSONEncoder().encode(body))
    let session = try JSONDecoder().decode(Session.self, from: response)
    try save(session, installation: installation)
    return session.access_token
  }

  func rpc(_ name: String, installation: UUID, data: Data) async throws {
    try await rpc(name, installation: installation, data: data, session: storedSession(installation))
  }

  private func rpc(_ name: String, installation: UUID, data: Data, session: Session?) async throws {
    let path = "/rest/v1/rpc/" + name
    let token = try await accessToken(installation, session: session, refresh: false)
    do {
      _ = try await post(path, data: data, token: token)
    } catch let error as ResponseError where error.status == 401 {
      guard let current = try storedSession(installation) else { throw error }
      _ = try await post(path, data: data, token: accessToken(installation, session: current, refresh: true))
    }
  }

  func retirePreviousInstallations() async throws {
    // 로컬 설치 파일이 없을 때만 호출하며 기존 버전이 저장한 개인 알림 세션도 찾는다.
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService,
                                kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
    // 접근 실패와 키체인에 세션이 없는 최초 설치를 구분한다.
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return }
    guard status == errSecSuccess, let items = result as? [[String: Any]] else { throw URLError(.cannotOpenFile) }
    for item in items {
      guard let account = item[kSecAttrAccount as String] as? String, let installation = UUID(uuidString: account),
            let session = try storedSession(installation) else { continue }
      do {
        try await rpc("mobit_retire_holding_installation", installation: installation, data: Data("{}".utf8), session: session)
      } catch is ExpiredSession {
        // 인증 복구가 불가능하면 서버의 FCM 무효 토큰 해제에 맡긴다.
        Log.warning("만료된 이전 설치의 개인 알림 세션", tag: "Push")
      }
      // 통신 실패 시에는 키체인을 보존해 다음 실행에도 같은 세션으로 재시도한다.
      let deletion = SecItemDelete(sessionQuery(installation) as CFDictionary)
      guard deletion == errSecSuccess || deletion == errSecItemNotFound else { throw URLError(.cannotWriteToFile) }
    }
  }
}
