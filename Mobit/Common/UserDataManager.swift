//
//  UserDataManager.swift
//  Mobit
//
//  Created by 조성재 on 1/26/25.
//

import Foundation
import RxSwift

class UserDataManager: NSObject {
  static let userAvailableBalanceSubject = BehaviorSubject<Double?>(value: nil)
  static var userAvailableBalanceObservable: Observable<Double?> {
	  return userAvailableBalanceSubject.asObservable()
  }
  
  private static let userCryptoListSubject = BehaviorSubject<[CryptoTransactionDataModel]?>(value: [])
  static var userCryptoListObservable: Observable<[CryptoTransactionDataModel]?> {
	return userCryptoListSubject.asObservable()
  }

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
  
  /// 사용자 즐겨찾기 (marketName을 String 배열로 저장)
  static var userFavoriteList: [String] {
	get {
	  let defaults = UserDefaults.standard
	  if let data = defaults.stringArray(forKey: "user-favorite-list") {
		return data
	  }
	  return []
	}
	set {
	  UserDefaults.standard.set(newValue, forKey: "user-favorite-list")
	}
  }
  
  /// 거래내역만 저장
  static var userTransactionList: [TransactionInfo]? {
	get {
	  let defaults = UserDefaults.standard
	  if let data = defaults.data(forKey: "user-transaction-list") {
		let decodedData = try? JSONDecoder().decode([TransactionInfo].self, from: data)
		return decodedData
	  }
	  return []
	}
	set {
	  let defaults = UserDefaults.standard
	  if let encodedData = try? JSONEncoder().encode(newValue) {
		defaults.set(encodedData, forKey: "user-transaction-list")
	  }
	}
  }
  
  /// 유효한 거래내역만 저장 (보유하고 있는 매수 & 매도 내역에 대해서만)
  static var userValidTransactionList: [ValidTransactionInfo]? {
	get {
	  let defaults = UserDefaults.standard
	  if let data = defaults.data(forKey: "user-valid-transaction-list") {
		let decodedData = try? JSONDecoder().decode([ValidTransactionInfo].self, from: data)
		return decodedData
	  }
	  return []
	}
	set {
	  let defaults = UserDefaults.standard
	  if let encodedData = try? JSONEncoder().encode(newValue) {
		defaults.set(encodedData, forKey: "user-valid-transaction-list")
	  }
	}
  }
  
  /// 사용자가 매수한 코인 정보 (현재)
  static var userCryptoList: [CryptoTransactionDataModel]? {
    get {
      let defaults = UserDefaults.standard
	  if let data = defaults.data(forKey: "user-crypto-list") {
		var decodedData = (try? JSONDecoder().decode([CryptoTransactionDataModel].self, from: data)) ?? []
		for i in decodedData.indices {
		  // identifier 없으면 새 UUID 부여
		  if decodedData[i].identifier == UUID() { // 초기값이 Optional → nil 처리
			decodedData[i].identifier = UUID()
		  }
		}
		return decodedData
	  }
	  return []
    }
    set {
	  let defaults = UserDefaults.standard
	  var newValueWithUUID = newValue ?? []
	  for i in newValueWithUUID.indices {
		  if newValueWithUUID[i].identifier == UUID() { // 초기값이면 새 UUID
			newValueWithUUID[i].identifier = UUID()
		  }
	  }
	  if let encodedData = try? JSONEncoder().encode(newValue) {
		defaults.set(encodedData, forKey: "user-crypto-list")
	  }
	  userCryptoListSubject.onNext(newValueWithUUID)
    }
  }
  
  /// 사용자 거래 내역 (실현손익 P&L 확인 가능한 목록)
  /// 매수 금액, 매도 금액, 매도 시간, 실현 손익
  static var userPNLHistory: [UserPNLHistoryModel]? {
	get {
	  let defaults = UserDefaults.standard
	  if let data = defaults.data(forKey: "user-pnl-list") {
		let decodedData = try? JSONDecoder().decode([UserPNLHistoryModel].self, from: data)
		return decodedData
	  }
	  return []
	}
	set {
	  let defaults = UserDefaults.standard
	  if let encodedData = try? JSONEncoder().encode(newValue) {
		defaults.set(encodedData, forKey: "user-pnl-list")
	  }
	  // userCryptoListSubject.onNext(newValue)
	}
  }
  
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
		self.userAvailableBalanceSubject.onNext(newValue?.userAvailableBalance)
      }
    }
  }
  
}
