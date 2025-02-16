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
	guard let userBalance = UserDataManager.userInformation?.userAvailableBalance
	else { return }
	
	self.availableTradePrice.text = String(userBalance).addComma()
  }
  
  func setData() {
	
  }
  
  @IBAction func tapOnMaxAmount(_ sender: UIButton) {
	guard let currentPrice = self.reactor?.currentState.cryptoInfo?.tradePrice,
		  let userBalance = UserDataManager.userInformation?.userAvailableBalance 
	else { return }
	
	let inputAmount = (userBalance / currentPrice)
	self.availableTradePrice.text = String(userBalance).addComma()
	self.inputTradeAmount.text = String(inputAmount.roundToSignificantDigits()).addComma()
	print("💵 : \(inputAmount)")
  }
  
  @IBAction func tapOnBidButton(_ sender: UIButton) {
	
  }
  
}

extension Double {
  func roundToSignificantDigits() -> String {
	let formatter = NumberFormatter()
	formatter.numberStyle = .decimal
	formatter.maximumFractionDigits = 20
	formatter.minimumFractionDigits = 0
	
	guard let stringValue = formatter.string(from: NSNumber(value: self)) else {
	  return "\(self)"
	}
	
	let components = stringValue.components(separatedBy: ".")
	guard components.count == 2, let fractionalPart = components.last else {
	  return stringValue
	}
	
	let significantDigits = fractionalPart.firstIndex(where: { $0 != "0" }).map { fractionalPart.distance(from: fractionalPart.startIndex, to: $0) + 1 } ?? 0
	
	formatter.maximumFractionDigits = significantDigits
	
	return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
  }
}
