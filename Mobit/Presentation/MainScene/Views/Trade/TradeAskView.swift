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
  
  weak var reactor: TradeReactor? = nil
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
  private var currentInvestData: CryptoTransactionDataModel? = nil
  
  deinit {
	print("deinit : \(String(describing: type(of: self)))")
  }
  
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
	self.endEditing(true)
  }
  
  static func instanceFromNib(
	reactor: TradeReactor,
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
	self.inputTradeAmount.setAdaptivePlaceholderColor()
	self.totalPriceTextField.setAdaptivePlaceholderColor()
	
	let marketName = self.reactor?.selectCrypto.market.components(separatedBy: "/").first
	self.marketNameLabels.forEach({ $0.text = marketName })
	self.inputTradeAmount.keyboardType = .decimalPad
	self.totalPriceTextField.keyboardType = .numberPad
	
	self.inputTradeAmount.attributedPlaceholder = NSAttributedString(
	  string: "0",
	  attributes: [
		.foregroundColor: UIColor.lightGray
	  ]
	)
	self.totalPriceTextField.attributedPlaceholder = NSAttributedString(
	  string: "0",
	  attributes: [
		.foregroundColor: UIColor.lightGray
	  ]
	)
  }
  
  func setData() {
	self.inputTradeAmount.delegate = self
	self.totalPriceTextField.delegate = self
	self.inputTradeAmount.accessibilityIdentifier = "amount"
	self.totalPriceTextField.accessibilityIdentifier = "totalPrice"
	self.updateCryptoData()
  }
  
  func updateCryptoData() {
	guard let crypto = self.currentInvestData,
		  let currentPrice = self.cryptoInfo?.tradePrice
	else {
	  // crypto를 찾지 못한 것은 이미 모두 매도했다는 의미로 간주
	  self.availableCrypto.text = "0"
	  self.availableTradePrice.text = "≈ 0"
	  
	  return
	}
	
	let krwAvailablePrice = currentPrice * crypto.staticData.holdingQuantity
	self.availableCryptoCount = crypto.staticData.holdingQuantity
	self.availableCrypto.text = String(self.availableCryptoCount.formatSignificantDigits())
	self.availableTradePrice.text = "≈ " + String(floor(krwAvailablePrice)).addComma()
	
	if self.inputAmount > 0 {
	  let totalPriceFromInputAmount = currentPrice * self.inputAmount
	  self.totalPriceTextField.text = String(floor(totalPriceFromInputAmount)).addComma()
	} else {
	  self.totalPriceTextField.text = "0"
	}
  }
  
  /// 최대 수량 버튼
  @IBAction func tapOnMaxAmount(_ sender: UIButton) {
	guard let availableCrypto = UserDataManager.userCryptoList?
			.compactMap({ $0 })
			.first(where: { $0.staticData.marketName == self.reactor?.selectCrypto.market }),
		  let currentPrice = self.cryptoInfo?.tradePrice
	else { return }
	
	let krwAvailablePrice = currentPrice * availableCrypto.staticData.holdingQuantity
	self.inputTradeAmount.text = String(availableCrypto.staticData.holdingQuantity.formatSignificantDigits())
	self.inputAmount = availableCrypto.staticData.holdingQuantity
	self.totalPriceTextField.text = String(floor(krwAvailablePrice)).addComma()
  }
  
  /// 초기화 버튼
  @IBAction func tapOnInitButton(_ sender: UIButton) {
	self.inputAmount = 0
	self.inputTradeAmount.text = ""
	self.totalPriceTextField.text = ""
  }
  
  @IBAction func tapOnAskButton(_ sender: UIButton) {
	self.endEditing(true)
	
	let vibrator = UIImpactFeedbackGenerator(style: .medium)
	vibrator.impactOccurred()
	
	guard let currentPrice = self.cryptoInfo?.tradePrice?.formatDigits(digits: 8),
		  let marketName = self.reactor?.selectCrypto.market,
		  let crypto = UserDataManager.userCryptoList?.compactMap({ $0 }).first(
			where: { $0.staticData.marketName == marketName }
		  )
	else {
	  self.callBack?(.alert(title: "알림", message: "매도 수량을 확인 해주세요."))
	  return
	}
	
	// 매도 버튼 누르는 시점 기준, total 금액으로 비교
	let calcUtil = CalculationUtil(currentPrice: currentPrice, newHoldingQuantity: inputAmount)
	let executedTotalPrice = calcUtil.calcBuyAmount()
	
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
	guard let postStaticTransaction = postStaticTransaction else { return }
	
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
	  
	  let newTransaction: TransactionInfo = TransactionInfo(
		marketName: crypto.staticData.marketName,
		orderType: .ask,
		executedDate: executedDate,
		executedPrice: currentPrice,
		executedQuantity: self.inputAmount,
		executedAmount: currentPrice * self.inputAmount
	  )
	  UserDataManager.userTransactionList?.append(newTransaction)
	  
	  let newValidTransactionData = ValidTransactionInfo.Transaction(
		orderType: .ask,
		quantity: self.inputAmount,
		buyPrice: currentPrice
	  )
	  
	  MarketDataServiceUtil.shared.addValidTransactionData(
		for: marketName,
		orderType: .ask,
		postValidTransactionList: UserDataManager.userValidTransactionList,
		newValidTransactionData: newValidTransactionData
	  )
	  
	  // 부분 매도
	  if self.inputAmount < postStaticTransaction.holdingQuantity {
		let newHoldingQuantity = postStaticTransaction.holdingQuantity - self.inputAmount
		let newBuyAmount = newHoldingQuantity * postStaticTransaction.averageBuyPrice
		
		let newCryptoStaticData = CryptoTransactionDataModel.CryptoTransactionStaticData(
		  marketName: crypto.staticData.marketName,
		  cryptoName: crypto.staticData.cryptoName,
		  holdingQuantity: newHoldingQuantity,
		  averageBuyPrice: postStaticTransaction.averageBuyPrice,
		  buyAmount: newBuyAmount
		)
		
		// 사용자 계좌 반영
		UserDataManager.userInformation?.userAvailableBalance += executedTotalPrice
		// 매도 후, 보유하고 있는 코인 매매정보 업데이트
		MarketDataServiceUtil.shared.fetchData(
		  data: newCryptoStaticData,
		  currentPrice: currentPrice
		)
	  } else {
		// 전체 매도
		// 사용자 계좌 반영
		UserDataManager.userInformation?.userAvailableBalance += executedTotalPrice
		// 전량 매도
		UserDataManager.userCryptoList?.remove(at: transactionIndex)
	  }
	  
	  // 실현손익 계산
	  let pnl = calcUtil.calcPnl(
		entryPrice: postStaticTransaction.averageBuyPrice,
		exitPrice: currentPrice,
		quantity: self.inputAmount
	  )
	  
	  let pnlHistory = UserPNLHistoryModel(
		marketName: crypto.staticData.marketName,
		entryPrice: postStaticTransaction.averageBuyPrice,
		exitPrice: currentPrice,
		transactionDate: executedDate,
		orderQuantity: self.inputAmount,
		pnl: pnl
	  )
	  
	  UserDataManager.userPNLHistory?.append(pnlHistory)
	  
	  
	  // self.callBack?(.alert(title: "알림", message: "매도 되었습니다."))
	  self.callBack?(.successLottie)	// 로띠 동작
	  self.initTextFieldValue()			// 텍스트 필드 초기화
	  
	  self.updateCryptoData()
	  self.callBack?(.updateHistory)
	  
	} else {
	  self.callBack?(.alert(title: "알림", message: "주문 수량을 재설정 해주세요."))
	}
  }
  
  func initTextFieldValue() {
	self.inputTradeAmount.text = nil
	self.totalPriceTextField.text = nil
	self.inputAmount = 0
  }
  
  func bind(reactor: TradeReactor) {
	reactor.state.map { $0.cryptoCellInfo }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] cellInfo in
		guard let self = self else { return }
		self.cryptoInfo = cellInfo
	  })
	  .disposed(by: self.disposeBag)
	
	reactor.state.map { $0.cryptoTransactionDatas }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] cryptos in
		guard let self = self else { return }
		self.currentInvestData = cryptos.first(where: {
		  $0.staticData.marketName == reactor.selectCrypto.market
		})
		self.updateCryptoData()
	  })
	  .disposed(by: self.disposeBag)
  }
}

extension TradeAskView: UITextFieldDelegate {

  enum InputType: String {
	case amount, totalPrice
  }
  
  func inputType(for textField: UITextField) -> InputType? {
	guard let id = textField.accessibilityIdentifier else { return nil }
	return InputType(rawValue: id)
  }
  
  /// 텍스트 필드에 텍스트가 변경될 때, 호출
  /// 텍스트가 변경되지 않아도 selection만 변경되어도 호출
  func textFieldDidChangeSelection(_ textField: UITextField) {
	guard let currentPrice = self.cryptoInfo?.tradePrice?.formatDigits(digits: 8),
		  let type = inputType(for: textField) else { return }
	
	switch type {
	case .totalPrice:
	  let inputTotalPrice = textField.text?.digitsOnlyDouble ?? 0
	  let inputAmount = inputTotalPrice / currentPrice
	  self.inputAmount = inputAmount
	  self.inputTradeAmount.text = inputAmount.formatSignificantDigits(digits: 4)
	  self.totalPrice = inputTotalPrice
	  
	case .amount:
	  let inputAmount = textField.text?.digitsOnlyDouble ?? 0
	  let totalPrice = floor(currentPrice * inputAmount)
	  self.totalPriceTextField.text = totalPrice.formatSignificantDigits()
	  self.inputAmount = inputAmount
	  self.totalPrice = totalPrice
	}
  }
  
  /// 텍스트 필드 포커스 해제시, 호출
  func textFieldDidEndEditing(_ textField: UITextField) {
	textField.text = textField.text?.addComma()
  }
  
  /// 텍스트 필드 입력을 시도할 때, 호출
  /// 입력값 허용 / 비허용, 입력 중간에 가로채서 수정할 수 있음
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
	
	// 소수점 중복 방지
	if string == "." && currentText.contains(".") {
	  return false
	}
	
	// "."이 맨 앞에 오면 "0." 처리
	if currentText.isEmpty && string == "." {
	  textField.text = "0."
	  DispatchQueue.main.async {
		self.textFieldDidChangeSelection(textField)
	  }
	  return false
	}
	
	// 선행 0 처리 (0으로 시작하고 뒤에 숫자가 오면 제거)
	if currentText.allSatisfy({ $0 == "0" }), string != ".", !string.isEmpty {
	  textField.text = string
	  DispatchQueue.main.async {
		self.textFieldDidChangeSelection(textField)
	  }
	  return false
	}
	
	return true
  }
}
