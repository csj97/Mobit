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
  private let mainUseCase: MainUseCase
  private let disposeBag = DisposeBag()
  
  // ReactorKit 외부에서 mutation을 주입하려면 이게 필요
  private let mutationSubject = PublishSubject<MainMutation>()
  
  var socketManager: NewWebSocketManager? = nil
  
  // 탭별 정렬 포지션을 **하나로 통합**
  private var sortedCryptoPosition: [String: Int] = [:]
  
  let initialState: MainReactorState = MainReactorState()
  private var firebaseDB = Database.database().reference()
  
  init(mainUseCase: MainUseCase) {
	self.mainUseCase = mainUseCase
	
	UserDataManager.userCryptoListObservable
	  .map { MainMutation.setUserCrypto($0) }
	  .bind(to: mutationSubject)
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
	case setSortType(sortBy: CryptoSortType)
	case setSelectedTab(tab: SelectedTab)
	case loadUserCryptos
  }
  
  // MARK: Mutation
  /// 상태 변경 단위, 작업 단위
  enum MainMutation {
	case setVersionDifferent(isDiffer: Bool)
	case setTotalCryptoList(cryptoList: [CryptoCellInfo])  // 전체 코인 리스트 (KRW, BTC, USDT)
	case setSortType(sortBy: CryptoSortType)
	case setSelectedTab(tab: SelectedTab)
	case setUserCrypto([CryptoTransactionDataModel]?)	// user cryptos
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
	}
  }
  
  func reduce(state: MainReactorState, mutation: MainMutation) -> MainReactorState {
	var newState = state
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
	}
	return newState
  }
}

// MARK: - Load Crypto & Socket

extension MainReactor {
  
  /// 1️⃣ 암호화폐 목록 로드 및 초기 티커 조회
  func loadCryptoList() -> Observable<MainMutation> {
	return self.mainUseCase.loadCryptoList()
	  .flatMapLatest { [weak self] cryptoList -> Observable<MainMutation> in
		guard let self = self else { return .empty() }
		
		// 소켓 연결 보장
		self.ensureSocketConnected()
		
		// 전체 마켓 목록 (KRW + BTC)
		let allMarkets = cryptoList.map { $0.market }
		
		// REST API로 전체 티커 조회
		return self.loadInitialTicker(cryptoList: cryptoList, markets: allMarkets)
	  }
  }
  
  /// 2️⃣ 초기 REST 티커 조회 후 소켓 연결
  private func loadInitialTicker(
	cryptoList: CryptoList,
	markets: [String]
  ) -> Observable<MainMutation> {
	guard !markets.isEmpty else { return .empty() }
	
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
	  .flatMap { [weak self] sortedCellInfos -> Observable<MainMutation> in
		guard let self = self else { return .empty() }
		
		// 정렬된 전체 리스트를 totalCryptoList에 저장
		let setListMutation = Observable.just(
		  MainMutation.setTotalCryptoList(cryptoList: sortedCellInfos)
		)
		
		// 소켓 스트림 시작 (현재 탭의 코인만)
		let socketStream = self.startSocketStream()
		
		return Observable.concat([setListMutation, socketStream])
	  }
  }
  
  /// 3️⃣ 소켓 스트림 시작 (**현재 탭의 코인만 구독**)
  private func startSocketStream() -> Observable<MainMutation> {
	return Observable.create { [weak self] observer in
	  guard let self = self,
			let socketManager = self.socketManager else {
		observer.onCompleted()
		return Disposables.create()
	  }
	  
	  // 소켓 연결 시 **현재 탭**의 마켓만 전송
	  socketManager.onConnected = { [weak self] in
		self?.sendSocketMessageForCurrentTab(self?.currentState.selectedTab ?? .krw)
	  }
	  
	  // 현재 탭의 마켓 전송
	  self.sendSocketMessageForCurrentTab(self.currentState.selectedTab)
	  
	  // 소켓 티커 데이터 수신
	  socketManager.tickerDataSubject
		.observe(on: MainScheduler.instance)
		.subscribe(onNext: { [weak self] data in
		  guard let self = self else { return }
		  
		  do {
			let cryptoTickerDTO = try JSONDecoder().decode(
			  CryptoSocketTickerDTO.self,
			  from: data
			)
			let ticker = cryptoTickerDTO.toDomain()
			
			// 전체 리스트에서 해당 코인만 업데이트
			let updatedList = self.updateSingleCrypto(ticker: ticker)
			
			observer.onNext(MainMutation.setTotalCryptoList(cryptoList: updatedList))
			
		  } catch {
			Log.error("Socket ticker decode error: \(error.localizedDescription)")
		  }
		})
		.disposed(by: self.disposeBag)
	  
	  return Disposables.create {
		socketManager.disconnect()
	  }
	}
  }
  
  /// 4️⃣ 단일 암호화폐 업데이트 (소켓 티커 수신 시)
  private func updateSingleCrypto(ticker: CryptoSocketTicker) -> [CryptoCellInfo] {
	var updatedList = self.currentState.totalCryptoList
	
	// 해당 마켓의 *인덱스* 찾기
	guard let index = updatedList.firstIndex(where: {
	  self.reverseTransformMarketForm(market: $0.market) == ticker.code
	}) else {
	  return updatedList
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
  private func sendSocketMessageForCurrentTab(_ tab: SelectedTab) {
	guard let socketManager = self.socketManager else { return }
	
	let totalList = self.currentState.totalCryptoList
	
	// 탭에 따른 필터링 마켓 목록
	let marketsToSubscribe: [String] = {
	  switch tab {
	  case .hold:
		return totalList
		  .filter { $0.market.contains("/KRW") }
		  .map { self.reverseTransformMarketForm(market: $0.market) }
		
	  case .krw:
		return totalList
		  .filter { $0.market.contains("/KRW") }
		  .map { self.reverseTransformMarketForm(market: $0.market) }
		
	  case .btc:
		return totalList
		  .filter { $0.market.contains("/BTC") }
		  .map { self.reverseTransformMarketForm(market: $0.market) }
		
	  case .favorite:
		// Set을 사용한 이유 : Array보다 해시테이블을 조회하기 때문에 탐색 시간이 빠름
		let favorites = Set(UserDataManager.userFavoriteList)
		return totalList
		  .filter { favorites.contains($0.market) }
		  .map { self.reverseTransformMarketForm(market: $0.market) }
	  }
	}()
	
	// 소켓에 해당 마켓만 구독 요청
	socketManager.sendMessage(codes: marketsToSubscribe, socketType: .ticker)
  }
  
  /// 소켓 연결 해제
  private func disconnectSocket() -> Observable<MainMutation> {
	guard let socketManager = self.socketManager else { return .empty() }
	socketManager.disconnect()
	self.socketManager = nil
	return .empty()
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
	
	return cryptoList.compactMap { crypto in
	  guard let ticker = tickerDict[crypto.market] else {
		return nil
	  }
	  
	  return CryptoCellInfo(
		cryptoName: crypto.koreanName,
		market: self.transformMarketForm(market: crypto.market),
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
	  return cellInfos
	  
	case .currentPriceAscending:
	  return cellInfos.sorted { ($0.tradePrice ?? 0) < ($1.tradePrice ?? 0) }
	  
	case .currentPriceDescending:
	  return cellInfos.sorted { ($0.tradePrice ?? 0) > ($1.tradePrice ?? 0) }
	  
	case .previousDayAscending:
	  return cellInfos.sorted { ($0.signedChangeRate ?? 0) < ($1.signedChangeRate ?? 0) }
	  
	case .previousDayDescending:
	  return cellInfos.sorted { ($0.signedChangeRate ?? 0) > ($1.signedChangeRate ?? 0) }
	  
	case .tradeVolumeAscending:
	  return cellInfos.sorted { ($0.accTradePrice24h ?? 0) < ($1.accTradePrice24h ?? 0) }
	  
	case .tradeVolumeDescending:
	  return cellInfos.sorted { ($0.accTradePrice24h ?? 0) > ($1.accTradePrice24h ?? 0) }
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
  
  /// 소켓 연결 보장
  private func ensureSocketConnected() {
	if let socket = self.socketManager {
	  if !socket.isConnected {
		socket.reconnectIfNeeded()
	  }
	} else {
	  self.socketManager = NewWebSocketManager()
	  self.socketManager?.connect()
	}
  }
  
  /// 'KRW-BTC' → 'BTC/KRW' 변환
  func transformMarketForm(market: String) -> String {
	let components = market.split(separator: "-")
	guard components.count == 2 else { return market }
	return "\(components[1])/\(components[0])"
  }
  
  /// 'BTC/KRW' → 'KRW-BTC' 역변환
  private func reverseTransformMarketForm(market: String) -> String {
	let components = market.split(separator: "/")
	guard components.count == 2 else { return market }
	return "\(components[1])-\(components[0])"
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
}
