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
  case krw, btc, favorite
//  case krw, favorite
}

class MainReactor: Reactor {
  private let mainUseCase: MainUseCase
  private let disposeBag = DisposeBag()
  private var sortedCryptoPositionKRW: [String: Int] = [:]
  private var sortedCryptoPositionBTC: [String: Int] = [:]
//  let socketManager: NewWebSocketManager = NewWebSocketManager()
  var socketManager: NewWebSocketManager? = nil
  let initialState: MainReactorState = MainReactorState()
  private var firebaseDB = Database.database().reference()
  
  init(mainUseCase: MainUseCase) {
    self.mainUseCase = mainUseCase
  }
}

// 기본 설정
extension MainReactor {
  enum MainAction {
	case checkNewVersion
    case loadCrypto
    case loadSocketTicker(cryptoList: CryptoList)
    case disconnectSocket
    case setSortType(sortBy: CryptoSortType)
	case setSelectedTab(tab: SelectedTab)
  }
  
  /// 상태 변경 단위, 작업 단위
  enum MainMutation {
	case setVersionDifferent(isDiffer: Bool)
    case loadCrypto(list: CryptoList)
    
    case setTabCryptoList(cryptoList: CryptoList)
    case setCombinedArray(cryptoCellInfo: [CryptoCellInfo])
    case setSortType(sortBy: CryptoSortType)
	case setSelectedTab(tab: SelectedTab)
  }
  
  struct MainReactorState {
	
	var isVersionDifferent: Bool = false
	
    // krw, btc, usdt
	var cryptoList: CryptoList = []
	var krwCryptoList: [CryptoCellInfo] = []
	var btcCryptoList: [CryptoCellInfo] = []
    
    var tabCryptoList: CryptoList = []
    // Cell에 필요한 정보들을 모아 놓은 모델 변수
    var cryptoCellInfos: [CryptoCellInfo] = []
    var cryptoSocketTicker: CryptoSocketTicker? = nil
    var sortBy: CryptoSortType = .normal
	var selectedTab: SelectedTab = .krw
  }
}

extension MainReactor {
  // Observable 방출
  func mutate(action: MainAction) -> Observable<MainMutation> {
    switch action {
	case .checkNewVersion:
	  return self.checkNewVersion()
	  
    case .loadCrypto:
	  return self.loadCryptoTicker()
      
    case .loadSocketTicker(let cryptoList):
	  let selectedTab = self.currentState.selectedTab
      return self.loadSocketTicker(selectedTab: selectedTab, cryptoList: cryptoList)
      
    case .disconnectSocket:
      return self.disconnectSocket()
      
    case .setSortType(let sortBy):
      return self.setSortType(sortBy: sortBy)
	  
	case .setSelectedTab(let tab):
	  // 탭이 바뀌면 이전 탭의 정렬 포지션은 초기화. > 다음에 다시 탭 전환되어 왔을 때, 기준으로 다시 정렬되어야 함.
	  if tab == .krw {
		self.sortedCryptoPositionBTC = [:]
	  } else if tab == .btc {
		self.sortedCryptoPositionKRW = [:]
	  }
	  return Observable.just( MainMutation.setSelectedTab(tab: tab) )
    }
  }
  
  // View 업데이트
  func reduce(state: MainReactorState, mutation: MainMutation) -> MainReactorState {
    var newState = state
    switch mutation {
	case .setVersionDifferent(let isDiffer):
	  newState.isVersionDifferent = isDiffer
	  
    case .loadCrypto(let cryptoList):
      newState.cryptoList = cryptoList
      
    case .setTabCryptoList(let cryptoList):
      newState.tabCryptoList = cryptoList
      
    case .setCombinedArray(let combinedResult):
	  if currentState.selectedTab == .krw {
		newState.krwCryptoList = combinedResult
	  } else {
		newState.btcCryptoList = combinedResult
	  }
      newState.cryptoCellInfos = combinedResult
      
    case .setSortType(let sortBy):
      newState.sortBy = sortBy
	  
	case .setSelectedTab(let tab):
	  newState.selectedTab = tab
    }
    return newState
  }
  
  /// CryptoList를 조회하고 이어서 바로 CryptoTicker를 조회한다. (SocketTicker와는 다름)
  /// - Returns: CryptoList와 CryptoTicker 구조체를 합쳐서 observer에 담고, MainMutation에 대한 Observable을 반환
  func loadCryptoTicker() -> Observable<MainMutation> {
    let loadCryptoObservable = self.mainUseCase.loadCryptoList()
      .flatMap { cryptoList -> Observable<MainMutation> in
        
        var observableConcat: [Observable<MainMutation>] = []
		
		if let _ = self.socketManager {
		  // socketManager 있으면 그냥 진행
		} else {
		  self.socketManager = NewWebSocketManager()
		  self.socketManager?.connect()
		}
		
		let selectedTab = self.currentState.selectedTab
		switch selectedTab {
        case .krw:
          let krwCryptoList = cryptoList.filter { $0.market.contains("KRW-") }
          let krwMarkets = krwCryptoList.map { $0.market }
          
          let setKRWCryptoMutation = Observable.just(
            MainMutation.setTabCryptoList(cryptoList: krwCryptoList)
          )
          let tickerObservable = self.loadTicker(
            selectedTab: selectedTab,
            cryptoList: krwCryptoList,
            markets: krwMarkets
          )
          observableConcat = [setKRWCryptoMutation, tickerObservable]
          
        case .btc:
          let btcCryptoList = cryptoList.filter { $0.market.contains("BTC-") }
          let btcMarkets = btcCryptoList.map { $0.market }

          let setBTCCryptoMutation = Observable.just(
            MainMutation.setTabCryptoList(cryptoList: btcCryptoList)
          )
          let tickerObservable = self.loadTicker(
            selectedTab: selectedTab,
            cryptoList: btcCryptoList,
            markets: btcMarkets
          )
          observableConcat = [setBTCCryptoMutation, tickerObservable]
          
        case .favorite:
          break
        }
        
        return Observable.concat(observableConcat)
      }
      .catch { error in
        return Observable.error(error)
      }
    
    return loadCryptoObservable
  }
  
  func loadTicker(
    selectedTab: SelectedTab,
    cryptoList: CryptoList,
    markets: [String]
  ) -> Observable<MainMutation> {
    
    let tickerObservable = Observable<MainMutation>.create { observer in
      let cryptoTickerObservable = self.mainUseCase.loadTickerList(markets: markets)
      
      cryptoTickerObservable.subscribe { cryptoTickerList in
        let combineCryptos = self.combineCrypto(
          selectedTab: selectedTab,
          cryptoList: cryptoList,
          cryptoTickerList: cryptoTickerList
        )
        
        self.sortCryptoCellInfos(
          sortBy: self.currentState.sortBy,
          cellInfos: combineCryptos
        ) { sortedCellInfos in
          
          guard let sortedCellInfos = sortedCellInfos else { return }
          
		  let sortedCryptoPosition = selectedTab == .krw ? self.sortedCryptoPositionKRW	: self.sortedCryptoPositionBTC
		  
          if sortedCryptoPosition.count == 0 {
			// 탭이 바뀌었는데, 이전 정렬된 포지션 정보가 없으면 여길로 들어옴
            observer.onNext(.setCombinedArray(cryptoCellInfo: sortedCellInfos))
            observer.onCompleted()
          } else {
            self.updateCryptoCellPositions(
			  positionedCryptoInfos: sortedCryptoPosition,
              cryptoCellInfos: sortedCellInfos
            ) { sortedCombineResult in
              guard let sortedCombineResult = sortedCombineResult else { return }
              observer.onNext(
                .setCombinedArray(cryptoCellInfo: sortedCombineResult)
              )
              observer.onCompleted()
            }
          }
        }
      }.disposed(by: self.disposeBag)
      
      return Disposables.create()
    }
    
	tickerObservable
	  .subscribe { mutaion in
		switch mutaion {
		case .completed:
		  self.action.onNext(
			.loadSocketTicker(cryptoList: self.currentState.tabCryptoList)
		  )
		case .next:
		  break
		case .error(let error):
		  Log.error("error : \(error.localizedDescription)")
		}
	  }.disposed(by: self.disposeBag)
	
    return tickerObservable
  }
  
  // MARK: - Combine Function
  
  /// CryptoList & CryptoTickerList 모델을 합치는 과정
  /// - Parameters:
  ///   - cryptoList: name, market, event 정보를 갖고 있음
  ///   - cryptoTickerList: tradePrice, signedChangeRate, change, accTradeVolume 정보를 갖고 있음
  /// - Returns: Main TableView Cell에 노출될 Cell 정보를 결합해서 반환
  func combineCrypto(
    selectedTab: SelectedTab,
    cryptoList: CryptoList,
    cryptoTickerList: CryptoTickerList
  ) -> [CryptoCellInfo] {
    var filteredCryptoList: CryptoList = []
    
    switch selectedTab {
    case .krw:
      filteredCryptoList = cryptoList.filter { $0.market.contains("KRW-") }
      
    case .btc:
      filteredCryptoList = cryptoList.filter { $0.market.contains("BTC-") }
      
    case .favorite:
      break
    }
    
    let cellInfos: [CryptoCellInfo] = filteredCryptoList.compactMap { crypto in
      return CryptoCellInfo(
        cryptoName: crypto.koreanName,
        market: crypto.market,
        marketEvent: crypto.marketEvent
      )
    }
    
    let cryptoCells: [CryptoCellInfo] = cellInfos.compactMap { cryptoCellInfo in
      guard let matchedTicker = cryptoTickerList.first(where: { $0.market == cryptoCellInfo.market }) else {
        return CryptoCellInfo(cryptoName: "", market: "", marketEvent: nil)
      }
      var updatedCryptoCellInfo = cryptoCellInfo
      updatedCryptoCellInfo.market = self.transformMarketForm(market: cryptoCellInfo.market)
      updatedCryptoCellInfo.prevPrice = matchedTicker.prevClosingPrice
      updatedCryptoCellInfo.tradePrice = matchedTicker.tradePrice
      updatedCryptoCellInfo.changePrice = matchedTicker.changePrice
      updatedCryptoCellInfo.signedChangeRate = matchedTicker.signedChangeRate
      updatedCryptoCellInfo.change = matchedTicker.change
	  updatedCryptoCellInfo.accTradePrice24h = matchedTicker.accTradePrice24h
	  updatedCryptoCellInfo.accTradeVolume24h = matchedTicker.accTradeVolume24h
	  updatedCryptoCellInfo.highest52WeekPrice = matchedTicker.highest52WeekPrice
	  updatedCryptoCellInfo.lowest52WeekPrice = matchedTicker.lowest52WeekPrice
      
      return updatedCryptoCellInfo
    }
    
    return cryptoCells
  }
  
  /// CryptoList & CryptoSocketTicker 모델을 합치는 과정 (ticker랑 socket ticker랑 제공되는 데이터가 다름)
  func combineTicker(
    selectedTab: SelectedTab,
    cryptoList: CryptoList,
    socketTicker: CryptoSocketTicker
  ) -> [CryptoCellInfo] {
    var filteredCryptoList: CryptoList = []
    
    switch selectedTab {
    case .krw:
      filteredCryptoList = cryptoList.filter { $0.market.contains("KRW-") }
      
    case .btc:
      filteredCryptoList = cryptoList.filter { $0.market.contains("BTC-") }
      
    case .favorite:
      break
    }
    
    let cellInfos: [CryptoCellInfo] = filteredCryptoList.compactMap { crypto in
      return CryptoCellInfo(cryptoName: crypto.koreanName, market: crypto.market, marketEvent: crypto.marketEvent)
    }
    let cryptoCells: [CryptoCellInfo] = cellInfos.compactMap { cryptoCellInfo in
      var updatedCryptoCellInfo = cryptoCellInfo
      
      if socketTicker.code == cryptoCellInfo.market {
        updatedCryptoCellInfo.market = self.transformMarketForm(market: cryptoCellInfo.market)
        updatedCryptoCellInfo.prevPrice = socketTicker.prevClosingPrice
        updatedCryptoCellInfo.tradePrice = socketTicker.tradePrice
        updatedCryptoCellInfo.changePrice = socketTicker.changePrice
        updatedCryptoCellInfo.signedChangeRate = socketTicker.signedChangeRate
        updatedCryptoCellInfo.change = socketTicker.change
        updatedCryptoCellInfo.accTradePrice24h = socketTicker.accTradePrice24H
		updatedCryptoCellInfo.accTradeVolume24h = socketTicker.accTradeVolume24H
		updatedCryptoCellInfo.highest52WeekPrice = socketTicker.highest52WeekPrice
		updatedCryptoCellInfo.lowest52WeekPrice = socketTicker.lowest52WeekPrice
        
        return updatedCryptoCellInfo
      } else {
        
        return nil
      }
    }
    
    return self.currentState.cryptoCellInfos.map { cellInfo in
      cryptoCells.first(where: { $0.cryptoName == cellInfo.cryptoName }) ?? cellInfo
    }
  }
  
  
  /// 'KRW-BTC' 형태의 종목 구분 코드를 'BTC/KRW' 형태로 변환 시키는 메소드
  /// - Parameter market: 변환 대상이 되는 종목 구분 코드
  /// - Returns: 'BTC/KRW' 형태의 String
  func transformMarketForm(market: String) -> String {
    var transformMarket = market
    let components = transformMarket.split(separator: "-")
    if components.count == 2 {
      transformMarket = "\(components[1])/\(components[0])"
    } else {
      // 기본값 유지
      transformMarket = market
    }
    return transformMarket
  }
  
  // WebSocket Ticker
  private func loadSocketTicker(
    selectedTab: SelectedTab,
    cryptoList: CryptoList
  ) -> Observable<MainMutation> {
    let cryptoJoined = cryptoList.map { $0.market }
    
    let socketObservable = Observable<MainMutation>.create { observer in
      
	  guard let socketManager = self.socketManager else {
		return Disposables.create {
		  self.socketManager?.disconnect()
		}
	  }
	  
	  socketManager.onConnected = {
		socketManager.sendMessage(
		  codes: cryptoJoined,
		  socketType: .ticker
		)
	  }
      
      socketManager.tickerDataSubject
        .observe(on: MainScheduler.instance)
        .subscribe { [weak self] data in
          guard let self = self else { return }

          do {
            let decodeTarget = CryptoSocketTickerDTO.self
            let cryptoTickerDTO = try JSONDecoder().decode(decodeTarget, from: data)
            let ticker = cryptoTickerDTO.toDomain()
            var combineResult = self.combineTicker(
              selectedTab: selectedTab,
              cryptoList: cryptoList,
              socketTicker: ticker
            )
            
            // 현재 정렬 타입으로 맞춤
//            self.sortCryptoCellInfos(
//              sortBy: currentState.sortBy,
//              cellInfos: combineResult,
//              completion: { sortedCellInfos in
//                
//                guard let sortedCellInfos = sortedCellInfos else { return }
//                combineResult = sortedCellInfos
//                
//                // 정렬된 배열 > 포지션 찾아가기 (포지션이 설정되어 있다면)
//				let sortedCryptoPosition = selectedTab == .krw ? self.sortedCryptoPositionKRW : self.sortedCryptoPositionBTC
//				if sortedCryptoPosition.count > 0 {
//                  self.updateCryptoCellPositions(
//					positionedCryptoInfos: sortedCryptoPosition,
//                    cryptoCellInfos: combineResult
//                  ) { sortedCombineResult in
//                    guard let sortedCombineResult = sortedCombineResult else { return }
//                    observer.onNext(
//                      .setCombinedArray(cryptoCellInfo: sortedCombineResult)
//                    )
//                  }
//                } else {
//                  // 일단 포지션 설정보단 레이아웃 설정
//                  observer.onNext(
//                    .setCombinedArray(cryptoCellInfo: combineResult)
//                  )
//                }
//              }
//            )
			
			// 정렬된 배열 > 포지션 찾아가기 (포지션이 설정되어 있다면)
			let sortedCryptoPosition = selectedTab == .krw ? self.sortedCryptoPositionKRW : self.sortedCryptoPositionBTC
			if sortedCryptoPosition.count > 0 {
			  self.updateCryptoCellPositions(
				positionedCryptoInfos: sortedCryptoPosition,
				cryptoCellInfos: combineResult
			  ) { sortedCombineResult in
				guard let sortedCombineResult = sortedCombineResult else { return }
				observer.onNext(
				  .setCombinedArray(cryptoCellInfo: sortedCombineResult)
				)
			  }
			} else {
			  // 일단 포지션 설정보단 레이아웃 설정
			  observer.onNext(
				.setCombinedArray(cryptoCellInfo: combineResult)
			  )
			}
            
          } catch {
			Log.error("MainReactor ticker websocket receive decoding error : \(error.localizedDescription)")
          }
        } onError: { error in
          observer.onError(error)
        } onCompleted: {
          observer.onCompleted()
        }.disposed(by: self.disposeBag)
      
      return Disposables.create {
        socketManager.disconnect()
      }
    }
    
    return socketObservable
  }
  
  /// SocketManager Disconnect
  private func disconnectSocket() -> Observable<MainMutation> {
	guard let socketManager = self.socketManager else { return .empty() }
    socketManager.disconnect()
	self.socketManager = nil
    return .empty()
  }
  
  /// Sort Type Setting
  func setSortType(sortBy: CryptoSortType) -> Observable<MainMutation> {
	var cryptoCellInfos: [CryptoCellInfo] = []
	if currentState.selectedTab == .krw {
	  cryptoCellInfos = currentState.krwCryptoList
	} else {
	  cryptoCellInfos = currentState.btcCryptoList
	}
	
    self.sortCryptoCellInfos(
      sortBy: sortBy,
	  cellInfos: cryptoCellInfos
	) { sortedCellInfos in
	  guard let sortedCellInfos = sortedCellInfos else { return }
	  
	  cryptoCellInfos = sortedCellInfos
	  
	  // 매번 소켓 데이터 수신때마다 하는 것이 아닌, 정렬 초기에 포지션 저장
	  let markets = sortedCellInfos.map({ $0.market })
	  let sortedCryptoPosition = Dictionary(
		uniqueKeysWithValues: markets.enumerated().map { ($1, $0) }
	  )
	  
	  if self.currentState.selectedTab == .krw {
		self.sortedCryptoPositionKRW = sortedCryptoPosition
	  } else {
		self.sortedCryptoPositionBTC = sortedCryptoPosition
	  }
    }
    
    // 포지션 저장하는 것과 별개로 sort type setting
	let setSortType = Observable.just(MainMutation.setSortType(sortBy: sortBy))
	let updateList = Observable.just(MainMutation.setCombinedArray(cryptoCellInfo: cryptoCellInfos))
	
	return Observable.concat([setSortType, updateList])
//    return Observable.just(
//      MainMutation.setSortType(sortBy: sortBy)
//    )
  }
  
  /// crypto cell infos 정렬
  func sortCryptoCellInfos(
    sortBy: CryptoSortType,
    cellInfos: [CryptoCellInfo],
    completion: @escaping ([CryptoCellInfo]?) -> ()
  ) {
    var sortedCellInfos: [CryptoCellInfo]? = nil
    
    switch sortBy {
    case .normal:
      sortedCellInfos = cellInfos
    case .currentPriceAscending:
      sortedCellInfos = cellInfos.sorted(
        by: { $0.tradePrice ?? 0 < $1.tradePrice ?? 0 }
      )
    case .currentPriceDescending:
      sortedCellInfos = cellInfos.sorted(
        by: { $0.tradePrice ?? 0 > $1.tradePrice ?? 0 }
      )
    case .previousDayAscending:
      sortedCellInfos = cellInfos.sorted(
        by: { $0.signedChangeRate ?? 0 < $1.signedChangeRate ?? 0 }
      )
    case .previousDayDescending:
      sortedCellInfos = cellInfos.sorted(
        by: { $0.signedChangeRate ?? 0 > $1.signedChangeRate ?? 0 }
      )
    case .tradeVolumeAscending:
      sortedCellInfos = cellInfos.sorted(
        by: { $0.accTradePrice24h ?? 0 < $1.accTradePrice24h ?? 0 }
      )
    case .tradeVolumeDescending:
      sortedCellInfos = cellInfos.sorted(
        by: { $0.accTradePrice24h ?? 0 > $1.accTradePrice24h ?? 0 }
      )
    }
    
    guard let sortedCellInfos = sortedCellInfos else {
      completion(nil)
      return
    }
    completion(sortedCellInfos)
  }
  
  
  /// 정렬 기준에 따라 설정된 crypto position
  /// 다음 소켓 데이터에선 그 포지션에 따라 정렬되어야함
  /// 타입에 따라 새로 소켓이 들어올 때마다 정렬하면 보이는 위치가 계속 달라짐
  func updateCryptoCellPositions(
	positionedCryptoInfos: [String: Int],
    cryptoCellInfos: [CryptoCellInfo],
    completion: @escaping ([CryptoCellInfo]?) -> ()
  ) {
	let selectedTab = currentState.selectedTab
    if positionedCryptoInfos.count > 0 {
      let cryptoInfoDict = Dictionary(
        uniqueKeysWithValues: cryptoCellInfos.map { ($0.market, $0) }
      )
	  // todo : krw 에서 정렬하고 btc 탭하면 키값이 달라서 nil이 반환됨. 그렇기 때문에 탭별 포지션데이터를 따로 관리해야할듯
	  // 만약 btc로 넘어왔는데 없으면, 정렬 방식을 btc 데이터에 적용
      let newPositionedCryptoInfos = positionedCryptoInfos
        .sorted { $0.value < $1.value }
        .compactMap { cryptoInfoDict[$0.key] }  // 해당 인덱스의 크립토 정보를 맵핑
      completion(newPositionedCryptoInfos)
    } else {
      completion(nil)
    }
  }
  
  /// 새로운 버전 확인
  func checkNewVersion() -> Observable<MainMutation>{
	let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
	
	let observable = Observable<MainMutation>.create { observer in
	  
	  self.fetchAppStoreVersion { appStoreVersion in
		guard let appStoreVersion = appStoreVersion else { return }
		
		if self.isAppStoreVersionNewer(current: currentVersion, appStore: appStoreVersion) {
		  // 새로운 버전이 있을 경우
		  observer.onNext(
			.setVersionDifferent(isDiffer: true)
		  )
		} else {
		  observer.onNext(
			.setVersionDifferent(isDiffer: false)
		  )
		}
		observer.onCompleted()
	  }
	  
	  return Disposables.create()
	}
	
	return observable
  }
  
  /// 앱 스토어에 등록된 버전
  func fetchAppStoreVersion(completion: @escaping (String?) -> Void) {
	guard let url = URL(string: "https://itunes.apple.com/lookup?id=6747009759") else {
	  completion(nil)
	  return
	}
	
	let task = URLSession.shared.dataTask(with: url) { data, _, error in
	  guard
		error == nil,
		let data = data,
		let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
		let results = json["results"] as? [[String: Any]],
		let appStoreVersion = results.first?["version"] as? String
	  else {
		completion(nil)
		return
	  }
	  
	  completion(appStoreVersion)
	}
	
	task.resume()
  }
  
  /// 앱 버전 비교
  func isAppStoreVersionNewer(current: String, appStore: String) -> Bool {
	let currentComponents = current.split(separator: ".").map { Int($0) ?? 0 }
	let appStoreComponents = appStore.split(separator: ".").map { Int($0) ?? 0 }
	
	// 배열의 길이를 맞추기 위해, 짧은 쪽에 0을 채워준다.
	let maxCount = max(currentComponents.count, appStoreComponents.count)
	let paddedCurrent = currentComponents + Array(repeating: 0, count: maxCount - currentComponents.count)
	let paddedAppStore = appStoreComponents + Array(repeating: 0, count: maxCount - appStoreComponents.count)
	
	for (curr, store) in zip(paddedCurrent, paddedAppStore) {
	  if store > curr { return true }
	  if store < curr { return false }
	}
	
	return false // 동일한 경우
  }
}
