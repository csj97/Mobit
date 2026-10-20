import SnapKit
import UIKit

final class ExchangeSelectionSheetViewController: UIViewController {
  private enum Layout {
    // 제목과 카드, 확인 버튼에 같은 좌우 여백을 적용한다.
    static let horizontalInset: CGFloat = 24
    // 시스템 손잡이 아래에서 본문이 시작되는 여백이다.
    static let contentTopInset: CGFloat = 20
    // 카드 목록과 확인 버튼을 구분하는 여백이다.
    static let confirmationSpacing: CGFloat = 24
    // 확인 버튼을 하단 안전 영역에서 띄운다.
    static let confirmationBottomInset: CGFloat = 20
    // 확인 버튼의 최소 높이는 배치와 자연 높이 측정에 함께 사용한다.
    static let confirmationMinimumHeight: CGFloat = 48
  }

  // 확인하기 전의 선택은 시트 안에서만 유지한다.
  private var selectedExchange: Exchange
  // 시트가 닫힌 뒤 기존 거래소 전환 경로에 선택을 전달한다.
  private let callBack: (Exchange) -> Void
  // 본문이 화면 최대 높이를 넘는 경우에만 스크롤한다.
  private let scrollView = UIScrollView()
  // 본문의 자연 높이를 측정해 시트 높이에 반영한다.
  private let contentStackView = UIStackView()
  // 제목과 닫기 버튼을 같은 행에 배치한다.
  private let titleStackView = UIStackView()
  // 시트가 거래소 선택 단계임을 안내한다.
  private let titleLabel = UILabel()
  // 모의투자에 사용할 거래소 선택을 안내한다.
  private let descriptionLabel = UILabel()
  // 현재 선택을 적용하지 않고 닫는다.
  private let closeButton = UIButton(type: .system)
  // 본문을 스크롤해도 선택 완료 동작은 하단에 유지한다.
  private let confirmButton = UIButton(type: .system)
  // 지원하는 국내 거래소만 선택지로 제공한다.
  private lazy var exchangeOptions = [Exchange.upbit, .bithumb].map { exchange in
    ExchangeSelectionOptionButton(exchange: exchange) { [weak self] in
      self?.selectExchange(exchange)
    }
  }

  init(
    selectedExchange: Exchange,
    callBack: @escaping (Exchange) -> Void
  ) {
    self.selectedExchange = selectedExchange == .bithumb ? .bithumb : .upbit
    self.callBack = callBack
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .pageSheet
    sheetPresentationController?.detents = [
      .custom(identifier: .init("investment.exchange.content")) { [weak self] context in
        // 최초 측정 전에는 시스템이 허용하는 높이 안에서 표시한다.
        guard let height = self?.preferredContentSize.height, height > 0 else {
          return context.maximumDetentValue
        }
        return min(height, context.maximumDetentValue)
      }
    ]
    sheetPresentationController?.prefersGrabberVisible = true
    sheetPresentationController?.preferredCornerRadius = 24
    sheetPresentationController?.prefersEdgeAttachedInCompactHeight = true
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    configureUI()
    selectExchange(selectedExchange)
  }

  func prepareSheet(for width: CGFloat) {
    loadViewIfNeeded()
    updateTextLayout()
    updatePreferredSheetSize(for: width)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updatePreferredSheetSize(for: view.safeAreaLayoutGuide.layoutFrame.width)
  }

  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    guard isViewLoaded else { return }
    view.setNeedsLayout()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard isViewLoaded else { return }
    updateTextLayout()
    view.setNeedsLayout()
  }

  private func configureUI() {
    view.backgroundColor = .mobitColors(.investmentBackground)
    view.accessibilityIdentifier = "investment.exchangeSheet"
    view.accessibilityViewIsModal = true

    titleLabel.text = FuturesText.text("investment_select_exchange")
    titleLabel.textColor = .mobitColors(.investmentTextPrimary)
    titleLabel.numberOfLines = 0
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.accessibilityTraits.insert(.header)
    titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    closeButton.setImage(
      UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)),
      for: .normal
    )
    closeButton.tintColor = .mobitColors(.investmentTextTertiary)
    closeButton.accessibilityIdentifier = "investment.exchangeClose"
    closeButton.accessibilityLabel = FuturesText.text("settings_close")
    closeButton.addTarget(self, action: #selector(closeSheet), for: .touchUpInside)
    closeButton.snp.makeConstraints { $0.width.height.equalTo(44) }
    titleStackView.alignment = .center
    titleStackView.spacing = 8
    titleStackView.addArrangedSubview(titleLabel)
    titleStackView.addArrangedSubview(closeButton)

    descriptionLabel.text = FuturesText.text("investment_exchange_description")
    descriptionLabel.textColor = .mobitColors(.investmentTextSecondary)
    descriptionLabel.numberOfLines = 0
    descriptionLabel.adjustsFontForContentSizeCategory = true
    descriptionLabel.setContentCompressionResistancePriority(.required, for: .vertical)

    contentStackView.axis = .vertical
    contentStackView.spacing = 4
    contentStackView.addArrangedSubview(titleStackView)
    contentStackView.addArrangedSubview(descriptionLabel)
    contentStackView.setCustomSpacing(20, after: descriptionLabel)
    // 두 거래소의 높이는 각 이름과 설명의 실제 길이에 따라 늘어난다.
    let optionsStackView = UIStackView(arrangedSubviews: exchangeOptions)
    optionsStackView.axis = .vertical
    optionsStackView.spacing = 12
    contentStackView.addArrangedSubview(optionsStackView)

    scrollView.showsVerticalScrollIndicator = false
    scrollView.alwaysBounceVertical = false
    scrollView.isScrollEnabled = false
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.accessibilityIdentifier = "investment.exchangeScroll"
    view.addSubview(scrollView)
    scrollView.addSubview(contentStackView)
    contentStackView.snp.makeConstraints {
      $0.edges.equalTo(scrollView.contentLayoutGuide)
      $0.width.equalTo(scrollView.frameLayoutGuide)
    }

    confirmButton.accessibilityIdentifier = "investment.exchangeConfirm"
    confirmButton.titleLabel?.adjustsFontForContentSizeCategory = true
    confirmButton.titleLabel?.numberOfLines = 0
    confirmButton.titleLabel?.textAlignment = .center
    confirmButton.addTarget(self, action: #selector(confirmExchange), for: .touchUpInside)
    view.addSubview(confirmButton)
    confirmButton.snp.makeConstraints {
      $0.horizontalEdges.equalTo(view.safeAreaLayoutGuide).inset(Layout.horizontalInset)
      $0.bottom.equalTo(view.safeAreaLayoutGuide).inset(Layout.confirmationBottomInset)
      $0.height.greaterThanOrEqualTo(Layout.confirmationMinimumHeight)
    }
    scrollView.snp.makeConstraints {
      $0.top.equalTo(view.safeAreaLayoutGuide).offset(Layout.contentTopInset)
      $0.horizontalEdges.equalTo(view.safeAreaLayoutGuide).inset(Layout.horizontalInset)
      $0.bottom.equalTo(confirmButton.snp.top).offset(-Layout.confirmationSpacing)
    }
    updateTextLayout()
  }

  private func updateTextLayout() {
    titleLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
      for: .systemFont(ofSize: 18, weight: .bold),
      compatibleWith: traitCollection
    )
    descriptionLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
      for: .systemFont(ofSize: 12),
      compatibleWith: traitCollection
    )
    // 버튼 글꼴도 현재 글자 크기에 맞춰 갱신한다.
    var confirmStyle = UIButton.Configuration.filled()
    confirmStyle.title = FuturesText.text("investment_exchange_confirm")
    confirmStyle.baseBackgroundColor = .mobitColors(.accountAction)
    confirmStyle.baseForegroundColor = .white
    confirmStyle.cornerStyle = .fixed
    confirmStyle.background.cornerRadius = 12
    confirmStyle.contentInsets = .init(top: 14, leading: 16, bottom: 14, trailing: 16)
    confirmStyle.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { [weak self] incoming in
      // 시스템 버튼 속성에 이 화면의 확인 버튼 글꼴만 반영한다.
      var outgoing = incoming
      outgoing.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
        for: .systemFont(ofSize: 15, weight: .bold),
        compatibleWith: self?.traitCollection
      )
      return outgoing
    }
    confirmButton.configuration = confirmStyle
    exchangeOptions.forEach { $0.updateTextLayout() }
  }

  private func selectExchange(_ exchange: Exchange) {
    guard confirmButton.isEnabled, !isBeingDismissed else { return }
    selectedExchange = exchange
    exchangeOptions.forEach { $0.isSelected = $0.exchange == exchange }
    view.setNeedsLayout()
  }

  @objc private func closeSheet() {
    guard confirmButton.isEnabled, !isBeingDismissed else { return }
    confirmButton.isEnabled = false
    dismiss(animated: true)
  }

  @objc private func confirmExchange() {
    guard confirmButton.isEnabled, !isBeingDismissed else { return }
    confirmButton.isEnabled = false
    // 닫히는 동안 선택이 바뀌거나 화면이 해제되어도 같은 거래소를 전달한다.
    let exchange = selectedExchange
    // 기존 화면을 교체하는 전환은 시트가 사라진 뒤 한 번만 실행한다.
    let completion = callBack
    dismiss(animated: true) { completion(exchange) }
  }

  private func updatePreferredSheetSize(for width: CGFloat) {
    guard width > Layout.horizontalInset * 2 else { return }
    // 스크롤 여부와 무관하게 본문 전체의 자연 높이를 측정한다.
    let contentHeight = contentStackView.systemLayoutSizeFitting(
      CGSize(width: width - Layout.horizontalInset * 2, height: 0),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
    // 큰 글자에서 높아진 확인 버튼도 콘텐츠 높이에 포함한다.
    let confirmHeight = confirmButton.systemLayoutSizeFitting(
      CGSize(width: width - Layout.horizontalInset * 2, height: 0),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
    // 버튼의 fitting 값은 실제 최소 높이보다 작을 수 있어 배치 기준을 함께 반영한다.
    let actionHeight = max(confirmHeight, Layout.confirmationMinimumHeight)
    // 시스템이 더하는 하단 안전 영역을 제외하고 상단 안전 영역과 실제 배치 여백을 합친다.
    let verticalInsets = view.safeAreaInsets.top + Layout.contentTopInset + Layout.confirmationSpacing + Layout.confirmationBottomInset
    // 글자와 카드의 자연 높이가 변한 경우에만 시트 높이를 갱신한다.
    let size = CGSize(width: width, height: ceil(contentHeight + actionHeight + verticalInsets))
    if preferredContentSize != size {
      preferredContentSize = size
      sheetPresentationController?.invalidateDetents()
    }
    updateScrolling(contentHeight: contentHeight)
  }

  private func updateScrolling(contentHeight: CGFloat) {
    guard scrollView.bounds.height > 0 else { return }
    // 픽셀 반올림 차이로 화면에 맞는 본문을 스크롤하지 않는다.
    let pixelTolerance = 1 / max(traitCollection.displayScale, 1)
    // 큰 글자에서 복귀할 때 아직 갱신되지 않은 contentSize 대신 방금 측정한 높이를 사용한다.
    scrollView.isScrollEnabled = contentHeight > scrollView.bounds.height + pixelTolerance
    if !scrollView.isScrollEnabled, scrollView.contentOffset != .zero {
      scrollView.setContentOffset(.zero, animated: false)
    }
  }
}

private final class ExchangeSelectionOptionButton: UIButton {
  // 행의 선택을 실제 거래소와 연결한다.
  let exchange: Exchange
  // 시트 안의 임시 선택만 갱신한다.
  private let callBack: () -> Void
  // 앱에서 사용하는 기존 거래소 로고를 표시한다.
  private let logoImageView = UIImageView()
  // 거래소명과 선택 배지를 함께 배치한다.
  private let nameStackView = UIStackView()
  // 이름과 배지가 벌어지지 않도록 남는 가로 공간만 채운다.
  private let nameSpacerView = UIView()
  // 카드에서 가장 먼저 읽는 거래소 이름이다.
  private let nameLabel = UILabel()
  // 색상 외에 현재 선택 상태를 글자로도 표시한다.
  private let selectedBadgeLabel = ExchangeSelectionBadgeLabel()
  // 두 모의투자 상품을 지원함을 안내한다.
  private let supportLabel = UILabel()
  // 이름과 설명의 높이에 따라 카드 높이를 늘린다.
  private let detailsStackView = UIStackView()
  // 선택 상태는 체크 또는 빈 원으로 구분한다.
  private let selectionImageView = UIImageView()

  override var isSelected: Bool {
    didSet { updateSelection() }
  }

  init(exchange: Exchange, callBack: @escaping () -> Void) {
    self.exchange = exchange
    self.callBack = callBack
    super.init(frame: .zero)
    configureUI()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    updateTextLayout()
    updateSelection()
  }

  private func configureUI() {
    layer.cornerRadius = 16
    layer.cornerCurve = .continuous
    accessibilityIdentifier = "investment.exchangeOption.\(exchange.rawValue)"
    isAccessibilityElement = true
    addTarget(self, action: #selector(selectOption), for: .touchUpInside)

    logoImageView.image = UIImage(named: exchange == .upbit ? "upbit_logo" : "bithumb_logo")
    logoImageView.contentMode = .scaleAspectFit
    logoImageView.layer.cornerRadius = 12
    logoImageView.clipsToBounds = true
    logoImageView.snp.makeConstraints { $0.width.height.equalTo(40) }

    nameLabel.text = FuturesText.text(exchange == .upbit ? "futures_upbit" : "futures_bithumb")
    nameLabel.textColor = .mobitColors(.investmentTextPrimary)
    nameLabel.numberOfLines = 0
    nameLabel.adjustsFontForContentSizeCategory = true
    nameLabel.setContentHuggingPriority(.required, for: .horizontal)
    selectedBadgeLabel.text = FuturesText.text("investment_exchange_selected")
    selectedBadgeLabel.textColor = .white
    selectedBadgeLabel.backgroundColor = .systemBlue
    selectedBadgeLabel.layer.cornerRadius = 4
    selectedBadgeLabel.clipsToBounds = true
    selectedBadgeLabel.adjustsFontForContentSizeCategory = true
    selectedBadgeLabel.setContentHuggingPriority(.required, for: .horizontal)
    selectedBadgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    nameStackView.addArrangedSubview(nameLabel)
    nameStackView.addArrangedSubview(selectedBadgeLabel)
    nameSpacerView.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
    nameSpacerView.snp.makeConstraints {
      $0.height.equalTo(0)
      $0.width.greaterThanOrEqualTo(0)
    }
    nameStackView.addArrangedSubview(nameSpacerView)
    nameStackView.spacing = 6

    supportLabel.text = FuturesText.text("investment_exchange_support")
    supportLabel.textColor = .mobitColors(.investmentTextSecondary)
    supportLabel.numberOfLines = 0
    supportLabel.adjustsFontForContentSizeCategory = true
    supportLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    detailsStackView.axis = .vertical
    detailsStackView.spacing = 4
    detailsStackView.addArrangedSubview(nameStackView)
    detailsStackView.addArrangedSubview(supportLabel)

    selectionImageView.contentMode = .scaleAspectFit
    selectionImageView.snp.makeConstraints { $0.width.height.equalTo(24) }
    // 로고와 선택 표시는 고정하고 설명에 줄바꿈 공간을 제공한다.
    let rowStackView = UIStackView(arrangedSubviews: [logoImageView, detailsStackView, selectionImageView])
    rowStackView.alignment = .center
    rowStackView.spacing = 12
    rowStackView.isUserInteractionEnabled = false
    addSubview(rowStackView)
    rowStackView.snp.makeConstraints { $0.edges.equalToSuperview().inset(14) }
    snp.makeConstraints { $0.height.greaterThanOrEqualTo(72) }
    updateTextLayout()
    updateSelection()
  }

  func updateTextLayout() {
    nameLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
      for: .systemFont(ofSize: 15, weight: .bold),
      compatibleWith: traitCollection
    )
    selectedBadgeLabel.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(
      for: .systemFont(ofSize: 10, weight: .bold),
      compatibleWith: traitCollection
    )
    supportLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
      for: .systemFont(ofSize: 12),
      compatibleWith: traitCollection
    )
    nameStackView.axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
    nameStackView.alignment = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .leading : .center
    nameSpacerView.isHidden = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
  }

  private func updateSelection() {
    backgroundColor = isSelected ? .mobitColors(.investmentSurface) : .mobitColors(.investmentBackground)
    layer.borderWidth = isSelected ? 2 : 1
    layer.borderColor = (isSelected ? UIColor.mobitColors(.accountAction) : UIColor.mobitColors(.investmentSeparator)).resolvedColor(with: traitCollection).cgColor
    selectedBadgeLabel.isHidden = !isSelected
    selectionImageView.image = UIImage(
      systemName: isSelected ? "checkmark.circle.fill" : "circle",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
    )
    selectionImageView.tintColor = isSelected ? .systemBlue : .mobitColors(.investmentTextTertiary)
    accessibilityLabel = nameLabel.text
    accessibilityValue = supportLabel.text
    accessibilityTraits = isSelected ? [.button, .selected] : [.button]
  }

  @objc private func selectOption() { callBack() }
}

private final class ExchangeSelectionBadgeLabel: UILabel {
  // 배지 글자가 배경 모서리에 붙지 않도록 여백을 둔다.
  private let textInsets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)

  override var intrinsicContentSize: CGSize {
    // 선택되지 않은 행에서는 배지 공간도 제거한다.
    guard !isHidden else { return .zero }
    // 글자와 배경 사이 여백을 배지의 자연 크기에 포함한다.
    let size = super.intrinsicContentSize
    return CGSize(width: size.width + 12, height: size.height + 4)
  }

  override var isHidden: Bool {
    didSet { invalidateIntrinsicContentSize() }
  }

  override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: textInsets)) }
}
