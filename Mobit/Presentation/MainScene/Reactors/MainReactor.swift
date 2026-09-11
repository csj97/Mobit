//
//  MainViewModel.swift
//  Mobit
//
//  Created by openobject on 2024/07/19.
//

import Foundation
import FirebaseDatabase
import UIKit
import RxSwift
import ReactorKit
import RxRelay

enum SelectedTab: Int {
  case hold, krw, btc, favorite
}

class MainReactor: Reactor {
  private let exchange = ExchangeSelectionStore.currentExchange
  private let mainUseCase: MainUseCase
  private let disposeBag = DisposeBag()
  private let tickerSocketService: TickerSocketServiceProtocol
  private var isBTCKRWRefreshInFlight = false
  private var nextBTCKRWRefreshAllowedAt = Date.distantPast
  private var isSocketMonitoringEnabled = false
  private var isLegacySettlementInFlight = false
  
  // ReactorKit 외부에서 mutation을 주입하려면 이게 필요
  private let mutationSubject = PublishSubject<MainMutation>()
  private(set) var isSocketConnected = false
  
  // 탭별 정렬 포지션을 **하나로 통합**
  private var sortedCryptoPosition: [String: Int] = [:]

  // 정렬 해제 시 되돌릴 초기(자연) 순서. combineCrypto가 만든 API 순서를 보관한다.
  private var initialMarketOrder: [String] = []
  
  let initialState: MainReactorState = MainReactorState()
  private var firebaseDB = Database.database().reference()
  
  init(
    mainUseCase: MainUseCase,
    tickerSocketService: TickerSocketServiceProtocol = TickerSocketService()
  ) {
	self.mainUseCase = mainUseCase
    self.tickerSocketService = tickerSocketService
	
	UserDataManager.userCryptoListObservable
      .observe(on: MainScheduler.asyncInstance)
	  .map { MainMutation.setUserCrypto($0) }
	  .bind(to: mutationSubject)
	  .disposed(by: disposeBag)

    self.tickerSocketService.stream
      .observe(on: MainScheduler.asyncInstance)
      .map { [weak self] ticker -> MainMutation? in
        guard let self = self,
              self.exchange == ExchangeSelectionStore.currentExchange else { return nil }
        let updatedList = self.updateSingleCrypto(ticker: ticker)
        return .setTotalCryptoList(cryptoList: updatedList)
      }
      .compactMap { $0 }
      .bind(to: mutationSubject)
      .disposed(by: disposeBag)

    Observable<Int>.interval(.seconds(5), scheduler: MainScheduler.asyncInstance)
      .map { _ in MainAction.validateBTCKRWPrice }
      .bind(to: self.action)
      .disposed(by: disposeBag)
  }
}

// MARK: - Action, Mutation, State
extension MainReactor {
  
  // MARK: Action
  enum MainAction {
	case checkNewVersion
	case loadCryptoList
	case disconnectSocket
    case pauseSocket
    case resumeSocket
    case clearErrorMessage
	case setSortType(sortBy: CryptoSortType)
	case setSelectedTab(tab: SelectedTab)
	case loadUserCryptos
	case loadFearGreedIndex
    case validateBTCKRWPrice
    case settleLegacyBTCMarketHoldings
  }

  enum LegacyBTCSettlementState: Equatable {
    case idle
    case loading
    case completed
    case failed(message: String)
  }
  
  // MARK: Mutation
  /// 상태 변경 단위, 작업 단위
  enum MainMutation {
	case setVersionDifferent(isDiffer: Bool)
	case setTotalCryptoList(cryptoList: [CryptoCellInfo])  // 전체 코인 리스트 (KRW, BTC, USDT)
	case setSortType(sortBy: CryptoSortType)
	case setSelectedTab(tab: SelectedTab)
	case setUserCrypto([CryptoTransactionDataModel]?)	// user cryptos
    case setLoading(isLoading: Bool)
    case setErrorMessage(message: String?)
	case setFearGreedIndex(FearGreedIndex?)
    case setLegacyBTCSettlementState(LegacyBTCSettlementState)
  }
  
  // MARK: State
  struct MainReactorState {
	
	var isVersionDifferent: Bool = false
	
	// 전체 암호화폐 리스트 (KRW + BTC 모두 포함)
	var totalCryptoList: [CryptoCellInfo] = []
	
	var sortBy: CryptoSortType = .normal
	var selectedTab: SelectedTab = .krw
	var preSelectedTab: SelectedTab = .krw
	var userCryptos: [CryptoTransactionDataModel] = []
    var isLoading: Bool = false
    var errorMessage: String?
	var fearGreedIndex: FearGreedIndex?
    var legacyBTCSettlementState: LegacyBTCSettlementState = .idle
  }
}

extension MainReactor {
  
  // Observable 방출
  func mutate(action: MainAction) -> Observable<MainMutation> {
	switch action {
	case .checkNewVersion:
	  return self.checkNewVersion()
	  
	case .loadCryptoList:
	  return self.loadCryptoList()
	  
	case .disconnectSocket:
	  return self.disconnectSocket()

    case .pauseSocket:
      return self.pauseSocket()

    case .resumeSocket:
      return self.resumeSocket()

    case .clearErrorMessage:
      return .just(.setErrorMessage(message: nil))
	  
	case .setSortType(let sortBy):
	  return self.setSortType(sortBy: sortBy)
	  
	case .setSelectedTab(let tab):
	  // 탭 변경 시 정렬 포지션 초기화
	  self.sortedCryptoPosition = [:]
	  
	  // 소켓 메시지 재전송 (**현재 탭의 코인만**)
	  self.sendSocketMessageForCurrentTab(tab)
	  
	  return Observable.just(MainMutation.setSelectedTab(tab: tab))
	  
	case .loadUserCryptos:
	  return .just(.setUserCrypto(UserDataManager.userCryptoList))

	case .loadFearGreedIndex:
	  return self.mainUseCase.loadFearGreedIndex()
		.map { MainMutation.setFearGreedIndex($0) }
		.catch { error in
		  // 조회 실패 시 카드를 숨긴다(nil). 재시도는 다음 화면 진입에 맡긴다.
		  Log.error("loadFearGreedIndex failed: \(error.localizedDescription)")
		  return .just(.setFearGreedIndex(nil))
		}

    case .validateBTCKRWPrice:
      return self.validateBTCKRWPrice()

    case .settleLegacyBTCMarketHoldings:
      return self.settleLegacyBTCMarketHoldings()
	}
  }
  
  func reduce(state: MainReactorState, mutation: MainMutation) -> MainReactorState {
	var newState = state
    self.isSocketConnected = tickerSocketService.isConnected
	switch mutation {
	case .setVersionDifferent(let isDiffer):
	  newState.isVersionDifferent = isDiffer
	  
	case .setTotalCryptoList(let cryptoList):
	  newState.totalCryptoList = cryptoList
	  
	case .setSortType(let sortBy):
	  newState.sortBy = sortBy
	  
	case .setSelectedTab(let tab):
	  newState.preSelectedTab = currentState.selectedTab
	  newState.selectedTab = tab
	case .setUserCrypto(let userCryptos):
	  newState.userCryptos = userCryptos ?? []
    case .setLoading(let isLoading):
      newState.isLoading = isLoading
    case .setErrorMessage(let message):
      newState.errorMessage = message
	case .setFearGreedIndex(let index):
	  newState.fearGreedIndex = index
    case .setLegacyBTCSettlementState(let settlementState):
      newState.legacyBTCSettlementState = settlementState
	}
	return newState
  }
}

extension MainReactor {
  private func settleLegacyBTCMarketHoldings() -> Observable<MainMutation> {
    guard !isLegacySettlementInFlight else { return .empty() }
    guard let holdings = UserDataManager.legacyBTCMarketHoldings() else {
      return .just(.setLegacyBTCSettlementState(
        .failed(message: "저장된 투자내역을 읽을 수 없습니다. 잠시 후 다시 시도해 주세요.")
      ))
    }
    guard !holdings.isEmpty else { return .empty() }

    isLegacySettlementInFlight = true
    let settlement = Observable.deferred {
      Observable.just(try UserDataManager.settleLegacyBTCMarketHoldings())
    }
      .map { _ in MainMutation.setLegacyBTCSettlementState(.completed) }
      .catch { error in
        Log.error("Legacy BTC settlement failed: \(error.localizedDescription)")
        return .just(.setLegacyBTCSettlementState(
          .failed(message: "저장된 평가금액을 확인하지 못해 기존 보유분을 정산하지 못했습니다.")
        ))
      }

    return Observable.concat([
      .just(.setLegacyBTCSettlementState(.loading)),
      settlement
    ])
    .do(onDispose: { [weak self] in
      self?.isLegacySettlementInFlight = false
    })
  }
}

// MARK: - Load Crypto & Socket

extension MainReactor {
  private func initialTickerMarkets(from cryptoList: CryptoList) -> [String] {
    let currentExchange = ExchangeSelectionStore.currentExchange
    Log.info("📊 initial ticker scope exchange=\(currentExchange.rawValue) totalMarkets=\(cryptoList.count)")
    return cryptoList.map { $0.market }
  }

  
  /// 1️⃣ 암호화폐 목록 로드 및 초기 티커 조회
  func loadCryptoList() -> Observable<MainMutation> {
	let request = self.mainUseCase.loadCryptoList()
	  .flatMapLatest { [weak self] cryptoList -> Observable<MainMutation> in
		guard let self = self else { return .empty() }
		
		self.tickerSocketService.connect()
		self.isSocketMonitoringEnabled = true
		
		let initialMarkets = self.initialTickerMarkets(from: cryptoList)
		
		// REST API로 전체 티커 조회
		return self.loadInitialTicker(cryptoList: cryptoList, markets: initialMarkets)
	  }
	
	return Observable.concat([
	  .just(.setLoading(isLoading: true)),
	  request,
	  .just(.setLoading(isLoading: false))
	])
	.catch { error in
	  Log.error("loadCryptoList failed: \(error.localizedDescription)")
	  return Observable.concat([
		.just(.setErrorMessage(message: "시세 데이터를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.")),
		.just(.setLoading(isLoading: false))
	  ])
	}
  }
  
  /// 2️⃣ 초기 REST 티커 조회 후 소켓 연결
  private func loadInitialTicker(
	cryptoList: CryptoList,
	markets: [String]
  ) -> Observable<MainMutation> {
	guard !markets.isEmpty else { return .just(.setTotalCryptoList(cryptoList: [])) }
	
	return self.mainUseCase.loadCryptoTicker(markets: markets)
	  .flatMap { [weak self] cryptoTickerList -> Observable<[CryptoCellInfo]> in
		guard let self = self else { return .just([]) }
		
		// 전체 암호화폐 + 티커 데이터 결합
		let combinedCryptos = self.combineCrypto(
		  cryptoList: cryptoList,
		  cryptoTickerList: cryptoTickerList
		)
		
		// 정렬 적용
		return self.sortedCellInfosObservable(
		  sortBy: self.currentState.sortBy,
		  cellInfos: combinedCryptos
		)
	  }
	  .map { [weak self] sortedCellInfos -> MainMutation in
		guard let self = self else {
		  return MainMutation.setTotalCryptoList(cryptoList: sortedCellInfos)
		}
		self.cacheBTCKRWPrice(from: sortedCellInfos)
		self.sendSocketMessageForCurrentTab(
		  self.currentState.selectedTab,
		  totalList: sortedCellInfos
		)
		return MainMutation.setTotalCryptoList(cryptoList: sortedCellInfos)
	  }
  }

  /// BTC 마켓 보유분을 원화로 환산하려면 다른 화면에서도 BTC/KRW 시세가 필요하다.
  private func cacheBTCKRWPrice(from cellInfos: [CryptoCellInfo]) {
	guard self.exchange == ExchangeSelectionStore.currentExchange,
          let btcHoldingMarket = SettlementCurrency.btc.holdingDisplayMarket,
		  let tradePrice = cellInfos.first(where: { $0.market == btcHoldingMarket })?.tradePrice
	else { return }

	AppDataManager.shared.updateBTCKRWPrice(
	  tradePrice,
	  for: self.exchange
	)
  }
  
  /// 4️⃣ 단일 암호화폐 업데이트 (소켓 티커 수신 시)
  private func updateSingleCrypto(ticker: CryptoSocketTicker) -> [CryptoCellInfo] {
	var updatedList = self.currentState.totalCryptoList
	guard self.exchange == ExchangeSelectionStore.currentExchange else { return updatedList }
	
	// 해당 마켓의 *인덱스* 찾기
	guard let index = updatedList.firstIndex(where: {
	  MarketFormat.apiMarket(fromDisplayMarket: $0.market) == ticker.code
	}) else {
	  return updatedList
	}
	
	if updatedList[index].market == SettlementCurrency.btc.holdingDisplayMarket {
	  AppDataManager.shared.updateBTCKRWPrice(
		ticker.tradePrice,
		for: self.exchange
	  )
	}

	// 해당 코인 정보만 업데이트
	var updatedCrypto = updatedList[index]
	updatedCrypto.prevPrice = ticker.prevClosingPrice
	updatedCrypto.tradePrice = ticker.tradePrice
	updatedCrypto.changePrice = ticker.changePrice
	updatedCrypto.signedChangeRate = ticker.signedChangeRate
	updatedCrypto.change = ticker.change
	updatedCrypto.accTradePrice24h = ticker.accTradePrice24H
	updatedCrypto.accTradeVolume24h = ticker.accTradeVolume24H
	updatedCrypto.highest52WeekPrice = ticker.highest52WeekPrice
	updatedCrypto.lowest52WeekPrice = ticker.lowest52WeekPrice
	
	updatedList[index] = updatedCrypto
	
	// 정렬 포지션이 설정되어 있으면 해당 순서 유지 (정렬 포지션은 전체 코인 정렬되어있음 KRW, BTC)
	if !self.sortedCryptoPosition.isEmpty {
	  return self.applySortedPosition(to: updatedList)
	}
	
	return updatedList
  }
  
  /// 5️⃣ 현재 탭에 맞는 소켓 메시지 전송
  private func sendSocketMessageForCurrentTab(
    _ tab: SelectedTab,
    totalList: [CryptoCellInfo]? = nil
  ) {
	let totalList = totalList ?? self.currentState.totalCryptoList

	var marketsToSubscribe = MarketFormat.apiMarketsForSubscription(
	  tab: tab,
	  totalList: totalList,
	  userCryptos: UserDataManager.userCryptoList,
	  favorites: UserDataManager.userFavoritePairs
	)
	
    let hasBTCHolding = UserDataManager.userCryptoList?.contains {
      $0.staticData.exchange == self.exchange && $0.settlementCurrency == .btc
    } ?? false
    if hasBTCHolding {
      let rateMarket = ExchangeMarketCodeConverter.rawMarketCode(fromDisplayMarket: "BTC/KRW", exchange: self.exchange)
      if !marketsToSubscribe.contains(rateMarket) { marketsToSubscribe.append(rateMarket) }
    }
	tickerSocketService.subscribe(markets: marketsToSubscribe)
  }
  
  /// 소켓 연결 해제
  private func disconnectSocket() -> Observable<MainMutation> {
	isSocketMonitoringEnabled = false
	tickerSocketService.disconnect(userInitiated: true)
    isSocketConnected = tickerSocketService.isConnected
	return .empty()
  }

  private func pauseSocket() -> Observable<MainMutation> {
    isSocketMonitoringEnabled = false
    tickerSocketService.disconnect(userInitiated: true)
    isSocketConnected = tickerSocketService.isConnected
    return .empty()
  }

  private func resumeSocket() -> Observable<MainMutation> {
    isSocketMonitoringEnabled = true
    tickerSocketService.reconnectIfNeeded()
    if !tickerSocketService.isConnected {
      tickerSocketService.connect()
    }
    sendSocketMessageForCurrentTab(currentState.selectedTab)
    isSocketConnected = tickerSocketService.isConnected
    return validateBTCKRWPrice()
  }

  /// 소켓이 끊겼거나 15초간 BTC/KRW 갱신이 없으면 연결을 복구하고 REST로 시세를 검증한다.
  private func validateBTCKRWPrice() -> Observable<MainMutation> {
    guard isSocketMonitoringEnabled else { return .empty() }
    let needsRate = self.currentState.totalCryptoList.contains {
      ExchangeMarketCodeConverter.settlementCurrency(
        fromDisplayMarket: $0.market,
        exchange: self.exchange
      ) == .btc
    } || (UserDataManager.userCryptoList?.contains {
      $0.staticData.exchange == self.exchange && $0.settlementCurrency == .btc
    } ?? false)

    guard needsRate else { return .empty() }

    if !tickerSocketService.isConnected {
      tickerSocketService.reconnectIfNeeded()
      if !tickerSocketService.isConnected { tickerSocketService.connect() }
      sendSocketMessageForCurrentTab(currentState.selectedTab)
    }

    guard self.exchange == ExchangeSelectionStore.currentExchange,
          AppDataManager.shared.needsBTCKRWPriceRefresh(for: self.exchange),
          !self.isBTCKRWRefreshInFlight,
          Date() >= self.nextBTCKRWRefreshAllowedAt,
          let holdingMarket = SettlementCurrency.btc.holdingDisplayMarket else { return .empty() }

    self.isBTCKRWRefreshInFlight = true
    self.nextBTCKRWRefreshAllowedAt = Date().addingTimeInterval(15)
    let market = ExchangeMarketCodeConverter.rawMarketCode(
      fromDisplayMarket: holdingMarket,
      exchange: self.exchange
    )
    return self.mainUseCase.loadCryptoTicker(markets: [market])
      .timeout(.seconds(10), scheduler: MainScheduler.asyncInstance)
      .do(onNext: { [weak self] tickers in
        guard let self else { return }
        guard self.exchange == ExchangeSelectionStore.currentExchange else { return }
        guard let price = tickers.first(where: { $0.market == market })?.tradePrice,
              price.isFinite,
              price > 0 else {
          return
        }
        AppDataManager.shared.updateBTCKRWPrice(price, for: self.exchange)
        self.nextBTCKRWRefreshAllowedAt = .distantPast
      })
      .flatMap { _ in Observable<MainMutation>.empty() }
      .catch { error in
        Log.error("BTC/KRW refresh failed: \(error.localizedDescription)")
        return .empty()
      }
      .do(onDispose: { [weak self] in
        self?.isBTCKRWRefreshInFlight = false
      })
  }
}

// MARK: - Combine Functions
extension MainReactor {
  
  /// CryptoList + CryptoTickerList 결합 (전체 리스트)
  private func combineCrypto(
	cryptoList: CryptoList,
	cryptoTickerList: CryptoTickerList
  ) -> [CryptoCellInfo] {
	
	// 티커를 딕셔너리로 변환 (O(1) 검색)
	let tickerDict = Dictionary(
	  uniqueKeysWithValues: cryptoTickerList.map { ($0.market, $0) }
	)
	
	let combined = cryptoList.compactMap { crypto -> CryptoCellInfo? in
	  guard let ticker = tickerDict[crypto.market] else {
		return nil
	  }

	  return self.makeCryptoCellInfo(crypto: crypto, ticker: ticker)
	}

	// 정렬 해제 시 복귀할 초기 순서 저장 (항상 API 자연 순서)
	self.initialMarketOrder = combined.map { $0.market }
	return combined
  }

  private func makeCryptoCellInfo(
	crypto: Crypto,
	ticker: CryptoTicker
  ) -> CryptoCellInfo {
	CryptoCellInfo(
	  cryptoName: crypto.koreanName,
	  market: MarketFormat.displayMarket(fromAPIMarket: crypto.market),
	  marketEvent: crypto.marketEvent,
	  prevPrice: ticker.prevClosingPrice,
	  tradePrice: ticker.tradePrice,
	  changePrice: ticker.changePrice,
	  signedChangeRate: ticker.signedChangeRate,
	  change: ticker.change,
	  accTradePrice24h: ticker.accTradePrice24h,
	  accTradeVolume24h: ticker.accTradeVolume24h,
	  highest52WeekPrice: ticker.highest52WeekPrice,
	  lowest52WeekPrice: ticker.lowest52WeekPrice
	)
  }
}

// MARK: - Sort
extension MainReactor {
  
  /// 정렬 타입 설정
  func setSortType(sortBy: CryptoSortType) -> Observable<MainMutation> {
	let currentList = self.currentState.totalCryptoList
	
	return self.sortedCellInfosObservable(sortBy: sortBy, cellInfos: currentList)
	  .map { sortedList in
		// 정렬 포지션 저장
		let markets = sortedList.map { $0.market }
		self.sortedCryptoPosition = Dictionary(
		  uniqueKeysWithValues: markets.enumerated().map { ($1, $0) }
		)
		
		return sortedList
	  }
	  .flatMap { sortedList -> Observable<MainMutation> in
		let setSortType = Observable.just(MainMutation.setSortType(sortBy: sortBy))
		let updateList = Observable.just(MainMutation.setTotalCryptoList(cryptoList: sortedList))
		
		return Observable.concat([setSortType, updateList])
	  }
  }
  
  /// Observable로 정렬 결과 반환
  private func sortedCellInfosObservable(
	sortBy: CryptoSortType,
	cellInfos: [CryptoCellInfo]
  ) -> Observable<[CryptoCellInfo]> {
	return Observable.create { emitter in
	  let sortedList = self.sortCryptoCellInfos(sortBy: sortBy, cellInfos: cellInfos)
	  emitter.onNext(sortedList)
	  emitter.onCompleted()
	  return Disposables.create()
	}
  }
  
  /// 정렬 로직
  private func sortCryptoCellInfos(
	sortBy: CryptoSortType,
	cellInfos: [CryptoCellInfo]
  ) -> [CryptoCellInfo] {
	
	switch sortBy {
	case .normal:
	  // 초기(자연) 순서로 복귀
	  guard !self.initialMarketOrder.isEmpty else { return cellInfos }
	  let orderIndex = Dictionary(
		uniqueKeysWithValues: self.initialMarketOrder.enumerated().map { ($1, $0) }
	  )
	  return cellInfos.sorted {
		(orderIndex[$0.market] ?? Int.max) < (orderIndex[$1.market] ?? Int.max)
	  }

	case .currentPriceAscending:
	  return cellInfos.sorted {
		self.isAscendingOrdered($0.tradePrice, $1.tradePrice, lhsMarket: $0.market, rhsMarket: $1.market)
	  }
	  
	case .currentPriceDescending:
	  return cellInfos.sorted {
		self.isDescendingOrdered($0.tradePrice, $1.tradePrice, lhsMarket: $0.market, rhsMarket: $1.market)
	  }
	  
	case .previousDayAscending:
	  return cellInfos.sorted {
		self.isAscendingOrdered($0.signedChangeRate, $1.signedChangeRate, lhsMarket: $0.market, rhsMarket: $1.market)
	  }
	  
	case .previousDayDescending:
	  return cellInfos.sorted {
		self.isDescendingOrdered($0.signedChangeRate, $1.signedChangeRate, lhsMarket: $0.market, rhsMarket: $1.market)
	  }
	  
	case .tradeVolumeAscending:
	  return cellInfos.sorted {
		self.isAscendingOrdered($0.accTradePrice24h, $1.accTradePrice24h, lhsMarket: $0.market, rhsMarket: $1.market)
	  }
	  
	case .tradeVolumeDescending:
	  return cellInfos.sorted {
		self.isDescendingOrdered($0.accTradePrice24h, $1.accTradePrice24h, lhsMarket: $0.market, rhsMarket: $1.market)
	  }

	default:
	  // 보유 탭 전용 정렬은 뷰(표시 시점)에서 처리하므로 리액터에서는 원본 유지
	  return cellInfos
	}
  }

  private func isAscendingOrdered(
	_ lhs: Double?,
	_ rhs: Double?,
	lhsMarket: String,
	rhsMarket: String
  ) -> Bool {
	switch (lhs, rhs) {
	case let (left?, right?):
	  return left == right ? lhsMarket < rhsMarket : left < right
	case (nil, nil):
	  return lhsMarket < rhsMarket
	case (nil, _?):
	  return false
	case (_?, nil):
	  return true
	}
  }

  private func isDescendingOrdered(
	_ lhs: Double?,
	_ rhs: Double?,
	lhsMarket: String,
	rhsMarket: String
  ) -> Bool {
	switch (lhs, rhs) {
	case let (left?, right?):
	  return left == right ? lhsMarket < rhsMarket : left > right
	case (nil, nil):
	  return lhsMarket < rhsMarket
	case (nil, _?):
	  return false
	case (_?, nil):
	  return true
	}
  }
  
  /// 정렬된 포지션 적용
  private func applySortedPosition(to cryptoList: [CryptoCellInfo]) -> [CryptoCellInfo] {
	let cryptoDict = Dictionary(
	  uniqueKeysWithValues: cryptoList.map { ($0.market, $0) }
	)
	
	return self.sortedCryptoPosition
	  .sorted { $0.value < $1.value }
	  .compactMap { cryptoDict[$0.key] }
  }
}

// MARK: - Helper Functions
extension MainReactor {
  /// 'KRW-BTC' → 'BTC/KRW' 변환
  func transformMarketForm(market: String) -> String {
	return MarketFormat.displayMarket(fromAPIMarket: market)
  }
  
  /// 'BTC/KRW' → 'KRW-BTC' 역변환
  private func reverseTransformMarketForm(market: String) -> String {
	return MarketFormat.apiMarket(fromDisplayMarket: market)
  }
  
  /// 앱 버전 체크
  func checkNewVersion() -> Observable<MainMutation> {
	let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
	
	return Observable.create { observer in
	  self.fetchAppStoreVersion { appStoreVersion in
		guard let appStoreVersion = appStoreVersion else {
		  observer.onNext(.setVersionDifferent(isDiffer: false))
		  observer.onCompleted()
		  return
		}
		
		let isNewer = self.isAppStoreVersionNewer(current: currentVersion, appStore: appStoreVersion)
		observer.onNext(.setVersionDifferent(isDiffer: isNewer))
		observer.onCompleted()
	  }
	  
	  return Disposables.create()
	}
  }
  
  func fetchAppStoreVersion(completion: @escaping (String?) -> Void) {
	guard let url = URL(string: "https://itunes.apple.com/lookup?id=6747009759") else {
	  completion(nil)
	  return
	}
	
	URLSession.shared.dataTask(with: url) { data, _, error in
	  guard error == nil,
			let data = data,
			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let results = json["results"] as? [[String: Any]],
			let version = results.first?["version"] as? String else {
		completion(nil)
		return
	  }
	  completion(version)
	}.resume()
  }
  
  func isAppStoreVersionNewer(current: String, appStore: String) -> Bool {
	let currentComponents = current.split(separator: ".").map { Int($0) ?? 0 }
	let appStoreComponents = appStore.split(separator: ".").map { Int($0) ?? 0 }
	
	let maxCount = max(currentComponents.count, appStoreComponents.count)
	let paddedCurrent = currentComponents + Array(repeating: 0, count: maxCount - currentComponents.count)
	let paddedAppStore = appStoreComponents + Array(repeating: 0, count: maxCount - appStoreComponents.count)
	
	for (curr, store) in zip(paddedCurrent, paddedAppStore) {
	  if store > curr { return true }
	  if store < curr { return false }
	}
	
	return false
  }

  func transform(mutation: Observable<MainMutation>) -> Observable<MainMutation> {
    Observable.merge(
      mutation,
      mutationSubject.asObservable()
    )
  }
}
