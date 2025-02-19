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
  @IBOutlet weak var currentPrice: UILabel!
  @IBOutlet weak var totalPriceTextField: UITextField!
    @IBOutlet weak var inputAmountTFView: UIView!
    
  var disposeBag = DisposeBag()
  weak var reactor: CryptoDetailReactor? = nil
  var cryptoInfo: CryptoCellInfo? = nil
  // 매수 수량
  var inputAmount: Double = 0.0
  
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
	selfView.bind(reactor: reactor)
	
	return selfView
  }
  
  func setUI() {
	self.inputTradeAmount.keyboardType = .numberPad
	self.totalPriceTextField.keyboardType = .numberPad
	self.inputAmountTFView.layer.cornerRadius = 8
	self.inputAmountTFView.layer.borderWidth = 1
	self.inputAmountTFView.layer.borderColor = UIColor.lightGray.cgColor
  }
  
  func setData() {
	  guard let userBalance = UserDataManager.userInformation?.userAvailableBalance
	  else { return }
	  
	  self.availableTradePrice.text = userBalance.formatSignificantDigits()
  }
  
  @IBAction func tapOnMaxAmount(_ sender: UIButton) {
	guard let currentPrice = self.reactor?.currentState.cryptoInfo?.tradePrice,
		  let userBalance = UserDataManager.userInformation?.userAvailableBalance
	else { return }
	
	let inputAmount = userBalance / currentPrice
	let totalPrice = floor(currentPrice.formatMax8Digits() * inputAmount.formatMax8Digits())
	self.inputTradeAmount.text = inputAmount.formatSignificantDigits()
	self.totalPriceTextField.text = totalPrice.formatSignificantDigits()
	
	print("💵 : \(inputAmount)")
  }
  
  @IBAction func tapOnBidButton(_ sender: UIButton) {
	
  }
  
  func bind(reactor: CryptoDetailReactor) {
	
	reactor.state.map { $0.cryptoInfo }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] cellInfo in
		guard let self = self else { return }
		self.cryptoInfo = cellInfo
		self.currentPrice.text = cellInfo?.tradePrice?.formatSignificantDigits()
	  })
	  .disposed(by: self.disposeBag)
  }
}

extension TradeBidView: UITextFieldDelegate {
  func textFieldDidChangeSelection(_ textField: UITextField) {
	// TODO: 수량 및 총액 입력시, 같이 수정 되어야 함.
	guard let currentPrice = self.cryptoInfo?.tradePrice,
		  let userBalance = UserDataManager.userInformation?.userAvailableBalance
	else { return }
	
	if textField == self.inputTradeAmount {
	  self.inputAmount = Double(textField.text ?? "0") ?? 0
	  let totalPrice = floor(currentPrice.formatMax8Digits() * inputAmount.formatMax8Digits())
	  self.totalPriceTextField.text = totalPrice.formatSignificantDigits()
	} else if textField == self.totalPriceTextField {
	  
	}
  }
}

extension Double {
  func formatMax8Digits() -> Double {
	let formattedValue = floor(self * 100_000_000) / 100_000_000
	return formattedValue
  }
  
  func formatSignificantDigits() -> String {
	// 1. 최대 소수점 8자리까지만 유지 (반올림 없이 자르기)
	let formattedValue = floor(self * 100_000_000) / 100_000_000
	
	// 2. 소수점 포함 숫자를 문자열로 변환
	var formattedString = String(format: "%.\(8)f", formattedValue)
	
	// 3. 불필요한 소수점 이하 0 제거
	while formattedString.last == "0" {
	  formattedString.removeLast()
	}
	if formattedString.last == "." {
	  formattedString.removeLast()
	}
	
	// 4. 콤마 추가 (소수점 앞부분만)
	if let dotIndex = formattedString.firstIndex(of: ".") {
	  let integerPart = formattedString[..<dotIndex]
	  let decimalPart = formattedString[dotIndex...]
	  let formattedInteger = integerPart.replacingOccurrences(
		of: "(?<=\\d)(?=(\\d{3})+(?!\\d))",
		with: ",",
		options: .regularExpression
	  )
	  return formattedInteger + decimalPart
	  
	} else {
	  
	  return formattedString.replacingOccurrences(
		of: "(?<=\\d)(?=(\\d{3})+(?!\\d))",
		with: ",",
		options: .regularExpression
	  )
	}
  }
}
