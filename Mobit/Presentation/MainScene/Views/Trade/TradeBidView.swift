//
//  TradeBidView.swift
//  Mobit
//
//  Created by 조성재 on 2/7/25.
//

import UIKit
import RxSwift

class TradeBidView: UIView, ViewRule {
  
  @IBOutlet weak var availableTradePrice: UILabel!
  @IBOutlet weak var inputTradeAmount: UITextField!
  
  var disposeBag = DisposeBag()
  weak var reactor: CryptoDetailReactor? = nil
  
  deinit {
	print("deinit : \(String(describing: type(of: self)))")
  }
  
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
	  print(#function)
  }
  
  static func instanceFromNib(
	reactor: CryptoDetailReactor,
	disposeBag: DisposeBag,
	result: @escaping () -> ()
  ) -> TradeBidView {
	
	let selfView = UINib(
	  nibName: String(describing: self),
	  bundle: nil
	).instantiate(
	  withOwner: self, options: nil
	).first as? TradeBidView
	
	guard let selfView = selfView else {
	  return TradeBidView()
	}
	
	selfView.reactor = reactor
	selfView.disposeBag = disposeBag
	selfView.setUI()
	selfView.setData()
	
	return selfView
  }
  
  func setUI() {
	self.isUserInteractionEnabled = true
  }
  
  func setData() {
	
  }
  
    @IBAction func tapOnMaxAmount(_ sender: UIButton) {
	guard let currentPrice = self.reactor?.currentState.cryptoInfo?.tradePrice,
		  let userBalance = UserDataManager.userInformation?.userAvailableBalance else { return }
	
	let availableAmount = round((userBalance / currentPrice) * 100) / 100
	self.availableTradePrice.text = String(availableAmount).addComma()
	print("💵 : \(availableAmount)")
  }
  
  @IBAction func tapOnBidButton(_ sender: UIButton) {
	
  }
    
}
