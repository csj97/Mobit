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
  @IBOutlet weak var inputMarketName: UILabel!
  
  weak var reactor: CryptoDetailReactor? = nil
  var callBack: ((OrderResult) -> ())? = nil
  var disposeBag = DisposeBag()
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
	callBack: @escaping (OrderResult) -> ()
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
	selfView.callBack = callBack
	selfView.setUI()
	selfView.setData()
	selfView.bind(reactor: reactor)
	
	return selfView
  }
  
  func setUI() {
	self.inputMarketName.text = self.reactor?.selectCrypto.market.components(separatedBy: "/").first
	self.inputTradeAmount.keyboardType = .decimalPad
	self.totalPriceTextField.keyboardType = .numberPad
  }
  
  func setData() {
	self.inputTradeAmount.delegate = self
	self.totalPriceTextField.delegate = self
	
	guard let userBalance = UserDataManager.userInformation?.userAvailableBalance
	else { return }
	
	self.availableTradePrice.text = userBalance.formatSignificantDigits()
  }
  
  @IBAction func tapOnMaxAmount(_ sender: UIButton) {
	guard let currentPrice = self.cryptoInfo?.tradePrice?.formatDigits(digits: 8),
		  let userBalance = UserDataManager.userInformation?.userAvailableBalance
	else { return }
	
	inputAmount = (userBalance / currentPrice)
	
	let calcUtil = CalculationUtil(currentPrice: currentPrice, newHoldingQuantity: inputAmount)
	let totalPrice = calcUtil.calcBuyAmount().formatSignificantDigits()
	self.inputTradeAmount.text = inputAmount.formatSignificantDigits()
	self.totalPriceTextField.text = String(totalPrice)
  }
  
  @IBAction func tapOnBidButton(_ sender: UIButton) {
	guard let marketName = self.cryptoInfo?.market,
		  let currentPrice = self.cryptoInfo?.tradePrice?.formatDigits(digits: 8),
		  let userBalance = UserDataManager.userInformation?.userAvailableBalance
	else {
	  callBack?(.alert(title: "알림", message: "매수 금액을 입력해주세요"))
	  return
	}
	
	// 매수 버튼 누르는 시점 기준, total 금액으로 비교
	let calcUtil = CalculationUtil(currentPrice: currentPrice, newHoldingQuantity: inputAmount)
	let executedTotalPrice = calcUtil.calcBuyAmount()
	
	if executedTotalPrice > 0.0, userBalance >= executedTotalPrice {
	  self.updateTransaction(marketName: marketName) {
		self.initTextFieldValue()
		self.callBack?(.alert(title: "알림", message: "매수 되었습니다."))
		self.callBack?(.updateHistory)
	  }
	} else {
	  callBack?(.alert(title: "알림", message: "매수 금액을 확인해 주세요"))
	}
  }
  
  /// 매도하고 나면 여기 업데이트
  func updateCryptoData() {
	guard let crypto = UserDataManager.userCryptoList?
	  .compactMap({ $0 })
	  .first(where: { $0.staticData.marketName == self.reactor?.selectCrypto.market }),
		  let currentPrice = self.cryptoInfo?.tradePrice
	else {
	  self.availableTradePrice.text = "0"
	  
	  return
	}
	
	let userBalance = UserDataManager.userInformation?.userAvailableBalance
	self.availableTradePrice.text = userBalance?.formatSignificantDigits()
  }
  
  func updateTransaction(marketName: String, completion: @escaping () -> ()) {
	
	guard let currentPrice = self.cryptoInfo?.tradePrice?.formatDigits(digits: 8),
		  let userBalance = UserDataManager.userInformation?.userAvailableBalance
	else { return }
	
	let formatter = DateFormatter()
	formatter.dateFormat = "MM.dd HH:mm"
	formatter.locale = Locale(identifier: "ko_KR") // 한국 시간 기준
	let currentTime = Date()
	let executedDate = formatter.string(from: currentTime)
	
	var availableBalance: Double = userBalance
	var postStaticTransaction: CryptoTransactionDataModel.CryptoTransactionStaticData? = nil
	
	if let matchedIndex = UserDataManager.userCryptoList?.compactMap({ $0 })
	  .firstIndex(where: { $0.staticData.marketName == marketName }) {
	  postStaticTransaction = UserDataManager.userCryptoList?[matchedIndex].staticData
	}
	
	// 체결 내역은 말그대로 체결된 내역이 전부 보여야 한다.
	// 매수 내역은 현재 가지고 있는 매매 기록에 대해서만 나와야한다.
	if let postStaticTransaction = postStaticTransaction {
	  
	  // *****기존 매수 내역이 있는 상태*****
	  let calcUtil = CalculationUtil(
		currentPrice: currentPrice.formatDigits(digits: 8),
		prevHoldingQuantity: postStaticTransaction.holdingQuantity,
		prevAverageBuyPrice: postStaticTransaction.averageBuyPrice,
		prevBuyAmount: postStaticTransaction.buyAmount,
		newHoldingQuantity: self.inputAmount
	  )
	  
	  // 새 매수 거래내역
	  let newTransactionInfo = TransactionInfo(
		marketName: marketName,
		orderType: .bid,
		executedDate: executedDate,
		executedPrice: currentPrice,
		executedQuantity: self.inputAmount,
		executedAmount: currentPrice * self.inputAmount
	  )
	  
	  // 기존 매수 내역의 (평균매수가, 매수금액, 보유수량)
	  let averageBuyPrice = calcUtil.calcAverBuyPrice(for: marketName)
	  let buyAmount = calcUtil.calcBuyAmount()
	  let holdingQuantity = calcUtil.calcHoldingQuantity()
	  let newBuyAmount = floor(currentPrice * self.inputAmount)
	  
	  // 새 정적 데이터
	  let newCryptoStaticData = CryptoTransactionDataModel.CryptoTransactionStaticData(
		marketName: marketName,
		holdingQuantity: holdingQuantity,
		averageBuyPrice: averageBuyPrice,
		buyAmount: buyAmount
	  )
	  
	  let newValidTransactionData = ValidTransactionInfo.Transaction(
		orderType: .bid,
		quantity: self.inputAmount,
		buyPrice: currentPrice
	  )
	  
	  MarketDataServiceUtil.shared.addValidTransactionData(
		for: marketName,
		orderType: .bid,
		postValidTransactionList: UserDataManager.userValidTransactionList,
		newValidTransactionData: newValidTransactionData
	  )
	  
	  // 새 매수 거래내역 추가
	  MarketDataServiceUtil.shared.addTransactionData(
		postTransactionList: UserDataManager.userTransactionList,
		data: newTransactionInfo
	  )
	  
	  // 새 데이터 업데이트
	  MarketDataServiceUtil.shared.fetchData(
		data: newCryptoStaticData,
		currentPrice: currentPrice
	  )
	  
	  // 사용자 거래 가능 금액 업데이트
	  MarketDataServiceUtil.shared.fetchUserAvailableBalance(
		orderType: .bid,
		balance: availableBalance,
		newBuyAmount: newBuyAmount
	  )
	  
	  availableBalance -= newBuyAmount
	  
	} else {
	  // *****이전 매수 기록 없음*****
	  let averageBuyPrice = currentPrice
	  let buyAmount = floor(currentPrice * self.inputAmount)
	  let holdingQuantity = self.inputAmount
	  
	  let newTransactionInfo = TransactionInfo(
		marketName: marketName,
		orderType: .bid,
		executedDate: executedDate,
		executedPrice: currentPrice,
		executedQuantity: holdingQuantity,
		executedAmount: buyAmount
	  )
	  
	  let newCryptoStaticData = CryptoTransactionDataModel.CryptoTransactionStaticData(
		marketName: marketName,
		holdingQuantity: holdingQuantity,
		averageBuyPrice: averageBuyPrice,
		buyAmount: buyAmount
	  )
	  
	  let newValidTransactionData = ValidTransactionInfo.Transaction(
		orderType: .bid,
		quantity: holdingQuantity,
		buyPrice: currentPrice
	  )
	  
	  MarketDataServiceUtil.shared.addValidTransactionData(
		for: marketName,
		orderType: .bid,
		postValidTransactionList: UserDataManager.userValidTransactionList,
		newValidTransactionData: newValidTransactionData
	  )
	  
	  // 새 거래내역 추가
	  MarketDataServiceUtil.shared.addTransactionData(
		postTransactionList: UserDataManager.userTransactionList,
		data: newTransactionInfo
	  )
	  
	  // 이전 매매기록 없는 상황에서, 첫 데이터 등록
	  MarketDataServiceUtil.shared.addCryptoFirstData(
		for: marketName,
		staticData: newCryptoStaticData,
		currentPrice: currentPrice
	  )
	  
	  // 사용자 거래 가능 금액 업데이트
	  MarketDataServiceUtil.shared.fetchUserAvailableBalance(
		orderType: .bid,
		balance: availableBalance,
		newBuyAmount: buyAmount
	  )
	  
	  availableBalance -= buyAmount
	}
	
	UserDataManager.userInformation?.userAvailableBalance = availableBalance
	self.availableTradePrice.text = availableBalance.formatSignificantDigits()
	
	completion()
  }
  
  func updateUserInformation(availableBalance: Double) {
	UserDataManager.userInformation = MobitUserInformation(
	  userAvailableBalance: availableBalance
	)
  }
  
  /// price format
  func formatTradePrice(_ tradePrice: Double?, precision: Int = 8) -> String {
	guard let price = tradePrice else {
	  return "N/A"  // 값이 없을 때 반환할 기본 문자열
	}
	return String(format: "%.\(precision)f", price)
  }
  
  func initTextFieldValue() {
	self.inputTradeAmount.text = nil
	self.totalPriceTextField.text = nil
  }
  
  func bind(reactor: CryptoDetailReactor) {
	
	reactor.state.map { $0.cryptoCellInfo }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] cellInfo in
		guard let self = self else { return }
		
		let numberFormatter = NumberFormatter()
		numberFormatter.numberStyle = .decimal
		
		self.cryptoInfo = cellInfo
		
		guard let tradePrice = self.cryptoInfo?.tradePrice else {
		  self.currentPrice.text = "N/A"
		  return
		}
		
		if tradePrice < 1 {
		  self.currentPrice.text = formatTradePrice(tradePrice)
		} else {
		  self.currentPrice.text = numberFormatter.string(
			from: NSNumber(value: tradePrice)
		  )
		}
	  })
	  .disposed(by: self.disposeBag)
  }
}

extension TradeBidView: UITextFieldDelegate {
  func checkTotalPriceTextField(_ textField: UITextField) {
	guard let currentPrice = self.cryptoInfo?.tradePrice?.formatDigits(digits: 8) else { return }
	let inputTotalPrice = textField.text?.digitsOnlyDouble ?? 0
	let inputAmount = inputTotalPrice / currentPrice
	
	if floor(self.inputAmount) > 0 {
	  self.inputTradeAmount.text = inputAmount.formatSignificantDigits(digits: 4)
	  self.inputAmount = Double(inputAmount.formatSignificantDigits(digits: 4)) ?? 0
	} else {
	  self.inputTradeAmount.text = inputAmount.formatSignificantDigits()
	  self.inputAmount = Double(inputAmount.formatSignificantDigits()) ?? 0
	}
  }
  
  func textFieldDidChangeSelection(_ textField: UITextField) {
	guard let currentPrice = self.cryptoInfo?.tradePrice else { return }
	
	if textField == self.inputTradeAmount {
	  self.inputAmount = textField.text?.digitsOnlyDouble ?? 0
	  let totalPrice = floor(
		currentPrice.formatDigits(digits: 8) * inputAmount.formatDigits(digits: 8)
	  )
	  self.totalPriceTextField.text = totalPrice.formatSignificantDigits()
	} else if textField == self.totalPriceTextField {
	  self.checkTotalPriceTextField(textField)
	}
  }
  
  func textFieldDidEndEditing(_ textField: UITextField) {
	textField.text = textField.text?.addComma()
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
	
	let allowedCharacters = CharacterSet(charactersIn: "0123456789.")
	if string.rangeOfCharacter(from: allowedCharacters.inverted) != nil {
	  return false
	}
	
	// 소숫점 입력 중복 방지
	if string == "." {
	  
	  if updatedText.filter({ $0 == "." }).count > 1 {
		return false
	  }
	  
	  // "."이 맨 앞에 입력되면 자동으로 "0."으로 바꿔주기
	  if currentText.isEmpty && string == "." {
		textField.text = "0."
		self.checkTotalPriceTextField(textField)
		return false
	  }
	}
	
	// "0"으로 시작하는데 다음 문자가 숫자일 경우 → "0" 제거
	if currentText == "0", string != ".", !string.isEmpty {
	  textField.text = string
	  self.checkTotalPriceTextField(textField)
	  return false
	}
	
	return true
  }
}
