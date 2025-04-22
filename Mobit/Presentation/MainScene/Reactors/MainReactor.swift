//
//  MainViewModel.swift
//  Mobit
//
//  Created by openobject on 2024/07/19.
//

import Foundation
import UIKit
import RxSwift
import ReactorKit
import RxRelay

enum SelectedTab {
  case krw, btc, favorite
}

class MainReactor: Reactor {
  private let mainUseCase: MainUseCase
  private let disposeBag = DisposeBag()
  private var sortedCryptoPosition: [String: Int] = [:]
  let socketManager: NewWebSocketManager = NewWebSocketManager()
  let initialState: MainReactorState = MainReactorState()
  
  init(mainUseCase: MainUseCase) {
    self.mainUseCase = mainUseCase
  }
}

// 기본 설정
extension MainReactor {
  enum MainAction {
    case loadCrypto(selectedTab: SelectedTab)
    case loadSocketTicker(selectedTab: SelectedTab, cryptoList: CryptoList)
    case disconnectSocket
    case setSortType(sortBy: CryptoSortType)
  }
  
  /// 상태 변경 단위, 작업 단위
  enum MainMutation {
    case loadCrypto(list: CryptoList)
    
    case setTabCryptoList(cryptoList: CryptoList)
    case setCombinedArray(cryptoCellInfo: [CryptoCellInfo])
    case setSortType(sortBy: CryptoSortType)
  }
  
  struct MainReactorState {
    // krw, btc, usdt
    var cryptoList: CryptoList = []
    
    var tabCryptoList: CryptoList = []
    // Cell에 필요한 정보들을 모아 놓은 모델 변수
    var cryptoCellInfo: [CryptoCellInfo] = []
    var cryptoSocketTicker: CryptoSocketTicker? = nil
    var sortBy: CryptoSortType = .normal
  }
}

extension MainReactor {
  // Observable 방출
  func mutate(action: MainAction) -> Observable<MainMutation> {
    switch action {
    case .loadCrypto(let selectedTab):
      return self.loadCryptoTicker(selectedTab: selectedTab)
      
    case .loadSocketTicker(let selectedTab, let cryptoList):
      return self.loadSocketTicker(selectedTab: selectedTab, cryptoList: cryptoList)
      
    case .disconnectSocket:
      return self.disconnectSocket()
      
    case .setSortType(let sortBy):
      return self.setSortType(sortBy: sortBy)
    }
  }
  
  // View 업데이트
  func reduce(state: MainReactorState, mutation: MainMutation) -> MainReactorState {
    var newState = state
    switch mutation {
    case .loadCrypto(let cryptoList):
      newState.cryptoList = cryptoList
      
    case .setTabCryptoList(let cryptoList):
      newState.tabCryptoList = cryptoList
      
    case .setCombinedArray(let combinedResult):
      newState.cryptoCellInfo = combinedResult
      
    case .setSortType(let sortBy):
      newState.sortBy = sortBy
    }
    return newState
  }
  
  /// CryptoList를 조회하고 이어서 바로 CryptoTicker를 조회한다. (SocketTicker와는 다름)
  /// - Returns: CryptoList와 CryptoTicker 구조체를 합쳐서 observer에 담고, MainMutation에 대한 Observable을 반환
  func loadCryptoTicker(selectedTab: SelectedTab) -> Observable<MainMutation> {
    let loadCryptoObservable = self.mainUseCase.loadCryptoList()
      .flatMap { cryptoList -> Observable<MainMutation> in
        
        var observableConcat: [Observable<MainMutation>] = []
		
		self.socketManager.connect()
		
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
    
    loadCryptoObservable
      .subscribe { mutation in
        switch mutation {
        case .completed:
          self.action.onNext(
            .loadSocketTicker(
              selectedTab: selectedTab,
              cryptoList: self.currentState.tabCryptoList
            )
          )
        case .next:
          break
        case .error(let error):
          print("error : \(error.localizedDescription)")
        }
      }
      .disposed(by: self.disposeBag)
    
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
        let combineCrypto = self.combineCrypto(
          selectedTab: selectedTab,
          cryptoList: cryptoList,
          cryptoTickerList: cryptoTickerList
        )
        
        self.sortCryptoCellInfos(
          sortBy: self.currentState.sortBy,
          cellInfos: combineCrypto
        ) { sortedCellInfos in
          
          guard let sortedCellInfos = sortedCellInfos else { return }
          
          if self.sortedCryptoPosition.count == 0 {
            observer.onNext(.setCombinedArray(cryptoCellInfo: sortedCellInfos))
            observer.onCompleted()
          } else {
            self.updateCryptoCellPositions(
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
      
      return updatedCryptoCellInfo
    }
    
    return cryptoCells
  }
  
  /// CryptoList & CryptoSocketTicker 모델을 합치는 과정 (ticker랑 socket ticker랑 제공되는 데이터가 다름)
  /// - Parameters:
  ///   - cryptoList: name, market, event 정보를 갖고 있음
  ///   - cryptoTickerList: tradePrice, signedChangeRate, change, accTradeVolume 정보를 갖고 있음
  /// - Returns: Main TableView Cell에 노출될 Cell 정보를 반환
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
        
        return updatedCryptoCellInfo
      } else {
        
        return nil
      }
    }
    
    return self.currentState.cryptoCellInfo.map { cellInfo in
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
      
	  self.socketManager.onConnected = {
		self.socketManager.sendMessage(
		  codes: cryptoJoined,
		  socketType: .ticker
		)
	  }
      
      self.socketManager.tickerDataSubject
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
            self.sortCryptoCellInfos(
              sortBy: currentState.sortBy,
              cellInfos: combineResult,
              completion: { sortedCellInfos in
                
                guard let sortedCellInfos = sortedCellInfos else { return }
                combineResult = sortedCellInfos
                
                // 정렬된 배열 > 포지션 찾아가기 (포지션이 설정되어 있다면)
                if self.sortedCryptoPosition.count > 0 {
                  self.updateCryptoCellPositions(
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
              }
            )
            
          } catch {
            print("MainReactor ticker websocket receive decoding error : \(error.localizedDescription)")
          }
        } onError: { error in
          observer.onError(error)
        } onCompleted: {
          observer.onCompleted()
        }.disposed(by: self.disposeBag)
      
      return Disposables.create {
        self.socketManager.disconnect()
      }
    }
    
    return socketObservable
  }
  
  /// SocketManager Disconnect
  private func disconnectSocket() -> Observable<MainMutation> {
    self.socketManager.disconnect()
    return .empty() 
  }
  
  /// Sort Type Setting
  func setSortType(sortBy: CryptoSortType) -> Observable<MainMutation> {
    
    self.sortCryptoCellInfos(
      sortBy: sortBy,
      cellInfos: currentState.cryptoCellInfo
    ) { sortedCellInfos in
      guard let sortedCellInfos = sortedCellInfos else { return }
      
      // 매번 소켓 데이터 수신때마다 하는 것이 아닌, 정렬 초기에 포지션 저장
      let markets = sortedCellInfos.map({ $0.market })
      self.sortedCryptoPosition = Dictionary(
        uniqueKeysWithValues: markets.enumerated().map { ($1, $0) }
      )
    }
    
    // 포지션 저장하는 것과 별개로 sort type setting
    return Observable.just(
      MainMutation.setSortType(sortBy: sortBy)
    )
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
    cryptoCellInfos: [CryptoCellInfo],
    completion: @escaping ([CryptoCellInfo]?) -> ()
  ) {
    let positionedCryptoInfos = self.sortedCryptoPosition
    if positionedCryptoInfos.count > 0 {
      let cryptoInfoDict = Dictionary(
        uniqueKeysWithValues: cryptoCellInfos.map { ($0.market, $0) }
      )
      let newPositionedCryptoInfos = positionedCryptoInfos
        .sorted { $0.value < $1.value }
        .compactMap { cryptoInfoDict[$0.key] }  // 해당 인덱스의 크립토 정보를 맵핑
      completion(newPositionedCryptoInfos)
    } else {
      completion(nil)
    }
  }
}
