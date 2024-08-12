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
  let initialState: MainReactorState = MainReactorState()
  var cryptoTickerRelay = PublishRelay<CryptoSocketTicker>() // 구독한 시점 이후부터 방출
  lazy var cryptoTickerObservable: Observable<CryptoSocketTicker> = cryptoTickerRelay.asObservable()
  
  init(mainUseCase: MainUseCase) {
    self.mainUseCase = mainUseCase
    self.action.onNext(.loadCrypto(selectedTab: .krw))
  }
}

// 기본 설정
extension MainReactor {
  enum MainAction {
    case loadCrypto(selectedTab: SelectedTab)
    case loadSocketTicker(selectedTab: SelectedTab, cryptoList: CryptoList)
    case setIsFirstTableSet(isSet: Bool)
  }
  
  /// 상태 변경 단위, 작업 단위
  enum MainMutation {
    case loadCrypto(list: CryptoList)
    
    case setKrwCrypto(krwCrypto: CryptoList)
    case setBtcCrypto(btcCrypto: CryptoList)
    
    case setCombinedKRWArray(cryptoCellInfo: [CryptoCellInfo])
    case setCombinedBTCArray(cryptoCellInfo: [CryptoCellInfo])
    
    case setCryptoSocketTicker(CryptoSocketTicker)
    
    case setIsFirstTableSet(isSet: Bool)
  }
  
  struct MainReactorState {
    // krw, btc, usdt
    var cryptoList: CryptoList = []
    var krwCryptoList: CryptoList = []
    var btcCryptoList: CryptoList = []
    var favoriteCryptoList: CryptoList = []
    var isFirstTableSet: Bool = false
    
    var cryptoSocketTicker: CryptoSocketTicker? = nil
    
    // Cell에 필요한 정보들을 모아 놓은 모델 변수
    var krwCryptoCellInfo: [CryptoCellInfo] = []
    var btcCryptoCellInfo: [CryptoCellInfo] = []
  }
}

extension MainReactor {
  // Observable 방출
  func mutate(action: MainAction) -> Observable<MainMutation> {
    switch action {
    case .loadCrypto(let selectedTab):
      return self.loadCrypto_Ticker(selectedTab: selectedTab)
      
    case .loadSocketTicker(let selectedTab, let cryptoList):
      return self.loadRealSocketTicker(selectedTab: selectedTab, cryptoList: cryptoList)
      
    case .setIsFirstTableSet(let isSet):
      return self.setIsSet(isSet: isSet)
    }
  }
  
  func setIsSet(isSet: Bool) -> Observable<MainMutation> {
    return Observable.just(.setIsFirstTableSet(isSet: isSet))
  }
  
  // View 업데이트
  func reduce(state: MainReactorState, mutation: MainMutation) -> MainReactorState {
    var newState = state
    switch mutation {
    case .loadCrypto(let cryptoList):
      newState.cryptoList = cryptoList
      
    case .setKrwCrypto(let krwCryptoList):
      newState.krwCryptoList = krwCryptoList
    case .setBtcCrypto(let btcCryptoList):
      newState.btcCryptoList = btcCryptoList
      
    case .setCryptoSocketTicker(let cryptoSocketTicker):
      newState.cryptoSocketTicker = cryptoSocketTicker
      
    case .setCombinedKRWArray(let combinedResult):
      newState.krwCryptoCellInfo = combinedResult
    case .setCombinedBTCArray(let combinedResult):
      newState.btcCryptoCellInfo = combinedResult
      
    case .setIsFirstTableSet(let isSet):
      newState.isFirstTableSet = isSet
    }
    return newState
  }
  
  /// CryptoList를 조회하고 이어서 바로 CryptoTicker를 조회한다. (SocketTicker와는 다름)
  /// - Returns: CryptoList와 CryptoTicker 구조체를 합쳐서 observer에 담고, MainMutation에 대한 Observable을 반환
  func loadCrypto_Ticker(selectedTab: SelectedTab) -> Observable<MainMutation> {
    let loadCryptoObservable = self.mainUseCase.loadCryptoList()
      .flatMap { cryptoList -> Observable<MainMutation> in
        
        var observableConcat: [Observable<MainMutation>] = []
        
        switch selectedTab {
        case .krw:
          let krwCrypto = cryptoList.filter { $0.market.contains("KRW-") }
          let krwMarkets = krwCrypto.map { $0.market }
          
          let setKRWCryptoMutation = Observable.just(MainMutation.setKrwCrypto(krwCrypto: krwCrypto))
          let tickerObservable = self.loadTicker(selectedTab: selectedTab, cryptoList: cryptoList, markets: krwMarkets)
          observableConcat = [setKRWCryptoMutation, tickerObservable]
          
        case .btc:
          let btcCrypto = cryptoList.filter { $0.market.contains("BTC-") }
          let btcMarkets = btcCrypto.map { $0.market }

          let setBTCCryptoMutation = Observable.just(MainMutation.setBtcCrypto(btcCrypto: btcCrypto))
          let tickerObservable = self.loadTicker(selectedTab: selectedTab, cryptoList: cryptoList, markets: btcMarkets)
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
          self.action.onNext(.setIsFirstTableSet(isSet: true))
        case .next:
          break
        case .error(let error):
          print("error : \(error.localizedDescription)")
        }
      }
      .disposed(by: self.disposeBag)
    
    return loadCryptoObservable
  }
  
  func loadTicker(selectedTab: SelectedTab, cryptoList: CryptoList, markets: [String]) -> Observable<MainMutation> {
    self.mainUseCase.loadTickerList(markets: markets)
      .flatMap { cryptoTickerList -> Observable<MainMutation> in
        let combineResult = self.combineCrypto(selectedTab: selectedTab, cryptoList: cryptoList, cryptoTickerList: cryptoTickerList)
        
        if selectedTab == .krw {
          return Observable.just(MainMutation.setCombinedKRWArray(cryptoCellInfo: combineResult))
        } else if selectedTab == .btc {
          return Observable.just(MainMutation.setCombinedBTCArray(cryptoCellInfo: combineResult))
        } else {
          return Observable.concat([])
        }
        
      }
  }
  
  
  // MARK: - Combine Function
  
  /// CryptoList & CryptoTickerList 모델을 합치는 과정
  /// - Parameters:
  ///   - cryptoList: name, market, event 정보를 갖고 있음
  ///   - cryptoTickerList: tradePrice, signedChangeRate, change, accTradeVolume 정보를 갖고 있음
  /// - Returns: Main TableView Cell에 노출될 Cell 정보를 반환
  func combineCrypto(selectedTab: SelectedTab, cryptoList: CryptoList, cryptoTickerList: CryptoTickerList) -> [CryptoCellInfo] {
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
      guard let matchedTicker = cryptoTickerList.first(where: { $0.market == cryptoCellInfo.market }) else {
        return CryptoCellInfo(cryptoName: "", market: "", marketEvent: nil)
      }
      var updatedCryptoCellInfo = cryptoCellInfo
      updatedCryptoCellInfo.market = self.transformMarketForm(market: cryptoCellInfo.market)
      updatedCryptoCellInfo.tradePrice = matchedTicker.tradePrice
      updatedCryptoCellInfo.signedChangeRate = matchedTicker.signedChangeRate
      updatedCryptoCellInfo.change = matchedTicker.change
      updatedCryptoCellInfo.accTradeVolume = matchedTicker.accTradeVolume24h
      
      return updatedCryptoCellInfo
    }
    
    return cryptoCells
  }
  
  
  func combineTicker(selectedTab: SelectedTab, cryptoList: CryptoList, socketTicker: CryptoSocketTicker) -> [CryptoCellInfo] {
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
        updatedCryptoCellInfo.tradePrice = socketTicker.tradePrice
        updatedCryptoCellInfo.signedChangeRate = socketTicker.signedChangeRate
        updatedCryptoCellInfo.change = socketTicker.change
        updatedCryptoCellInfo.accTradeVolume = socketTicker.accTradeVolume24H
        
        return updatedCryptoCellInfo
      } else {
        
        return nil
      }
    }
    
    var tempCellInfos: [CryptoCellInfo] = []
    
    switch selectedTab {
    case .krw:
      tempCellInfos = self.currentState.krwCryptoCellInfo.map { cellInfo in
        cryptoCells.first(where: { $0.cryptoName == cellInfo.cryptoName }) ?? cellInfo
      }
      
    case .btc:
      tempCellInfos = self.currentState.btcCryptoCellInfo.map { cellInfo in
        cryptoCells.first(where: { $0.cryptoName == cellInfo.cryptoName }) ?? cellInfo
      }
      
    case .favorite:
      break
    }
    
    return tempCellInfos
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
  
  private func loadRealSocketTicker(selectedTab: SelectedTab, cryptoList: CryptoList) -> Observable<MainMutation> {
    let socketObservable = Observable<MainMutation>.create { observer in
      self.loadSocketTicker(cryptoList: cryptoList)
        .subscribe { event in
          switch event {
          case .completed:
            break
          case .error(let error):
            print(error.localizedDescription)
          case .next(let ticker):
            let combineResult = self.combineTicker(selectedTab: selectedTab, cryptoList: cryptoList, socketTicker: ticker)
            observer.onNext(.setCombinedKRWArray(cryptoCellInfo: combineResult))
          }
        }.disposed(by: self.disposeBag)
      
      return Disposables.create()
    }
    
    return socketObservable
  }
  
  // WebSocket Ticker
  private func loadSocketTicker(cryptoList: CryptoList) -> Observable<CryptoSocketTicker> {
    let cryptoJoined = cryptoList.map { $0.market }
    WebSocketManager.shared.connect(codes: cryptoJoined)
    WebSocketManager.shared.observeReceivedData()
      .observe(on: MainScheduler.instance)
      .subscribe { [weak self] data in
        let decodeTarget = CryptoSocketTickerDTO.self
        
        do {
          let cryptoTickerDTO = try JSONDecoder().decode(decodeTarget, from: data)
          self?.cryptoTickerRelay.accept(cryptoTickerDTO.toDomain())
        } catch {
          print("websocket receive decoding error : \(error.localizedDescription)")
        }
      }.disposed(by: self.disposeBag)
    
    return self.cryptoTickerObservable
  }
}
