import UIKit
import SnapKit
import RxSwift

final class FuturesCloseViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
  // 종료 시트가 완전히 닫힌 뒤 상위 화면에서 완료 안내를 표시한다.
  var tradeCompletedCallBack: (() -> Void)?
  // 주문 처리와 실시간 시세를 제공하는 기존 화면 상태다.
  private let reactor: FuturesAccountReactor
  // 시트를 열었던 포지션만 종료하며 같은 종목의 새 포지션으로 바꾸지 않는다.
  private let positionID: UUID
  // 종료 이후 포지션이 사라져도 시트를 열었던 종목으로 행동을 기록한다.
  private let instrument: TradingInstrumentID?
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
  // 카드·입력·하단 동작이 공유하는 시트 좌우 여백이다.
  private let horizontalPadding: CGFloat = 20
  // 포지션의 종목·방향·보유 정보를 묶는 카드다.
  private let positionCard = UIStackView()
  // 현재 시세를 보유 수량과 별도 열에 표시한다.
  private let priceLabel = FuturesText.label(style: .subheadline)
  // 종료 가능한 전체 수량과 코인 단위를 표시한다.
  private let holdingLabel = FuturesText.label(style: .subheadline)
  // 원금 입력에 적용할 최대 금액을 알려준다.
  private let maximumAmountLabel = FuturesText.label(style: .caption1)
  // 수량 입력에 적용할 최대 보유분을 알려준다.
  private let maximumQuantityLabel = FuturesText.label(style: .caption1)
  // 입력창과 단위의 경계를 함께 강조한다.
  private let amountInputContainer = UIStackView()
  // 수량 입력창도 원금과 같은 포커스·테마 정책을 사용한다.
  private let quantityInputContainer = UIStackView()
  // 종료 전 예상 손익과 실제 계좌에 더해질 예상 금액을 구분한다.
  private let summaryStack = UIStackView()
  // 선택 수량을 종료했을 때의 예상 손익이며 체결 전 확정값이 아니다.
  private let estimatedPnLLabel = FuturesText.label(style: .headline)
  // 선택 수량의 증거금과 손익을 합친 예상 수령액이다.
  private let receivedAmountLabel = FuturesText.label(style: .subheadline)
  // 주문 알럿과 별개인 자산 조회 실패·연결 상태를 표시한다.
  private let statusLabel = FuturesText.label(style: .footnote)
  // 0·25·50·100%를 빠르게 선택하는 버튼 묶음이다.
  private let percentButtons = UIStackView()
  // 현재 입력 조건으로 부분 또는 전량 종료를 요청한다.
  private lazy var closeButton = FuturesText.button("futures_close", filled: true) { [weak self] in self?.submit() }
  // 처리 중에는 취소를 막고 그 외에는 종료하지 않고 시트를 닫는다.
  private lazy var cancelButton = FuturesText.button("futures_cancel") { [weak self] in
    self?.sendCloseClick("선물_종료시트_취소", detail: "닫기_버튼")
    self?.dismiss(animated: true)
  }

  init(
    reactor: FuturesAccountReactor,
    positionID: UUID,
    captureOrderPrice: @escaping () -> FuturesOrderPrice?,
    orderPriceUpdates: Observable<Void> = .empty()
  ) {
    self.reactor = reactor
    self.positionID = positionID
    self.instrument = reactor.positions.first { $0.id == positionID }?.order.instrument
    self.captureOrderPrice = captureOrderPrice
    self.orderPriceUpdates = orderPriceUpdates
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .mobitColors(.tradeBackground)
    view.accessibilityIdentifier = "futuresCloseSheet"
    presentationController?.delegate = self
    // 하단 동작은 스크롤·키보드 위치와 무관하게 접근할 수 있게 고정한다.
    closeButton.configuration?.background.cornerRadius = 16
    closeButton.configuration?.contentInsets = .init(top: 17, leading: 20, bottom: 17, trailing: 20)
    closeButton.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      // 기존 버튼의 상태별 색상을 유지하고 강조 글꼴만 적용한다.
      var attributes = incoming
      attributes.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 18, weight: .bold))
      return attributes
    }
    closeButton.accessibilityIdentifier = "futuresCloseSubmit"
    closeButton.setContentHuggingPriority(.required, for: .vertical)
    cancelButton.configuration = .plain()
    cancelButton.configuration?.image = UIImage(systemName: "xmark")
    cancelButton.configuration?.preferredSymbolConfigurationForImage = .init(pointSize: 17, weight: .semibold)
    cancelButton.configuration?.baseForegroundColor = .mobitColors(.tradeTextSecondary)
    cancelButton.configuration?.background.backgroundColor = .mobitColors(.tradeSurface)
    cancelButton.configuration?.background.cornerRadius = 22
    cancelButton.configuration?.contentInsets = .zero
    cancelButton.accessibilityLabel = FuturesText.text("futures_cancel")
    cancelButton.snp.makeConstraints { $0.size.equalTo(44) }
    // 제목과 닫기는 내용을 스크롤해도 같은 위치에 남는다.
    let titleLabel = styledLabel(size: 23, weight: .bold, style: .title2)
    titleLabel.text = FuturesText.text("futures_close")
    // 종료 대상 정보와 구분한 시트 헤더다.
    let header = UIStackView(arrangedSubviews: [titleLabel, cancelButton])
    header.alignment = .center
    header.spacing = 12
    cancelButton.setContentHuggingPriority(.required, for: .horizontal)
    configurePositionCard()
    configureInput(amountTextField, key: "futures_close_amount", identifier: "futuresCloseAmount")
    configureInput(quantityTextField, key: "futures_close_quantity", identifier: "futuresCloseQuantity")
    percentControl.minimumValue = 0
    percentControl.maximumValue = 100
    percentControl.valueSuffix = "%"
    percentControl.value = 100
    percentControl.accessibilityLabel = FuturesText.text("futures_close_percent")
    percentControl.accessibilityIdentifier = "futuresClosePercent"
    percentControl.addTarget(self, action: #selector(percentChanged), for: .valueChanged)
    percentControl.addTarget(self, action: #selector(percentConfirmed), for: .editingDidEnd)
    // 선택 비율을 별도 배지로 표시해 입력 영역과 구분한다.
    let percentTitle = styledLabel(size: 15, weight: .semibold)
    percentTitle.text = FuturesText.text("futures_close_percent")
    percentLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 16, weight: .bold))
    percentLabel.textColor = .mobitColors(.accentPrimary)
    percentLabel.accessibilityIdentifier = "futuresClosePercentValue"
    percentLabel.setContentHuggingPriority(.required, for: .horizontal)
    // 배지의 여백은 텍스트 길이와 글자 크기에 맞춰 늘어난다.
    let percentBadge = UIStackView(arrangedSubviews: [percentLabel])
    percentBadge.isLayoutMarginsRelativeArrangement = true
    percentBadge.directionalLayoutMargins = .init(top: 4, leading: 10, bottom: 4, trailing: 10)
    percentBadge.backgroundColor = UIColor.mobitColors(.accentPrimary).withAlphaComponent(0.08)
    percentBadge.layer.cornerRadius = 8
    percentBadge.setContentHuggingPriority(.required, for: .horizontal)
    // 종료 비율 제목과 현재 선택값을 양쪽에 배치한다.
    let percentHeader = UIStackView(arrangedSubviews: [percentTitle, percentBadge])
    percentHeader.alignment = .center
    percentHeader.spacing = 12
    percentButtons.distribution = .fillEqually
    percentButtons.spacing = 8
    for percent in [0, 25, 50, 100] {
      // 비율 직접 입력과도 선택 표시를 동기화할 빠른 선택 버튼이다.
      let button = UIButton(type: .custom)
      button.tag = percent
      button.setTitle("\(percent)%", for: .normal)
      button.titleLabel?.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 14, weight: .semibold))
      button.titleLabel?.adjustsFontForContentSizeCategory = true
      button.layer.cornerRadius = 12
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
      button.accessibilityIdentifier = "futuresClosePercent\(percent)"
      button.addAction(UIAction { [weak self] _ in
        self?.view.endEditing(true)
        self?.selection = .percent(percent)
        self?.sendCloseClick("선물_종료비율_선택", detail: "\(percent)%")
        self?.render()
      }, for: .touchUpInside)
      percentButtons.addArrangedSubview(button)
    }
    // 비율 조절과 빠른 선택을 하나의 입력 그룹으로 묶는다.
    let percentSection = UIStackView(arrangedSubviews: [percentHeader, percentControl, percentButtons])
    percentSection.axis = .vertical
    percentSection.spacing = 8
    configureSummary()
    // 실제 수령액과 미리보기의 차이를 아이콘과 짧은 문장으로 설명한다.
    let noteLabel = FuturesText.label(style: .footnote)
    noteLabel.text = FuturesText.text("futures_close_note")
    noteLabel.textColor = .mobitColors(.tradeTextSecondary)
    // 안내 아이콘은 옆 문구와 같은 정보를 중복 낭독하지 않는다.
    let noteIcon = UIImageView(image: UIImage(systemName: "info.circle"))
    noteIcon.tintColor = .mobitColors(.tradeTextSecondary)
    noteIcon.contentMode = .scaleAspectFit
    noteIcon.isAccessibilityElement = false
    noteIcon.snp.makeConstraints { $0.size.equalTo(16) }
    // 여러 줄 안내의 첫 줄에 아이콘을 맞춘다.
    let note = UIStackView(arrangedSubviews: [noteIcon, noteLabel])
    note.alignment = .top
    note.spacing = 8
    statusLabel.textColor = .mobitColors(.tradeTextSecondary)
    statusLabel.accessibilityIdentifier = "futuresCloseStatus"
    // 코인 단위는 실제 종료 대상의 심볼에서 가져온다.
    let symbol = currentPosition().map { FuturesText.symbol($0.order.instrument).marketSymbol } ?? ""
    // 고정 높이 없이 정보 카드·입력·예상 금액 순서로 배치한다.
    let content = UIStackView(
      arrangedSubviews: [
        positionCard,
        inputRow(key: "futures_close_amount", field: amountTextField, unit: "KRW", hint: maximumAmountLabel, container: amountInputContainer),
        inputRow(key: "futures_close_quantity", field: quantityTextField, unit: symbol, hint: maximumQuantityLabel, container: quantityInputContainer),
        percentSection, summaryStack, note, statusLabel
      ]
    )
    content.axis = .vertical
    content.spacing = 22
    // 입력 영역 전체를 스크롤하고 하단 주문 버튼은 키보드 위에 둔다.
    let scrollView = UIScrollView()
    scrollView.keyboardDismissMode = .interactive
    scrollView.accessibilityIdentifier = "futuresCloseScroll"
    view.addSubview(header)
    view.addSubview(scrollView)
    view.addSubview(closeButton)
    scrollView.addSubview(content)
    header.snp.makeConstraints {
      $0.top.equalTo(view.safeAreaLayoutGuide).offset(20)
      $0.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(horizontalPadding)
    }
    closeButton.snp.makeConstraints {
      $0.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(horizontalPadding)
      $0.bottom.equalTo(view.keyboardLayoutGuide.snp.top).offset(-12)
    }
    scrollView.snp.makeConstraints {
      $0.top.equalTo(header.snp.bottom).offset(12)
      $0.leading.trailing.equalTo(view.safeAreaLayoutGuide)
      $0.bottom.equalTo(closeButton.snp.top).offset(-12)
    }
    content.snp.makeConstraints {
      $0.edges.equalTo(scrollView.contentLayoutGuide).inset(UIEdgeInsets(top: 8, left: horizontalPadding, bottom: 12, right: horizontalPadding))
      $0.width.equalTo(scrollView.frameLayoutGuide).offset(-horizontalPadding * 2)
    }
    updateBorderColors()
    updatePercentSelection(100)
    reactor.action.onNext(.clearMessage)
    // 시세 묶음의 마지막 가격을 다음 메인 루프에서 읽고 화면 갱신은 초당 최대 10회로 제한한다.
    Observable.merge(
      orderPriceUpdates,
      Observable<Int>.interval(.seconds(1), scheduler: MainScheduler.instance)
        .filter { [weak self] _ in self?.viewIfLoaded?.window != nil }.map { _ in () }
    ).throttle(.milliseconds(100), latest: true, scheduler: MainScheduler.instance)
      .observe(on: MainScheduler.asyncInstance).subscribe(onNext: { [weak self] in
        self?.render()
      }).disposed(by: disposeBag)
    // 가격은 주문 화면의 소켓 경로로만 갱신하고 계좌·주문 상태가 바뀔 때만 전체 내용을 다시 확인한다.
    let accountChanges: Observable<(
      snapshot: FuturesAccountSnapshot?, submitting: Bool, loadFailed: Bool, message: String?, status: String, canSubmit: Bool
    )> = reactor.state.map { [weak reactor] state in
      (
        snapshot: state.snapshot, submitting: state.submitting, loadFailed: state.loadFailed,
        message: state.message, status: reactor.map { FuturesText.status($0) } ?? "",
        canSubmit: reactor?.canSubmit ?? false
      )
    }
    accountChanges.distinctUntilChanged { previous, current in
      previous.snapshot == current.snapshot && previous.submitting == current.submitting
        && previous.loadFailed == current.loadFailed && previous.message == current.message
        && previous.status == current.status && previous.canSubmit == current.canSubmit
    }.observe(on: MainScheduler.instance).subscribe(onNext: { [weak self] state in
      guard let self else { return }
      if didSubmit, !state.submitting {
        didSubmit = false
        isModalInPresentation = false
        if state.message == FuturesText.text("futures_order_done") {
          dismiss(animated: true, completion: tradeCompletedCallBack)
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

  override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()
    // 숫자 중간의 줄바꿈 대신 긴 금액·큰 글씨는 제목 아래에 온전히 표시한다.
    let availableWidth = view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right
      - horizontalPadding * 2 - summaryStack.directionalLayoutMargins.leading - summaryStack.directionalLayoutMargins.trailing
    guard availableWidth > 0 else { return }
    for case let row as UIStackView in summaryStack.arrangedSubviews {
      guard let captions = row.arrangedSubviews.first as? UIStackView, let value = row.arrangedSubviews.last as? UILabel else { continue }
      // 각 문구를 한 줄로 읽는 데 필요한 실제 글꼴 폭이다.
      let titleWidth = captions.arrangedSubviews.compactMap { $0 as? UILabel }.map {
        ($0.text ?? "").size(withAttributes: [.font: $0.font ?? UIFont.preferredFont(forTextStyle: .subheadline)]).width
      }.max() ?? 0
      // 금액은 현재 표시 글꼴로 필요한 폭을 구해 숫자 중간 줄바꿈을 피한다.
      let valueWidth = (value.text ?? "").size(withAttributes: [.font: value.font ?? UIFont.preferredFont(forTextStyle: .headline)]).width
      // 가용 폭에서 두 열을 모두 읽을 수 있을 때만 가로 배치를 유지한다.
      let axis: NSLayoutConstraint.Axis = titleWidth + valueWidth + row.spacing > availableWidth ? .vertical : .horizontal
      if row.axis != axis {
        row.axis = axis
        row.alignment = axis == .vertical ? .fill : .center
      }
    }
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
    updateBorderColors()
  }

  private func styledLabel(
    size: CGFloat,
    weight: UIFont.Weight,
    style: UIFont.TextStyle = .subheadline
  ) -> UILabel {
    // 카드·입력 제목에 같은 Dynamic Type 정책을 적용한다.
    let label = FuturesText.label(style: style)
    label.font = UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size, weight: weight))
    label.textColor = .mobitColors(.tradeTextPrimary)
    return label
  }

  private func configurePositionCard() {
    guard let position = currentPosition() else { return }
    // 원본 포지션의 종목으로만 표시하며 시세 준비 여부와 분리한다.
    let symbol = FuturesText.symbol(position.order.instrument).marketSymbol
    // 외부 로고 요청 없이 코인 심볼을 구분하는 표식이다.
    let icon = styledLabel(size: 11, weight: .bold, style: .caption1)
    icon.text = symbol
    icon.textAlignment = .center
    icon.textColor = .white
    icon.backgroundColor = .mobitColors(.accentButton)
    icon.layer.cornerRadius = 18
    icon.clipsToBounds = true
    icon.numberOfLines = 1
    icon.adjustsFontSizeToFitWidth = true
    icon.minimumScaleFactor = 0.5
    icon.isAccessibilityElement = false
    icon.snp.makeConstraints { $0.size.equalTo(36) }
    // 포지션의 마켓 이름을 카드의 첫 정보로 표시한다.
    let market = styledLabel(size: 18, weight: .bold, style: .headline)
    market.text = FuturesText.symbol(position.order.instrument).replacingOccurrences(of: "/", with: " / ")
    market.accessibilityIdentifier = "futuresCloseMarket"
    // 실제 제공하는 상품·거래소만 설명한다.
    let subtitle = FuturesText.label(style: .caption1)
    subtitle.text = FuturesText.text("futures_" + position.order.instrument.exchange.rawValue) + " · " + FuturesText.text("futures_paper")
    subtitle.textColor = .mobitColors(.tradeTextSecondary)
    // 종목과 계좌 정보를 세로로 묶는다.
    let names = UIStackView(arrangedSubviews: [market, subtitle])
    names.axis = .vertical
    names.spacing = 3
    // 방향과 배수는 손익과 같은 사용자 색상 설정을 따른다.
    let side = styledLabel(size: 13, weight: .semibold)
    side.text = "\(FuturesText.side(position.order.side)) \(position.order.leverage)×"
    side.textColor = position.order.side == .long ? MarketColorPalette.riseColor : MarketColorPalette.fallColor
    side.accessibilityIdentifier = "futuresCloseSide"
    side.setContentHuggingPriority(.required, for: .horizontal)
    // 글자 수에 맞는 여백으로 배지를 구성한다.
    let badge = UIStackView(arrangedSubviews: [side])
    badge.isLayoutMarginsRelativeArrangement = true
    badge.directionalLayoutMargins = .init(top: 6, leading: 10, bottom: 6, trailing: 10)
    badge.backgroundColor = side.textColor.withAlphaComponent(0.10)
    badge.layer.cornerRadius = 14
    badge.setContentHuggingPriority(.required, for: .horizontal)
    badge.setContentCompressionResistancePriority(.required, for: .horizontal)
    // 이름은 줄바꿈하고 방향 배지는 읽을 수 있는 폭을 유지한다.
    let identity = UIStackView(arrangedSubviews: [icon, names, badge])
    identity.alignment = .center
    identity.spacing = 10
    // 현재가와 보유 수량은 독립된 두 열로 보여준다.
    let metrics = UIStackView()
    metrics.distribution = .fillEqually
    metrics.spacing = 12
    for (key, value) in [("futures_current", priceLabel), ("futures_close_holding", holdingLabel)] {
      // 각 수치의 의미를 알려주는 보조 제목이다.
      let title = FuturesText.label(style: .caption1)
      title.text = FuturesText.text(key)
      title.textColor = .mobitColors(.tradeTextSecondary)
      value.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .monospacedDigitSystemFont(ofSize: 15, weight: .semibold))
      value.textColor = .mobitColors(.tradeTextPrimary)
      value.text = "—"
      if value === holdingLabel { title.textAlignment = .right; value.textAlignment = .right }
      // 숫자가 길어지면 카드 높이가 자연스럽게 늘어난다.
      let column = UIStackView(arrangedSubviews: [title, value])
      column.axis = .vertical
      column.spacing = 5
      metrics.addArrangedSubview(column)
    }
    positionCard.axis = .vertical
    positionCard.spacing = 14
    positionCard.isLayoutMarginsRelativeArrangement = true
    positionCard.directionalLayoutMargins = .init(top: 16, leading: 16, bottom: 16, trailing: 16)
    positionCard.backgroundColor = .mobitColors(.tradeSurface)
    positionCard.layer.cornerRadius = 16
    positionCard.layer.borderWidth = 1
    positionCard.accessibilityIdentifier = "futuresClosePosition"
    [identity, separator(), metrics].forEach { positionCard.addArrangedSubview($0) }
  }

  private func configureInput(_ field: UITextField, key: String, identifier: String) {
    field.placeholder = "0"
    field.accessibilityLabel = FuturesText.text(key)
    field.accessibilityIdentifier = identifier
    field.font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: .monospacedDigitSystemFont(ofSize: 20, weight: .semibold))
    field.adjustsFontForContentSizeCategory = true
    field.adjustsFontSizeToFitWidth = true
    field.minimumFontSize = 14
    field.textColor = .mobitColors(.tradeTextPrimary)
    field.keyboardType = .decimalPad
    // 숫자 키보드에서도 예상 금액을 확인하고 입력을 마칠 수 있다.
    let toolbar = UIToolbar()
    toolbar.items = [
      UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
      UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(endEditing))
    ]
    toolbar.sizeToFit()
    field.inputAccessoryView = toolbar
    field.addTarget(self, action: #selector(inputChanged(_:)), for: .editingChanged)
    field.addTarget(self, action: #selector(finishInput(_:)), for: .editingDidEnd)
    field.addTarget(self, action: #selector(inputFocusChanged), for: [.editingDidBegin, .editingDidEnd])
  }

  private func inputRow(
    key: String,
    field: UITextField,
    unit: String,
    hint: UILabel,
    container: UIStackView
  ) -> UIView {
    // 제목과 최대 입력값을 같은 그룹 안에 표시한다.
    let title = styledLabel(size: 15, weight: .semibold)
    title.text = FuturesText.text(key)
    hint.textColor = .mobitColors(.tradeTextSecondary)
    hint.textAlignment = .right
    // 긴 번역·큰 금액은 각 열에서 줄바꿈한다.
    let header = UIStackView(arrangedSubviews: [title, hint])
    header.distribution = .fillEqually
    header.alignment = .center
    header.spacing = 8
    // 입력 내용과 분리해 단위가 편집되거나 가려지지 않게 한다.
    let unitLabel = styledLabel(size: 14, weight: .semibold)
    unitLabel.text = unit
    unitLabel.textColor = .mobitColors(.tradeTextSecondary)
    unitLabel.setContentHuggingPriority(.required, for: .horizontal)
    unitLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    container.addArrangedSubview(field)
    container.addArrangedSubview(unitLabel)
    container.alignment = .center
    container.spacing = 10
    container.isLayoutMarginsRelativeArrangement = true
    container.directionalLayoutMargins = .init(top: 14, leading: 16, bottom: 14, trailing: 16)
    container.backgroundColor = .mobitColors(.tradeControlSurface)
    container.layer.cornerRadius = 14
    container.layer.borderWidth = 1
    container.snp.makeConstraints { $0.height.greaterThanOrEqualTo(54) }
    // 폼은 기존 Auto Layout 구조 안에서 직접 배치한다.
    let row = UIStackView(arrangedSubviews: [header, container])
    row.axis = .vertical
    row.spacing = 8
    return row
  }

  private func separator() -> UIView {
    // 카드 내부의 정보 그룹을 분리하는 선이다.
    let line = UIView()
    line.backgroundColor = UIColor.mobitColors(.tradeSeparator).withAlphaComponent(0.6)
    line.snp.makeConstraints { $0.height.equalTo(1 / UIScreen.main.scale) }
    return line
  }

  private func configureSummary() {
    summaryStack.axis = .vertical
    summaryStack.spacing = 14
    summaryStack.isLayoutMarginsRelativeArrangement = true
    summaryStack.directionalLayoutMargins = .init(top: 16, leading: 16, bottom: 16, trailing: 16)
    summaryStack.backgroundColor = .mobitColors(.tradeControlSurface)
    summaryStack.layer.cornerRadius = 16
    summaryStack.layer.borderWidth = 1
    summaryStack.accessibilityIdentifier = "futuresCloseSummary"
    estimatedPnLLabel.accessibilityIdentifier = "futuresCloseEstimatedPnL"
    receivedAmountLabel.accessibilityIdentifier = "futuresCloseReceivedAmount"
    for (key, label) in [("futures_close_estimated_pnl", estimatedPnLLabel), ("futures_close_return", receivedAmountLabel)] {
      // 수령액을 가장 강하게 표시하고 손익은 별도 행으로 구분한다.
      let isReceived = label === receivedAmountLabel
      // 길어진 문구와 금액도 정해진 높이 없이 표시한다.
      let title = styledLabel(size: 14, weight: isReceived ? .semibold : .regular)
      title.text = FuturesText.text(key)
      title.textColor = .mobitColors(isReceived ? .tradeTextPrimary : .tradeTextSecondary)
      // 수령액의 구성은 확정 실현손익으로 오인하지 않게 설명한다.
      let captions = UIStackView(arrangedSubviews: [title])
      captions.axis = .vertical
      captions.spacing = 5
      if isReceived {
        summaryStack.addArrangedSubview(separator())
        // 선택한 수량에 해당하는 원금과 예상 손익의 합이다.
        let detail = FuturesText.label(style: .caption2)
        detail.text = FuturesText.text("futures_close_return_detail")
        detail.textColor = .mobitColors(.tradeTextSecondary)
        captions.addArrangedSubview(detail)
      }
      label.textAlignment = .right
      label.setContentHuggingPriority(.required, for: .horizontal)
      label.setContentCompressionResistancePriority(.required, for: .horizontal)
      label.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .monospacedDigitSystemFont(ofSize: isReceived ? 22 : 18, weight: .bold))
      label.textColor = .mobitColors(.tradeTextPrimary)
      // 공간이 부족하면 실제 텍스트 폭을 기준으로 세로 배치한다.
      let row = UIStackView(arrangedSubviews: [captions, label])
      row.alignment = .center
      row.distribution = .fill
      row.spacing = 12
      row.isAccessibilityElement = true
      row.accessibilityLabel = title.text
      summaryStack.addArrangedSubview(row)
    }
    clearSummary()
  }

  @objc private func inputFocusChanged() { updateBorderColors() }

  private func updateBorderColors() {
    for case let button as UIButton in percentButtons.arrangedSubviews {
      button.layer.borderColor = UIColor.mobitColors(button.isSelected ? .accentPrimary : .tradeSeparator).resolvedColor(with: traitCollection).cgColor
    }
    for card in [positionCard, summaryStack] {
      card.layer.borderColor = UIColor.mobitColors(.tradeSeparator).withAlphaComponent(0.6).resolvedColor(with: traitCollection).cgColor
    }
    for (field, container) in [(amountTextField, amountInputContainer), (quantityTextField, quantityInputContainer)] {
      container.layer.borderColor = UIColor.mobitColors(field.isFirstResponder ? .accentPrimary : .tradeSeparator).resolvedColor(with: traitCollection).cgColor
      container.layer.borderWidth = field.isFirstResponder ? 1.5 : 1
    }
  }

  private func updatePercentSelection(_ percent: Decimal?) {
    updateText(percentLabel, text: percent.map { FuturesText.number($0, digits: 2) + "%" } ?? "—")
    // 수량 절삭 오차로 배지의 표시 비율과 선택 버튼이 달라지지 않게 한다.
    let displayedPercent = percent.map { value -> Decimal in
      // 원본 계산값은 보존하고 표시용 비율만 소수 둘째 자리로 맞춘다.
      var original = value
      // 버튼 선택에 사용하는 반올림 결과다.
      var rounded = Decimal()
      NSDecimalRound(&rounded, &original, 2, .plain)
      return rounded
    }
    for case let button as UIButton in percentButtons.arrangedSubviews {
      button.isSelected = displayedPercent == Decimal(button.tag)
      button.accessibilityTraits = button.isSelected ? [.button, .selected] : .button
      button.setTitleColor(.mobitColors(button.isSelected ? .accentPrimary : .tradeTextSecondary), for: .normal)
      button.setTitleColor(.mobitColors(.accentPrimary), for: .selected)
      button.backgroundColor = .mobitColors(button.isSelected ? .tradeSurface : .tradeControlSurface)
      button.layer.borderColor = UIColor.mobitColors(button.isSelected ? .accentPrimary : .tradeSeparator).resolvedColor(with: traitCollection).cgColor
      button.layer.borderWidth = button.isSelected ? 2 : 1
    }
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

  @objc private func percentConfirmed() {
    sendCloseClick("선물_종료비율_선택", detail: "\(Int(percentControl.value))%")
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    sendCloseClick("선물_종료시트_취소", detail: "드래그_닫기")
  }

  private func currentPosition() -> FuturesPosition? {
    reactor.positions.first { $0.id == positionID }
  }

  private func render() {
    // 입력값은 유지하며 시세와 실제 제출 가능 조건을 함께 갱신한다.
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
    // 표시와 제출 가능 판정에 동일한 포지션과 캡처 시세를 사용한다.
    let position = currentPosition()
    // 화면 갱신 중 중복 캡처로 서로 다른 가격을 판정하지 않게 한다.
    let price = captureOrderPrice()
    // 연결·검증 상태는 탭 시 안내하고 실제 제출 중에만 버튼을 잠근다.
    if closeButton.isEnabled != enabled { closeButton.isEnabled = enabled }
    updateText(statusLabel, text: FuturesText.status(reactor))
    guard let position else {
      clearSummary()
      return
    }
    // 포지션 정보와 입력 한도는 시세 수신 전에도 저장된 원본으로 표시한다.
    let symbol = FuturesText.symbol(position.order.instrument).marketSymbol
    updateText(holdingLabel, text: FuturesText.number(position.quantity) + " " + symbol)
    updateText(maximumAmountLabel, text: String(format: FuturesText.text("futures_close_maximum"), FuturesText.number(try? position.margin), FuturesText.text("currency_krw_unit")))
    updateText(maximumQuantityLabel, text: String(format: FuturesText.text("futures_close_maximum"), FuturesText.number(position.quantity), symbol))
    guard let price, price.quote.instrument == position.order.instrument else {
      // 연결 대기 중에는 마지막 평가를 유지하고 제출할 때 최신 가격을 확인한다.
      return
    }
    // 표시 문자열이 같으면 라벨의 레이아웃을 다시 무효화하지 않는다.
    updateText(priceLabel, text: FuturesText.number(price.quote.price) + " " + FuturesText.text("currency_krw_unit"))
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
      updatePercentSelection(percent)
      guard quantity > 0 else {
        clearSummary()
        return
      }
      // 종료 수량의 원금과 손익만 돌려주는 예상 정산 결과다.
      let quote = try FuturesCalculator.closingQuote(
        position,
        executionPrice: price.quote.price,
        exitFeeRate: TradingRules.Futures.closingFeeRate(for: position.order.instrument),
        quantity: quantity
      )
      updateText(receivedAmountLabel, text: "\(FuturesText.number(quote.returnedMargin)) \(FuturesText.text("currency_krw_unit"))")
      updateText(estimatedPnLLabel, text: "\(quote.realizedPnL > 0 ? "+" : "")\(FuturesText.number(quote.realizedPnL)) \(FuturesText.text("currency_krw_unit"))")
      estimatedPnLLabel.textColor = quote.realizedPnL == 0 ? .mobitColors(.tradeTextPrimary)
        : (quote.realizedPnL > 0 ? MarketColorPalette.riseColor : MarketColorPalette.fallColor)
      updateSummaryAccessibility()
    } catch {
      updatePercentSelection(nil)
      clearSummary()
      if case .amount = selection { updateText(quantityTextField, text: nil) }
      if case .quantity = selection { updateText(amountTextField, text: nil) }
    }
  }

  private func clearSummary() {
    updateText(estimatedPnLLabel, text: "—")
    updateText(receivedAmountLabel, text: "—")
    estimatedPnLLabel.textColor = .mobitColors(.tradeTextPrimary)
    updateSummaryAccessibility()
  }

  private func updateSummaryAccessibility() {
    for (row, label) in zip(summaryStack.arrangedSubviews.compactMap { $0 as? UIStackView }, [estimatedPnLLabel, receivedAmountLabel]) {
      row.accessibilityValue = label.text
    }
  }

  private func updateText(_ label: UILabel, text: String?) {
    if label.text != text { label.text = text }
  }

  private func updateText(_ field: UITextField, text: String?) {
    if field.text != (text ?? "") { field.text = text }
  }

  private func submit() {
    guard !didSubmit, !reactor.currentState.submitting, presentedViewController == nil else { return }
    guard let position = currentPosition() else {
      sendCloseClick("선물_주문_차단", detail: "포지션_종료됨")
      showCloseError(FuturesText.text("futures_position_closed"))
      return
    }
    guard let selection else {
      sendCloseClick("선물_주문_차단", detail: "종료_입력오류")
      showCloseError(FuturesText.text("futures_close_invalid"))
      return
    }
    do {
      // 현재 남은 원금을 기준으로 수량을 확인하고 체결 가격만 최신 소켓 값으로 고정한다.
      let quantity = try selection.calculateQuantity(position: position)
      guard quantity > 0 else { throw FuturesCalculationError.invalidNumber }
      // 버튼 표시와 무관하게 제출 순간의 자산·연결·가격 조건을 모두 검증한다.
      let price = captureOrderPrice()
      if let message = FuturesText.orderError(reactor, instrument: position.order.instrument, price: price) {
        sendCloseClick("선물_주문_차단", detail: orderBlockReason)
        showCloseError(message)
        return
      }
      guard let price else { return }
      // 시세로 종료가 불가능해진 경우에도 버튼 대신 탭 시점에 요청을 막는다.
      let quote = try FuturesCalculator.closingQuote(
        position,
        executionPrice: price.quote.price,
        exitFeeRate: TradingRules.Futures.closingFeeRate(for: position.order.instrument),
        quantity: quantity
      )
      guard quote.returnedMargin > 0 else {
        sendCloseClick("선물_주문_차단", detail: "청산_대기")
        showCloseError(FuturesText.text("futures_retry_order"))
        return
      }
      view.endEditing(true)
      reactor.action.onNext(.clearMessage)
      didSubmit = true
      reactor.action.onNext(.closeQuantity(positionID, quantity, position.quantity, price))
    } catch {
      sendCloseClick("선물_주문_차단", detail: "종료_입력오류")
      showCloseError(FuturesText.text("futures_close_invalid"))
    }
  }

  private var orderBlockReason: String {
    if reactor.currentState.networkAvailable == false { return "네트워크_연결끊김" }
    if reactor.currentState.loadFailed || reactor.currentState.dataFailure?.hold == .storageFailed { return "저장_조회실패" }
    if reactor.needsDataRetry { return "과거검증_실패" }
    if !reactor.canSubmit { return "과거검증_미완료" }
    return "시세_준비안됨"
  }

  private func sendCloseClick(_ action: String, detail: String? = nil) {
    // 종료 비율·취소 방식은 실패 사유로 집계하지 않는다.
    var parameters: [String: Any] = ["order_type": "종료"]
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

  private func showCloseError(_ message: String) {
    guard presentedViewController == nil else { return }
    view.endEditing(true)
    // 제출을 막은 이유를 스크롤 위치와 무관하게 바로 안내한다.
    let alert = UIAlertController(title: FuturesText.text("futures_close"), message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: FuturesText.text("common_confirm"), style: .default))
    present(alert, animated: true)
  }
}
