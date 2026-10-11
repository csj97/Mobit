import UIKit
import SnapKit
import RxSwift

final class FuturesCloseViewController: UIViewController {
  // 주문 처리와 실시간 시세를 제공하는 기존 화면 상태다.
  private let reactor: FuturesAccountReactor
  // 시트를 열었던 포지션만 종료하며 같은 종목의 새 포지션으로 바꾸지 않는다.
  private let positionID: UUID
  // 체결 순간 기존 주문 화면이 표시하는 소켓 가격을 고정한다.
  private let captureOrderPrice: () -> FuturesOrderPrice?
  // 별도 포지션 감시 소켓보다 주문 화면의 시세가 먼저 바뀌어도 즉시 다시 계산한다.
  private let orderPriceUpdates: Observable<Void>
  // 시트를 닫으면 실시간 화면 구독도 함께 정리한다.
  private let disposeBag = DisposeBag()
  // 기본 시트의 dim 아래에 밝은 색을 더해 다크 모드에서 시트 경계를 구분한다.
  private let dimView: UIView = {
    // 터치와 바깥 영역 탭 처리는 UIKit의 기본 시트에 맡긴다.
    let view = UIView()
    view.isUserInteractionEnabled = false
    view.accessibilityIdentifier = "futuresCloseDim"
    view.backgroundColor = UIColor { traits in
      traits.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.12) : .clear
    }
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    return view
  }()
  // 마지막 입력 방식과 종료 비율을 유지하며 시세는 예상 손익에만 반영한다.
  private var selection: FuturesCloseSelection? = .percent(100)
  // 이 시트의 제출이 끝났을 때만 성공 메시지에 따라 닫는다.
  private var didSubmit = false
  // 종료할 수량에 배분되는 사용자 원금(증거금)을 KRW로 입력받는다.
  private let amountTextField = UITextField()
  // 종료할 코인 수량을 직접 입력받는다.
  private let quantityTextField = UITextField()
  // 기존 주문 슬라이더의 모양과 선택 진동을 그대로 사용한다.
  private let percentControl = FuturesLeverageControl()
  // 실제 선택한 수량이 전체 수량의 몇 %인지 표시한다.
  private let percentLabel = FuturesText.label(style: .subheadline)
  // 현재 시세와 종료 가능한 전체 수량을 표시한다.
  private let priceLabel = FuturesText.label(style: .subheadline)
  // 종료 후 반환금액·실현 손익·잔여 수량을 보여준다.
  private let summaryLabel = FuturesText.label(style: .subheadline)
  // 입력 오류와 시세 연결·주문 처리 상태를 표시한다.
  private let statusLabel = FuturesText.label(style: .footnote)
  // 0·25·50·100%를 빠르게 선택하는 버튼 묶음이다.
  private let percentButtons = UIStackView()
  // 현재 입력 조건으로 부분 또는 전량 종료를 요청한다.
  private lazy var closeButton = FuturesText.button("futures_close", filled: true) { [weak self] in self?.submit() }
  // 처리 중에는 취소를 막고 그 외에는 종료하지 않고 시트를 닫는다.
  private lazy var cancelButton = FuturesText.button("futures_cancel") { [weak self] in self?.dismiss(animated: true) }

  init(
    reactor: FuturesAccountReactor,
    positionID: UUID,
    captureOrderPrice: @escaping () -> FuturesOrderPrice?,
    orderPriceUpdates: Observable<Void> = .empty()
  ) {
    self.reactor = reactor
    self.positionID = positionID
    self.captureOrderPrice = captureOrderPrice
    self.orderPriceUpdates = orderPriceUpdates
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .mobitColors(.tradeBackground)
    view.accessibilityIdentifier = "futuresCloseSheet"
    // 기존 진입 주문 버튼과 동일한 모서리와 글자 스타일을 사용한다.
    closeButton.configuration?.cornerStyle = .fixed
    closeButton.configuration?.background.cornerRadius = 8
    closeButton.configuration?.background.strokeWidth = 1
    closeButton.configuration?.background.strokeColor = .mobitColors(.tradeSeparator)
    cancelButton.configuration = .plain()
    cancelButton.configuration?.image = UIImage(systemName: "xmark.circle.fill")
    cancelButton.configuration?.preferredSymbolConfigurationForImage = .init(pointSize: 24)
    cancelButton.configuration?.baseForegroundColor = .mobitColors(.tradeTextSecondary)
    cancelButton.configuration?.contentInsets = .zero
    cancelButton.accessibilityLabel = FuturesText.text("futures_cancel")
    cancelButton.snp.makeConstraints { $0.width.greaterThanOrEqualTo(44) }
    closeButton.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      // 기존 버튼 설정에서 글꼴만 주문 화면에 맞춘다.
      var attributes = incoming
      attributes.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
        for: .systemFont(ofSize: 18, weight: .semibold)
      )
      return attributes
    }
    // 키보드와 큰 글자에서도 모든 입력 항목에 접근할 수 있는 스크롤 영역이다.
    let scrollView = UIScrollView()
    scrollView.keyboardDismissMode = .interactive
    // 종료 시트 제목과 취소 버튼을 배치한다.
    let titleLabel = FuturesText.label(style: .title3)
    titleLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
      for: .systemFont(ofSize: 18, weight: .semibold)
    )
    titleLabel.text = FuturesText.text("futures_close")
    // 제목과 취소 동작을 한 줄에 표시한다.
    let header = UIStackView(arrangedSubviews: [titleLabel, cancelButton])
    header.alignment = .center
    cancelButton.setContentHuggingPriority(.required, for: .horizontal)
    for (field, key, identifier) in [
      (amountTextField, "futures_close_amount", "futuresCloseAmount"),
      (quantityTextField, "futures_close_quantity", "futuresCloseQuantity")
    ] {
      field.placeholder = FuturesText.text(key)
      field.accessibilityLabel = FuturesText.text(key)
      field.accessibilityIdentifier = identifier
      field.font = .preferredFont(forTextStyle: .body)
      field.adjustsFontForContentSizeCategory = true
      field.borderStyle = .roundedRect
      field.backgroundColor = .mobitColors(.tradeControlSurface)
      field.textColor = .mobitColors(.tradeTextPrimary)
      field.keyboardType = .decimalPad
      // 숫자 키보드에서도 입력을 마치고 전체 정산 내용을 볼 수 있게 한다.
      let toolbar = UIToolbar()
      toolbar.items = [
        UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
        UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(endEditing))
      ]
      toolbar.sizeToFit()
      field.inputAccessoryView = toolbar
      field.addTarget(self, action: #selector(inputChanged(_:)), for: .editingChanged)
      field.addTarget(self, action: #selector(finishInput(_:)), for: .editingDidEnd)
      field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }
    percentControl.minimumValue = 0
    percentControl.maximumValue = 100
    percentControl.valueSuffix = "%"
    percentControl.value = 100
    percentControl.accessibilityLabel = FuturesText.text("futures_close_percent")
    percentControl.accessibilityIdentifier = "futuresClosePercent"
    percentControl.addTarget(self, action: #selector(percentChanged), for: .valueChanged)
    percentButtons.distribution = .fillEqually
    percentButtons.spacing = 4
    for percent in [0, 25, 50, 100] {
      // 빠르게 종료 비율을 선택하는 버튼이다.
      let button = UIButton(type: .system)
      button.setTitle("\(percent)%", for: .normal)
      button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
      button.backgroundColor = .mobitColors(.tradeControlSurface)
      button.setTitleColor(.mobitColors(.tradeTextPrimary), for: .normal)
      button.layer.cornerRadius = 8
      button.layer.borderWidth = 1
      button.layer.borderColor = UIColor.mobitColors(.tradeSeparator).resolvedColor(with: traitCollection).cgColor
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
      button.accessibilityIdentifier = "futuresClosePercent\(percent)"
      button.addAction(UIAction { [weak self] _ in
        self?.view.endEditing(true)
        self?.selection = .percent(percent)
        self?.render()
      }, for: .touchUpInside)
      percentButtons.addArrangedSubview(button)
    }
    // 종료 원금과 실시간 손익이 포함된 반환금액을 구분해 설명한다.
    let noteLabel = FuturesText.label(style: .footnote)
    noteLabel.text = FuturesText.text("futures_close_note")
    noteLabel.textColor = .mobitColors(.tradeTextSecondary)
    statusLabel.textColor = .mobitColors(.tradeTextSecondary)
    // 숫자 너비를 일정하게 유지해 실시간 금액의 자릿수가 바뀔 때 흔들림을 줄인다.
    summaryLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
      for: .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
    )
    summaryLabel.accessibilityIdentifier = "futuresCloseSummary"
    closeButton.accessibilityIdentifier = "futuresCloseSubmit"
    closeButton.setContentHuggingPriority(.required, for: .vertical)
    // 항목 높이는 내용과 글자 크기에 따라 결정한다.
    let content = UIStackView(
      arrangedSubviews: [
        header, priceLabel,
        inputRow(key: "futures_close_amount", field: amountTextField),
        inputRow(key: "futures_close_quantity", field: quantityTextField),
        percentLabel, percentControl, percentButtons, summaryLabel, noteLabel, statusLabel
      ]
    )
    content.axis = .vertical
    content.spacing = 12
    view.addSubview(scrollView)
    view.addSubview(closeButton)
    scrollView.addSubview(content)
    closeButton.snp.makeConstraints {
      $0.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(16)
      $0.bottom.equalTo(view.keyboardLayoutGuide.snp.top).offset(-12)
    }
    scrollView.snp.makeConstraints {
      $0.top.leading.trailing.equalTo(view.safeAreaLayoutGuide)
      $0.bottom.equalTo(closeButton.snp.top).offset(-12)
    }
    content.snp.makeConstraints {
      $0.edges.equalTo(scrollView.contentLayoutGuide).inset(16)
      $0.width.equalTo(scrollView.frameLayoutGuide).offset(-32)
    }
    reactor.action.onNext(.clearMessage)
    // 시세 묶음의 마지막 가격을 다음 메인 루프에서 읽고 화면 갱신은 초당 최대 10회로 제한한다.
    orderPriceUpdates.throttle(.milliseconds(100), latest: true, scheduler: MainScheduler.instance)
      .observe(on: MainScheduler.asyncInstance).subscribe(onNext: { [weak self] in
        self?.render()
      }).disposed(by: disposeBag)
    // 가격은 주문 화면의 소켓 경로로만 갱신하고 계좌·주문 상태가 바뀔 때만 전체 내용을 다시 확인한다.
    let accountChanges: Observable<(
      snapshot: FuturesAccountSnapshot?, submitting: Bool, loadFailed: Bool, message: String?, status: String
    )> = reactor.state.map { [weak reactor] state in
      (
        snapshot: state.snapshot, submitting: state.submitting, loadFailed: state.loadFailed,
        message: state.message, status: reactor.map { FuturesText.status($0) } ?? ""
      )
    }
    accountChanges.distinctUntilChanged { previous, current in
      previous.snapshot == current.snapshot && previous.submitting == current.submitting
        && previous.loadFailed == current.loadFailed && previous.message == current.message
        && previous.status == current.status
    }.observe(on: MainScheduler.instance).subscribe(onNext: { [weak self] state in
      guard let self else { return }
      if didSubmit, !state.submitting {
        didSubmit = false
        isModalInPresentation = false
        if state.message == FuturesText.text("futures_order_done") {
          dismiss(animated: true)
          return
        }
        if let message = state.message { showCloseError(message) }
      }
      render()
    }).disposed(by: disposeBag)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    // 드래그 닫기가 취소되어 다시 나타날 때는 기존 dim의 복구 애니메이션을 유지한다.
    guard dimView.superview == nil, let container = presentationController?.containerView else { return }
    dimView.frame = container.bounds
    container.insertSubview(dimView, at: 0)
    dimView.alpha = 0
    if let transitionCoordinator {
      transitionCoordinator.animate(
        alongsideTransition: { [weak self] _ in self?.dimView.alpha = 1 },
        completion: { [weak self] context in
          if context.isCancelled { self?.dimView.removeFromSuperview() }
        }
      )
    } else {
      dimView.alpha = 1
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    guard isBeingDismissed || presentingViewController?.isBeingDismissed == true else { return }
    if let transitionCoordinator {
      transitionCoordinator.animate(
        alongsideTransition: { [weak self] _ in self?.dimView.alpha = 0 },
        completion: { [weak self] context in
          if context.isCancelled { self?.dimView.alpha = 1 }
          else { self?.dimView.removeFromSuperview() }
        }
      )
    } else {
      dimView.removeFromSuperview()
    }
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
    for button in percentButtons.arrangedSubviews {
      button.layer.borderColor = UIColor.mobitColors(.tradeSeparator).resolvedColor(with: traitCollection).cgColor
    }
  }

  private func inputRow(key: String, field: UITextField) -> UIView {
    // 입력값의 단위와 목적을 알려주는 제목이다.
    let label = FuturesText.label(style: .caption1)
    label.text = FuturesText.text(key)
    // 제목과 입력창을 세로로 배치한다.
    let row = UIStackView(arrangedSubviews: [label, field])
    row.axis = .vertical
    row.spacing = 6
    return row
  }

  @objc private func inputChanged(_ field: UITextField) {
    // 쉼표를 제외한 사용자의 숫자 입력 원문이다.
    let text = (field.text ?? "").replacingOccurrences(of: ",", with: "")
    // 소수점부터 입력한 수량도 허용하되 잘못된 문자열은 숫자로 오인하지 않는다.
    let value = text.range(of: "^(?:[0-9]+(?:\\.[0-9]{0,8})?|\\.[0-9]{1,8})$", options: .regularExpression) != nil
      ? Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) : nil
    selection = value.map { field === amountTextField ? .amount(TradingNumberFormat.truncated($0)) : .quantity($0) }
    if value == nil {
      if field === amountTextField { quantityTextField.text = nil } else { amountTextField.text = nil }
    }
    render()
  }

  @objc private func finishInput(_ field: UITextField) {
    if case .amount(let value) = selection, field === amountTextField { field.text = FuturesText.number(value) }
    if case .quantity(let value) = selection, field === quantityTextField { field.text = FuturesText.number(value) }
  }

  @objc private func endEditing() { view.endEditing(true) }

  @objc private func percentChanged() {
    view.endEditing(true)
    selection = .percent(Int(percentControl.value))
    render()
  }

  private func currentPosition() -> FuturesPosition? {
    reactor.positions.first { $0.id == positionID }
  }

  private func render() {
    // 시세 갱신은 평가 값만 바꾸고 종료 버튼의 상태·설정은 건드리지 않는다.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    UIView.performWithoutAnimation { updateContent() }
    CATransaction.commit()
  }

  private func updateContent() {
    // 제출 중에는 이탈과 입력 변경을 막아 같은 종료 요청을 중복 실행하지 않는다.
    let enabled = !reactor.currentState.submitting
    isModalInPresentation = !enabled
    for control in [amountTextField, cancelButton, quantityTextField, percentControl]
      + percentButtons.arrangedSubviews.compactMap({ $0 as? UIControl })
    where control.isEnabled != enabled {
      control.isEnabled = enabled
    }
    updateText(statusLabel, text: reactor.currentState.message ?? FuturesText.status(reactor))
    guard let position = currentPosition() else {
      updateText(statusLabel, text: FuturesText.text("futures_position_closed"))
      updateText(summaryLabel, text: nil)
      return
    }
    guard let price = captureOrderPrice(), price.quote.instrument == position.order.instrument else {
      updateText(statusLabel, text: FuturesText.text("futures_socket_wait"))
      // 연결 대기 중에는 마지막 평가를 유지하고 제출할 때 최신 가격을 확인한다.
      return
    }
    // 표시 문자열이 같으면 라벨의 레이아웃을 다시 무효화하지 않는다.
    let priceText = "\(FuturesText.symbol(position.order.instrument)) · \(FuturesText.side(position.order.side)) \(position.order.leverage)×\n"
      + "\(FuturesText.text("futures_current")) \(FuturesText.number(price.quote.price)) \(FuturesText.text("currency_krw_unit")) · \(FuturesText.text("futures_quantity")) \(FuturesText.number(position.quantity))"
    updateText(priceLabel, text: priceText)
    do {
      guard let selection else { throw FuturesCalculationError.invalidNumber }
      // 보유 원금을 기준으로 산출한 종료 수량이며 시세 변화로 바꾸지 않는다.
      let quantity = try selection.calculateQuantity(position: position)
      // 실제 정산 때 반환할 원금과 동일한 배분 기준의 입력 금액이다.
      let amount = try FuturesCalculator.calculateClosingMargin(position, quantity: quantity)
      switch selection {
      case .percent:
        updateText(amountTextField, text: FuturesText.number(amount))
        updateText(quantityTextField, text: FuturesText.number(quantity))
      case .amount: updateText(quantityTextField, text: FuturesText.number(quantity))
      case .quantity: updateText(amountTextField, text: FuturesText.number(amount))
      }
      // 실제 체결 가능한 수량에 해당하는 종료 비율이다.
      let percent = try FuturesDecimal.multiply(FuturesDecimal.divide(quantity, position.quantity), 100)
      // 슬라이더는 정수 눈금 값이 달라졌을 때만 다시 그린다.
      let sliderValue = NSDecimalNumber(decimal: percent).doubleValue.rounded()
      if percentControl.value != sliderValue { percentControl.value = sliderValue }
      updateText(percentLabel, text: FuturesText.text("futures_close_percent") + " " + FuturesText.number(percent, digits: 2) + "%")
      guard quantity > 0 else {
        updateText(summaryLabel, text: nil)
        updateText(statusLabel, text: FuturesText.text("futures_close_invalid"))
        return
      }
      // 종료 수량의 원금과 손익만 돌려주는 예상 정산 결과다.
      let quote = try FuturesCalculator.closingQuote(
        position,
        executionPrice: price.quote.price,
        exitFeeRate: TradingRules.Futures.closingFeeRate(for: position.order.instrument),
        quantity: quantity
      )
      // 반환금액·손익·잔여 수량의 최종 표시값을 한 번에 적용한다.
      let summaryText = "\(FuturesText.text("futures_close_return")) \(FuturesText.number(quote.returnedMargin)) \(FuturesText.text("currency_krw_unit"))\n"
        + "\(FuturesText.text("futures_realized")) \(FuturesText.number(quote.realizedPnL)) \(FuturesText.text("currency_krw_unit"))\n"
        + "\(FuturesText.text("futures_close_remaining")) \(FuturesText.number(try FuturesDecimal.subtract(position.quantity, quantity)))"
      updateText(summaryLabel, text: summaryText)
    } catch {
      updateText(summaryLabel, text: nil)
      updateText(statusLabel, text: FuturesText.text("futures_close_invalid"))
      if case .amount = selection { updateText(quantityTextField, text: nil) }
      if case .quantity = selection { updateText(amountTextField, text: nil) }
    }
  }

  private func updateText(_ label: UILabel, text: String?) {
    if label.text != text { label.text = text }
  }

  private func updateText(_ field: UITextField, text: String?) {
    if field.text != (text ?? "") { field.text = text }
  }

  private func submit() {
    guard !didSubmit, !reactor.currentState.submitting else { return }
    guard reactor.canRequestOrder else {
      showCloseError(FuturesText.text(reactor.currentState.loadFailed ? "futures_storage_error" : "futures_wait"))
      return
    }
    guard let position = currentPosition() else {
      showCloseError(FuturesText.text("futures_position_closed"))
      return
    }
    guard let selection else {
      showCloseError(FuturesText.text("futures_close_invalid"))
      return
    }
    guard let price = captureOrderPrice(), price.quote.instrument == position.order.instrument else {
      showCloseError(FuturesText.text("futures_socket_wait"))
      return
    }
    do {
      // 현재 남은 원금을 기준으로 수량을 확인하고 체결 가격만 최신 소켓 값으로 고정한다.
      let quantity = try selection.calculateQuantity(position: position)
      guard quantity > 0 else { throw FuturesCalculationError.invalidNumber }
      // 시세로 종료가 불가능해진 경우에도 버튼 대신 탭 시점에 요청을 막는다.
      let quote = try FuturesCalculator.closingQuote(
        position,
        executionPrice: price.quote.price,
        exitFeeRate: TradingRules.Futures.closingFeeRate(for: position.order.instrument),
        quantity: quantity
      )
      guard quote.returnedMargin > 0 else {
        showCloseError(FuturesText.text("futures_retry_order"))
        return
      }
      view.endEditing(true)
      reactor.action.onNext(.clearMessage)
      didSubmit = true
      reactor.action.onNext(.closeQuantity(positionID, quantity, position.quantity, price))
    } catch {
      showCloseError(FuturesText.text("futures_close_invalid"))
    }
  }

  private func showCloseError(_ message: String) {
    updateText(statusLabel, text: message)
    guard presentedViewController == nil else { return }
    view.endEditing(true)
    // 제출을 막은 이유를 스크롤 위치와 무관하게 바로 안내한다.
    let alert = UIAlertController(title: FuturesText.text("futures_close"), message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: FuturesText.text("common_confirm"), style: .default))
    present(alert, animated: true)
  }
}
