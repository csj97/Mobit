//
//  AppDataManager.swift
//  Mobit
//
//  Created by 조성재 on 9/3/25.
//

import Foundation
import FirebaseDatabase

final class AppDataManager {
  static let shared = AppDataManager()
  
  private(set) var cachedKRWCMCList: [FirebaseCMCResponse] = []
  private(set) var cachedBTCCMCList: [FirebaseCMCResponse] = []
  private let firebaseDB = Database.database().reference()
  
  /// 현재(또는 지정) 거래소의 KRW·BTC CMC 정보를 함께 갱신한다.
  func refreshCMCData(for exchange: Exchange = ExchangeSelectionStore.currentExchange) {
	downloadFromFirebase(child_path: "cryptoInformations", exchange: exchange)
	downloadFromFirebase(child_path: "btc_cryptoInformations", exchange: exchange)
  }

  /// 파이어베이스에서 거래소별 CMC 코인 정보 가져오기
  /// 경로: CMCResponse/exchanges/{거래소}/{child_path}
  func downloadFromFirebase(
	child_path: String,
	exchange: Exchange = ExchangeSelectionStore.currentExchange
  ) {
	let path = firebaseDB
	  .child("CMCResponse")
	  .child("exchanges")
	  .child(exchange.rawValue)
	  .child(child_path)

	path.observeSingleEvent(of: .value) { snapshot in
	  guard let value = snapshot.value as? [String: [String: Any]] else {
		Log.error("❌ CMC 데이터 변환 실패 exchange=\(exchange.rawValue) path=\(child_path)")
		return
	  }
	  Log.info("✅ \(value.values.count)개 CMC 데이터 불러오기 성공 exchange=\(exchange.rawValue) path=\(child_path)")

	  if child_path == "cryptoInformations" {
		self.cachedKRWCMCList = value.compactMap { self.parseToCryptoData(dict: $0.value) }
	  } else {
		self.cachedBTCCMCList = value.compactMap { self.parseToCryptoData(dict: $0.value) }
	  }

	}
  }
  
  /// Data Model에 맞게 디코딩
  func parseToCryptoData(dict: [String: Any]) -> FirebaseCMCResponse? {
	do {
	  // Step 1. dict → jsonData
	  let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
	  
	  // Step 2. jsonData → DTO
	  let decoder = JSONDecoder()
	  decoder.dateDecodingStrategy = .iso8601
	  let dto = try decoder.decode(FirebaseCMCResponseDTO.self, from: jsonData)
	  
	  // Step 3. DTO → Domain
	  return dto.toDomain()
	  
	} catch {
	  Log.error("❌ 디코딩 실패: \(error)")
	  return nil
	}
  }
}
