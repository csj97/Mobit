//
//  TradeInformationView.swift
//  Mobit
//
//  Created by 조성재 on 5/25/25.
//

import Foundation
import UIKit
import RxSwift

class TradeInformationView: UIView, ViewRule {
  
  @IBOutlet weak var cryptoImageView: UIImageView!
  @IBOutlet weak var marketNameLabel: UILabel!
  @IBOutlet weak var symbolLabel: UILabel!
  
  var symbol: String? = nil
  var reactor: CryptoDetailReactor? = nil
  var disposeBag = DisposeBag()
  
  static func instanceFromNib(
	reactor: CryptoDetailReactor
  ) -> TradeInformationView {
	
	let selfView = UINib(
	  nibName: String(describing: self),
	  bundle: nil
	).instantiate(
	  withOwner: self, options: nil
	).first as? TradeInformationView
	
	guard let selfView = selfView else {
	  return TradeInformationView()
	}
	
	selfView.reactor = reactor
	selfView.setUI()
	selfView.setData()
	
	return selfView
  }
  
  func setUI() {
  }
  
  func setData() {
	guard let reactor = self.reactor else { return }
	self.bind(reactor: reactor)
	self.reactor?.action.onNext(.getCryptoInformation)
  }
}

// MARK: Reactor - View
extension TradeInformationView {
  
  func bind(reactor: CryptoDetailReactor) {
	reactor.state.map { $0.cryptoQuotesInfo }
	  .distinctUntilChanged()
	  .subscribe(onNext: { cryptoQuotesInfo in
		guard let cryptoQuotesInfo = cryptoQuotesInfo else { return }
		self.symbolLabel.text = cryptoQuotesInfo.symbol
		print("🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁")
		print(cryptoQuotesInfo)
	  })
	  .disposed(by: disposeBag)
	 
  }
}
