import Foundation
import Security

/// 사용자 로그인 화면 없이 이 설치의 인증 세션으로만 개인 알림 RPC를 호출한다.
actor HoldingAlertAPI {
  // 운영은 앱 기본 세션, 테스트는 외부 통신을 차단한 세션으로 실행한다.
  private let transport: URLSession

  init(transport: URLSession = .shared) {
    self.transport = transport
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

  private func storedSession(_ installation: UUID) throws -> Session? {
    // 동일 앱의 동일 프로젝트 토큰만 읽는다.
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: host, kSecAttrAccount as String: installation.uuidString,
                                kSecReturnData as String: true]
    // 잠금 등 Keychain 오류를 새 익명 사용자로 해석하지 않는다.
    var value: CFTypeRef?
    let result = SecItemCopyMatching(query as CFDictionary, &value)
    if result == errSecItemNotFound { return nil }
    guard result == errSecSuccess, let bytes = value as? Data else { throw URLError(.userAuthenticationRequired) }
    return try JSONDecoder().decode(Session.self, from: bytes)
  }

  private func save(_ session: Session, installation: UUID) throws {
    // 회전한 refresh token을 기존 항목에 원자적으로 덮어쓴다.
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: host, kSecAttrAccount as String: installation.uuidString]
    let data = try JSONEncoder().encode(session)
    let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecSuccess { return }
    guard status == errSecItemNotFound else { throw URLError(.cannotWriteToFile) }
    var item = query
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    item[kSecValueData as String] = data
    guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw URLError(.cannotWriteToFile) }
  }

  private func post(_ path: String, data: Data, token: String? = nil) async throws -> Data {
    guard let url = URL(string: "https://" + host + path) else { throw URLError(.badURL) }
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.httpMethod = "POST"
    request.httpBody = data
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(publicKey, forHTTPHeaderField: "apikey")
    if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
    let (responseData, response) = try await transport.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    guard (200..<300).contains(http.statusCode) else {
      throw ResponseError(status: http.statusCode)
    }
    return responseData
  }

  private func accessToken(_ installation: UUID, refresh: Bool) async throws -> String {
    let stored = try storedSession(installation)
    if let stored, !refresh, stored.expires_at > Date().timeIntervalSince1970 + 60 { return stored.access_token }
    let path = stored == nil ? "/auth/v1/signup" : "/auth/v1/token?grant_type=refresh_token"
    let body = stored.map { ["refresh_token": $0.refresh_token] } ?? [:]
    let response = try await post(path, data: JSONEncoder().encode(body))
    let session = try JSONDecoder().decode(Session.self, from: response)
    try save(session, installation: installation)
    return session.access_token
  }

  func rpc(_ name: String, installation: UUID, data: Data) async throws {
    let path = "/rest/v1/rpc/" + name
    let token = try await accessToken(installation, refresh: false)
    do {
      _ = try await post(path, data: data, token: token)
    } catch let error as ResponseError where error.status == 401 {
      _ = try await post(path, data: data, token: accessToken(installation, refresh: true))
    }
  }
}
