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
  @IBOutlet weak var orderButton: UIButton!
  @IBOutlet weak var orderNoticeLabel: UILabel!

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
	self.updateOrderValidationState()
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
	  self.updateOrderValidationState()

	  return
	}

	let krwAvailablePrice = currentPrice * crypto.staticData.holdingQuantity
	self.availableCryptoCount = crypto.staticData.holdingQuantity
	self.availableCrypto.text = String(self.availableCryptoCount.formatSignificantDigits())
	self.availableTradePrice.text = "≈ " + floor(krwAvailablePrice).formatSignificantDigits()

	if self.inputAmount > 0 {
	  let totalPriceFromInputAmount = currentPrice * self.inputAmount
	  self.totalPriceTextField.text = floor(totalPriceFromInputAmount).formatSignificantDigits()
	} else {
	  self.totalPriceTextField.text = "0"
	}

	self.updateOrderValidationState()
  }

  /// 최대 수량 버튼
  @IBAction func tapOnMaxAmount(_ sender: UIButton) {
    // 키보드가 올라온 채로 값을 채우면 편집 콜백이 화면 표시용(소수점 8자리) 값으로 수량을 덮어써 전량 매도가 되지 않는다.
    self.endEditing(true)

    guard let targetPairID = self.reactor.map({
      ExchangeMarketCodeConverter.pairID(
        fromDisplayMarket: $0.selectCrypto.market,
        exchange: ExchangeSelectionStore.currentExchange
      )
    }) else { return }
	guard let availableCrypto = UserDataManager.userCryptoList?
			.compactMap({ $0 })
			.first(where: { $0.staticData.exchangePairID == targetPairID }),
		  let currentPrice = self.cryptoInfo?.tradePrice
	else { return }

	let krwAvailablePrice = currentPrice * availableCrypto.staticData.holdingQuantity
	self.inputTradeAmount.text = String(availableCrypto.staticData.holdingQuantity.formatSignificantDigits())
	self.inputAmount = availableCrypto.staticData.holdingQuantity
	self.totalPriceTextField.text = floor(krwAvailablePrice).formatSignificantDigits()
	self.updateOrderValidationState()
  }

  /// 초기화 버튼
  @IBAction func tapOnInitButton(_ sender: UIButton) {
	self.initTextFieldValue(focusAmount: true)
  }

  @IBAction func tapOnAskButton(_ sender: UIButton) {
	self.endEditing(true)

	let vibrator = UIImpactFeedbackGenerator(style: .medium)
	vibrator.impactOccurred()

	guard let currentPrice = self.cryptoInfo?.tradePrice?.formatDigits(digits: 8),
          let targetPairID = self.reactor.map({
            ExchangeMarketCodeConverter.pairID(
              fromDisplayMarket: $0.selectCrypto.market,
              exchange: ExchangeSelectionStore.currentExchange
            )
          }),
		  let crypto = UserDataManager.userCryptoList?.compactMap({ $0 }).first(
			where: { $0.staticData.exchangePairID == targetPairID }
		  )
	else {
	  self.callBack?(.alert(title: "알림", message: TradeOrderValidator.ValidationError.missingPrice.message))
	  return
	}

	let validation = TradeOrderValidator.validateAsk(
	  price: currentPrice,
	  quantity: inputAmount,
	  holdingQuantity: crypto.staticData.holdingQuantity
	)

	guard case .success = validation else {
	  if case .failure(let error) = validation {
		self.callBack?(.alert(title: "알림", message: error.message))
	  }
	  return
	}

	let result = TradeOrderService.executeAsk(
	  marketName: crypto.staticData.marketName,
	  currentPrice: currentPrice,
	  quantity: inputAmount,
      exchange: crypto.staticData.exchange
	)

	switch result {
	case .success:
	  self.callBack?(.successLottie)
	  self.initTextFieldValue()
	  self.currentInvestData = UserDataManager.userCryptoList?.first(where: {
		$0.staticData.exchangePairID == targetPairID
	  })
	  self.updateCryptoData()
	  self.callBack?(.updateHistory)
	case .failure(let error):
	  self.callBack?(.alert(title: "알림", message: error.message))
	}
  }

  func initTextFieldValue() {
	self.initTextFieldValue(focusAmount: false)
  }

  func initTextFieldValue(focusAmount: Bool) {
	self.inputTradeAmount.text = nil
	self.totalPriceTextField.text = nil
	self.inputAmount = 0
	self.totalPrice = 0
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

	let validation = TradeOrderValidator.validateAsk(
	  price: cryptoInfo?.tradePrice?.formatDigits(digits: 8),
	  quantity: inputAmount,
	  holdingQuantity: currentInvestData?.staticData.holdingQuantity ?? 0
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
	orderNoticeLabel?.textColor = isError ? .systemRed : .systemBlue
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
        let targetPairID = ExchangeMarketCodeConverter.pairID(
          fromDisplayMarket: reactor.selectCrypto.market,
          exchange: ExchangeSelectionStore.currentExchange
        )
		self.currentInvestData = cryptos.first(where: {
		  $0.staticData.exchangePairID == targetPairID
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
	  self.totalPrice = inputTotalPrice

	case .amount:
	  let inputAmount = textField.text?.digitsOnlyDouble ?? 0
	  let totalPrice = floor(currentPrice * inputAmount)
	  self.totalPriceTextField.text = totalPrice.formatSignificantDigits()
	  self.inputAmount = inputAmount
	  self.totalPrice = totalPrice
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

	// 삭제 결과 끝에 콤마만 남으면 사용자가 콤마까지 다시 지워야 하므로 함께 제거한다
	if string.isEmpty, let deletionRange = Range(range, in: currentText) {
	  var deletedText = currentText.replacingCharacters(in: deletionRange, with: "")
	  guard deletedText.hasSuffix(",") else { return true }

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
