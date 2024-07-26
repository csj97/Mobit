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
  }
  
  /// 상태 변경 단위, 작업 단위
  enum MainMutation {
    case loadCrypto(list: CryptoList)
    
    case setCombinedKRWArray(cryptoCellInfo: [CryptoCellInfo])
    case setCombinedBTCArray(cryptoCellInfo: [CryptoCellInfo])
    
    case setCryptoTicker(CryptoSocketTickerList)
  }
  
  struct MainReactorState {
    // krw, btc, usdt
    var cryptoList: CryptoList = []
    var krwCryptoList: CryptoList = []
    var btcCryptoList: CryptoList = []
    var favoriteCryptoList: CryptoList = []
    
    var cryptoTickerList: CryptoSocketTickerList = []
    
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
//      return self.mainUseCase.loadCryptoList()
//        .flatMap({ cryptoList -> Observable<MainMutation> in
//          return Observable.concat([
//            self.classifyCrypto(cryptoList: cryptoList),
//          ])
//        })
    }
  }
  
  // View 업데이트
  func reduce(state: MainReactorState, mutation: MainMutation) -> MainReactorState {
    var newState = state
    switch mutation {
    case .loadCrypto(let cryptoList):
      newState.cryptoList = cryptoList
    case .setCryptoTicker(let cryptoTickerList):
      newState.cryptoTickerList = cryptoTickerList
    case .setCombinedKRWArray(let combinedResult):
      newState.krwCryptoCellInfo = combinedResult
    case .setCombinedBTCArray(let combinedResult):
      newState.btcCryptoCellInfo = combinedResult
    }
    return newState
  }
  
  func combineCrypto(cryptoList: CryptoList, cryptoTickerList: CryptoTickerList) -> [CryptoCellInfo] {
    let krwCrypto = cryptoList.filter { $0.market.contains("KRW-") }
//      .map { self.transformCrypto(crypto: $0) }
    
    let krwCellInfos: [CryptoCellInfo] = krwCrypto.compactMap { crypto in
      return CryptoCellInfo(cryptoName: crypto.koreanName, market: crypto.market, marketEvent: crypto.marketEvent)
    }
    
    let krwCryptoCells: [CryptoCellInfo] = krwCellInfos.compactMap { cryptoCellInfo in
      guard let matchedTicker = cryptoTickerList.first(where: { $0.market == cryptoCellInfo.market }) else { return CryptoCellInfo(cryptoName: "", market: "", marketEvent: nil) }
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
  
  func loadCrypto_Ticker() -> Observable<MainMutation> {
    let loadCryptoObservable = Observable<MainMutation>.create { observer in
      self.mainUseCase.loadCryptoList()
        .subscribe { cryptoList in
          let cryptoMarkets = cryptoList.map { $0.market }
          self.mainUseCase.loadTickerList(markets: cryptoMarkets)
            .subscribe { event in
              switch event {
              case .completed:
                break
              case .next(let cryptoTickerList):
                let combineResult = self.combineCrypto(cryptoList: cryptoList, cryptoTickerList: cryptoTickerList)
                observer.onNext(.setCombinedKRWArray(cryptoCellInfo: combineResult))
              
              case .error(let error):
                print("loadCrypto_Ticker() Error Occured : \(error.localizedDescription)")
              }
              
            }
            .disposed(by: self.disposeBag)
        }
        .disposed(by: self.disposeBag)
      
      return Disposables.create()
    }
    
    return Observable.concat([loadCryptoObservable])
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
  private func ticker(cryptoList: CryptoList) -> Observable<CryptoSocketTicker> {
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
