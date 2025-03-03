//
//  TradeAskView.swift
//  Mobit
//
//  Created by 조성재 on 2/7/25.
//

import UIKit
import RxSwift

class TradeAskView: UIView, ViewRule {
  
  
  @IBOutlet var marketNameLabels: [UILabel]!
  @IBOutlet weak var availableCrypto: UILabel!
  @IBOutlet weak var availableTradePrice: UILabel!
  @IBOutlet weak var inputTradeAmount: UITextField!
  @IBOutlet weak var currentPrice: UILabel!
  @IBOutlet weak var totalPriceTextField: UITextField!
  @IBOutlet weak var inputAmountTFView: UIView!
  
  var disposeBag = DisposeBag()
  weak var reactor: CryptoDetailReactor? = nil
  var availableCryptoCount: Double = 0.0
  
  deinit {
	print("deinit : \(String(describing: type(of: self)))")
  }
  
  static func instanceFromNib(
	reactor: CryptoDetailReactor,
	disposeBag: DisposeBag,
	result: @escaping () -> ()
  ) ->  TradeAskView {
	
	let selfView = UINib(
	  nibName: String(describing: self),
	  bundle: nil
	).instantiate(
	  withOwner: self, options: nil
	).first as? TradeAskView
	
	guard let selfView = selfView else {
	  return TradeAskView()
	}
	
	selfView.reactor = reactor
	selfView.disposeBag = disposeBag
	selfView.setUI()
	selfView.setData()
	
	return selfView
  }
  
  func setUI() {
	let marketName = self.reactor?.selectCrypto.market.components(separatedBy: "/").first
	self.marketNameLabels.forEach({ $0.text = marketName })
	self.inputTradeAmount.keyboardType = .decimalPad
	self.totalPriceTextField.keyboardType = .decimalPad
  }
  
  func setData() {
	guard let crypto = UserDataManager.bidCryptoList
	  .compactMap({ $0 })
	  .first(where: { $0.marketName == self.reactor?.selectCrypto.market }),
		  let currentPrice = self.reactor?.selectCrypto.tradePrice?.formatDigits(digits: 8)
	else { return }
	
	let krwAvailablePrice = crypto.buyAmount.formatSignificantDigits()
	self.availableCryptoCount = crypto.holdingQuantity
	self.availableCrypto.text = String(self.availableCryptoCount)
	self.availableTradePrice.text = "≈ " + String(krwAvailablePrice)
  }
  
  /// 최대 수량 버튼
  @IBAction func tapOnMaxAmount(_ sender: UIButton) {
	self.inputTradeAmount.text = String(self.availableCryptoCount)
  }
  
  @IBAction func tapOnAskButton(_ sender: UIButton) {
  }
  
}
