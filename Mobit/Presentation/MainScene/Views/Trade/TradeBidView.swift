//
//  TradeBidView.swift
//  Mobit
//
//  Created by 조성재 on 2/7/25.
//

import AVFoundation
import UIKit
import RxSwift

class TradeBidView: UIView, ViewRule {

  @IBOutlet weak var availableTradePrice: UILabel!
  @IBOutlet weak var inputTradeAmount: UITextField!
  @IBOutlet weak var currentPrice: UILabel!
  @IBOutlet weak var totalPriceTextField: UITextField!
  @IBOutlet weak var inputAmountTFView: UIView!
  @IBOutlet weak var inputMarketName: UILabel!
  @IBOutlet weak var orderButton: UIButton!
  @IBOutlet weak var orderNoticeLabel: UILabel!

  weak var reactor: TradeReactor? = nil
  var callBack: ((OrderResult) -> ())? = nil
  var disposeBag = DisposeBag()
  var cryptoInfo: CryptoCellInfo? = nil
  // 매수 수량
  var inputAmount: Double = 0.0
  private let defaultOrderNotice = "*시장가 주문은 현재 시장 유동성에 따라\n체결 가격이 달라질 수 있습니다."

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
	self.inputTradeAmount.setAdaptivePlaceholderColor()
	self.totalPriceTextField.setAdaptivePlaceholderColor()

	self.inputMarketName.text = self.reactor?.selectCrypto.market.components(separatedBy: "/").first
	self.inputTradeAmount.keyboardType = .decimalPad
	self.totalPriceTextField.keyboardType = .numberPad
	self.updateOrderValidationState()
  }

  func setData() {
	self.inputTradeAmount.delegate = self
	self.totalPriceTextField.delegate = self
	self.inputTradeAmount.accessibilityIdentifier = "amount"
	self.totalPriceTextField.accessibilityIdentifier = "totalPrice"

	guard let userBalance = UserDataManager.userInformation?.userAvailableBalance
	else { return }

	self.availableTradePrice.text = userBalance.formatSignificantDigits()
  }

  @IBAction func tapOnMaxAmount(_ sender: UIButton) {
	// 키보드가 올라온 채로 값을 채우면 편집 콜백이 화면 표시용(소수점 8자리) 값으로 수량을 덮어쓴다.
	self.endEditing(true)

	guard let currentPrice = self.cryptoInfo?.tradePrice?.formatDigits(digits: 8),
		  let userBalance = UserDataManager.userInformation?.userAvailableBalance
	else { return }

	inputAmount = (userBalance / currentPrice)

	let calcUtil = CalculationUtil(currentPrice: currentPrice, newHoldingQuantity: inputAmount)
	let totalPrice = calcUtil.calcBuyAmount().formatSignificantDigits()
	self.inputTradeAmount.text = inputAmount.formatSignificantDigits()
	self.totalPriceTextField.text = String(totalPrice)
	self.updateOrderValidationState()
  }

  /// 초기화 버튼
  @IBAction func tapOnInitButton(_ sender: UIButton) {
	self.initTextFieldValue(focusAmount: true)
  }

  @IBAction func tapOnBidButton(_ sender: UIButton) {
	self.endEditing(true)

	let vibrator = UIImpactFeedbackGenerator(style: .medium)
	vibrator.impactOccurred()

	guard let marketName = self.cryptoInfo?.market,
		  let currentPrice = self.cryptoInfo?.tradePrice?.formatDigits(digits: 8)
	else {
	  callBack?(.alert(title: "알림", message: TradeOrderValidator.ValidationError.missingPrice.message))
	  return
	}

	let validation = TradeOrderValidator.validateBid(
	  price: currentPrice,
	  quantity: inputAmount,
	  availableBalance: UserDataManager.userInformation?.userAvailableBalance
	)

	switch validation {
	case .success:
	  let result = TradeOrderService.executeBid(
		marketName: marketName,
		cryptoName: self.cryptoInfo?.cryptoName,
		currentPrice: currentPrice,
		quantity: inputAmount,
        exchange: ExchangeSelectionStore.currentExchange
	  )

	  switch result {
	  case .success(let execution):
		self.availableTradePrice.text = execution.availableBalance.formatSignificantDigits()
		self.callBack?(.successLottie)
		self.initTextFieldValue()
		self.callBack?(.updateHistory)
	  case .failure(let error):
		callBack?(.alert(title: "알림", message: error.message))
	  }
	case .failure(let error):
	  callBack?(.alert(title: "알림", message: error.message))
	}
  }

  /// 매매하고 나면 여기 업데이트
  func updateCryptoData() {
	guard self.cryptoInfo?.tradePrice != nil else {
	  self.availableTradePrice.text = "0"
	  self.updateOrderValidationState()

	  return
	}

	let userBalance = UserDataManager.userInformation?.userAvailableBalance
	self.availableTradePrice.text = userBalance?.formatSignificantDigits()
	self.updateOrderValidationState()
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
	self.initTextFieldValue(focusAmount: false)
  }

  func initTextFieldValue(focusAmount: Bool) {
	self.inputTradeAmount.text = nil
	self.totalPriceTextField.text = nil
	self.inputAmount = 0
	self.updateOrderValidationState()

	if focusAmount {
	  self.inputTradeAmount.becomeFirstResponder()
	}
  }

  private func updateOrderValidationState() {
	guard inputAmount > 0 else {
	  applyOrderButtonState(isEnabled: false, notice: defaultOrderNotice, isError: false)
	  return
	}

	let validation = TradeOrderValidator.validateBid(
	  price: cryptoInfo?.tradePrice?.formatDigits(digits: 8),
	  quantity: inputAmount,
	  availableBalance: UserDataManager.userInformation?.userAvailableBalance
	)

	switch validation {
	case .success:
	  applyOrderButtonState(isEnabled: true, notice: defaultOrderNotice, isError: false)
	case .failure(let error):
	  applyOrderButtonState(isEnabled: false, notice: error.message, isError: true)
	}
  }

  private func applyOrderButtonState(isEnabled: Bool, notice: String, isError: Bool) {
	orderButton?.isEnabled = isEnabled
	orderButton?.alpha = isEnabled ? 1 : 0.45
	orderNoticeLabel?.text = notice
	orderNoticeLabel?.textColor = .systemRed
  }

  func bind(reactor: TradeReactor) {

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
		self.updateOrderValidationState()
	  })
	  .disposed(by: self.disposeBag)
  }
}

extension TradeBidView: UITextFieldDelegate {

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
	// 코드로 텍스트를 채울 때도 호출되므로, 반대편 필드 값이 서로를 덮어쓰지 않도록 편집 중인 필드만 반영한다.
	guard textField.isFirstResponder,
		  let currentPrice = self.cryptoInfo?.tradePrice?.formatDigits(digits: 8),
		  let type = inputType(for: textField) else { return }

	switch type {
	case .totalPrice:
	  let inputTotalPrice = textField.text?.digitsOnlyDouble ?? 0
	  let inputAmount = inputTotalPrice / currentPrice

	  self.inputAmount = inputAmount
	  self.inputTradeAmount.text = inputAmount.formatSignificantDigits(digits: 4)

	case .amount:
	  let inputAmount = textField.text?.digitsOnlyDouble ?? 0
	  self.inputAmount = inputAmount

	  let totalPrice = floor(currentPrice * inputAmount)
	  self.totalPriceTextField.text = totalPrice.formatSignificantDigits()
	}

	self.updateOrderValidationState()
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

	// 삭제 결과 끝에 콤마만 남으면 사용자가 콤마까지 다시 지워야 하므로 함께 제거한다
	if string.isEmpty, updatedText.hasSuffix(",") {
	  var deletedText = updatedText
	  while deletedText.hasSuffix(",") {
		deletedText.removeLast()
	  }
	  textField.text = deletedText
	  DispatchQueue.main.async {
		self.textFieldDidChangeSelection(textField)
	  }
	  return false
	}

	let allowedCharacters = CharacterSet(charactersIn: "0123456789.")
	if string.rangeOfCharacter(from: allowedCharacters.inverted) != nil {
	  return false
	}

	if string == "." {
	  // 소숫점 중복 입력 방지
	  if updatedText.filter({ $0 == "." }).count > 1 {
		return false
	  }

	  if currentText.isEmpty {
		textField.text = "0."
		return false
	  }
	}

	// 선행 0 처리 (0으로 시작하고 뒤에 숫자가 오면 제거)
	if currentText == "0", string != ".", !string.isEmpty {
	  textField.text = string
	  DispatchQueue.main.async {
		self.textFieldDidChangeSelection(textField)
	  }
	  return false
	}

	return true
  }
}
