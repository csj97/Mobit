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
  
  private(set) var cachedCMCList: [FirebaseCMCResponse] = []
  private let firebaseDB = Database.database().reference()
  
  /// 파이어베이스에서 CMC 코인 정보 가져오기
  func downloadFromFirebase() {
	let path = firebaseDB.child("CMCResponse").child("cryptoInformations")
	
	path.observeSingleEvent(of: .value) { snapshot in
	  guard let value = snapshot.value as? [String: [String: Any]] else {
		Log.error("❌ 데이터 변환 실패")
		return
	  }
	  Log.info("✅ \(value.values.count)개 데이터 불러오기 성공")
	  
	  self.cachedCMCList = value.compactMap { self.parseToCryptoData(dict: $0.value) }
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
