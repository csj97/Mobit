//
//  MainWebSocket.swift
//  Mobit
//
//  Created by openobject on 2024/07/23.
//

import Foundation
import RxSwift

class MainWebSocket {
  var cryptoList: CryptoList
  var currentPriceList = PublishSubject<CurrentPriceList>()
  private let disposeBag = DisposeBag()
  
  init(cryptoList: CryptoList) {
    self.cryptoList = cryptoList
    
    WebSocketManager.shared.openWebSocket()
    
    let cryptoJoined = self.cryptoList.map { $0.market }.joined(separator: ",")
//    WebSocketManager.shared.send(cryptoJoined)
//    
//    WebSocketManager.shared.currentPriceSubject
//      .observe(on: MainScheduler.instance)
//      .subscribe { [weak self] resultEvent in
//        guard let self = self else { return }
//        switch resultEvent {
//        case .next(let curPriceList):
//          self.currentPriceList = currentPriceList
//          print("curPriceList =====> \(curPriceList.count)")
//        case .completed:
//          break
//        case .error(let error):
//          print(error.localizedDescription)
//        }
//      }.disposed(by: self.disposeBag)
  }
  
  deinit {
    WebSocketManager.shared.closeWebSocket()
  }
}
