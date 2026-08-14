//
//  TradeAverageCalcView.swift
//  Mobit
//
//  Created by 조성재 on 11/28/25.
//

import UIKit

class TradeAverageCalcView: UIView {
  
  @IBOutlet weak var calcResultView: UIView!
  @IBOutlet weak var averageResultLabel: UILabel!
  @IBOutlet weak var holdingQuantityLabel: UILabel!
  @IBOutlet weak var holdingAverageLabel: UILabel!
  @IBOutlet weak var newBuyQuantityTextField: UITextField!
  @IBOutlet weak var newBuyPriceTextField: UITextField!
  @IBOutlet weak var newBuyQuantitySymbolLabel: UILabel!
  @IBOutlet weak var newBuyAveragePriceCurrencyLabel: UILabel!
    
  
  private var holdingQuantity: Double?
  private var holdingAverage: Double?
  private var cryptoSymbol: String?
  
  var onClose: (() -> Void)?
  
  /// holdingQuantity (보유 수량) 자릿수 2자리 잘라서 보내야함
  /// holdingAverage (평균 매수가) 자릿수 2자리 잘라서 보내야함
  /// cryptoSymbole (코인 심볼)
  static func instanceFromNib(
	holdingQuantity: Double,
	holdingAverage: Double,
	cryptoSymbol: String
  ) -> TradeAverageCalcView {
	
	let selfView = UINib(
	  nibName: String(describing: self),
	  bundle: nil
	).instantiate(
	  withOwner: self, options: nil
	).first as? TradeAverageCalcView
	
	guard let selfView = selfView else {
	  return TradeAverageCalcView()
	}
	
	selfView.holdingQuantity = holdingQuantity
	selfView.holdingAverage = holdingAverage
	selfView.cryptoSymbol = cryptoSymbol
	selfView.setUI()
	selfView.setData()
	selfView.configure()
	
	DispatchQueue.main.async {
	  selfView.setNeedsLayout()
	  selfView.layoutIfNeeded()
	}
	
	return selfView
  }
  
  func configure() {
	
  }
  
  func setUI() {
	self.newBuyQuantityTextField.setAdaptivePlaceholderColor()
	self.newBuyPriceTextField.setAdaptivePlaceholderColor()
	self.backgroundColor = .mobitColors(.backgroundPrimary)
	self.calcResultView.backgroundColor = .mobitColors(.surfacePrimary)
	[
	  self.averageResultLabel,
	  self.holdingQuantityLabel,
	  self.holdingAverageLabel,
	  self.newBuyQuantitySymbolLabel,
	  self.newBuyAveragePriceCurrencyLabel
	].forEach { $0?.textColor = .mobitColors(.textPrimary) }
	[self.newBuyQuantityTextField, self.newBuyPriceTextField].forEach { textField in
	  textField?.textColor = .mobitColors(.textPrimary)
	  textField?.backgroundColor = .mobitColors(.surfacePrimary)
	}
	
	self.calcResultView.isHidden = true
	self.newBuyQuantitySymbolLabel.isHidden = true
	self.newBuyAveragePriceCurrencyLabel.isHidden = true
	
	guard let holdingQuantity = self.holdingQuantity?.formatSignificantDigits(digits: 2),
		  let holdingAverage = self.holdingAverage,
		  let cryptoSymbol = self.cryptoSymbol else { return }
	
	self.newBuyQuantityTextField.placeholder = "0 \(cryptoSymbol)"
	self.holdingQuantityLabel.attributedText = "\(holdingQuantity) \(cryptoSymbol)".highlightTexts(fontSize: 16, texts: [cryptoSymbol])
	self.holdingAverageLabel.attributedText = "\(holdingAverage) KRW".highlightTexts(fontSize: 16, texts: ["KRW"])
  }
  
  func setData() {
	self.newBuyQuantitySymbolLabel.text = self.cryptoSymbol
	self.newBuyAveragePriceCurrencyLabel.text = "KRW"
	
	self.newBuyQuantityTextField.keyboardType = .decimalPad
	self.newBuyPriceTextField.keyboardType = .decimalPad
	
	self.newBuyQuantityTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
	self.newBuyPriceTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
	
	self.newBuyQuantityTextField.addTarget(self, action: #selector(textFieldEndChange(_:)), for: .editingDidEnd)
	self.newBuyPriceTextField.addTarget(self, action: #selector(textFieldEndChange(_:)), for: .editingDidEnd)
  }
  
  /// 계산하기 버튼 클릭
  @IBAction func tapOnCalcButton(_ sender: UIButton) {
	guard let holdingQty = self.holdingQuantity,
		  let holdingAvg = self.holdingAverage else { return }
	
	guard let newBuyQtyString = self.newBuyQuantityTextField.text?.replacingOccurrences(of: ",", with: ""),
		  let newBuyPriceString = self.newBuyPriceTextField.text?.replacingOccurrences(of: ",", with: ""),
		  let newQty = Double(newBuyQtyString),
		  let newPrice = Double(newBuyPriceString)
	else { return }
	
	let totalQty = holdingQty + newQty
	
	guard totalQty > 0 else {
	  self.averageResultLabel.text = "-"
	  return
	}
	
	self.calcResultView.isHidden = false

	let newAverage = (holdingQty * holdingAvg + newQty * newPrice) / totalQty
	self.averageResultLabel.text = "\(newAverage.formatSignificantDigits(digits: 4)) KRW"
  }
  
  /// 닫기 버튼
  @IBAction func tapOnCloseButton(_ sender: UIButton) {
	self.onClose?()
  }
}

extension TradeAverageCalcView: UITextFieldDelegate {
  @objc private func textFieldDidChange(_ textField: UITextField) {
	let text = textField.text ?? ""
	
	if textField == newBuyQuantityTextField {
		newBuyQuantitySymbolLabel.isHidden = text.isEmpty
	}
	
	if textField == newBuyPriceTextField {
		newBuyAveragePriceCurrencyLabel.isHidden = text.isEmpty
	}
  }
  
  @objc private func textFieldEndChange(_ textField: UITextField) {
	textField.text = textField.text?.addComma()
  }
}
