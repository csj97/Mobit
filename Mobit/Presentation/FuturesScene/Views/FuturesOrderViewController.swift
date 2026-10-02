import UIKit
import SnapKit
import RxSwift
import RxCocoa

final class FuturesOrderViewController: MobitBaseViewController {
  let reactor: FuturesAccountReactor
  let instrument: TradingInstrumentID
  private var expectedPositionID: UUID?
  private let bag = DisposeBag()
  private let summary = FuturesText.label(style: .subheadline)
  private let status = FuturesText.label(style: .footnote)
  private let estimate = FuturesText.label(style: .footnote)
  private let side = UISegmentedControl(items: [FuturesText.text("futures_long"), FuturesText.text("futures_short")])
  private let available = FuturesText.label(style: .footnote)
  private let historyStack = UIStackView()
  private let orderStack = UIStackView()
  private let margin = UITextField()
  private let leverage = FuturesLeverageControl()
  private let leverageLabel = FuturesText.label()
  private lazy var submit = FuturesText.button("futures_open", filled: true) { [weak self] in self?.open() }
  private lazy var close = FuturesText.button("futures_close") { [weak self] in self?.confirmClose() }
  
  init(reactor: FuturesAccountReactor, instrument: TradingInstrumentID) {
	self.reactor = reactor
	self.instrument = instrument
	self.expectedPositionID = reactor.position(for: instrument)?.id
	super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  
  override func viewDidLoad() {
	super.viewDidLoad()
	view.backgroundColor = .mobitColors(.tradeBackground)
	let scroll = UIScrollView()
	scroll.keyboardDismissMode = .interactive
	let marketOrder = FuturesText.label(style: .subheadline)
	marketOrder.text = FuturesText.text("futures_market_order")
	marketOrder.textAlignment = .center
	marketOrder.backgroundColor = .mobitColors(.tradeControlSurface)
	marketOrder.layer.cornerRadius = 8
	marketOrder.clipsToBounds = true
	marketOrder.snp.makeConstraints { $0.height.greaterThanOrEqualTo(36) }
	let leverageRow = UIStackView(arrangedSubviews: [leverageLabel, leverage])
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
	  button.layer.cornerRadius = 6
	  button.snp.makeConstraints { $0.height.greaterThanOrEqualTo(32) }
	  button.addAction(UIAction { [weak self] _ in
		guard let self, margin.isEnabled,
			  let cash = reactor.currentState.snapshot?.accounts.first(where: { $0.id == self.reactor.account })?.availableBalance else { return }
		let amount = cash * Decimal(percent) / 100
		margin.text = NSDecimalNumber(decimal: amount).stringValue
		updateEstimate()
	  }, for: .touchUpInside)
	  percentages.addArrangedSubview(button)
	}
	[side, marketOrder, available, leverageRow, margin, percentages, estimate, submit, summary, close, status]
	  .forEach { orderStack.addArrangedSubview($0) }
	orderStack.axis = .vertical
	orderStack.spacing = 12
	historyStack.axis = .vertical
	historyStack.spacing = 12
	historyStack.isHidden = true
	let stack = UIStackView(arrangedSubviews: [orderStack, historyStack])
	stack.axis = .vertical
	view.addSubview(scroll)
	scroll.addSubview(stack)
	scroll.snp.makeConstraints { $0.top.leading.trailing.equalToSuperview(); $0.bottom.equalTo(view.keyboardLayoutGuide.snp.top) }
	stack.snp.makeConstraints {
	  $0.edges.equalTo(scroll.contentLayoutGuide).inset(10)
	  $0.width.equalTo(scroll.frameLayoutGuide).offset(-20)
	}
	[available, leverageLabel, summary, estimate, status].forEach {
	  $0.font = .preferredFont(forTextStyle: .caption1)
	  $0.textColor = .mobitColors(.tradeTextSecondary)
	}
	for button in [submit, close] {
	  button.configuration?.cornerStyle = .fixed
	  button.configuration?.background.cornerRadius = 8
	  button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
		var attributes = incoming
		attributes.font = .preferredFont(forTextStyle: .subheadline)
		return attributes
	  }
	}
	submit.accessibilityIdentifier = "futuresSubmit"
	close.accessibilityIdentifier = "futuresClose"
	margin.accessibilityIdentifier = "futuresMargin"
	side.selectedSegmentIndex = reactor.position(for: instrument)?.order.side == .short ? 1 : 0
	side.accessibilityLabel = FuturesText.text("futures_direction")
	leverage.maximumValue = Double(instrument.maximumPaperLeverage ?? 1)
	leverage.value = min(10, leverage.maximumValue)
	leverage.accessibilityLabel = FuturesText.text("futures_leverage")
	margin.borderStyle = .roundedRect
	margin.textColor = .mobitColors(.textPrimary)
	margin.backgroundColor = .mobitColors(.tradeControlSurface)
	margin.keyboardType = .numberPad
	margin.placeholder = FuturesText.text("futures_margin_placeholder")
	margin.attributedPlaceholder = NSAttributedString(string: FuturesText.text("futures_margin_placeholder"),
													  attributes: [.foregroundColor: UIColor.secondaryLabel])
	margin.accessibilityLabel = FuturesText.text("futures_margin_placeholder")
	margin.font = .preferredFont(forTextStyle: .body)
	margin.adjustsFontForContentSizeCategory = true
	margin.snp.makeConstraints { $0.height.greaterThanOrEqualTo(48) }
	let toolbar = UIToolbar()
	toolbar.items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
					 UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(endEditing))]
	toolbar.sizeToFit()
	margin.inputAccessoryView = toolbar
	side.rx.selectedSegmentIndex.changed.subscribe(onNext: { [weak self] _ in self?.render() }).disposed(by: bag)
	leverage.rx.controlEvent(.valueChanged).subscribe(onNext: { [weak self] _ in self?.render() }).disposed(by: bag)
	margin.rx.text.orEmpty.subscribe(onNext: { [weak self] _ in self?.updateEstimate() }).disposed(by: bag)
	reactor.state.observe(on: MainScheduler.instance).subscribe(onNext: { [weak self] _ in self?.render() }).disposed(by: bag)
  }
  
  override func viewWillAppear(_ animated: Bool) {
	super.viewWillAppear(animated)
	reactor.action.onNext(.clearMessage)
	reactor.action.onNext(.reload)
  }
  
  func selectTab(_ index: Int) {
	loadViewIfNeeded()
	side.isHidden = true
	view.endEditing(true)
	orderStack.isHidden = index == 2
	historyStack.isHidden = index != 2
	if index < 2 { side.selectedSegmentIndex = index }
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
	  let records = try snapshot.transactionHistory(for: reactor.account).filter { $0.instrument == instrument }.reversed()
	  if records.isEmpty {
		let label = FuturesText.label(style: .footnote)
		label.text = FuturesText.text("futures_empty_history")
		historyStack.addArrangedSubview(label)
	  }
	  for record in records {
		let title = FuturesText.label(style: .subheadline)
		title.text = "\(FuturesText.side(record.side)) · \(record.leverage)× · \(FuturesText.text("futures_" + record.kind.rawValue))"
		title.textColor = record.side == .long ? MarketColorPalette.riseColor : MarketColorPalette.fallColor
		let detail = FuturesText.label(style: .caption1)
		var lines = [FuturesText.date(Date(timeIntervalSince1970: Double(record.intervalStart) / 1000)),
					 "\(FuturesText.text("futures_price")) \(FuturesText.number(record.price, digits: 4)) KRW",
					 "\(FuturesText.text("futures_quantity")) \(FuturesText.number(record.quantity, digits: 8))"]
		if let end = record.intervalEndExclusive {
		  lines.append("~ \(FuturesText.date(Date(timeIntervalSince1970: Double(end) / 1000)))")
		  lines.append("\(FuturesText.text("futures_settled")) \(FuturesText.date(record.recordedAt))")
		}
		if let pnl = record.realizedPnL {
		  lines.append("\(FuturesText.text("futures_realized")) \(FuturesText.number(pnl)) KRW")
		}
		detail.text = lines.joined(separator: "\n")
		detail.textColor = .mobitColors(.tradeTextSecondary)
		let entry = UIStackView(arrangedSubviews: [title, detail])
		entry.axis = .vertical
		entry.spacing = 6
		historyStack.addArrangedSubview(entry)
		let divider = UIView()
		divider.backgroundColor = .mobitColors(.borderPrimary)
		divider.snp.makeConstraints { $0.height.equalTo(1) }
		historyStack.addArrangedSubview(divider)
	  }
	} catch {
	  let label = FuturesText.label(style: .footnote)
	  label.text = FuturesText.text("futures_storage_error")
	  historyStack.addArrangedSubview(label)
	}
  }
  
  @objc private func endEditing() { view.endEditing(true) }
  
  private func render() {
	if !historyStack.isHidden { renderHistory() }
	let position = reactor.position(for: instrument)
	let selectedSide: FuturesSide = side.selectedSegmentIndex == 0 ? .long : .short
	let directionMatches = position == nil || position?.order.side == selectedSide
	let cash = reactor.currentState.snapshot?.accounts.first { $0.id == reactor.account }?.availableBalance
	available.text = "\(FuturesText.text("futures_available"))\n\(FuturesText.number(cash)) KRW"
	if expectedPositionID == nil { expectedPositionID = position?.id }
	let closed = expectedPositionID != nil && position?.id != expectedPositionID
	if let position, let snapshot = reactor.currentState.snapshot {
	  do { summary.text = try FuturesText.position(position, snapshot: snapshot, quotes: reactor.currentState.quotes) }
	  catch { summary.text = FuturesText.text("futures_storage_error") }
	  leverage.value = Double(position.order.leverage)
	} else {
	  summary.text = nil
	}
	summary.isHidden = position == nil
	if closed {
	  status.text = FuturesText.text("futures_position_closed")
	} else if !directionMatches {
	  status.text = FuturesText.text("futures_same_conditions")
	} else {
	  status.text = reactor.currentState.message ?? FuturesText.status(reactor)
	}
	side.isEnabled = !reactor.currentState.submitting
	leverage.isEnabled = position == nil && !closed && !reactor.currentState.submitting
	margin.isEnabled = !reactor.currentState.submitting && !closed
	leverageLabel.text = "\(FuturesText.text("futures_leverage")) \(Int(leverage.value))× / \(instrument.maximumPaperLeverage ?? 1)×"
	leverage.tintColor = selectedSide == .long ? MarketColorPalette.riseColor : MarketColorPalette.fallColor
	submit.configuration?.title = FuturesText.text(selectedSide == .long ? "futures_enter_long" : "futures_enter_short")
	submit.configuration?.baseBackgroundColor = selectedSide == .long ? MarketColorPalette.riseColor : MarketColorPalette.fallColor
	submit.configuration?.baseForegroundColor = .white
	submit.isEnabled = reactor.canRequestOrder && !closed && directionMatches
	close.isHidden = position == nil
	close.isEnabled = reactor.canRequestOrder && !closed
	updateEstimate()
  }
  
  private func updateEstimate() {
	guard let amount = Decimal(string: margin.text ?? "", locale: Locale(identifier: "en_US_POSIX")),
		  !amount.isNaN, amount > 0, let notional = try? FuturesDecimal.multiply(amount, Decimal(Int(leverage.value))) else {
	  estimate.text = FuturesText.text("futures_margin_hint")
	  return
	}
	estimate.text = "\(FuturesText.text("futures_notional")) \(FuturesText.number(notional)) KRW\n\(FuturesText.text("futures_execution_note"))"
  }
  
  private func open() {
	guard let amount = Decimal(string: margin.text ?? "", locale: Locale(identifier: "en_US_POSIX")),
		  !amount.isNaN, amount > 0 else {
	  status.text = FuturesText.text("futures_input_error")
	  return
	}
	guard let cash = reactor.currentState.snapshot?.accounts.first(where: { $0.id == reactor.account })?.availableBalance,
		  amount <= cash else {
	  status.text = FuturesText.text("futures_insufficient")
	  return
	}
	view.endEditing(true)
	let current = reactor.position(for: instrument)
	let selectedSide: FuturesSide = side.selectedSegmentIndex == 0 ? .long : .short
	guard current == nil || current?.order.side == selectedSide else {
	  status.text = FuturesText.text("futures_same_conditions")
	  return
	}
	reactor.action.onNext(.open(instrument, selectedSide,
								amount, current?.order.leverage ?? Int(leverage.value), expectedPositionID ?? current?.id))
  }
  
  private func confirmClose() {
	guard let position = reactor.position(for: instrument) else { return }
	let alert = UIAlertController(title: FuturesText.text("futures_close"), message: FuturesText.text("futures_close_confirm"), preferredStyle: .alert)
	alert.addAction(UIAlertAction(title: FuturesText.text("futures_cancel"), style: .cancel))
	alert.addAction(UIAlertAction(title: FuturesText.text("futures_close"), style: .destructive) { [weak self] _ in
	  self?.reactor.action.onNext(.close(position.id))
	})
	present(alert, animated: true)
  }
}

final class FuturesLeverageControl: UIControl {
  private let slider = UISlider()
  private let feedback = UISelectionFeedbackGenerator()
  private let ticks = (0...5).map { _ in UIView() }
  private let track = UIView()
  private let selectedTrack = UIView()
  var maximumValue: Double = 100 {
	didSet {
	  maximumValue = max(1, maximumValue.rounded())
	  value = min(value, maximumValue)
	}
  }
  var value: Double = 1 {
	didSet {
	  value = min(maximumValue, max(1, value.rounded()))
	  slider.value = value == 1 ? 0 : Float(value / maximumValue)
	  accessibilityValue = "\(Int(value))×"
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
	selectedTrack.frame = CGRect(x: start, y: track.midY - 1.5,
								 width: (end - start) * CGFloat(slider.value), height: 3)
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
  
  override func accessibilityIncrement() { select(value + 1) }
  override func accessibilityDecrement() { select(value - 1) }
  
  @objc private func prepareFeedback() { feedback.prepare() }
  
  @objc private func sliderChanged() {
	// 0%는 최소 1배이며, 중간 눈금은 종목별 최대 배율의 비율을 나타낸다.
	select(Double(slider.value) * maximumValue)
  }
  
  private func select(_ proposedValue: Double) {
	guard isEnabled else { return }
	let next = min(maximumValue, max(1, proposedValue.rounded()))
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
