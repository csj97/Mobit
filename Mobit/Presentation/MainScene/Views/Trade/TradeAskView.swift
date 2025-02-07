//
//  TradeAskView.swift
//  Mobit
//
//  Created by 조성재 on 2/7/25.
//

import UIKit

class TradeAskView: UIView, ViewRule {

  var disposeBag = DisposeBag()
  var reactor: CryptoDetailReactor? = nil
  
  deinit {
	print("deinit : \(String(describing: type(of: self)))")
  }
  
  static func instanceFromNib(
	reactor: CryptoDetailReactor,
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
	selfView.setUI()
	selfView.setData()
	
	return selfView
  }
  
  func setUI() {
	<#code#>
  }
  
  func setData() {
	<#code#>
  }
}
