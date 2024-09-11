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
  }
  
  /// 상태 변경 단위, 작업 단위
  enum MainMutation {
    case loadCrypto(list: CryptoList)
    
    case setTabCryptoList(cryptoList: CryptoList)
    case setCombinedArray(cryptoCellInfo: [CryptoCellInfo])
  }
  
  struct MainReactorState {
    // krw, btc, usdt
    var cryptoList: CryptoList = []
    
    var tabCryptoList: CryptoList = []
    // Cell에 필요한 정보들을 모아 놓은 모델 변수
    var cryptoCellInfo: [CryptoCellInfo] = []
    var cryptoSocketTicker: CryptoSocketTicker? = nil
    
  }
}

extension MainReactor {
  // Observable 방출
  func mutate(action: MainAction) -> Observable<MainMutation> {
    switch action {
    case .loadCrypto(let selectedTab):
      return self.loadCrypto_Ticker(selectedTab: selectedTab)
      
    case .loadSocketTicker(let selectedTab, let cryptoList):
      return self.loadSocketTicker(selectedTab: selectedTab, cryptoList: cryptoList)
      
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
          let krwCryptoList = cryptoList.filter { $0.market.contains("KRW-") }
          let krwMarkets = krwCryptoList.map { $0.market }
          
          let setKRWCryptoMutation = Observable.just(MainMutation.setTabCryptoList(cryptoList: krwCryptoList))
          let tickerObservable = self.loadTicker(selectedTab: selectedTab, cryptoList: krwCryptoList, markets: krwMarkets)
          observableConcat = [setKRWCryptoMutation, tickerObservable]
          
        case .btc:
          let btcCryptoList = cryptoList.filter { $0.market.contains("BTC-") }
          let btcMarkets = btcCryptoList.map { $0.market }

          let setBTCCryptoMutation = Observable.just(MainMutation.setTabCryptoList(cryptoList: btcCryptoList))
          let tickerObservable = self.loadTicker(selectedTab: selectedTab, cryptoList: btcCryptoList, markets: btcMarkets)
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
          self.action.onNext(.loadSocketTicker(selectedTab: selectedTab, cryptoList: self.currentState.tabCryptoList))
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
        
        return Observable.just(MainMutation.setCombinedArray(cryptoCellInfo: combineResult))
      }
  }
  
  
  // MARK: - Combine Function
  
  /// CryptoList & CryptoTickerList 모델을 합치는 과정
  /// - Parameters:
  ///   - cryptoList: name, market, event 정보를 갖고 있음
  ///   - cryptoTickerList: tradePrice, signedChangeRate, change, accTradeVolume 정보를 갖고 있음
  /// - Returns: Main TableView Cell에 노출될 Cell 정보를 결합해서 반환
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
      updatedCryptoCellInfo.changePrice = matchedTicker.changePrice
      updatedCryptoCellInfo.signedChangeRate = matchedTicker.signedChangeRate
      updatedCryptoCellInfo.change = matchedTicker.change
      updatedCryptoCellInfo.accTradeVolume = matchedTicker.accTradeVolume24h
      
      return updatedCryptoCellInfo
    }
    
    return cryptoCells
  }
  
  /// CryptoList & CryptoSocketTicker 모델을 합치는 과정 (ticker랑 socket ticker랑 제공되는 데이터가 다름)
  /// - Parameters:
  ///   - cryptoList: name, market, event 정보를 갖고 있음
  ///   - cryptoTickerList: tradePrice, signedChangeRate, change, accTradeVolume 정보를 갖고 있음
  /// - Returns: Main TableView Cell에 노출될 Cell 정보를 반환
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
        updatedCryptoCellInfo.changePrice = socketTicker.changePrice
        updatedCryptoCellInfo.signedChangeRate = socketTicker.signedChangeRate
        updatedCryptoCellInfo.change = socketTicker.change
        updatedCryptoCellInfo.accTradeVolume = socketTicker.accTradeVolume24H
        
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
  private func loadSocketTicker(selectedTab: SelectedTab, cryptoList: CryptoList) -> Observable<MainMutation> {
    let cryptoJoined = cryptoList.map { $0.market }
    
    let socketObservable = Observable<MainMutation>.create { observer in
      WebSocketManager.shared.connect(codes: cryptoJoined, socketType: .ticker)
      WebSocketManager.shared.tickerDataSubject
        .observe(on: MainScheduler.instance)
        .subscribe { [weak self] data in
          guard let self = self else { return }

          do {
            let decodeTarget = CryptoSocketTickerDTO.self
            let cryptoTickerDTO = try JSONDecoder().decode(decodeTarget, from: data)
            let ticker = cryptoTickerDTO.toDomain()
            let combineResult = self.combineTicker(selectedTab: selectedTab, cryptoList: cryptoList, socketTicker: ticker)
            observer.onNext(.setCombinedArray(cryptoCellInfo: combineResult))
          } catch {
            print("MainReactor ticker websocket receive decoding error : \(error.localizedDescription)")
          }
        } onError: { error in
          observer.onError(error)
        } onCompleted: {
          observer.onCompleted()
        }.disposed(by: self.disposeBag)
      
      return Disposables.create {
        WebSocketManager.shared.disconnect(socketType: .ticker)
      }
    }
    
    return socketObservable
  }
}
