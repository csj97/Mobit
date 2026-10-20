import UIKit
import SnapKit
import RxSwift
import RxCocoa

final class FuturesOrderViewController: MobitBaseViewController {
  let reactor: FuturesAccountReactor
  let instrument: TradingInstrumentID
  var captureOrderPrice: (() -> FuturesOrderPrice?)?
  // 실제 체결 완료 안내를 주문 패널 밖의 전체 화면으로 전달한다.
  var tradeCompletedCallBack: (() -> Void)?
  // 이 화면에서 요청한 진입 결과만 한 번 안내한다.
  private var didSubmitOpening = false
  // 종료 시트 계산도 주문 화면이 표시하는 소켓 시세 갱신을 따른다.
  var orderPriceUpdates: Observable<Void> = .empty()
  private var expectedPositionID: UUID?
  // 화면이 해제될 때 Rx 구독을 함께 정리한다.
  private let disposeBag = DisposeBag()
  private lazy var positionCard = FuturesPositionSummaryView(closeButton: closeButton)
  // 주문 전 확인 실패도 자산 요약과 같은 재시도 경로로 처리한다.
  private lazy var dataStatusView = FuturesDataStatusView { [weak self] in
    self?.sendOrderClick("선물_데이터_재시도")
    self?.reactor.action.onNext(.reload)
  }
  private let estimate = FuturesText.label(style: .footnote)
  // 진입할 포지션의 롱·숏 방향을 선택한다.
  private let sideSegmentedControl = UISegmentedControl(items: [FuturesText.text("futures_long"), FuturesText.text("futures_short")])
  // 시장가 주문 방식을 표시하고 테마에 맞는 테두리를 유지한다.
  private let marketOrderLabel = FuturesText.label(style: .subheadline)
  // 주문에 사용할 수 있는 금액의 설명을 왼쪽에 표시한다.
  private let availableTitleLabel = FuturesText.label(style: .caption1)
  // 주문가능 잔액을 설명과 구분해 오른쪽에 표시한다.
  private let availableAmountLabel = FuturesText.label(style: .caption1)
  // 일반 글자 크기에서는 잔액을 한 줄로, 접근성 크기에서는 세로로 배치한다.
  private lazy var availableRow = UIStackView(arrangedSubviews: [availableTitleLabel, availableAmountLabel])
  // 빈 내역도 현재 키보드를 제외한 표시 영역의 높이를 사용한다.
  private let orderScrollView = UIScrollView()
  // 주문과 내역 콘텐츠가 세그먼트 아래에서 시작하는 간격이다.
  private let contentTopInset: CGFloat = 20
  // 스크롤 콘텐츠의 기존 하단 여백을 유지한다.
  private let contentBottomInset: CGFloat = 10
  private let historyStack = UIStackView()
  private let orderStack = UIStackView()
  // 새 진입이나 추가 진입에 사용할 증거금을 입력받는다.
  private let marginTextField = UITextField()
  // 종목별 허용 범위 안에서 주문 레버리지를 선택한다.
  private let leverageControl = FuturesLeverageControl()
  private let leverageLabel = FuturesText.label()
  // 입력한 조건으로 신규 진입 또는 추가 진입을 요청한다.
  private lazy var orderButton = FuturesText.button("futures_open", filled: true) { [weak self] in self?.open() }
  // 현재 포지션의 종료 여부를 확인하는 창을 연다.
  private lazy var closeButton = FuturesText.button("futures_close") { [weak self] in self?.confirmClose() }

  init(reactor: FuturesAccountReactor, instrument: TradingInstrumentID) {
	self.reactor = reactor
	self.instrument = instrument
	self.expectedPositionID = reactor.position(for: instrument)?.id
	super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
	super.viewDidLoad()
	view.backgroundColor = .clear
	orderScrollView.keyboardDismissMode = .interactive
	orderScrollView.contentInsetAdjustmentBehavior = .never
	marketOrderLabel.text = FuturesText.text("futures_market_order")
	marketOrderLabel.textAlignment = .center
	marketOrderLabel.backgroundColor = .mobitColors(.tradeControlSurface)
	marketOrderLabel.layer.cornerRadius = 8
	marketOrderLabel.layer.borderWidth = 1
	marketOrderLabel.clipsToBounds = true
	marketOrderLabel.accessibilityIdentifier = "futuresMarketOrder"
	marketOrderLabel.snp.makeConstraints { $0.height.greaterThanOrEqualTo(36) }
	availableTitleLabel.text = FuturesText.text("futures_available")
	availableTitleLabel.textColor = .mobitColors(.tradeTextSecondary)
	availableTitleLabel.numberOfLines = 1
	availableAmountLabel.textColor = .mobitColors(.tradeTextPrimary)
	availableAmountLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
	  for: .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
	)
	availableAmountLabel.numberOfLines = 1
	availableAmountLabel.accessibilityIdentifier = "futuresAvailableAmount"
	availableAmountLabel.setContentHuggingPriority(.required, for: .horizontal)
	availableAmountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
	availableRow.spacing = 8
	let leverageRow = UIStackView(arrangedSubviews: [leverageLabel, leverageControl])
	leverageRow.axis = .vertical
	leverageRow.spacing = 6
	leverageRow.alignment = .fill
	let percentages = UIStackView()
	percentages.distribution = .fillEqually
	percentages.spacing = 4
	for percent in [25, 50, 75, 100] {
	  let button = UIButton(type: .system)
	  button.setTitle("\(percent)%", for: .normal)
	  button.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
	  button.backgroundColor = .mobitColors(.tradeControlSurface)
	  button.setTitleColor(.mobitColors(.tradeTextPrimary), for: .normal)
	  button.layer.cornerRadius = 8
	  // 종료 버튼과 같은 UIKit 배경 설정으로 테마별 테두리를 그린다.
	  var configuration = UIButton.Configuration.plain()
	  configuration.cornerStyle = .fixed
	  configuration.background.cornerRadius = 8
	  configuration.background.backgroundColor = .mobitColors(.tradeControlSurface)
	  configuration.background.strokeWidth = 1
	  configuration.background.strokeColor = .mobitColors(.tradeSeparator)
	  configuration.baseForegroundColor = .mobitColors(.tradeTextPrimary)
	  configuration.title = "\(percent)%"
	  configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4)
	  configuration.titleLineBreakMode = .byTruncatingTail
	  configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
		// 좁은 주문 패널에서도 비율 문구를 한 줄로 유지할 글꼴 설정이다.
		var attributes = incoming
		attributes.font = .systemFont(ofSize: 11, weight: .medium)
		return attributes
	  }
	  button.configuration = configuration
	  button.accessibilityIdentifier = "futuresOrderPercent\(percent)"
	  button.snp.makeConstraints { $0.height.greaterThanOrEqualTo(32) }
	  button.addAction(
		UIAction { [weak self] _ in
		  guard let self, marginTextField.isEnabled,
			let cash = reactor.currentState.snapshot?.accounts.first(where: { $0.id == self.reactor.account })?
			  .availableBalance
		  else { return }
		  guard let amount = try? FuturesDecimal.divide(FuturesDecimal.multiply(cash, Decimal(percent)), 100)
		  else { return }
		  let rounded = TradingNumberFormat.truncated(amount)
		  marginTextField.text = formattedMarginText(NSDecimalNumber(decimal: rounded).stringValue)
		  sendOrderClick("선물_증거금비율_선택", detail: "\(percent)%")
		  updateEstimate()
		},
		for: .touchUpInside
	  )
	  percentages.addArrangedSubview(button)
	}
	[sideSegmentedControl, marketOrderLabel, availableRow, leverageRow, marginTextField, percentages, estimate, orderButton, positionCard, dataStatusView]
	  .forEach { orderStack.addArrangedSubview($0) }
	orderStack.axis = .vertical
	orderStack.spacing = 12
	historyStack.axis = .vertical
	historyStack.spacing = 0
	historyStack.isHidden = true
	let stack = UIStackView(arrangedSubviews: [orderStack, historyStack])
	stack.axis = .vertical
	view.addSubview(orderScrollView)
	orderScrollView.addSubview(stack)
	orderScrollView.snp.makeConstraints {
	  $0.top.leading.trailing.equalToSuperview(); $0.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
	}
	stack.snp.makeConstraints {
	  $0.top.equalTo(orderScrollView.contentLayoutGuide).offset(contentTopInset)
	  $0.leading.trailing.equalTo(orderScrollView.contentLayoutGuide).inset(10)
	  $0.bottom.equalTo(orderScrollView.contentLayoutGuide).inset(contentBottomInset)
	  $0.width.equalTo(orderScrollView.frameLayoutGuide).offset(-20)
	}
	[leverageLabel, estimate].forEach {
	  $0.font = .preferredFont(forTextStyle: .caption1)
	  $0.textColor = .mobitColors(.tradeTextSecondary)
	}
	for button in [orderButton, closeButton] {
	  button.configuration?.cornerStyle = .fixed
	  button.configuration?.background.cornerRadius = 8
	  button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
		var attributes = incoming
		attributes.font = .preferredFont(forTextStyle: .subheadline)
		return attributes
	  }
	}
	closeButton.configuration?.background.backgroundColor = .mobitColors(.tradeControlSurface)
	closeButton.configuration?.baseForegroundColor = .mobitColors(.tradeTextPrimary)
	closeButton.configuration?.background.strokeWidth = 1
	closeButton.configuration?.background.strokeColor = .mobitColors(.tradeSeparator)
	orderButton.accessibilityIdentifier = "futuresSubmit"
	closeButton.accessibilityIdentifier = "futuresClose"
	marginTextField.accessibilityIdentifier = "futuresMargin"
	sideSegmentedControl.selectedSegmentIndex = reactor.position(for: instrument)?.order.side == .short ? 1 : 0
	sideSegmentedControl.accessibilityLabel = FuturesText.text("futures_direction")
	leverageControl.maximumValue = Double(instrument.maximumPaperLeverage ?? 1)
	leverageControl.value = min(10, leverageControl.maximumValue)
	leverageControl.accessibilityLabel = FuturesText.text("futures_leverage")
	marginTextField.borderStyle = .roundedRect
	marginTextField.textColor = .mobitColors(.textPrimary)
	marginTextField.backgroundColor = .mobitColors(.tradeControlSurface)
	marginTextField.keyboardType = .numberPad
	marginTextField.placeholder = FuturesText.text("futures_margin_placeholder")
	marginTextField.attributedPlaceholder = NSAttributedString(
	  string: FuturesText.text("futures_margin_placeholder"),
	  attributes: [.foregroundColor: UIColor.secondaryLabel]
	)
	marginTextField.accessibilityLabel = FuturesText.text("futures_margin_placeholder")
	marginTextField.font = .preferredFont(forTextStyle: .body)
	marginTextField.adjustsFontForContentSizeCategory = true
	marginTextField.snp.makeConstraints { $0.height.greaterThanOrEqualTo(48) }
	let toolbar = UIToolbar()
	toolbar.items = [
	  UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
	  UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(endEditing))
	]
	toolbar.sizeToFit()
	marginTextField.inputAccessoryView = toolbar
	updateOrderAppearance()
	sideSegmentedControl.rx.selectedSegmentIndex.changed.subscribe(onNext: { [weak self] _ in
      guard let self else { return }
      sendOrderClick("선물_방향_선택", detail: sideSegmentedControl.selectedSegmentIndex == 0 ? "롱" : "숏")
      render()
    }).disposed(by: disposeBag)
	leverageControl.rx.controlEvent(.valueChanged).subscribe(onNext: { [weak self] _ in self?.render() }).disposed(by: disposeBag)
    leverageControl.rx.controlEvent(.editingDidEnd).subscribe(onNext: { [weak self] in
      guard let self else { return }
      sendOrderClick("선물_레버리지_확정", detail: "\(Int(leverageControl.value))배")
    }).disposed(by: disposeBag)
	marginTextField.rx.text.orEmpty.subscribe(onNext: { [weak self] _ in
	  self?.formatMarginInput()
	  self?.updateEstimate()
	}).disposed(by: disposeBag)
    Observable.merge(
      orderPriceUpdates,
      Observable<Int>.interval(.seconds(1), scheduler: MainScheduler.instance)
        .filter { [weak self] _ in self?.viewIfLoaded?.window != nil }.map { _ in () }
    )
      .observe(on: MainScheduler.instance)
      .subscribe(onNext: { [weak self] _ in self?.updateOrderAvailability() }).disposed(by: disposeBag)
	reactor.state.observe(on: MainScheduler.instance).subscribe(onNext: { [weak self] state in
      guard let self else { return }
      render()
      if didSubmitOpening, !state.submitting, let message = state.message {
        didSubmitOpening = false
        if message == FuturesText.text("futures_order_done") { tradeCompletedCallBack?() }
        else { showOrderError(message) }
      }
    }).disposed(
	  by: disposeBag
	)
	let historyChanges: Observable<(snapshot: FuturesAccountSnapshot?, status: String)> = reactor.state.map {
	  [weak reactor] state in
	  let status = reactor.map { FuturesText.status($0) } ?? ""
	  return (state.snapshot, status)
	}
	historyChanges.distinctUntilChanged { previous, current in
	  previous.snapshot == current.snapshot && previous.status == current.status
	}.observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] _ in
		guard let self, !historyStack.isHidden else { return }
		renderHistory()
	  }).disposed(by: disposeBag)
  }

  override func viewWillAppear(_ animated: Bool) {
	super.viewWillAppear(animated)
	reactor.action.onNext(.clearMessage)
	reactor.action.onNext(.reload)
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard isViewLoaded else { return }
	updateOrderAppearance()
  }

  private func updateOrderAppearance() {
	marketOrderLabel.layer.borderColor = UIColor.mobitColors(.tradeSeparator).resolvedColor(with: traitCollection).cgColor
	availableRow.axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
	availableRow.alignment = availableRow.axis == .vertical ? .fill : .firstBaseline
	availableAmountLabel.textAlignment = availableRow.axis == .vertical ? .left : .right
	availableTitleLabel.numberOfLines = availableRow.axis == .vertical ? 0 : 1
	availableAmountLabel.numberOfLines = availableRow.axis == .vertical ? 0 : 1
  }

  func selectTab(_ index: Int) {
	loadViewIfNeeded()
    // 화면 구성 때 기본 선택을 적용하는 호출은 사용자 탭 전환으로 집계하지 않는다.
    let previousIndex = historyStack.isHidden ? sideSegmentedControl.selectedSegmentIndex : 2
	sideSegmentedControl.isHidden = true
	view.endEditing(true)
	orderStack.isHidden = index == 2
	historyStack.isHidden = index != 2
	if index < 2 { sideSegmentedControl.selectedSegmentIndex = index }
    if viewIfLoaded?.window != nil, previousIndex != index {
      if index == 2 {
        MobitAnalyticsUtil.sendScreenEvent(
          location: "트레이딩_화면",
          stepDepth01: "선물_모의투자",
          stepDepth02: "선물_거래내역_조회",
          account: reactor.account,
          instrument: instrument
        )
      } else {
        sendOrderClick("선물_방향_선택", detail: index == 0 ? "롱" : "숏")
      }
    }
	if index == 2 { renderHistory() }
	render()
  }

  private func renderHistory() {
	historyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
	do {
	  guard let snapshot = reactor.currentState.snapshot else {
		let label = FuturesText.label(style: .footnote)
		label.text = FuturesText.status(reactor)
		historyStack.addArrangedSubview(label)
		return
	  }
	  let records = try snapshot.transactionHistory(for: reactor.account).filter { $0.instrument == instrument }
		.reversed()
	  if records.isEmpty {
		// 현물처럼 빈 안내가 내역 영역 전체를 사용하고, 큰 글자에서는 콘텐츠만큼 늘어난다.
		let emptyView = UIView()
		// 빈 내역 문구의 여러 줄 텍스트도 가로 중앙에 정렬한다.
		let label = FuturesText.label(style: .footnote)
		label.text = FuturesText.text("futures_empty_history")
		label.textAlignment = .center
		emptyView.addSubview(label)
		historyStack.addArrangedSubview(emptyView)
		emptyView.snp.makeConstraints {
		  $0.height.equalTo(orderScrollView.frameLayoutGuide.snp.height)
			.offset(-contentTopInset - contentBottomInset).priority(.low)
		}
		label.snp.makeConstraints {
		  $0.center.equalToSuperview()
		  $0.leading.trailing.equalToSuperview()
		  $0.top.greaterThanOrEqualToSuperview()
		  $0.bottom.lessThanOrEqualToSuperview()
		}
	  }
	  for record in records {
		historyStack.addArrangedSubview(try FuturesHistoryEntryView(record: record))
		let divider = UIView()
		divider.backgroundColor = .mobitColors(.tradeSeparator)
		divider.snp.makeConstraints { $0.height.equalTo(1) }
		historyStack.addArrangedSubview(divider)
	  }
	} catch {
	  let label = FuturesText.label(style: .footnote)
	  label.text = FuturesText.text("futures_storage_error")
	  // 일부 내역 뒤에 나오는 오류 안내도 구분선과 간격을 유지한다.
	  if let lastHistoryView = historyStack.arrangedSubviews.last {
		historyStack.setCustomSpacing(TradeHistoryCellLayout.verticalPadding, after: lastHistoryView)
	  }
	  historyStack.addArrangedSubview(label)
	}
  }

  @objc private func endEditing() { view.endEditing(true) }

  private func render() {
	let position = reactor.position(for: instrument)
	let selectedSide: FuturesSide = sideSegmentedControl.selectedSegmentIndex == 0 ? .long : .short
	let cash = reactor.currentState.snapshot?.accounts.first { $0.id == reactor.account }?.availableBalance
	availableAmountLabel.text = "\(FuturesText.number(cash)) \(FuturesText.text("currency_krw_unit"))"
	if expectedPositionID == nil { expectedPositionID = position?.id }
	let closed = expectedPositionID != nil && position?.id != expectedPositionID
	if let position {
	  positionCard.configure(position, quotes: reactor.valuationQuotes)
	  leverageControl.value = Double(position.order.leverage)
	}
	positionCard.isHidden = position == nil

	sideSegmentedControl.isEnabled = !reactor.currentState.submitting
	leverageControl.isEnabled = position == nil && !closed && !reactor.currentState.submitting
	marginTextField.isEnabled = !reactor.currentState.submitting && !closed
	leverageLabel.text =
	  "\(FuturesText.text("futures_leverage")) \(Int(leverageControl.value))× / \(instrument.maximumPaperLeverage ?? 1)×"
	leverageControl.tintColor = selectedSide == .long ? MarketColorPalette.riseColor : MarketColorPalette.fallColor
	orderButton.configuration?.title = FuturesText.text(selectedSide == .long ? "futures_enter_long" : "futures_enter_short")
	orderButton.configuration?.baseBackgroundColor =
	  selectedSide == .long ? MarketColorPalette.riseColor : MarketColorPalette.fallColor
	orderButton.configuration?.baseForegroundColor = .white
    closeButton.isHidden = position == nil
    updateOrderAvailability()
	dataStatusView.render(reactor)
	updateEstimate()
  }

  private func updateOrderAvailability() {
    // 준비 상태나 입력값은 탭할 때 안내하고 실제 제출 중에만 중복 요청을 막는다.
    let enabled = !reactor.currentState.submitting
    if orderButton.isEnabled != enabled { orderButton.isEnabled = enabled }
    if closeButton.isEnabled != enabled { closeButton.isEnabled = enabled }
  }

  private var marginAmount: Decimal? {
    let text = (marginTextField.text ?? "").replacingOccurrences(of: ",", with: "")
    guard text.range(of: #"^[0-9]+(?:\.[0-9]*)?$"#, options: .regularExpression) != nil else { return nil }
    guard let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !amount.isNaN else { return nil }
    return TradingNumberFormat.truncated(amount)
  }

  private func formattedMarginText(_ text: String) -> String {
    let raw = text.replacingOccurrences(of: ",", with: "")
    guard raw.range(of: #"^[0-9]+(?:\.[0-9]*)?$"#, options: .regularExpression) != nil else { return text }
    guard let amount = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")), !amount.isNaN else { return text }
    let normalized = amount >= TradingNumberFormat.integerThreshold
      ? NSDecimalNumber(decimal: TradingNumberFormat.truncated(amount)).stringValue : raw
    var parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
    if parts.count == 2 { parts[1] = parts[1].prefix(TradingNumberFormat.maximumFractionDigits) }
    guard let integer = parts.first else { return text }
    let grouped = integer.reversed().enumerated().map { index, digit in
      (index > 0 && index % 3 == 0 ? "," : "") + String(digit)
    }.joined().reversed()
    return String(grouped) + (parts.count == 2 ? "." + String(parts[1]) : "")
  }

  private func formatMarginInput() {
    guard marginTextField.markedTextRange == nil else { return }
    let text = marginTextField.text ?? ""
    let formatted = formattedMarginText(text)
    guard text != formatted else { return }
    let selection = marginTextField.selectedTextRange
    let offset = selection.map { marginTextField.offset(from: marginTextField.beginningOfDocument, to: $0.start) } ?? text.utf16.count
    let precedingCount = (text as NSString).substring(to: min(offset, text.utf16.count))
      .filter { $0 != "," }.count
    marginTextField.text = formatted
    // 콤마가 추가돼도 입력 중인 숫자 위치를 유지한다.
    var remaining = precedingCount
    var newOffset = 0
    for character in formatted {
      guard remaining > 0 else { break }
      newOffset += 1
      if character != "," { remaining -= 1 }
    }
    if let position = marginTextField.position(from: marginTextField.beginningOfDocument, offset: newOffset) {
      marginTextField.selectedTextRange = marginTextField.textRange(from: position, to: position)
    }
  }

  private func updateEstimate() {
	guard let amount = marginAmount,
	  // 입력 증거금과 선택한 레버리지로 계산한 예상 거래금액이다.
	  !amount.isNaN, amount > 0, let tradeAmount = try? FuturesDecimal.multiply(amount, Decimal(Int(leverageControl.value)))
	else {
	  estimate.text = FuturesText.text("futures_margin_hint")
	  return
	}
	estimate.text =
	  "\(FuturesText.text("futures_notional")) \(FuturesText.number(tradeAmount)) \(FuturesText.text("currency_krw_unit"))\n\(FuturesText.text("futures_execution_note"))"
  }

  private func open() {
    guard !didSubmitOpening, !reactor.currentState.submitting, presentedViewController == nil else { return }
    guard let amount = marginAmount, !amount.isNaN, amount > 0 else {
      sendOrderBlocked("증거금_입력오류")
      showOrderError(FuturesText.text("futures_input_error"))
      return
    }
    // 현재 화면이 추적하던 포지션이 사라져도 새 포지션을 실수로 열지 않는다.
    let current = reactor.position(for: instrument)
    guard expectedPositionID == nil || current?.id == expectedPositionID else {
      sendOrderBlocked("포지션_종료됨")
      showOrderError(FuturesText.text("futures_position_closed"))
      return
    }
    // 기존 포지션과 반대 방향으로 추가 진입할 수 없는 이유도 탭 시 안내한다.
    let selectedSide: FuturesSide = sideSegmentedControl.selectedSegmentIndex == 0 ? .long : .short
    guard current == nil || current?.order.side == selectedSide else {
      sendOrderBlocked("진입조건_불일치")
      showOrderError(FuturesText.text("futures_same_conditions"))
      return
    }
    if let cash = reactor.currentState.snapshot?.accounts.first(where: { $0.id == reactor.account })?.availableBalance,
      amount > cash {
      sendOrderBlocked("잔액_부족")
      showOrderError(FuturesText.text("futures_margin_exceeds_balance"))
      return
    }
    // 탭 순간의 표시 가격을 한 번만 캡처해 검사와 주문에 같이 사용한다.
    let price = captureOrderPrice?()
    if let message = FuturesText.orderError(reactor, instrument: instrument, price: price) {
      sendOrderBlocked(orderBlockReason)
      showOrderError(message)
      return
    }
    view.endEditing(true)
    reactor.action.onNext(.clearMessage)
    didSubmitOpening = true
    reactor.action.onNext(
      .open(
        instrument,
        selectedSide,
        amount,
        current?.order.leverage ?? Int(leverageControl.value),
        expectedPositionID ?? current?.id,
        price
      )
    )
  }

  private func showOrderError(_ message: String) {
    guard presentedViewController == nil, viewIfLoaded?.window != nil else { return }
    view.endEditing(true)
    // 주문 오류는 알럿으로만 안내해 폼 아래에 같은 문구를 남기지 않는다.
    let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: FuturesText.text("common_confirm"), style: .default))
    present(alert, animated: true)
  }

  private func confirmClose() {
    guard !reactor.currentState.submitting, presentedViewController == nil else { return }
    guard let position = reactor.position(for: instrument) else {
      showOrderError(FuturesText.text("futures_position_closed"))
      return
    }
    // 부분 종료 입력과 실시간 시세를 함께 보여줄 바텀 시트다.
    let controller = FuturesCloseViewController(
      reactor: reactor,
      positionID: position.id,
      captureOrderPrice: { [weak self] in self?.captureOrderPrice?() },
      orderPriceUpdates: orderPriceUpdates
    )
    controller.tradeCompletedCallBack = { [weak self] in
      guard let self else { return }
      // 직접 종료한 뒤에는 남은 포지션으로 폼을 갱신해 같은 화면에서 다시 진입할 수 있게 한다.
      expectedPositionID = reactor.position(for: instrument)?.id
      render()
      tradeCompletedCallBack?()
    }
    controller.modalPresentationStyle = .pageSheet
    controller.sheetPresentationController?.detents = [.medium(), .large()]
    controller.sheetPresentationController?.selectedDetentIdentifier = .large
    controller.sheetPresentationController?.prefersGrabberVisible = true
    present(controller, animated: true) { [account = reactor.account, instrument] in
      MobitAnalyticsUtil.sendScreenEvent(
        location: "트레이딩_화면",
        stepDepth01: "선물_모의투자",
        stepDepth02: "선물_종료시트_열기",
        account: account,
        instrument: instrument
      )
    }
  }

  private var orderBlockReason: String {
    if reactor.currentState.networkAvailable == false { return "네트워크_연결끊김" }
    if reactor.currentState.loadFailed || reactor.currentState.dataFailure?.hold == .storageFailed { return "저장_조회실패" }
    if reactor.needsDataRetry { return "과거검증_실패" }
    if !reactor.canSubmit { return "과거검증_미완료" }
    return "시세_준비안됨"
  }

  private func sendOrderBlocked(_ reason: String) {
    sendOrderClick("선물_주문_차단", detail: reason)
  }

  private func sendOrderClick(_ action: String, detail: String? = nil) {
    // 일반 입력 선택값과 실제 주문 차단 사유를 구분해 전송한다.
    var parameters: [String: Any] = [
      "order_type": expectedPositionID != nil || reactor.position(for: instrument) != nil ? "추가_진입" : "신규_진입",
      "position_side": sideSegmentedControl.selectedSegmentIndex == 0 ? "롱" : "숏"
    ]
    if let detail, action.hasSuffix("_차단") || action.hasSuffix("_실패") { parameters["failure_reason"] = detail }
    MobitAnalyticsUtil.sendClickEvent(
      location: "트레이딩_화면",
      stepDepth01: "선물_모의투자",
      stepDepth02: action,
      stepDepth03: detail,
      account: reactor.account,
      instrument: instrument,
      extraParameters: parameters
    )
  }

}

private final class FuturesHistoryEntryView: UIView {
  // 체결 방향과 시각은 일반 크기에서 같은 줄에 표시한다.
  private let headerStack = UIStackView()
  // 접근성 글자 크기에서는 각 항목을 세로로 전환한다.
  private var detailRows: [UIStackView] = []

  init(record: FuturesTransactionRecord) throws {
    super.init(frame: .zero)
    accessibilityIdentifier = "futuresHistoryEntry.\(record.id)"
    // 추가 진입도 최초 진입과 같은 문구로 묶고 원본 체결 종류는 보존한다.
    let isOpening = record.kind == .opening || record.kind == .addition
    // 체결 방향 대신 포지션의 진입·종료·강제 청산을 제목으로 구분한다.
    let titleKey: String
    switch record.kind {
    case .opening, .addition: titleKey = "futures_history_open"
    case .closing: titleKey = "futures_history_close"
    case .liquidation: titleKey = "futures_history_liquidation"
    }
    // 롱·숏 방향과 거래 유형을 함께 표시한다.
    let orderType = FuturesText.label(style: .subheadline)
    orderType.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 14, weight: .bold))
    orderType.textColor = .mobitColors(.tradeTextPrimary)
    // 거래 유형은 테마에 맞는 기본 글자색으로 표시한다.
    let title = NSMutableAttributedString(
      string: String(format: FuturesText.text(titleKey), FuturesText.side(record.side)),
      attributes: [.foregroundColor: UIColor.mobitColors(.tradeTextPrimary)]
    )
    // 번역에 따라 방향 단어의 위치가 달라도 롱·숏에만 강조색을 적용한다.
    let directionRange = (title.string as NSString).range(of: FuturesText.side(record.side))
    if directionRange.location != NSNotFound {
      title.addAttribute(
        .foregroundColor,
        value: record.side == .long ? MarketColorPalette.riseColor : MarketColorPalette.fallColor,
        range: directionRange
      )
    }
    orderType.attributedText = title
    orderType.accessibilityIdentifier = "futuresHistory.orderType"
    orderType.setContentHuggingPriority(.required, for: .horizontal)
    orderType.setContentCompressionResistancePriority(.required, for: .horizontal)
    // 정산 저장 시각 대신 기존 체결·청산 발생 시각을 유지한다.
    let date = FuturesText.label(style: .caption2)
    date.text = FuturesText.occurrenceDate(record)
    date.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .monospacedDigitSystemFont(ofSize: 11, weight: .regular))
    date.textColor = .mobitColors(.tradeTextSecondary)
    date.textAlignment = .right
    date.accessibilityIdentifier = "futuresHistory.date"
    date.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    headerStack.addArrangedSubview(orderType)
    headerStack.addArrangedSubview(date)
    // 가격과 금액은 기록된 결제 통화를 함께 표시한다.
    let currency = record.instrument.settlementCurrency.rawValue
    addField(
      "futures_positions",
      value: "\(FuturesText.side(record.side)) · \(record.leverage)×",
      identifier: "position",
      emphasized: true
    )
    addField("futures_history_price", value: "\(FuturesText.number(record.price)) \(currency)", identifier: "price")
    addField(
      "futures_history_quantity",
      value: "\(FuturesText.number(record.quantity)) \(FuturesText.symbol(record.instrument).marketSymbol)",
      identifier: "quantity"
    )
    if isOpening {
      // 수량 내림이 반영된 실제 체결금액을 원본 Decimal로 계산한다.
      let tradeAmount = try FuturesDecimal.multiply(record.price, record.quantity)
      addField(
        "futures_history_amount",
        value: "\(FuturesText.number(tradeAmount)) \(currency)",
        identifier: "amount",
        emphasized: true
      )
    } else {
      // 종료 내역에는 정산된 실현손익을 부호와 함께 표시한다.
      let pnl = record.realizedPnL
      // 손익의 부호는 롱·숏 방향과 별도로 강조한다.
      let amountLabel = addField(
        "futures_realized",
        value: (pnl.map { $0 > 0 ? "+" : "" } ?? "") + "\(FuturesText.number(pnl)) \(currency)",
        identifier: "amount",
        emphasized: true
      )
      if let pnl {
        amountLabel.textColor = pnl == 0
          ? .mobitColors(.tradeTextPrimary)
          : (pnl > 0 ? MarketColorPalette.riseColor : MarketColorPalette.fallColor)
      }
    }
    if let end = record.intervalEndExclusive, record.kind != .liquidation {
      addField(
        "futures_occurrence",
        value: "~ \(FuturesText.date(Date(timeIntervalSince1970: Double(end) / 1000)))",
        identifier: "interval"
      )
      addField("futures_settled", value: FuturesText.date(record.recordedAt), identifier: "settled")
    }
    // 항목명과 오른쪽 값을 일정한 간격으로 묶는다.
    let detailsStack = UIStackView(arrangedSubviews: detailRows)
    detailsStack.axis = .vertical
    detailsStack.spacing = TradeHistoryCellLayout.rowSpacing
    // 헤더와 본문 사이에만 여유를 주고 셀 높이는 콘텐츠로 결정한다.
    let content = UIStackView(arrangedSubviews: [headerStack, detailsStack])
    content.axis = .vertical
    content.spacing = TradeHistoryCellLayout.headerSpacing
    addSubview(content)
    content.snp.makeConstraints {
      $0.horizontalEdges.equalToSuperview()
      $0.verticalEdges.equalToSuperview().inset(TradeHistoryCellLayout.verticalPadding)
    }
    isAccessibilityElement = true
    accessibilityLabel = ([orderType.text, date.text].compactMap { $0 } + detailRows.flatMap { row in
      row.arrangedSubviews.compactMap { ($0 as? UILabel)?.text }
    }).joined(separator: ", ")
    updateTextLayout()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    updateTextLayout()
  }

  @discardableResult
  private func addField(
    _ key: String,
    value: String,
    identifier: String,
    emphasized: Bool = false
  ) -> UILabel {
    // 설명은 보조 색상으로 표시해 실제 체결값을 먼저 읽게 한다.
    let title = FuturesText.label(style: .subheadline)
    title.text = FuturesText.text(key)
    title.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 14, weight: .regular))
    title.textColor = .mobitColors(.tradeTextSecondary)
    title.accessibilityIdentifier = "futuresHistory.\(identifier)Title"
    title.setContentHuggingPriority(.required, for: .horizontal)
    title.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    // 값은 오른쪽에 정렬하고 긴 숫자는 생략 없이 줄바꿈한다.
    let valueLabel = FuturesText.label(style: .footnote)
    valueLabel.text = value
    valueLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
      for: .monospacedDigitSystemFont(ofSize: 13, weight: emphasized ? .semibold : .regular)
    )
    valueLabel.textColor = .mobitColors(.tradeTextPrimary)
    valueLabel.textAlignment = .right
    valueLabel.accessibilityIdentifier = "futuresHistory.\(identifier)"
    valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    // 좁은 주문 패널에서도 항목명이 값의 영역을 넘지 않도록 배치한다.
    let row = UIStackView(arrangedSubviews: [title, valueLabel])
    detailRows.append(row)
    return valueLabel
  }

  private func updateTextLayout() {
    // 큰 글자에서는 한 항목씩 세로로 읽으며 모든 값을 유지한다.
    let vertical = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    for row in [headerStack] + detailRows {
      row.axis = vertical ? .vertical : .horizontal
      row.alignment = vertical ? .fill : .firstBaseline
      row.spacing = vertical ? 4 : 8
    }
  }
}

private final class FuturesPositionSummaryView: UIView {
  private let direction = FuturesText.label(style: .caption1)
  // 롱·숏 문구에 같은 여백과 배경색을 적용하는 배지다.
  private lazy var directionView = UIStackView(arrangedSubviews: [direction])
  private let symbol = FuturesText.label(style: .headline)
  private let leverage = FuturesText.label(style: .caption1)
  private let opened = FuturesText.label(style: .caption2)
  private let errorLabel = FuturesText.label(style: .footnote)
  private let metrics = UIStackView()
  private let profits = UIStackView()
  private var values: [String: UILabel] = [:]
  private var metricViews: [UIView] = []
  private var columnCount = 0

  init(closeButton: UIButton) {
	super.init(frame: .zero)
	accessibilityIdentifier = "futuresPositionCard"
	backgroundColor = .mobitColors(.tradeSurface)
	layer.cornerRadius = 12
	layer.borderWidth = 1
	layer.borderColor = UIColor.mobitColors(.tradeSeparator).cgColor
	directionView.layer.cornerRadius = 4
	directionView.clipsToBounds = true
	directionView.isLayoutMarginsRelativeArrangement = true
	directionView.layoutMargins = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
	directionView.setContentHuggingPriority(.required, for: .horizontal)
	direction.textColor = .white
	direction.textAlignment = .center
	direction.setContentHuggingPriority(.required, for: .horizontal)
	leverage.textColor = .mobitColors(.tradeTextSecondary)
	leverage.setContentHuggingPriority(.required, for: .horizontal)
	symbol.textColor = .mobitColors(.tradeTextPrimary)
	symbol.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
	let header = UIStackView(arrangedSubviews: [directionView, symbol, leverage])
	header.spacing = 6
	header.alignment = .center
	let title = FuturesText.label(style: .subheadline)
	title.text = FuturesText.text("futures_held_position")
	title.textColor = .mobitColors(.tradeTextPrimary)
	let divider = UIView()
	divider.backgroundColor = .mobitColors(.tradeSeparator)
	divider.snp.makeConstraints { $0.height.equalTo(1) }
	profits.addArrangedSubview(field("futures_pnl", unit: FuturesText.text("currency_krw_unit"), prominent: true))
	profits.addArrangedSubview(field("futures_roe", prominent: true))
	values["futures_roe"]?.textAlignment = .right
	(profits.arrangedSubviews.last as? UIStackView)?.arrangedSubviews.compactMap { $0 as? UILabel }
	  .forEach { $0.textAlignment = .right }
	profits.spacing = 10
	profits.distribution = .fillEqually
	metricViews = [
	  field("futures_position_size", unit: FuturesText.text("currency_krw_unit")),
	  field("futures_margin", unit: FuturesText.text("currency_krw_unit")),
	  field("futures_quantity"),
	  field("futures_entry", unit: FuturesText.text("currency_krw_unit")),
	  field("futures_current", unit: FuturesText.text("currency_krw_unit")),
	  field("futures_liquidation_price", unit: FuturesText.text("currency_krw_unit"))
	]
	metrics.axis = .vertical
	metrics.spacing = 14
	opened.textColor = .mobitColors(.tradeTextSecondary)
	errorLabel.textColor = .mobitColors(.tradeTextSecondary)
	errorLabel.isHidden = true
	let content = UIStackView(arrangedSubviews: [title, divider, header, profits, metrics, opened, errorLabel, closeButton])
	content.axis = .vertical
	content.spacing = 14
	addSubview(content)
	content.snp.makeConstraints { $0.edges.equalToSuperview().inset(12) }
	updateMetrics(columns: 2)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
	super.layoutSubviews()
	// 기존 주문 패널은 호가창 옆에 있어 좁은 폭에서는 지표를 두 열로 배치한다.
	let columns = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 1 : (bounds.width >= 360 ? 3 : 2)
	updateMetrics(columns: columns)
  }

  private func updateMetrics(columns: Int) {
	guard columnCount != columns else { return }
	columnCount = columns
	values.values.forEach { $0.numberOfLines = columns == 1 ? 0 : 1 }
	profits.axis = columns == 1 ? .vertical : .horizontal
	profits.distribution = columns == 1 ? .fill : .fillEqually
	metricViews.forEach { $0.removeFromSuperview() }
	metrics.arrangedSubviews.forEach { $0.removeFromSuperview() }
	for start in stride(from: 0, to: metricViews.count, by: columns) {
	  let row = UIStackView(arrangedSubviews: Array(metricViews[start..<min(start + columns, metricViews.count)]))
	  row.distribution = .fillEqually
	  row.alignment = .top
	  row.spacing = 10
	  metrics.addArrangedSubview(row)
	}
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	layer.borderColor = UIColor.mobitColors(.tradeSeparator).resolvedColor(with: traitCollection).cgColor
	setNeedsLayout()
  }

  func configure(_ position: FuturesPosition, quotes: [TradingInstrumentID: FuturesMarkQuote]) {
	defer { values.values.forEach { $0.superview?.accessibilityValue = $0.text } }
	symbol.text = FuturesText.symbol(position.order.instrument)
	direction.text = FuturesText.side(position.order.side)
	directionView.backgroundColor = position.order.side == .long ? MarketColorPalette.riseColor : MarketColorPalette.fallColor
	leverage.text = "\(position.order.leverage)×"
	opened.text = "\(FuturesText.text("futures_opened"))\n\(FuturesText.date(position.order.executedAt))"
	values.values.forEach {
	  $0.text = "—"
	  $0.textColor = .mobitColors(.tradeTextPrimary)
	}
	do {
	  let valuation = try FuturesText.valuation(position, quotes: quotes)
	  let pnl = try valuation?.displayedPnL
	  let roe = valuation?.displayedROEPercent
	  let price = valuation == nil ? nil : quotes[position.order.instrument]?.price
	  let size = try price.map { try FuturesDecimal.multiply($0, position.quantity) }
	  values["futures_pnl"]?.text = signed(pnl)
	  values["futures_roe"]?.text = roe.map { signed($0, digits: 2) + "%" } ?? "—"
	  for key in ["futures_pnl", "futures_roe"] {
		if let pnl {
		  values[key]?.textColor = MarketColorPalette.color(forSignedValue: NSDecimalNumber(decimal: pnl).doubleValue)
		}
	  }
	  values["futures_position_size"]?.text = FuturesText.number(size)
	  values["futures_margin"]?.text = FuturesText.number(try position.margin)
	  values["futures_quantity"]?.text = FuturesText.number(position.quantity)
	  values["futures_entry"]?.text = FuturesText.number(try position.averageEntryPrice)
	  values["futures_current"]?.text = FuturesText.number(price)
	  values["futures_liquidation_price"]?.text = FuturesText.number(try FuturesCalculator.estimatedLiquidationPrice(position))
	  errorLabel.isHidden = true
	} catch {
	  values.values.forEach { $0.text = "—" }
	  errorLabel.text = FuturesText.text("futures_storage_error")
	  errorLabel.isHidden = false
	}
  }

  private func signed(_ value: Decimal?, digits: Int? = nil) -> String {
	guard let value else { return "—" }
	return (value > 0 ? "+" : "") + FuturesText.number(value, digits: digits)
  }

  private func field(_ key: String, unit: String? = nil, prominent: Bool = false) -> UIView {
	let title = FuturesText.label(style: .caption1)
	title.text = FuturesText.text(key) + (unit.map { " (\($0))" } ?? "")
	title.textColor = .mobitColors(.tradeTextSecondary)
	let value = FuturesText.label(style: prominent ? .title3 : .subheadline)
	if prominent, let descriptor = value.font.fontDescriptor.withSymbolicTraits(.traitBold) {
	  value.font = UIFont(descriptor: descriptor, size: 0)
	}
	value.adjustsFontSizeToFitWidth = true
	value.minimumScaleFactor = prominent ? 0.5 : 0.6
	value.numberOfLines = 1
	value.accessibilityIdentifier = key
	value.textColor = .mobitColors(.tradeTextPrimary)
	let field = UIStackView(arrangedSubviews: [title, value])
	field.axis = .vertical
	field.spacing = 4
	field.isAccessibilityElement = true
	field.accessibilityLabel = title.text
	values[key] = value
	return field
  }
}

final class FuturesLeverageControl: UIControl {
  private let slider = UISlider()
  private let feedback = UISelectionFeedbackGenerator()
  private let ticks = (0...5).map { _ in UIView() }
  private let track = UIView()
  private let selectedTrack = UIView()
  // 종료 비율은 0%, 기존 레버리지는 1배부터 선택한다.
  var minimumValue: Double = 1 {
    didSet { value = max(minimumValue, value) }
  }
  // 접근성에 표시할 값의 단위로, 레버리지는 배수·종료 비율은 %를 사용한다.
  var valueSuffix = "×" {
    didSet { accessibilityValue = "\(Int(value))" + valueSuffix }
  }
  var maximumValue: Double = 100 {
	didSet {
	  maximumValue = max(1, maximumValue.rounded())
	  value = min(value, maximumValue)
	}
  }
  var value: Double = 1 {
	didSet {
	  value = min(maximumValue, max(minimumValue, value.rounded()))
	  slider.value = value == minimumValue ? 0 : Float(value / maximumValue)
	  accessibilityValue = "\(Int(value))" + valueSuffix
	  updateAppearance()
	}
  }
  override var isEnabled: Bool {
	didSet {
	  slider.isEnabled = isEnabled
	  alpha = isEnabled ? 1 : 0.45
	  accessibilityTraits = isEnabled ? [.adjustable] : [.adjustable, .notEnabled]
	}
  }
  override var intrinsicContentSize: CGSize {
	CGSize(width: UIView.noIntrinsicMetric, height: 44)
  }

  override init(frame: CGRect) {
	super.init(frame: frame)
	isAccessibilityElement = true
	accessibilityTraits = .adjustable
	accessibilityIdentifier = "futuresLeverage"
	slider.isAccessibilityElement = false
	slider.minimumValue = 0
	slider.maximumValue = 1
	[track, selectedTrack].forEach {
	  $0.isUserInteractionEnabled = false
	  $0.layer.cornerRadius = 1.5
	  addSubview($0)
	}
	ticks.forEach {
	  $0.isUserInteractionEnabled = false
	  $0.layer.cornerRadius = 6
	  addSubview($0)
	}
	addSubview(slider)
	slider.addTarget(self, action: #selector(prepareFeedback), for: .touchDown)
	slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
    slider.addTarget(self, action: #selector(finishSelection), for: [.touchUpInside, .touchUpOutside])
	updateThumb()
	updateAppearance()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
	super.layoutSubviews()
	slider.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 44)
	let track = slider.trackRect(forBounds: slider.bounds)
	let start = slider.thumbRect(forBounds: slider.bounds, trackRect: track, value: 0).midX
	let end = slider.thumbRect(forBounds: slider.bounds, trackRect: track, value: 1).midX
	self.track.frame = CGRect(x: start, y: track.midY - 1.5, width: end - start, height: 3)
	selectedTrack.frame = CGRect(
	  x: start,
	  y: track.midY - 1.5,
	  width: (end - start) * CGFloat(slider.value),
	  height: 3
	)
	for index in ticks.indices {
	  let center = start + (end - start) * CGFloat(index) / 5
	  ticks[index].frame = CGRect(x: center - 6, y: track.midY - 6, width: 12, height: 12)
	}
  }

  override func tintColorDidChange() {
	super.tintColorDidChange()
	updateThumb()
	updateAppearance()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	updateThumb()
	setNeedsLayout()
  }

  override func accessibilityIncrement() {
    guard isEnabled, value < maximumValue else { return }
    select(value + 1)
    sendActions(for: .editingDidEnd)
  }
  override func accessibilityDecrement() {
    guard isEnabled, value > minimumValue else { return }
    select(value - 1)
    sendActions(for: .editingDidEnd)
  }

  @objc private func finishSelection() { sendActions(for: .editingDidEnd) }

  @objc private func prepareFeedback() { feedback.prepare() }

  @objc private func sliderChanged() {
	// 기존 레버리지는 1배, 종료 비율은 0%까지 같은 눈금과 진동으로 조절한다.
	select(Double(slider.value) * maximumValue)
  }

  private func select(_ proposedValue: Double) {
	guard isEnabled else { return }
	let next = min(maximumValue, max(minimumValue, proposedValue.rounded()))
	guard next != value else { return }
	value = next
	feedback.selectionChanged()
	feedback.prepare()
	sendActions(for: .valueChanged)
  }

  private func updateThumb() {
	let thumb = UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { _ in
	  let circle = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 20, height: 20))
	  (tintColor ?? UIColor.mobitColors(.accentPrimary)).setFill()
	  circle.fill()
	  UIColor.mobitColors(.tradeBackground).setStroke()
	  circle.lineWidth = 2
	  circle.stroke()
	}
	slider.setThumbImage(thumb, for: .normal)
  }

  private func updateAppearance() {
	let active = tintColor ?? UIColor.mobitColors(.accentPrimary)
	let inactive = UIColor.mobitColors(.borderPrimary)
	slider.minimumTrackTintColor = .clear
	slider.maximumTrackTintColor = .clear
	track.backgroundColor = inactive
	selectedTrack.backgroundColor = active
	setNeedsLayout()
	slider.thumbTintColor = active
	for index in ticks.indices {
	  let passed = Float(index) / 5 <= slider.value
	  ticks[index].backgroundColor = passed ? active : inactive
	}
  }
}
