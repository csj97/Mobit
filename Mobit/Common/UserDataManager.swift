//
//  UserDataManager.swift
//  Mobit
//
//  Created by 조성재 on 1/26/25.
//

import Foundation
import RxSwift
import UIKit

class UserDataManager: NSObject {
  struct TradingViewChartSettings: Codable, Equatable {
	enum Interval: String, Codable {
	  case minute15 = "15"
	  case hour1 = "60"
	  case hour4 = "240"
	  case day1 = "1D"
	  case week1 = "1W"
	  case month1 = "1M"
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

  enum AppTheme: String, Codable, CaseIterable {
	case system
	case light
	case dark

	var userInterfaceStyle: UIUserInterfaceStyle {
	  switch self {
	  case .system:
		return .unspecified
	  case .light:
		return .light
	  case .dark:
		return .dark
	  }
	}
  }

  enum Keys {
	static let isFirstLaunch = "isFirstLaunch"
	static let userFavoriteList = "user-favorite-list"
	static let userTransactionList = "user-transaction-list"
	static let userValidTransactionList = "user-valid-transaction-list"
	static let userCryptoList = "user-crypto-list"
	static let userPNLHistory = "user-pnl-list"
	static let userInformation = "user-information"
	static let userInformationByExchange = "user-information-by-exchange"
	static let tradingViewChartSettings = "tradingview-chart-settings"
	static let marketColorTheme = "market-color-theme"
	static let marketCellTintEnabled = "market-cell-tint-enabled"
	static let appTheme = "app-theme"
    static let pendingInvestmentState = "pending-investment-state"
  }

  private struct InvestmentState: Codable {
    var cryptoList: [CryptoTransactionDataModel]
    var transactionList: [TransactionInfo]
    var validTransactionList: [ValidTransactionInfo]
    var pnlHistory: [UserPNLHistoryModel]
    var informationByExchange: [String: MobitUserInformation]
  }

  enum InvestmentStateError: Error {
    case invalidStoredData
  }

  private static let investmentStateLock = NSRecursiveLock()
  private static var stagedInvestmentState: InvestmentState?

  private static func synchronized<T>(_ work: () throws -> T) rethrows -> T {
    investmentStateLock.lock()
    defer { investmentStateLock.unlock() }
    return try work()
  }

  /// 주문 중 변경분을 메모리에 모은 뒤 한 번에 저장한다. 실패하면 staged state를 버려 부분 체결을 막는다.
  static func performAtomicInvestmentUpdate<T>(_ update: () throws -> T) throws -> T {
    try synchronized {
      if let pendingData = UserDefaults.standard.data(forKey: Keys.pendingInvestmentState),
         (try? JSONDecoder().decode(InvestmentState.self, from: pendingData)) == nil {
        throw InvestmentStateError.invalidStoredData
      }
      recoverPendingInvestmentStateIfNeeded()
      guard stagedInvestmentState == nil,
            let cryptoList = userCryptoList,
            let transactionList = userTransactionList,
            let validTransactionList = userValidTransactionList,
            let pnlHistory = userPNLHistory else {
        throw InvestmentStateError.invalidStoredData
      }

      stagedInvestmentState = InvestmentState(
        cryptoList: cryptoList,
        transactionList: transactionList,
        validTransactionList: validTransactionList,
        pnlHistory: pnlHistory,
        informationByExchange: userInformationStore
      )

      do {
        let result = try update()
        guard let committedState = stagedInvestmentState else {
          throw InvestmentStateError.invalidStoredData
        }
        try persistInvestmentState(committedState)
        stagedInvestmentState = nil
        publishInvestmentState(committedState)
        return result
      } catch {
        stagedInvestmentState = nil
        throw error
      }
    }
  }

  /// 이전 실행이 개별 키 저장 도중 종료됐으면 단일 pending snapshot으로 마지막 주문을 복구한다.
  private static func recoverPendingInvestmentStateIfNeeded() {
    let defaults = UserDefaults.standard
    guard let data = defaults.data(forKey: Keys.pendingInvestmentState),
          let state = try? JSONDecoder().decode(InvestmentState.self, from: data) else { return }
    try? persistInvestmentState(state)
  }

  private static func persistInvestmentState(_ state: InvestmentState) throws {
    let encoder = JSONEncoder()
    let pendingData = try encoder.encode(state)
    let cryptoData = try encoder.encode(state.cryptoList)
    let transactionData = try encoder.encode(state.transactionList)
    let validTransactionData = try encoder.encode(state.validTransactionList)
    let pnlData = try encoder.encode(state.pnlHistory)
    let informationData = try encoder.encode(state.informationByExchange)
    let defaults = UserDefaults.standard

    defaults.set(pendingData, forKey: Keys.pendingInvestmentState)
    defaults.set(cryptoData, forKey: Keys.userCryptoList)
    defaults.set(transactionData, forKey: Keys.userTransactionList)
    defaults.set(validTransactionData, forKey: Keys.userValidTransactionList)
    defaults.set(pnlData, forKey: Keys.userPNLHistory)
    defaults.set(informationData, forKey: Keys.userInformationByExchange)
    defaults.removeObject(forKey: Keys.pendingInvestmentState)
  }

  private static func publishInvestmentState(_ state: InvestmentState) {
    let currentBalance = state.informationByExchange[ExchangeSelectionStore.currentExchange.rawValue]?
      .userAvailableBalance ?? 0
    DispatchQueue.main.async {
      userCryptoListSubject.onNext(state.cryptoList)
      userAvailableBalanceSubject.onNext(currentBalance)
    }
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
  
  /// 사용자 즐겨찾기 레거시 호환용 표시 마켓 목록
  static var userFavoriteList: [String] {
    get {
      userFavoritePairs.map(\.displayMarket)
    }
    set {
      userFavoritePairs = UserDataMigration.migrateFavoritePairs(from: newValue)
    }
  }

  static var userFavoritePairs: [FavoritePair] {
    get {
      let defaults = UserDefaults.standard

      if let data = defaults.data(forKey: Keys.userFavoriteList),
         let decoded = try? JSONDecoder().decode([FavoritePair].self, from: data) {
        return decoded
      }

      if let legacy = defaults.stringArray(forKey: Keys.userFavoriteList) {
        let migrated = UserDataMigration.migrateFavoritePairs(from: legacy)
        if let encoded = try? JSONEncoder().encode(migrated) {
          defaults.set(encoded, forKey: Keys.userFavoriteList)
        }
        return migrated
      }

      return []
    }
    set {
      let defaults = UserDefaults.standard
      guard let encoded = try? JSONEncoder().encode(newValue) else { return }
      defaults.set(encoded, forKey: Keys.userFavoriteList)
    }
  }
  
  /// 거래내역만 저장
  static var userTransactionList: [TransactionInfo]? {
	get {
	  synchronized {
        if let stagedInvestmentState { return stagedInvestmentState.transactionList }
        recoverPendingInvestmentStateIfNeeded()
	    let defaults = UserDefaults.standard
	    if let data = defaults.data(forKey: Keys.userTransactionList) {
		  return try? JSONDecoder().decode([TransactionInfo].self, from: data)
	    }
	    return []
      }
	}
	set {
	  synchronized {
        if stagedInvestmentState != nil {
          guard let newValue else { return }
          stagedInvestmentState?.transactionList = newValue
          return
        }
	    let defaults = UserDefaults.standard
	    if let encodedData = try? JSONEncoder().encode(newValue) {
		  defaults.set(encodedData, forKey: Keys.userTransactionList)
	    }
      }
	}
  }
  
  /// 유효한 거래내역만 저장 (보유하고 있는 매수 & 매도 내역에 대해서만)
  static var userValidTransactionList: [ValidTransactionInfo]? {
	get {
	  synchronized {
        if let stagedInvestmentState { return stagedInvestmentState.validTransactionList }
        recoverPendingInvestmentStateIfNeeded()
	    let defaults = UserDefaults.standard
	    if let data = defaults.data(forKey: Keys.userValidTransactionList) {
		  return try? JSONDecoder().decode([ValidTransactionInfo].self, from: data)
	    }
	    return []
      }
	}
	set {
	  synchronized {
        if stagedInvestmentState != nil {
          guard let newValue else { return }
          stagedInvestmentState?.validTransactionList = newValue
          return
        }
	    let defaults = UserDefaults.standard
	    if let encodedData = try? JSONEncoder().encode(newValue) {
		  defaults.set(encodedData, forKey: Keys.userValidTransactionList)
	    }
      }
	}
  }
  
  /// 사용자가 매수한 코인 정보 (현재)
  static var userCryptoList: [CryptoTransactionDataModel]? {
	get {
	  synchronized {
        if let stagedInvestmentState { return stagedInvestmentState.cryptoList }
        recoverPendingInvestmentStateIfNeeded()
	    let defaults = UserDefaults.standard
	  guard let data = defaults.data(forKey: Keys.userCryptoList) else { return [] }
	  
	  do {
		let decodedData = try JSONDecoder().decode([CryptoTransactionDataModel].self, from: data)
		return decodedData
	  } catch {
		// Decoding 실패
		// Legacy -> Migrate
		if let legacy = try? JSONDecoder().decode([LegacyModel].self, from: data) {
		  let migrated = UserDataMigration.migrateUserCryptoList(from: legacy)
		  
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
	}
	set {
	  synchronized {
        guard let newValue else { return }
        if stagedInvestmentState != nil {
          stagedInvestmentState?.cryptoList = newValue
          return
        }
	    let defaults = UserDefaults.standard
	    if let encodedData = try? JSONEncoder().encode(newValue) {
		  defaults.set(encodedData, forKey: Keys.userCryptoList)
	    }
        DispatchQueue.main.async {
          userCryptoListSubject.onNext(newValue)
        }
      }
	}
  }
  
  /// 사용자 거래 내역 (실현손익 P&L 확인 가능한 목록)
  /// 매수 금액, 매도 금액, 매도 시간, 실현 손익
  static var userPNLHistory: [UserPNLHistoryModel]? {
	get {
	  synchronized {
        if let stagedInvestmentState { return stagedInvestmentState.pnlHistory }
        recoverPendingInvestmentStateIfNeeded()
	    let defaults = UserDefaults.standard
	    if let data = defaults.data(forKey: Keys.userPNLHistory) {
		  return try? JSONDecoder().decode([UserPNLHistoryModel].self, from: data)
	    }
	    return []
      }
	}
	set {
	  synchronized {
        if stagedInvestmentState != nil {
          guard let newValue else { return }
          stagedInvestmentState?.pnlHistory = newValue
          return
        }
	    let defaults = UserDefaults.standard
	    if let encodedData = try? JSONEncoder().encode(newValue) {
		  defaults.set(encodedData, forKey: Keys.userPNLHistory)
	    }
      }
	  // userCryptoListSubject.onNext(newValue)
	}
  }
  
  /// 거래소별 보유 현금 저장소. 레거시 단일 잔고는 최초 접근 시 Upbit 잔고로 승격한다.
  private static var userInformationStore: [String: MobitUserInformation] {
    get {
      synchronized {
      if let stagedInvestmentState { return stagedInvestmentState.informationByExchange }
      recoverPendingInvestmentStateIfNeeded()
      let defaults = UserDefaults.standard
      if let data = defaults.data(forKey: Keys.userInformationByExchange),
         let decoded = try? JSONDecoder().decode([String: MobitUserInformation].self, from: data) {
        return decoded
      }
      // 레거시 단일 거래소 잔고를 Upbit 잔고로 이관. 신규 거래소는 0원으로 시작한다.
      if let legacyData = defaults.data(forKey: Keys.userInformation),
         let legacy = try? JSONDecoder().decode(MobitUserInformation.self, from: legacyData) {
        let migrated = UserDataMigration.migrateUserInformationStore(from: legacy)
        if let encoded = try? JSONEncoder().encode(migrated) {
          defaults.set(encoded, forKey: Keys.userInformationByExchange)
        }
        return migrated
      }
      return [:]
      }
    }
    set {
      synchronized {
        if stagedInvestmentState != nil {
          stagedInvestmentState?.informationByExchange = newValue
          return
        }
        let defaults = UserDefaults.standard
        guard let encoded = try? JSONEncoder().encode(newValue) else { return }
        defaults.set(encoded, forKey: Keys.userInformationByExchange)
      }
    }
  }

  /// 현재 선택 거래소의 보유 현금 정보. 신규 거래소는 0원으로 시작한다.
  static var userInformation: MobitUserInformation? {
    get {
      let store = userInformationStore
      // 최초 실행(시드) 이전에는 nil, 이후에는 거래소별 잔고(없으면 0원)를 반환한다.
      guard !store.isEmpty else { return nil }
      return store[ExchangeSelectionStore.currentExchange.rawValue]
        ?? MobitUserInformation(userAvailableBalance: 0)
    }
    set {
      guard let newValue else { return }
      var store = userInformationStore
      store[ExchangeSelectionStore.currentExchange.rawValue] = newValue
      userInformationStore = store
      guard synchronized({ stagedInvestmentState == nil }) else { return }
      DispatchQueue.main.async {
        self.userAvailableBalanceSubject.onNext(newValue.userAvailableBalance)
      }
    }
  }

  /// 지정한 거래소의 보유 현금 정보. 주문 처리처럼 대상 거래소가 명시된 흐름에서 사용한다.
  static func userInformation(for exchange: Exchange) -> MobitUserInformation? {
    let store = userInformationStore
    guard !store.isEmpty else { return nil }
    return store[exchange.rawValue] ?? MobitUserInformation(userAvailableBalance: 0)
  }

  /// 지정한 거래소의 보유 현금 갱신. 선택 거래소가 바뀐 뒤 주문이 끝나도 잔고가 섞이지 않도록 분리한다.
  static func updateUserInformation(
    _ information: MobitUserInformation,
    for exchange: Exchange
  ) {
    var store = userInformationStore
    store[exchange.rawValue] = information
    userInformationStore = store

    guard exchange == ExchangeSelectionStore.currentExchange,
          synchronized({ stagedInvestmentState == nil }) else { return }
    DispatchQueue.main.async {
      self.userAvailableBalanceSubject.onNext(information.userAvailableBalance)
    }
  }

  /// 거래소 전환 시 현재 거래소 잔고를 구독자에게 다시 브로드캐스트한다.
  static func publishCurrentExchangeBalance() {
    userAvailableBalanceSubject.onNext(userInformation?.userAvailableBalance)
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

  // 시세 리스트 셀 배경 색상 틴트 표시 여부 (기본 ON)
  static var marketCellTintEnabled: Bool {
	get {
	  let defaults = UserDefaults.standard
	  if defaults.object(forKey: Keys.marketCellTintEnabled) == nil {
		return true
	  }
	  return defaults.bool(forKey: Keys.marketCellTintEnabled)
	}
	set {
	  UserDefaults.standard.set(newValue, forKey: Keys.marketCellTintEnabled)
	}
  }

  static var appTheme: AppTheme {
	get {
	  let defaults = UserDefaults.standard
	  guard let rawValue = defaults.string(forKey: Keys.appTheme),
			let theme = AppTheme(rawValue: rawValue)
	  else {
		return .system
	  }
	  return theme
	}
	set {
	  UserDefaults.standard.set(newValue.rawValue, forKey: Keys.appTheme)
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
	synchronized {
	  UserDefaults.standard.removeObject(forKey: Keys.pendingInvestmentState)
	  // 초기화도 주문과 같은 잠금·스냅샷 경로를 사용해 동시 체결과 섞이지 않게 한다.
	  var store: [String: MobitUserInformation] = [:]
	  for exchange in Exchange.allCases {
		store[exchange.rawValue] = MobitUserInformation(userAvailableBalance: 0)
	  }
	  store[ExchangeSelectionStore.currentExchange.rawValue] = MobitUserInformation(
		userAvailableBalance: availableBalance
	  )
	  let state = InvestmentState(
		cryptoList: [],
		transactionList: [],
		validTransactionList: [],
		pnlHistory: [],
		informationByExchange: store
	  )
	  guard (try? persistInvestmentState(state)) != nil else { return }
	  stagedInvestmentState = nil
	  publishInvestmentState(state)
	}
  }

  static func isFavorite(pairID: ExchangePairID) -> Bool {
    userFavoritePairs.contains { $0.pairID == pairID }
  }

  static func addFavorite(displayMarket: String, exchange: Exchange) {
    let favorite = FavoritePair(displayMarket: displayMarket, exchange: exchange)
    guard !isFavorite(pairID: favorite.pairID) else { return }
    userFavoritePairs.append(favorite)
  }

  static func removeFavorite(displayMarket: String, exchange: Exchange) {
    let pairID = ExchangeMarketCodeConverter.pairID(
      fromDisplayMarket: displayMarket,
      exchange: exchange
    )
    userFavoritePairs.removeAll { $0.pairID == pairID }
  }
}
