//
//  UserDataManager.swift
//  Mobit
//
//  Created by 조성재 on 1/26/25.
//

import Foundation

class UserDataManager: NSObject {
  
  /// 앱 설치 후, 첫 실행 여부
  static var isFirstLaunch: Bool {
    get {
	  let defaults = UserDefaults.standard
	  if defaults.object(forKey: "isFirstLaunch") == nil {
		return true
	  }
	  return defaults.bool(forKey: "isFirstLaunch")
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "isFirstLaunch")
    }
  }
  
  /// 사용자 직전 로그인 시간
  static var userAvailableBalance: Double {
    get {
      let defaults = UserDefaults.standard
      let data = defaults.double(forKey: "user-balance")
      return data
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "user-balance")
    }
  }
  
  /// 사용자가 매수한 코인 정보
//  static var userCryptoList: [MobitUserInformation.UserCrypto]? {
//    get {
//      let defaults = UserDefaults.standard
//      let data = defaults.object(forKey: "user-crypto-list") as? [MobitUserInformation.UserCrypto]
//      return data
//    }
//    set {
//      UserDefaults.standard.set(newValue, forKey: "user-crypto-list")
//    }
//  }
  
  static var userInformation: MobitUserInformation? {
    get {
      let defaults = UserDefaults.standard
      if let data = defaults.data(forKey: "user-information") {
        let decodedData = try? JSONDecoder().decode(MobitUserInformation.self, from: data)
        return decodedData
      }
      return nil
    }
    set {
      let defaults = UserDefaults.standard
      if let encodedData = try? JSONEncoder().encode(newValue) {
        defaults.set(encodedData, forKey: "user-information")
      } else {
        defaults.removeObject(forKey: "user-information")
      }
    }
  }
  
  /// 매수한 코인 목록
  static var bidCryptoList: [CryptoTransaction?] {
	get {
	  let defaults = UserDefaults.standard
	  if let data = defaults.data(forKey: "mobit-crypto-transaction") {
		// TODO: 이미 같은 코인 매수 히스토리가 있다면, 평균 금액을 산정해서 업데이트 필요
		let decodedData = try? JSONDecoder().decode([CryptoTransaction?].self, from: data)
		return decodedData ?? []
	  }
	  return []
	}
	set {
	  let defaults = UserDefaults.standard
	  if let encodedData = try? JSONEncoder().encode(newValue) {
		defaults.set(encodedData, forKey: "mobit-crypto-transaction")
	  } else {
		defaults.removeObject(forKey: "mobit-crypto-transaction")
	  }
	}
  }
  
  // TODO: 매도를 하고 나면, bidCryptoList에서 제거하고 History에 따로 담기 (최종 투자 내역)
}
