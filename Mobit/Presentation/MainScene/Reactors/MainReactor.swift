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

class MainReactor: Reactor {
  private let mainUseCase: MainUseCase
  private let disposeBag = DisposeBag()
  let initialState: MainReactorState = MainReactorState()
  var cryptoTickerRelay = PublishRelay<CryptoSocketTicker>() // 구독한 시점 이후부터 방출
  lazy var cryptoTickerObservable: Observable<CryptoSocketTicker> = cryptoTickerRelay.asObservable()
  
  init(mainUseCase: MainUseCase) {
    self.mainUseCase = mainUseCase
    self.action.onNext(.loadCrypto)
  }
  
}

// 기본 설정
extension MainReactor {
  enum MainAction {
    case loadCrypto
    case loadSocketTicker(cryptoList: CryptoList)
    case setIsFirstTableSet(isSet: Bool)
//    case updateSocketCellInfo(cellInfo: CryptoCellInfo, socketTicker: CryptoSocketTicker)
  }
  
  /// 상태 변경 단위, 작업 단위
  enum MainMutation {
    case loadCrypto(list: CryptoList)
    case setKrwCrypto(krwCrypto: CryptoList)
    
    case setCombinedKRWArray(cryptoCellInfo: [CryptoCellInfo])
    case setCombinedBTCArray(cryptoCellInfo: [CryptoCellInfo])
    
    case setCryptoSocketTicker(CryptoSocketTicker)
    
    case connectSocket(socketTicker: CryptoSocketTicker)
    
    case setIsFirstTableSet(isSet: Bool)
  }
  
  struct MainReactorState {
    // krw, btc, usdt
    var cryptoList: CryptoList = []
    var krwCryptoList: CryptoList = []
    var btcCryptoList: CryptoList = []
    var favoriteCryptoList: CryptoList = []
    var isFirstTableSet: Bool = false
    
    var cryptoSocketTicker: CryptoSocketTicker = CryptoSocketTicker(type: "",
                                                                    code: "",
                                                                    openingPrice: 0.0,
                                                                    highPrice: 0.0,
                                                                    lowPrice: 0.0,
                                                                    tradePrice: 0.0,
                                                                    prevClosingPrice: 0.0,
                                                                    change: "",
                                                                    changePrice: 0.0,
                                                                    signedChangePrice: 0.0,
                                                                    changeRate: 0.0,
                                                                    signedChangeRate: 0.0,
                                                                    tradeVolume: 0.0,
                                                                    accTradeVolume: 0.0,
                                                                    accTradeVolume24H: 0.0,
                                                                    accTradePrice: 0.0,
                                                                    accTradePrice24H: 0.0,
                                                                    tradeDate: "",
                                                                    tradeTime: "",
                                                                    tradeTimestamp: 0,
                                                                    askBid: "",
                                                                    accAskVolume: 0.0,
                                                                    accBidVolume: 0.0,
                                                                    highest52WeekPrice: 0.0,
                                                                    highest52WeekDate: "",
                                                                    lowest52WeekPrice: 0.0,
                                                                    lowest52WeekDate: "",
                                                                    tradeStatus: nil,
                                                                    marketState: "",
                                                                    marketStateForIOS: nil,
                                                                    isTradingSuspended: false,
                                                                    delistingDate: nil,
                                                                    marketWarning: "",
                                                                    timestamp: 0,
                                                                    streamType: "")
    
    // Cell에 필요한 정보들을 모아 놓은 모델 변수
    var krwCryptoCellInfo: [CryptoCellInfo] = []
    var btcCryptoCellInfo: [CryptoCellInfo] = []
  }
}

extension MainReactor {
  // Observable 방출
  func mutate(action: MainAction) -> Observable<MainMutation> {
    switch action {
    case .loadCrypto:
      return self.loadCrypto_Ticker()
      
    case .loadSocketTicker(let cryptoList):
      return self.loadRealSocketTicker(cryptoList: cryptoList)
      
    case .setIsFirstTableSet(let isSet):
      return self.setIsSet(isSet: isSet)
//      return self.mainUseCase.loadCryptoList()
//        .flatMap({ cryptoList -> Observable<MainMutation> in
//          return Observable.concat([
//            self.classifyCrypto(cryptoList: cryptoList),
//          ])
//        })
//    case .updateSocketCellInfo(let cellInfo, let socketTicker):
//      return self.updateSocketTicker(cellInfo: cellInfo, socketTicker: socketTicker)
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
    case .setCryptoSocketTicker(let cryptoSocketTicker):
      newState.cryptoSocketTicker = cryptoSocketTicker
    case .setCombinedKRWArray(let combinedResult):
      newState.krwCryptoCellInfo = combinedResult
    case .setCombinedBTCArray(let combinedResult):
      newState.btcCryptoCellInfo = combinedResult
    case .connectSocket(let socketTicker):
      newState.cryptoSocketTicker = socketTicker
    case .setIsFirstTableSet(let isSet):
      newState.isFirstTableSet = isSet
    }
    return newState
  }
  
  /// CryptoList & CryptoTickerList 모델을 합치는 과정
  /// - Parameters:
  ///   - cryptoList: name, market, event 정보를 갖고 있음
  ///   - cryptoTickerList: tradePrice, signedChangeRate, change, accTradeVolume 정보를 갖고 있음
  /// - Returns: Main TableView Cell에 노출될 Cell 정보를 반환
  func combineCrypto(cryptoList: CryptoList, cryptoTickerList: CryptoTickerList) -> [CryptoCellInfo] {
    let krwCrypto = cryptoList.filter { $0.market.contains("KRW-") }
//      .map { self.transformCrypto(crypto: $0) }
    
    let krwCellInfos: [CryptoCellInfo] = krwCrypto.compactMap { crypto in
      return CryptoCellInfo(cryptoName: crypto.koreanName, market: crypto.market, marketEvent: crypto.marketEvent)
    }
    
    let krwCryptoCells: [CryptoCellInfo] = krwCellInfos.compactMap { cryptoCellInfo in
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
    
    return krwCryptoCells
  }
  
  func combineTicker(cryptoList: CryptoList, socketTicker: CryptoSocketTicker) -> [CryptoCellInfo] {
    let krwCrypto = cryptoList.filter { $0.market.contains("KRW-") }
//      .map { self.transformCrypto(crypto: $0) }
    
    let krwCellInfos: [CryptoCellInfo] = krwCrypto.compactMap { crypto in
      return CryptoCellInfo(cryptoName: crypto.koreanName, market: crypto.market, marketEvent: crypto.marketEvent)
    }
    
    let krwCryptoCells: [CryptoCellInfo] = krwCellInfos.compactMap { cryptoCellInfo in
      var updatedCryptoCellInfo = cryptoCellInfo
      
      if socketTicker.code == cryptoCellInfo.market {
        updatedCryptoCellInfo.market = self.transformMarketForm(market: cryptoCellInfo.market)
        updatedCryptoCellInfo.tradePrice = socketTicker.tradePrice
        updatedCryptoCellInfo.signedChangeRate = socketTicker.signedChangeRate
        updatedCryptoCellInfo.change = socketTicker.change
        updatedCryptoCellInfo.accTradeVolume = socketTicker.accTradeVolume24H
        
        return updatedCryptoCellInfo
      } else {
        return CryptoCellInfo(cryptoName: "", market: "", marketEvent: nil)
      }
    }
    
    return krwCryptoCells
  }
  
  /// CryptoList를 조회하고 이어서 바로 CryptoTicker를 조회한다. (SocketTicker와는 다름)
  /// - Returns: CryptoList와 CryptoTicker 구조체를 합쳐서 observer에 담고, MainMutation에 대한 Observable을 반환
  func loadCrypto_Ticker() -> Observable<MainMutation> {
    let loadCryptoObservable = self.mainUseCase.loadCryptoList()
      .flatMap { cryptoList -> Observable<MainMutation> in
        let krwCrypto = cryptoList.filter { $0.market.contains("KRW-") }
        let btcCrypto = cryptoList.filter { $0.market.contains("BTC-") }
        let krwMarkets = krwCrypto.map { $0.market }
        let btcMarkets = btcCrypto.map { $0.market }
        
        let setKRWCryptoMutation = Observable.just(MainMutation.setKrwCrypto(krwCrypto: krwCrypto))
        
        let tickerObservable = self.mainUseCase.loadTickerList(markets: krwMarkets)
          .flatMap { cryptoTickerList -> Observable<MainMutation> in
            let combineResult = self.combineCrypto(cryptoList: cryptoList, cryptoTickerList: cryptoTickerList)
            return Observable.just(MainMutation.setCombinedKRWArray(cryptoCellInfo: combineResult))
          }
        
        return Observable.concat([setKRWCryptoMutation, tickerObservable])
        
      }
      .concat(Observable.just(MainMutation.setIsFirstTableSet(isSet: true)))
      .catch { error in
        return Observable.error(error)
      }
    
    loadCryptoObservable
      .subscribe { mutation in
        switch mutation {
        case .completed:
          // 여기서 MainMutation.setIsFirstTableSet을 해주고 싶어.
          self.action.onNext(.setIsFirstTableSet(isSet: true))
        case .next(let mutation):
          break
        case .error(let error):
          print("error : \(error.localizedDescription)")
        }
      }
      .disposed(by: self.disposeBag)
    
    return loadCryptoObservable
  }
  
  func transformCrypto(crypto: Crypto) -> Crypto {
    var transformedCrypto = crypto
    let components = crypto.market.split(separator: "-")
    if components.count == 2 {
      transformedCrypto.market = "\(components[1])/\(components[0])"
    } else {
      // 기본값 유지
      transformedCrypto.market = crypto.market
    }
    return transformedCrypto
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
  
  func transformMarketForm22(market: String) -> String {
    var transformMarket = market
    let components = transformMarket.split(separator: "/")
    if components.count == 2 {
      transformMarket = "\(components[1])-\(components[0])"
    } else {
      // 기본값 유지
      transformMarket = market
    }
    return transformMarket
  }
  
  private func loadRealSocketTicker(cryptoList: CryptoList) -> Observable<MainMutation> {
    let socketObservable = Observable<MainMutation>.create { observer in
      self.loadSocketTicker(cryptoList: cryptoList)
        .subscribe { event in
          switch event {
          case .completed:
            break
          case .error(let error):
            print(error.localizedDescription)
          case .next(let ticker):
            let combineResult = self.combineTicker(cryptoList: cryptoList, socketTicker: ticker)
  //          observer.onNext(.connectSocket(socketTicker: ticker))
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
