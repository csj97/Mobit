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
  @IBOutlet weak var contentContainerView: UIView!
  @IBOutlet weak var inputMarketName: UILabel!
  @IBOutlet weak var orderButton: UIButton!
  @IBOutlet weak var resetButton: UIButton!
  @IBOutlet weak var maxAmountButton: UIButton!
  @IBOutlet weak var orderNoticeLabel: UILabel!
  @IBOutlet var settlementCurrencyLabels: [UILabel]!

  weak var reactor: TradeReactor? = nil
  var callBack: ((OrderResult) -> ())? = nil
  var disposeBag = DisposeBag()
  var cryptoInfo: CryptoCellInfo? = nil
  // 매수 수량
  var inputAmount: Double = 0.0
  private let defaultOrderNotice = "*시장가 주문은 현재 시장 유동성에 따라\n체결 가격이 달라질 수 있습니다."
  private var isOrderSubmissionLocked = false

  /// BTC 마켓은 원화 잔고가 아니라 보유 BTC로 결제한다.
  private var settlementCurrency: SettlementCurrency {
    self.reactor?.settlementCurrency ?? .krw
  }

  private var availableSettlementBalance: Double {
    TradeOrderService.availableSettlementBalance(currency: self.settlementCurrency) ?? 0
  }

  deinit {
	print("deinit : \(String(describing: type(of: self)))")
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
	self.endEditing(true)
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
	applyThemeColors()
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
	applyThemeColors()

	self.inputMarketName.text = self.reactor?.selectCrypto.market.components(separatedBy: "/").first
	self.inputTradeAmount.keyboardType = .decimalPad
	// BTC 마켓은 총액도 소수라 정수 키패드로는 입력할 수 없다.
	self.totalPriceTextField.keyboardType = self.settlementCurrency == .krw ? .numberPad : .decimalPad
	self.applySettlementCurrencyText()
	self.updateOrderValidationState()
  }

  private func applySettlementCurrencyText() {
	self.settlementCurrencyLabels?.forEach { $0.text = self.settlementCurrency.rawValue }
  }

  private func applyThemeColors() {
	self.applyContainerTheme()
	self.applyLabelColors()
	self.applyInputFieldColors()
	self.applyButtonColors()
	self.updateOrderValidationState()
  }

  func refreshMarketColors() {
	applyThemeColors()
  }

  // 주문 카드 배경과 그림자
  private func applyContainerTheme() {
	let isDarkMode = traitCollection.userInterfaceStyle == .dark
	self.backgroundColor = .clear
	self.contentContainerView.backgroundColor = isDarkMode ? .mobitColors(.tradeSurface) : .white
	self.applyContentContainerShadow(isDarkMode: isDarkMode)
  }

  // 주요 라벨 색상
  private func applyLabelColors() {
	[
	  self.availableTradePrice,
	  self.currentPrice,
	  self.inputMarketName
	].forEach { $0?.textColor = .mobitColors(.tradeTextPrimary) }
  }

  // 수량과 총액 입력 영역
  private func applyInputFieldColors() {
	self.inputTradeAmount.setAdaptivePlaceholderColor()
	self.totalPriceTextField.setAdaptivePlaceholderColor()
	[self.inputTradeAmount, self.totalPriceTextField].forEach {
	  $0?.textColor = .mobitColors(.tradeTextPrimary)
	}
	self.inputTradeAmount.backgroundColor = .mobitColors(.tradeControlSurface)
	self.totalPriceTextField.backgroundColor = .clear
	self.inputAmountTFView.backgroundColor = .mobitColors(.tradeControlSurface)
  }

  // 주문 관련 버튼
  private func applyButtonColors() {
	self.orderButton.setTitleColor(.white, for: .normal)
	self.orderButton.backgroundColor = MarketColorPalette.riseColor
	self.applyResetButtonColors()
	self.maxAmountButton.setTitleColor(.mobitColors(.tradeTextPrimary), for: .normal)
	self.maxAmountButton.backgroundColor = .mobitColors(.tradeControlSurface)
  }

  // 라이트 모드는 앱스토어 스타일 유지
  private func applyResetButtonColors() {
	let isDarkMode = traitCollection.userInterfaceStyle == .dark
	self.resetButton.backgroundColor = isDarkMode
	  ? .mobitColors(.tradeControlSurface)
	  : UIColor(white: 0.333, alpha: 1)
	self.resetButton.setTitleColor(
	  isDarkMode ? .mobitColors(.tradeTextPrimary) : .white,
	  for: .normal
	)
  }

  // 다크 모드에서는 카드 그림자 제거
  private func applyContentContainerShadow(isDarkMode: Bool) {
	self.contentContainerView.layer.shadowColor = UIColor.black.withAlphaComponent(0.3).cgColor
	self.contentContainerView.layer.shadowOffset = CGSize(width: 2, height: 6)
	self.contentContainerView.layer.shadowRadius = 12
	self.contentContainerView.layer.shadowOpacity = isDarkMode ? 0 : 0.4
	self.contentContainerView.layer.masksToBounds = false
  }

  func setData() {
	self.inputTradeAmount.delegate = self
	self.totalPriceTextField.delegate = self
	self.inputTradeAmount.accessibilityIdentifier = "amount"
	self.totalPriceTextField.accessibilityIdentifier = "totalPrice"

	self.availableTradePrice.text = self.availableSettlementBalance.formatSignificantDigits()
  }

  @IBAction func tapOnMaxAmount(_ sender: UIButton) {
	// 키보드가 올라온 채로 값을 채우면 편집 콜백이 화면 표시용(소수점 8자리) 값으로 수량을 덮어쓴다.
	self.endEditing(true)

	guard let currentPrice = self.cryptoInfo?.tradePrice?.formatDigits(digits: 8),
		  currentPrice > 0
	else { return }

	inputAmount = (self.availableSettlementBalance / currentPrice)

	let totalPrice = PortfolioCalculator.executedAmount(
	  price: currentPrice,
	  quantity: inputAmount,
	  currency: self.settlementCurrency
	)
	self.inputTradeAmount.text = inputAmount.formatSignificantDigits()
	self.totalPriceTextField.text = totalPrice.formatSignificantDigits()
	self.updateOrderValidationState()
  }

  /// 초기화 버튼
  @IBAction func tapOnInitButton(_ sender: UIButton) {
	self.initTextFieldValue(focusAmount: true)
  }

  @IBAction func tapOnBidButton(_ sender: UIButton) {
	guard !isOrderSubmissionLocked else { return }
	isOrderSubmissionLocked = true
	updateOrderValidationState()
	DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
	  self?.isOrderSubmissionLocked = false
	  self?.updateOrderValidationState()
	}
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
	  availableBalance: self.availableSettlementBalance,
	  currency: self.settlementCurrency
	)

	switch validation {
	case .success:
	  let result = TradeOrderService.executeBid(
		marketName: marketName,
		cryptoName: self.cryptoInfo?.cryptoName,
        currentPrice: currentPrice,
		quantity: inputAmount,
        exchange: self.reactor?.exchange ?? ExchangeSelectionStore.currentExchange,
        btcKRWPrice: self.reactor.flatMap {
          AppDataManager.shared.btcKRWPrice(for: $0.exchange)
        }
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

	self.availableTradePrice.text = self.availableSettlementBalance.formatSignificantDigits()
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
	guard !isOrderSubmissionLocked else {
	  applyOrderButtonState(isEnabled: false, notice: defaultOrderNotice, isError: false)
	  return
	}
	guard inputAmount > 0 else {
	  applyOrderButtonState(isEnabled: false, notice: defaultOrderNotice, isError: false)
	  return
	}

	// BTC 마켓은 결제용 BTC/KRW 시세가 도착하기 전에는 체결할 수 없다.
	if settlementCurrency == .btc,
       reactor.map({ AppDataManager.shared.btcKRWPrice(for: $0.exchange) }) == nil {
	  applyOrderButtonState(
		isEnabled: false,
		notice: TradeOrderValidator.ValidationError.missingSettlementRate.message,
		isError: true
	  )
	  return
	}

	let validation = TradeOrderValidator.validateBid(
	  price: cryptoInfo?.tradePrice?.formatDigits(digits: 8),
	  quantity: inputAmount,
	  availableBalance: self.availableSettlementBalance,
	  currency: self.settlementCurrency
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
	orderNoticeLabel?.textColor = isError ? MarketColorPalette.fallColor : .mobitColors(.accentPrimary)
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

	// BTC/KRW 시세가 뒤늦게 도착하면 잠겨 있던 주문 버튼을 풀어야 한다.
	reactor.state.map { $0.settlementRatePrice }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] _ in
		self?.updateOrderValidationState()
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

	  let totalPrice = PortfolioCalculator.executedAmount(
		price: currentPrice,
		quantity: inputAmount,
		currency: self.settlementCurrency
	  )
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
