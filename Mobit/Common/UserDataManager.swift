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
    var initialGrantCompleted: Bool?
    var adRewardClaims: [AdRewardClaim]?
  }

  private struct SpotCashState: Codable {
    let schemaVersion: Int
    let informationByExchange: [String: MobitUserInformation]
    let adRewardClaims: [AdRewardClaim]
  }

  enum InvestmentStateError: Error {
    case invalidStoredData
  }

  struct LegacyBTCSettlementResult: Equatable {
    let restoredKRWByExchange: [Exchange: Double]

    var totalRestoredKRW: Double {
      restoredKRWByExchange.values.reduce(0, +)
    }
  }

  private static let investmentStateLock = NSRecursiveLock()
  private static var stagedInvestmentState: InvestmentState?

  private static func synchronized<T>(_ work: () throws -> T) rethrows -> T {
    investmentStateLock.lock()
    defer { investmentStateLock.unlock() }
    return try work()
  }

  /// 구버전에서 Optional 배열의 nil이 JSON null로 저장된 경우 빈 배열로 복구한다.
  private static func storedArray<Element: Codable>(
    forKey key: String,
    as type: [Element].Type
  ) -> [Element]? {
    let defaults = UserDefaults.standard
    guard defaults.object(forKey: key) != nil else { return [] }
    guard let data = defaults.data(forKey: key) else { return nil }

    if (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) is NSNull {
      if let emptyData = try? JSONEncoder().encode([Element]()) {
        defaults.set(emptyData, forKey: key)
      }
      return []
    }

    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      return nil
    }
  }

  private static func storeArray<Element: Encodable>(
    _ value: [Element]?,
    forKey key: String
  ) {
    let defaults = UserDefaults.standard
    guard let value else {
      defaults.removeObject(forKey: key)
      return
    }
    guard let encodedData = try? JSONEncoder().encode(value) else { return }
    defaults.set(encodedData, forKey: key)
  }

  /// 주문 중 변경분을 메모리에 모은 뒤 한 번에 저장한다. 실패하면 staged state를 버려 부분 체결을 막는다.
  static func performAtomicInvestmentUpdate<T>(_ update: () throws -> T) throws -> T {
    try synchronized {
      if let pending = UserDefaults.standard.object(forKey: Keys.pendingInvestmentState) {
        guard let pendingData = pending as? Data,
              let state = try? JSONDecoder().decode(InvestmentState.self, from: pendingData) else {
          throw InvestmentStateError.invalidStoredData
        }
        try persistInvestmentState(state)
      }
      guard stagedInvestmentState == nil,
            let cryptoList = userCryptoList,
            let transactionList = userTransactionList,
            let validTransactionList = userValidTransactionList,
            let pnlHistory = userPNLHistory,
            let informationByExchange = userInformationStore,
            let claims = storedAdRewardClaims() else {
        throw InvestmentStateError.invalidStoredData
      }

      stagedInvestmentState = InvestmentState(
        cryptoList: cryptoList,
        transactionList: transactionList,
        validTransactionList: validTransactionList,
        pnlHistory: pnlHistory,
        informationByExchange: informationByExchange,
        initialGrantCompleted: !isFirstLaunch,
        adRewardClaims: claims
      )

      do {
        let result = try update()
        guard let committedState = stagedInvestmentState else {
          throw InvestmentStateError.invalidStoredData
        }
        try persistInvestmentState(committedState)
        stagedInvestmentState = nil
        publishInvestmentState()
        return result
      } catch {
        stagedInvestmentState = nil
        throw error
      }
    }
  }

  /// 구버전에서 BTC 가격을 원화처럼 계산한 보유분만 반환한다.
  static func legacyBTCMarketHoldings() -> [CryptoTransactionDataModel]? {
    guard let holdings = userCryptoList else { return nil }
    return holdings.filter {
      $0.settlementCurrency == .btc && $0.staticData.costBasisKRW == nil
    }
  }

  /// 구버전 화면의 현재 평가금액으로 원화 정산하고 정상 보유분은 유지한다.
  static func settleLegacyBTCMarketHoldings() throws -> LegacyBTCSettlementResult {
    try performAtomicInvestmentUpdate {
      guard let holdings = userCryptoList,
            let transactions = userTransactionList,
            let validTransactions = userValidTransactionList else {
        throw InvestmentStateError.invalidStoredData
      }

      let legacyHoldings = holdings.filter {
        $0.settlementCurrency == .btc && $0.staticData.costBasisKRW == nil
      }
      guard !legacyHoldings.isEmpty else {
        return LegacyBTCSettlementResult(restoredKRWByExchange: [:])
      }

      var restoredKRWByExchange: [Exchange: Double] = [:]
      var settlementTransactions: [TransactionInfo] = []
      let settlementTimestamp = TradeTimestampFormatter.timestamp(from: Date())
      for holding in legacyHoldings {
        let displayedEvaluation = holding.dynamicData.evaluationPrice
        guard displayedEvaluation.isFinite, displayedEvaluation >= 0 else {
          throw InvestmentStateError.invalidStoredData
        }

        let restoredKRW = displayedEvaluation.formatDigits(digits: 0)
        restoredKRWByExchange[holding.staticData.exchange, default: 0] += restoredKRW

        let quantity = holding.staticData.holdingQuantity
        let settlementPrice = quantity > 0 ? displayedEvaluation / quantity : 0
        settlementTransactions.append(TransactionInfo(
          exchange: holding.staticData.exchange,
          marketName: holding.staticData.marketName,
          orderType: .ask,
          executedTimestamp: settlementTimestamp,
          executedPrice: settlementPrice,
          executedQuantity: quantity,
          executedAmount: restoredKRW,
          recordType: .legacyBTCSettlement
        ))
      }

      let legacyPairIDs = Set(legacyHoldings.map { $0.staticData.exchangePairID })
      userCryptoList = holdings.filter {
        !($0.settlementCurrency == .btc && $0.staticData.costBasisKRW == nil)
      }
      userValidTransactionList = validTransactions.filter {
        !legacyPairIDs.contains($0.exchangePairID)
      }
      userTransactionList = transactions + settlementTransactions

      for (exchange, restoredKRW) in restoredKRWByExchange {
        let previousBalance = userInformation(for: exchange)?.userAvailableBalance ?? 0
        let updatedBalance = previousBalance + restoredKRW
        guard updatedBalance.isFinite else {
          throw InvestmentStateError.invalidStoredData
        }
        updateUserInformation(
          MobitUserInformation(userAvailableBalance: updatedBalance),
          for: exchange
        )
      }

      return LegacyBTCSettlementResult(
        restoredKRWByExchange: restoredKRWByExchange
      )
    }
  }

  /// 이전 실행이 개별 키 저장 도중 종료됐으면 단일 pending snapshot으로 마지막 주문을 복구한다.
  private static func recoverPendingInvestmentStateIfNeeded() -> Bool {
    let defaults = UserDefaults.standard
    guard let pending = defaults.object(forKey: Keys.pendingInvestmentState) else { return true }
    guard let data = pending as? Data,
          let state = try? JSONDecoder().decode(InvestmentState.self, from: data) else { return false }
    do {
      try persistInvestmentState(state)
      return true
    } catch {
      return false
    }
  }

  private static func persistInvestmentState(_ state: InvestmentState) throws {
    guard state.informationByExchange.values.allSatisfy({
      $0.userAvailableBalance.isFinite && $0.userAvailableBalance >= 0
    }) else { throw InvestmentStateError.invalidStoredData }
    if state.adRewardClaims == nil, let current = storedSpotCashState(), !current.adRewardClaims.isEmpty {
      throw InvestmentStateError.invalidStoredData
    }
    let claims = state.adRewardClaims ?? []
    try AdRewardClaim.validateCollection(claims)
    guard claims.allSatisfy({ $0.account.product == .spot }) else { throw AdRewardError.invalidClaim }
    let encoder = JSONEncoder()
    let pendingData = try encoder.encode(state)
    let cryptoData = try encoder.encode(state.cryptoList)
    let transactionData = try encoder.encode(state.transactionList)
    let validTransactionData = try encoder.encode(state.validTransactionList)
    let pnlData = try encoder.encode(state.pnlHistory)
    let informationData = try encoder.encode(SpotCashState(
      schemaVersion: 1, informationByExchange: state.informationByExchange, adRewardClaims: claims
    ))
    let defaults = UserDefaults.standard

    defaults.set(pendingData, forKey: Keys.pendingInvestmentState)
    defaults.set(cryptoData, forKey: Keys.userCryptoList)
    defaults.set(transactionData, forKey: Keys.userTransactionList)
    defaults.set(validTransactionData, forKey: Keys.userValidTransactionList)
    defaults.set(pnlData, forKey: Keys.userPNLHistory)
    defaults.set(informationData, forKey: Keys.userInformationByExchange)
    if state.initialGrantCompleted == true { defaults.set(false, forKey: Keys.isFirstLaunch) }
    defaults.removeObject(forKey: Keys.pendingInvestmentState)
  }

  private static func storedAdRewardClaims() -> [AdRewardClaim]? {
    if let stagedInvestmentState { return stagedInvestmentState.adRewardClaims ?? [] }
    return storedSpotCashState()?.adRewardClaims
  }

  private static func storedSpotCashState() -> SpotCashState? {
    let defaults = UserDefaults.standard
    let balances: [String: MobitUserInformation]
    let claims: [AdRewardClaim]
    if defaults.object(forKey: Keys.userInformationByExchange) != nil {
      guard let data = defaults.data(forKey: Keys.userInformationByExchange),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
      if object["schemaVersion"] != nil {
        guard let state = try? JSONDecoder().decode(SpotCashState.self, from: data),
              state.schemaVersion == 1 else { return nil }
        balances = state.informationByExchange
        claims = state.adRewardClaims
      } else {
        guard let legacy = try? JSONDecoder().decode([String: MobitUserInformation].self, from: data) else { return nil }
        balances = legacy
        claims = []
      }
    } else if defaults.object(forKey: Keys.userInformation) != nil {
      guard let data = defaults.data(forKey: Keys.userInformation),
            let legacy = try? JSONDecoder().decode(MobitUserInformation.self, from: data) else { return nil }
      balances = UserDataMigration.migrateUserInformationStore(from: legacy)
      claims = []
    } else {
      balances = [:]
      claims = []
    }
    guard balances.values.allSatisfy({ $0.userAvailableBalance.isFinite && $0.userAvailableBalance >= 0 }),
          claims.allSatisfy({ $0.account.product == .spot }),
          (try? AdRewardClaim.validateCollection(claims)) != nil else { return nil }
    return SpotCashState(schemaVersion: 1, informationByExchange: balances, adRewardClaims: claims)
  }

  static func applyAdvertisementReward(_ claim: AdRewardClaim) throws {
    try claim.validate()
    guard claim.account.product == .spot, claim.account.currency == .krw else { throw AdRewardError.invalidClaim }
    try performAtomicInvestmentUpdate {
      let claims = stagedInvestmentState?.adRewardClaims ?? []
      if let existing = claims.first(where: { $0.id == claim.id }) {
        guard existing == claim else { throw AdRewardError.conflictingClaim }
        return
      }
      guard var information = userInformation(for: claim.account.exchange) else {
        throw InvestmentStateError.invalidStoredData
      }
      let amount = NSDecimalNumber(decimal: claim.amount).doubleValue
      let balance = information.userAvailableBalance + amount
      guard balance.isFinite, balance > information.userAvailableBalance else {
        throw InvestmentStateError.invalidStoredData
      }
      information.userAvailableBalance = balance
      updateUserInformation(information, for: claim.account.exchange)
      stagedInvestmentState?.adRewardClaims = claims + [claim]
    }
  }

  private static func publishInvestmentState() {
    DispatchQueue.main.async {
      // 큐 대기 중 주문이나 거래소 선택이 바뀌면 최신 확정 상태를 발행한다.
      userCryptoListSubject.onNext(userCryptoList)
      publishCurrentExchangeBalance()
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
        guard recoverPendingInvestmentStateIfNeeded() else { return nil }
        return storedArray(
          forKey: Keys.userTransactionList,
          as: [TransactionInfo].self
        )
      }
	}
	set {
	  synchronized {
        if stagedInvestmentState != nil {
          guard let newValue else { return }
          stagedInvestmentState?.transactionList = newValue
          return
        }
        storeArray(newValue, forKey: Keys.userTransactionList)
      }
	}
  }
  
  /// 유효한 거래내역만 저장 (보유하고 있는 매수 & 매도 내역에 대해서만)
  static var userValidTransactionList: [ValidTransactionInfo]? {
	get {
	  synchronized {
        if let stagedInvestmentState { return stagedInvestmentState.validTransactionList }
        guard recoverPendingInvestmentStateIfNeeded() else { return nil }
        return storedArray(
          forKey: Keys.userValidTransactionList,
          as: [ValidTransactionInfo].self
        )
      }
	}
	set {
	  synchronized {
        if stagedInvestmentState != nil {
          guard let newValue else { return }
          stagedInvestmentState?.validTransactionList = newValue
          return
        }
        storeArray(newValue, forKey: Keys.userValidTransactionList)
      }
	}
  }
  
  /// 사용자가 매수한 코인 정보 (현재)
  static var userCryptoList: [CryptoTransactionDataModel]? {
	get {
	  synchronized {
        if let stagedInvestmentState { return stagedInvestmentState.cryptoList }
        guard recoverPendingInvestmentStateIfNeeded() else { return nil }
	    let defaults = UserDefaults.standard
	  guard defaults.object(forKey: Keys.userCryptoList) != nil else { return [] }
      guard let data = defaults.data(forKey: Keys.userCryptoList) else { return nil }
	  
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
        guard let encodedData = try? JSONEncoder().encode(newValue) else { return }
        defaults.set(encodedData, forKey: Keys.userCryptoList)
        DispatchQueue.main.async {
          userCryptoListSubject.onNext(userCryptoList)
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
        guard recoverPendingInvestmentStateIfNeeded() else { return nil }
        return storedArray(
          forKey: Keys.userPNLHistory,
          as: [UserPNLHistoryModel].self
        )
      }
	}
	set {
	  synchronized {
        if stagedInvestmentState != nil {
          guard let newValue else { return }
          stagedInvestmentState?.pnlHistory = newValue
          return
        }
        storeArray(newValue, forKey: Keys.userPNLHistory)
      }
	  // userCryptoListSubject.onNext(newValue)
	}
  }
  
  /// 거래소별 보유 현금 저장소. 레거시 단일 잔고는 최초 접근 시 Upbit 잔고로 승격한다.
  private static var userInformationStore: [String: MobitUserInformation]? {
    get {
      synchronized {
        if let stagedInvestmentState { return stagedInvestmentState.informationByExchange }
        guard recoverPendingInvestmentStateIfNeeded() else { return nil }
        return storedSpotCashState()?.informationByExchange
      }
    }
    set {
      synchronized {
        guard let newValue else { return }
        if stagedInvestmentState != nil {
          stagedInvestmentState?.informationByExchange = newValue
          return
        }
        guard newValue.values.allSatisfy({ $0.userAvailableBalance.isFinite && $0.userAvailableBalance >= 0 }),
              let current = storedSpotCashState(),
              let encoded = try? JSONEncoder().encode(SpotCashState(
                schemaVersion: 1, informationByExchange: newValue, adRewardClaims: current.adRewardClaims
              )) else { return }
        UserDefaults.standard.set(encoded, forKey: Keys.userInformationByExchange)
      }
    }
  }

  static var userInformation: MobitUserInformation? {
    get { userInformation(for: ExchangeSelectionStore.currentExchange) }
    set {
      guard let newValue else { return }
      updateUserInformation(newValue, for: ExchangeSelectionStore.currentExchange)
    }
  }

  static func userInformation(for exchange: Exchange) -> MobitUserInformation? {
    synchronized {
      guard let store = userInformationStore, !store.isEmpty else { return nil }
      return store[exchange.rawValue] ?? MobitUserInformation(userAvailableBalance: TradingRules.Funding.unfundedAccountBalance)
    }
  }

  // 미충전 계좌의 0원과 저장 실패를 구분해 계좌 목록에 잘못된 잔고를 표시하지 않는다.
  static func getAvailableBalance(for exchange: Exchange) throws -> Double {
    try synchronized {
      guard let store = userInformationStore else { throw InvestmentStateError.invalidStoredData }
      return store[exchange.rawValue]?.userAvailableBalance ?? TradingRules.Funding.unfundedAccountBalance
    }
  }

  static func updateUserInformation(_ information: MobitUserInformation, for exchange: Exchange) {
    synchronized {
      guard var store = userInformationStore else { return }
      store[exchange.rawValue] = information
      userInformationStore = store
      guard stagedInvestmentState == nil else { return }
      DispatchQueue.main.async { publishCurrentExchangeBalance() }
    }
  }

  /// 잔고를 읽고 변경하는 전체 구간을 주문과 같은 잠금에 포함한다.
  static func updateUserInformation(
    for exchange: Exchange,
    transform: (inout MobitUserInformation) throws -> Void
  ) throws {
    try performAtomicInvestmentUpdate {
      guard var information = userInformation(for: exchange) else {
        throw InvestmentStateError.invalidStoredData
      }
      try transform(&information)
      guard information.userAvailableBalance.isFinite, information.userAvailableBalance >= 0 else {
        throw InvestmentStateError.invalidStoredData
      }
      updateUserInformation(information, for: exchange)
    }
  }

  static func publishCurrentExchangeBalance() {
    if Thread.isMainThread {
      userAvailableBalanceSubject.onNext(userInformation?.userAvailableBalance)
    } else {
      DispatchQueue.main.async { publishCurrentExchangeBalance() }
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

  // 시세 리스트 셀 배경 색상 틴트 표시 여부 (기본 OFF)
  static var marketCellTintEnabled: Bool {
	get {
	  let defaults = UserDefaults.standard
	  if defaults.object(forKey: Keys.marketCellTintEnabled) == nil {
		return false
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
  static func seedInitialUserInformationIfNeeded(initialBalance: Double = TradingFundingPolicy.initialKRWBalance) -> Bool {
    synchronized {
      guard isFirstLaunch, initialBalance.isFinite, initialBalance > 0 else { return false }
      let defaults = UserDefaults.standard
      let hasExistingInvestment = [
        Keys.userInformation, Keys.userInformationByExchange, Keys.userCryptoList,
        Keys.userTransactionList, Keys.userValidTransactionList, Keys.userPNLHistory,
        Keys.pendingInvestmentState
      ].contains { defaults.object(forKey: $0) != nil }
      do {
        return try performAtomicInvestmentUpdate {
          if !hasExistingInvestment {
            updateUserInformation(
              MobitUserInformation(userAvailableBalance: initialBalance),
              for: TradingRules.Funding.initialGrantAccount.exchange
            )
          }
          stagedInvestmentState?.initialGrantCompleted = true
          return !hasExistingInvestment
        }
      } catch {
        // 손상 기록을 신규 설치로 간주해 초기 자금으로 덮어쓰지 않는다.
        return false
      }
    }
  }

  @discardableResult
  static func resetInvestmentData(availableBalance: Double = TradingRules.Funding.unfundedAccountBalance) -> Bool {
	synchronized {
      guard availableBalance.isFinite, availableBalance >= 0, stagedInvestmentState == nil,
            recoverPendingInvestmentStateIfNeeded(), let claims = storedAdRewardClaims() else { return false }
	  // 초기화도 주문과 같은 잠금·스냅샷 경로를 사용해 동시 체결과 섞이지 않게 한다.
	  var store: [String: MobitUserInformation] = [:]
	  for exchange in Exchange.allCases {
		store[exchange.rawValue] = MobitUserInformation(userAvailableBalance: TradingRules.Funding.unfundedAccountBalance)
	  }
	  store[ExchangeSelectionStore.currentExchange.rawValue] = MobitUserInformation(
		userAvailableBalance: availableBalance
	  )
	  let state = InvestmentState(
		cryptoList: [],
		transactionList: [],
		validTransactionList: [],
		pnlHistory: [],
		informationByExchange: store,
        initialGrantCompleted: true,
        adRewardClaims: claims
	  )
	  guard (try? persistInvestmentState(state)) != nil else { return false }
	  stagedInvestmentState = nil
	  publishInvestmentState()
      return true
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
