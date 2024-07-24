//
//  MainWebSocket.swift
//  Mobit
//
//  Created by openobject on 2024/07/23.
//

import Foundation
import RxSwift
import RxRelay

class MainWebSocket {
  var cryptoList: CryptoList
  var currentPriceList = PublishRelay<CurrentPriceList>()
  private let disposeBag = DisposeBag()
  
  init(cryptoList: CryptoList) {
    self.cryptoList = cryptoList
    let cryptoJoined = self.cryptoList.map { $0.market }
    
    WebSocketManager.shared.connect(codes: cryptoJoined)
    WebSocketManager.shared.currentPriceSubject
      .observe(on: MainScheduler.instance)
      .subscribe { [weak self] resultEvent in
        guard let self = self else { return }
        switch resultEvent {
        case .next(let curPriceList):
          self.currentPriceList = currentPriceList
          print("curPriceList =====> \(curPriceList)")
        case .completed:
          break
        case .error(let error):
          print(error.localizedDescription)
        }
      }.disposed(by: self.disposeBag)
  }
  
  deinit {
//    WebSocketManager.shared.disconnect()
  }
}
