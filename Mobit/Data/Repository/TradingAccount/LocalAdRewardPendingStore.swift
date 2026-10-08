import Foundation

final class LocalAdRewardPendingStore: AdRewardPendingStore {
  private struct Snapshot: Codable {
    let schemaVersion: Int
    let claims: [AdRewardClaim]
  }

  private let fileURL: URL?
  private let write: (Data, URL) throws -> Void

  init(fileURL: URL? = nil, write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
    self.fileURL = fileURL
    self.write = write
  }

  private func resolvedURL() throws -> URL {
    if let fileURL { return fileURL }
    return try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true)
      .appendingPathComponent("AdRewards", isDirectory: true).appendingPathComponent("pending.json")
  }

  // 로컬 저장소에서 지급 대기 중인 광고 보상 요청을 읽는다.
  func fetchClaims() throws -> [AdRewardClaim] {
    let data: Data
    do { data = try Data(contentsOf: resolvedURL()) }
    catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
    let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
    guard snapshot.schemaVersion == 1 else { throw AdRewardError.invalidStoredData }
    try AdRewardClaim.validateCollection(snapshot.claims)
    return snapshot.claims
  }

  func save(_ claims: [AdRewardClaim]) throws {
    try AdRewardClaim.validateCollection(claims)
    let data = try JSONEncoder().encode(Snapshot(schemaVersion: 1, claims: claims))
    let url = try resolvedURL()
    var directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try directory.setResourceValues(values)
    try write(data, url)
  }
}
