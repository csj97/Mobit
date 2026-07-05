//
//  UserDataManager.swift
//  Mobit
//
//  Created by 조성재 on 1/26/25.
//

import Foundation
import RxSwift

class UserDataManager: NSObject {
  struct TradingViewChartSettings: Codable, Equatable {
	enum Interval: String, Codable {
	  case minute15 = "15"
	  case hour1 = "60"
	  case hour4 = "240"
	  case day1 = "1D"
	}
	
	enum Theme: String, Codable {
	  case light
	  case dark
	}
	
	var interval: Interval
	var theme: Theme
	var showsToolbar: Bool
	
	static let `default` = TradingViewChartSettings(
	  interval: .hour1,
	  theme: .light,
	  showsToolbar: true
	)
  }
  
  enum MarketColorTheme: String, Codable {
	case riseRedFallBlue
	case riseGreenFallRed
  }

  enum Keys {
	static let isFirstLaunch = "isFirstLaunch"
	static let userFavoriteList = "user-favorite-list"
	static let userTransactionList = "user-transaction-list"
	static let userValidTransactionList = "user-valid-transaction-list"
	static let userCryptoList = "user-crypto-list"
	static let userPNLHistory = "user-pnl-list"
	static let userInformation = "user-information"
	static let tradingViewChartSettings = "tradingview-chart-settings"
	static let marketColorTheme = "market-color-theme"
  }

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
	  if defaults.object(forKey: Keys.isFirstLaunch) == nil {
		return true
	  }
	  return defaults.bool(forKey: Keys.isFirstLaunch)
    }
    set {
      UserDefaults.standard.set(newValue, forKey: Keys.isFirstLaunch)
    }
  }
  
  /// 사용자 즐겨찾기 (marketName을 String 배열로 저장)
  static var userFavoriteList: [String] {
	get {
	  let defaults = UserDefaults.standard
	  if let data = defaults.stringArray(forKey: Keys.userFavoriteList) {
		return data
	  }
	  return []
	}
	set {
	  UserDefaults.standard.set(newValue, forKey: Keys.userFavoriteList)
	}
  }
  
  /// 거래내역만 저장
  static var userTransactionList: [TransactionInfo]? {
	get {
	  let defaults = UserDefaults.standard
	  if let data = defaults.data(forKey: Keys.userTransactionList) {
		let decodedData = try? JSONDecoder().decode([TransactionInfo].self, from: data)
		return decodedData
	  }
	  return []
	}
	set {
	  let defaults = UserDefaults.standard
	  if let encodedData = try? JSONEncoder().encode(newValue) {
		defaults.set(encodedData, forKey: Keys.userTransactionList)
	  }
	}
  }
  
  /// 유효한 거래내역만 저장 (보유하고 있는 매수 & 매도 내역에 대해서만)
  static var userValidTransactionList: [ValidTransactionInfo]? {
	get {
	  let defaults = UserDefaults.standard
	  if let data = defaults.data(forKey: Keys.userValidTransactionList) {
		let decodedData = try? JSONDecoder().decode([ValidTransactionInfo].self, from: data)
		return decodedData
	  }
	  return []
	}
	set {
	  let defaults = UserDefaults.standard
	  if let encodedData = try? JSONEncoder().encode(newValue) {
		defaults.set(encodedData, forKey: Keys.userValidTransactionList)
	  }
	}
  }
  
  /// 사용자가 매수한 코인 정보 (현재)
  static var userCryptoList: [CryptoTransactionDataModel]? {
	get {
	  let defaults = UserDefaults.standard
	  guard let data = defaults.data(forKey: Keys.userCryptoList) else { return [] }
	  
	  do {
		let decodedData = try JSONDecoder().decode([CryptoTransactionDataModel].self, from: data)
		return decodedData
	  } catch {
		// Decoding 실패
		// Legacy -> Migrate
		if let legacy = try? JSONDecoder().decode([LegacyModel].self, from: data) {
		  let migrated = migratedUserCryptoList(from: legacy)
		  
		  // migration 데이터 저장 **성공시에만 덮어쓰기
		  if let migratedDataEncode = try? JSONEncoder().encode(migrated) {
			defaults.set(migratedDataEncode, forKey: Keys.userCryptoList)
		  }
		  
		  return migrated
		} else {
		  // 최신 모델 디코딩 실패 + 레거시 마이그레이션 실패
		  // 빈 배열로 덮어쓰지 않고, nil로 반환해서 호출 측에서 처리하도록
		  return nil
		}
	  }
	}
	set {
	  let defaults = UserDefaults.standard
	  
	  // nil이면 아무 작업하지 않음 (덮어쓰기 방지)
	  guard let newValue = newValue else { return }
	  
	  if let encodedData = try? JSONEncoder().encode(newValue) {
		defaults.set(encodedData, forKey: Keys.userCryptoList)
	  }
      DispatchQueue.main.async {
        userCryptoListSubject.onNext(newValue)
      }
	}
  }
  
  /// 사용자 거래 내역 (실현손익 P&L 확인 가능한 목록)
  /// 매수 금액, 매도 금액, 매도 시간, 실현 손익
  static var userPNLHistory: [UserPNLHistoryModel]? {
	get {
	  let defaults = UserDefaults.standard
	  if let data = defaults.data(forKey: Keys.userPNLHistory) {
		let decodedData = try? JSONDecoder().decode([UserPNLHistoryModel].self, from: data)
		return decodedData
	  }
	  return []
	}
	set {
	  let defaults = UserDefaults.standard
	  if let encodedData = try? JSONEncoder().encode(newValue) {
		defaults.set(encodedData, forKey: Keys.userPNLHistory)
	  }
	  // userCryptoListSubject.onNext(newValue)
	}
  }
  
  static var userInformation: MobitUserInformation? {
    get {
      let defaults = UserDefaults.standard
      if let data = defaults.data(forKey: Keys.userInformation) {
        let decodedData = try? JSONDecoder().decode(MobitUserInformation.self, from: data)
        return decodedData
      }
      return nil
    }
    set {
      let defaults = UserDefaults.standard
      if let encodedData = try? JSONEncoder().encode(newValue) {
        defaults.set(encodedData, forKey: Keys.userInformation)
        DispatchQueue.main.async {
		  self.userAvailableBalanceSubject.onNext(newValue?.userAvailableBalance)
        }
      }
    }
  }
  
  static var tradingViewChartSettings: TradingViewChartSettings {
	get {
	  let defaults = UserDefaults.standard
	  guard let data = defaults.data(forKey: Keys.tradingViewChartSettings),
			let decodedData = try? JSONDecoder().decode(TradingViewChartSettings.self, from: data)
	  else {
		return .default
	  }
	  return decodedData
	}
	set {
	  let defaults = UserDefaults.standard
	  guard let encodedData = try? JSONEncoder().encode(newValue) else { return }
	  defaults.set(encodedData, forKey: Keys.tradingViewChartSettings)
	}
  }
  
  static var marketColorTheme: MarketColorTheme {
	get {
	  let defaults = UserDefaults.standard
	  guard let rawValue = defaults.string(forKey: Keys.marketColorTheme),
			let theme = MarketColorTheme(rawValue: rawValue)
	  else {
		return .riseRedFallBlue
	  }
	  return theme
	}
	set {
	  let defaults = UserDefaults.standard
	  defaults.set(newValue.rawValue, forKey: Keys.marketColorTheme)
	}
  }

  @discardableResult
  static func seedInitialUserInformationIfNeeded(
	initialBalance: Double = 1_000_000
  ) -> Bool {
	guard isFirstLaunch else { return false }
	isFirstLaunch = false
	userInformation = MobitUserInformation(userAvailableBalance: initialBalance)
	return true
  }

  static func resetInvestmentData(availableBalance: Double = 0) {
	userInformation = MobitUserInformation(userAvailableBalance: availableBalance)
	userCryptoList = []
	userTransactionList = []
	userValidTransactionList = []
	userPNLHistory = []
  }

  static func migratedUserCryptoList(
	from legacy: [LegacyModel]
  ) -> [CryptoTransactionDataModel] {
	legacy.map { item in
	  let staticData = CryptoTransactionDataModel.CryptoTransactionStaticData(
		identifier: UUID(),
		marketName: item.staticData.marketName,
		cryptoName: item.staticData.cryptoName,
		holdingQuantity: item.staticData.holdingQuantity,
		averageBuyPrice: item.staticData.averageBuyPrice,
		buyAmount: item.staticData.buyAmount
	  )
	  let dynamicData = CryptoTransactionDataModel.CryptoTransactionDynamicData(
		identifier: UUID(),
		marketName: item.dynamicData.marketName,
		profitRate: item.dynamicData.profitRate,
		evaluationProfitLoss: item.dynamicData.evaluationProfitLoss,
		evaluationPrice: item.dynamicData.evaluationPrice
	  )
	  return CryptoTransactionDataModel(
		identifier: UUID(),
		staticData: staticData,
		dynamicData: dynamicData
	  )
	}
  }
  
}
