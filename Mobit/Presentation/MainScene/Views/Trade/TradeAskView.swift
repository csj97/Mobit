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
  
  weak var reactor: CryptoDetailReactor? = nil
  var callBack: ((OrderResult) -> ())? = nil
  var disposeBag = DisposeBag()
  var cryptoInfo: CryptoCellInfo? = nil {
	didSet {
	  self.updateCryptoData()
	}
  }
  var availableCryptoCount: Double = 0.0
  // 매도 수량
  var inputAmount: Double = 0.0
  // 매도 금액
  var totalPrice: Double = 0.0
  var askCryptoIndex: Int? = nil
  
  deinit {
	print("deinit : \(String(describing: type(of: self)))")
  }
  
  static func instanceFromNib(
	reactor: CryptoDetailReactor,
	disposeBag: DisposeBag,
	callBack: @escaping (OrderResult) -> ()
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
	selfView.callBack = callBack
	selfView.setUI()
	selfView.setData()
	selfView.bind(reactor: reactor)
	
	return selfView
  }
  
  func setUI() {
	let marketName = self.reactor?.selectCrypto.market.components(separatedBy: "/").first
	self.marketNameLabels.forEach({ $0.text = marketName })
	self.inputTradeAmount.keyboardType = .decimalPad
	self.totalPriceTextField.keyboardType = .numberPad
  }
  
  func setData() {
	self.inputTradeAmount.delegate = self
	self.totalPriceTextField.delegate = self
	self.updateCryptoData()
  }
  
  func updateCryptoData() {
	guard let crypto = UserDataManager.userCryptoList?
	  .compactMap({ $0 })
	  .first(where: { $0.staticData.marketName == self.reactor?.selectCrypto.market }),
		  let currentPrice = self.cryptoInfo?.tradePrice
	else { return }
	
	let krwAvailablePrice = currentPrice * crypto.staticData.holdingQuantity
	self.availableCryptoCount = crypto.staticData.holdingQuantity
	self.availableCrypto.text = String(self.availableCryptoCount.formatSignificantDigits())
	self.availableTradePrice.text = "≈ " + String(floor(krwAvailablePrice)).addComma()
  }
  
  func updateCalcUtil(updateCrypto: CryptoCellInfo?) {
	guard let currentPrice = updateCrypto?.tradePrice else { return }
	
  }
  
  /// 최대 수량 버튼
  @IBAction func tapOnMaxAmount(_ sender: UIButton) {
	guard let availableCrypto = UserDataManager.userCryptoList?
			.compactMap({ $0 })
			.first(where: { $0.staticData.marketName == self.reactor?.selectCrypto.market })
	else { return }
	
	self.inputTradeAmount.text = String(availableCrypto.staticData.holdingQuantity.formatSignificantDigits())
	self.inputAmount = availableCrypto.staticData.holdingQuantity
	self.totalPriceTextField.text = String(availableCrypto.staticData.buyAmount.formatSignificantDigits())
  }
  
  @IBAction func tapOnAskButton(_ sender: UIButton) {
	guard let totalPrice = self.totalPriceTextField.text,
		  let doubleTotalPrice = Double(totalPrice.replacingOccurrences(of: ",", with: "")),
		  let currentPrice = self.cryptoInfo?.tradePrice?.formatDigits(digits: 8),
		  let crypto = UserDataManager.userCryptoList?.compactMap({ $0 }).first(
			where: { $0.staticData.marketName == self.reactor?.selectCrypto.market }
		  )
	else {
	  self.callBack?(.alert(title: "알림", message: "매도 수량을 확인 해주세요."))
	  return
	}
	
	let userCryptoList = UserDataManager.userCryptoList
	var postStaticTransaction: CryptoTransactionDataModel.CryptoTransactionStaticData? = nil
	var postDynamicTransaction: CryptoTransactionDataModel.CryptoTransactionDynamicData? = nil
	var transactionIndex: Int = 0
	
	if let matchedIndex = userCryptoList?.compactMap({ $0 }).firstIndex(
	  where: { $0.staticData.marketName == crypto.staticData.marketName }
	) {
	  postStaticTransaction = UserDataManager.userCryptoList?[matchedIndex].staticData
	  postDynamicTransaction = UserDataManager.userCryptoList?[matchedIndex].dynamicData
	  transactionIndex = matchedIndex
	}
  
	// 체결 내역은 말그대로 체결된 내역이 전부 보여야 한다.
	// 매수 내역은 현재 가지고 있는 매매 기록에 대해서만 나와야한다.
	if let postStaticTransaction = postStaticTransaction {
	  if inputAmount > 0, inputAmount <= crypto.staticData.holdingQuantity {
		
		if let totalPrice = Double(self.totalPriceTextField.text ?? "0"),
		   totalPrice < 500 {
		  self.callBack?(.alert(title: "알림", message: "500원 이상 매수/매도 가능합니다."))
		  return
		}
		
		let formatter = DateFormatter()
		formatter.dateFormat = "MM.dd HH:mm"
		formatter.locale = Locale(identifier: "ko_KR") // 한국 시간 기준
		let currentTime = Date()
		let executedDate = formatter.string(from: currentTime)
		
		self.callBack?(.alert(title: "알림", message: "매도 되었습니다."))
		
		let newTransaction: TransactionInfo = TransactionInfo(
		  marketName: crypto.staticData.marketName,
		  orderType: .ask,
		  executedDate: executedDate,
		  executedPrice: currentPrice,
		  executedQuantity: self.inputAmount,
		  executedAmount: currentPrice * self.inputAmount
		)
		UserDataManager.userTransactionList?.append(newTransaction)
		
		if self.inputAmount < postStaticTransaction.holdingQuantity {
		  let newHoldingQuantity = postStaticTransaction.holdingQuantity - self.inputAmount
		  let newBuyAmount = newHoldingQuantity * postStaticTransaction.averageBuyPrice
		
		  let newCryptoStaticData = CryptoTransactionDataModel.CryptoTransactionStaticData(
			marketName: crypto.staticData.marketName,
			holdingQuantity: newHoldingQuantity,
			averageBuyPrice: postStaticTransaction.averageBuyPrice,
			buyAmount: newBuyAmount
		  )
		  
		  // 매도 후, 보유하고 있는 코인 매매정보 업데이트
		  MarketDataServiceUtil.shared.fetchData(
			data: newCryptoStaticData,
			currentPrice: currentPrice
		  )
		} else {
		  // 전량 매도
		  UserDataManager.userCryptoList?.remove(at: transactionIndex)
		}
		
		// 사용자 계좌 반영
		UserDataManager.userInformation?.userAvailableBalance += self.totalPrice
		self.updateCryptoData()
		self.callBack?(.updateHistory)
		
	  } else {
		self.callBack?(.alert(title: "알림", message: "주문 수량을 재설정 해주세요."))
	  }
	}
  }
  
  func bind(reactor: CryptoDetailReactor) {
	reactor.state.map { $0.cryptoCellInfo }
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

extension TradeAskView: UITextFieldDelegate {
  func checkTotalPriceTextField(_ textField: UITextField) {
	guard let currentPrice = self.cryptoInfo?.tradePrice?.formatDigits(digits: 8) else { return }
	let inputTotalPrice = textField.text?.digitsOnlyDouble ?? 0
	self.totalPrice = inputTotalPrice
	let inputAmount = inputTotalPrice / currentPrice
	
	if floor(self.inputAmount) > 0 {
	  self.inputTradeAmount.text = inputAmount.formatSignificantDigits(digits: 4)
	  self.inputAmount = Double(inputAmount.formatSignificantDigits(digits: 4)) ?? 0
	} else {
	  self.inputTradeAmount.text = inputAmount.formatSignificantDigits()
	  self.inputAmount = Double(inputAmount.formatSignificantDigits()) ?? 0
	}
  }
  
  func textFieldDidEndEditing(_ textField: UITextField) {
	textField.text = textField.text?.addComma()
  }
  
  func textFieldDidChangeSelection(_ textField: UITextField) {
	guard let currentPrice = self.cryptoInfo?.tradePrice else { return }
	
	if textField == self.inputTradeAmount {
	  self.inputAmount = textField.text?.digitsOnlyDouble ?? 0
	  let totalPrice = floor(
		currentPrice.formatDigits(digits: 8) * inputAmount.formatDigits(digits: 8)
	  )
	  self.totalPriceTextField.text = totalPrice.formatSignificantDigits()
	  self.totalPrice = totalPrice
	} else if textField == self.totalPriceTextField {
	  self.checkTotalPriceTextField(textField)
	}
  }
  
  func textField(
	_ textField: UITextField,
	shouldChangeCharactersIn range: NSRange,
	replacementString string: String
  ) -> Bool {
	let currentText = textField.text ?? ""
	
	// 바뀐 텍스트 예측
	guard let stringRange = Range(range, in: currentText) else { return false }
	
	let updatedText = currentText.replacingCharacters(in: stringRange, with: string)
	
	if string == "." && currentText.contains(".") {
	  return false
	}
	
	if currentText.isEmpty && string == "." {
	  textField.text = "0."
	  self.checkTotalPriceTextField(textField)
	  return false
	}
	
	// "0"으로 시작하는데 다음 문자가 숫자일 경우 → "0" 제거
	if currentText == "0", string != ".", !string.isEmpty {
	  textField.text = string
	  self.checkTotalPriceTextField(textField)
	  return false
	}
	
//	textField.text = updatedText.addComma()
	
	return true
  }
}
