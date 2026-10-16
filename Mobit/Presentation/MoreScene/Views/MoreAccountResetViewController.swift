import RxSwift
import SnapKit
import UIKit

final class MoreAccountResetViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
  private enum Layout {
    // 시스템 손잡이와 제목 사이의 여백이다.
    static let headerTop: CGFloat = 28
    // 시트의 제목과 계좌 카드에 같은 좌우 여백을 사용한다.
    static let contentInset: CGFloat = 24
    // 본문 위아래 여백도 콘텐츠 높이 측정에 포함한다.
    static let bodyInset: CGFloat = 16
    // 고정 버튼을 화면 가장자리에서 띄운다.
    static let actionsInset: CGFloat = 16
  }

  // 계좌 선택을 바꾸거나 저장하지 않고 실제 잔액만 읽는다.
  private let accountsUseCase: MoreAccountsUseCase
  // 초기화할 계좌는 사용자가 이 시트 안에서 선택한 값으로 유지한다.
  private var selectedAccount: TradingAccountID
  // 선택과 별개로 시트를 열 당시 사용 중인 계좌를 표시한다.
  private let currentAccount: TradingAccountID
  // 시트가 닫힌 뒤 초기화할 계좌를 전달한다.
  private let callBack: (TradingAccountID) -> Void
  // 안전 영역 안에 고정 헤더와 본문, 버튼을 배치한다.
  private let containerView = UIView()
  // 설명과 닫기 버튼을 포함한 헤더의 실제 높이를 측정한다.
  private let headerStackView = UIStackView()
  // 큰 글자에서는 제목과 설명을 본문으로 옮겨 버튼 영역을 보존한다.
  private let headerTextStackView = UIStackView()
  // 보통 글자 크기에서는 제목과 초기화 배지를 한 줄로 표시한다.
  private let titleStackView = UIStackView()
  // 초기화할 계좌를 선택하는 시트임을 안내한다.
  private let titleLabel = AccountResetContentLabel(textStyle: .title2)
  // 초기화 기능의 주의를 제목 옆 배지로 표시한다.
  private let resetBadgeLabel = AccountResetBadgeLabel()
  // 계좌 선택 단계의 사용 방법을 설명한다.
  private let descriptionLabel = FuturesText.label(style: .footnote)
  // 취소와 같은 동작을 제공하는 44포인트 닫기 버튼이다.
  private let closeButton = UIButton(type: .system)
  // 큰 글자와 작은 화면에서 계좌 목록만 스크롤한다.
  private let scrollView = UIScrollView()
  // 계좌 목록과 읽기 오류, 초기화 주의를 콘텐츠 높이로 묶는다.
  private let bodyStackView = UIStackView()
  // 접근성 글자에서는 제목과 안내도 본문과 함께 스크롤한다.
  private let bodyIntroStackView = UIStackView()
  // 저장소 읽기에 실패했을 때만 재시도를 표시한다.
  private let errorStackView = UIStackView()
  // 실패한 잔액을 0원으로 오해하지 않도록 오류를 설명한다.
  private let errorLabel = FuturesText.label(style: .footnote)
  // 실패한 잔액 읽기를 같은 선택 상태에서 다시 실행한다.
  private let retryButton = UIButton(type: .system)
  // 초기화 정책은 시안의 예시 지급액 대신 기존 정책을 안내한다.
  private let warningLabel = FuturesText.label(style: .footnote)
  // 파괴적인 동작의 범위를 별도 카드로 표시한다.
  private let warningView = UIView()
  // 고정 버튼은 접근성 글자 크기에서 세로로 배치한다.
  private let actionsStackView = UIStackView()
  // 선택을 저장하지 않고 시트를 닫는다.
  private let cancelButton = UIButton(type: .system)
  // 주의사항을 확인하고 선택한 계좌의 초기화를 요청한다.
  private let confirmButton = UIButton(type: .system)
  // 가로 배치에서는 초기화 버튼에 더 넓은 공간을 제공한다.
  private lazy var actionsWidthConstraint = confirmButton.widthAnchor.constraint(equalTo: cancelButton.widthAnchor, multiplier: 1.5)
  // 초기 읽기와 재시도를 한 구독으로 관리한다.
  private let reloadBalances = PublishSubject<Void>()
  // 시트가 해제되면 진행 중인 읽기 구독도 종료한다.
  private let disposeBag = DisposeBag()
  // 잔액 갱신은 행을 재생성하지 않아 사용자 선택이 유지된다.
  private lazy var accountRows = MoreAccountsUseCase.accounts.map { account in
    AccountResetRow(account: account, current: account == currentAccount) { [weak self] in
      self?.selectAccount(account)
    }
  }

  init(
    accountsUseCase: MoreAccountsUseCase,
    currentAccount: TradingAccountID,
    callBack: @escaping (TradingAccountID) -> Void
  ) {
    self.accountsUseCase = accountsUseCase
    self.currentAccount = currentAccount
    self.selectedAccount = MoreAccountsUseCase.accounts.contains(currentAccount) ? currentAccount : MoreAccountsUseCase.accounts[0]
    self.callBack = callBack
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .pageSheet
    sheetPresentationController?.detents = [
      .custom(identifier: .init("reset.content")) { [weak self] context in
        // 실제 콘텐츠 측정 전에는 시스템이 허용하는 높이를 사용한다.
        guard let height = self?.preferredContentSize.height, height > 0 else { return context.maximumDetentValue }
        return min(height, context.maximumDetentValue)
      }
    ]
    sheetPresentationController?.prefersGrabberVisible = true
    sheetPresentationController?.preferredCornerRadius = 32
    sheetPresentationController?.prefersEdgeAttachedInCompactHeight = true
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    configureUI()
    bindActions()
    selectAccount(selectedAccount)
    bindBalances()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    presentationController?.delegate = self
    MobitAnalyticsUtil.sendScreenEvent(
      location: "더보기_화면",
      stepDepth01: "더보기_초기화",
      stepDepth02: "초기화_시트_노출",
      account: selectedAccount,
      extraParameters: ["selection_source": "기본_선택"]
    )
  }

  func prepareSheet(for width: CGFloat) {
    loadViewIfNeeded()
    updateTextLayout(for: width)
    updatePreferredSheetSize(for: width)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    accountRows.forEach { $0.updateWidthLayout(for: containerView.bounds.width - Layout.contentInset * 2) }
    updatePreferredSheetSize(for: containerView.bounds.width)
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard isViewLoaded else { return }
    updateTextLayout(for: containerView.bounds.width)
    updateColors()
    view.setNeedsLayout()
  }

  private func configureUI() {
    view.backgroundColor = .mobitColors(.surfaceElevated)
    containerView.backgroundColor = .mobitColors(.surfaceElevated)
    containerView.accessibilityIdentifier = "reset.card"
    view.addSubview(containerView)
    containerView.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }

    titleLabel.text = FuturesText.text("more_reset_sheet_title")
    titleLabel.accessibilityTraits.insert(.header)
    titleLabel.setContentHuggingPriority(.required, for: .horizontal)
    // 스택이 여러 줄 제목을 절반 폭으로 제한하는 내부 우선순위 950보다 높게 유지한다.
    titleLabel.setContentCompressionResistancePriority(UILayoutPriority(999), for: .horizontal)
    titleLabel.setContentCompressionResistancePriority(UILayoutPriority(751), for: .vertical)
    resetBadgeLabel.text = FuturesText.text("more_reset_badge")
    resetBadgeLabel.textColor = AccountResetColors.warningText
    resetBadgeLabel.backgroundColor = AccountResetColors.warningBackground
    resetBadgeLabel.layer.cornerRadius = 12
    resetBadgeLabel.clipsToBounds = true
    titleStackView.addArrangedSubview(titleLabel)
    titleStackView.addArrangedSubview(resetBadgeLabel)
    // 남는 헤더 폭은 빈 영역이 받아 제목과 배지 사이 간격을 유지한다.
    let titleSpacerView = UIView()
    titleSpacerView.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
    titleSpacerView.snp.makeConstraints {
      $0.height.equalTo(0)
      $0.width.greaterThanOrEqualTo(0)
    }
    titleStackView.addArrangedSubview(titleSpacerView)
    titleStackView.alignment = .center
    titleStackView.spacing = 8
    descriptionLabel.text = FuturesText.text("more_reset_sheet_description")
    descriptionLabel.textColor = .mobitColors(.textSecondary)
    descriptionLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    headerTextStackView.addArrangedSubview(titleStackView)
    headerTextStackView.addArrangedSubview(descriptionLabel)
    headerTextStackView.axis = .vertical
    headerTextStackView.spacing = 6
    closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)), for: .normal)
    closeButton.tintColor = .mobitColors(.textSecondary)
    closeButton.backgroundColor = AccountResetColors.controlBackground
    closeButton.layer.cornerRadius = 22
    closeButton.accessibilityIdentifier = "reset.close"
    closeButton.accessibilityLabel = FuturesText.text("settings_close")
    closeButton.snp.makeConstraints { $0.width.height.equalTo(44) }
    headerStackView.addArrangedSubview(headerTextStackView)
    headerStackView.addArrangedSubview(closeButton)
    headerStackView.alignment = .top
    headerStackView.spacing = 12
    containerView.addSubview(headerStackView)
    headerStackView.snp.makeConstraints {
      $0.horizontalEdges.equalToSuperview().inset(Layout.contentInset)
      $0.top.equalToSuperview().inset(Layout.headerTop)
    }
    // 제목과 계좌 선택 영역을 옅은 선으로 구분한다.
    let headerDivider = UIView()
    headerDivider.backgroundColor = .mobitColors(.borderPrimary).withAlphaComponent(0.45)
    containerView.addSubview(headerDivider)
    headerDivider.snp.makeConstraints {
      $0.top.equalTo(headerStackView.snp.bottom).offset(Layout.bodyInset)
      $0.horizontalEdges.equalToSuperview()
      $0.height.equalTo(0.5)
    }

    scrollView.accessibilityIdentifier = "reset.scroll"
    scrollView.showsVerticalScrollIndicator = false
    scrollView.alwaysBounceVertical = false
    containerView.addSubview(scrollView)
    bodyStackView.axis = .vertical
    bodyStackView.spacing = 16
    scrollView.addSubview(bodyStackView)
    bodyIntroStackView.axis = .vertical
    bodyIntroStackView.alignment = .leading
    bodyIntroStackView.spacing = 8
    bodyIntroStackView.isHidden = true
    bodyStackView.addArrangedSubview(bodyIntroStackView)
    // 네 계좌의 표시 순서는 더보기 화면과 동일하게 유지한다.
    let accountsStackView = UIStackView(arrangedSubviews: accountRows)
    accountsStackView.axis = .vertical
    accountsStackView.spacing = 10
    bodyStackView.addArrangedSubview(accountsStackView)
    errorLabel.text = FuturesText.text("more_accounts_read_error")
    errorLabel.textColor = AccountResetColors.warningText
    retryButton.setTitle(FuturesText.text("data_retry"), for: .normal)
    retryButton.tintColor = .mobitColors(.accentPrimary)
    retryButton.accessibilityIdentifier = "reset.retry"
    retryButton.titleLabel?.adjustsFontForContentSizeCategory = true
    retryButton.snp.makeConstraints { $0.height.greaterThanOrEqualTo(44) }
    errorStackView.axis = .vertical
    errorStackView.alignment = .leading
    errorStackView.spacing = 4
    errorStackView.addArrangedSubview(errorLabel)
    errorStackView.addArrangedSubview(retryButton)
    errorStackView.isHidden = true
    bodyStackView.addArrangedSubview(errorStackView)
    configureWarning()
    bodyStackView.addArrangedSubview(warningView)
    bodyStackView.snp.makeConstraints {
      $0.edges.equalTo(scrollView.contentLayoutGuide).inset(UIEdgeInsets(top: Layout.bodyInset, left: Layout.contentInset, bottom: Layout.bodyInset, right: Layout.contentInset))
      $0.width.equalTo(scrollView.frameLayoutGuide).offset(-Layout.contentInset * 2)
    }

    // 스크롤할 때에도 선택 취소와 초기화를 바로 실행할 수 있게 한다.
    let footer = UIView()
    containerView.addSubview(footer)
    // 고정 버튼 위의 경계는 카드 테두리보다 옅게 표시한다.
    let footerDivider = UIView()
    footerDivider.backgroundColor = .mobitColors(.borderPrimary).withAlphaComponent(0.45)
    footer.addSubview(footerDivider)
    footerDivider.snp.makeConstraints {
      $0.top.horizontalEdges.equalToSuperview()
      $0.height.equalTo(0.5)
    }
    actionsStackView.accessibilityIdentifier = "reset.actions"
    actionsStackView.spacing = 12
    actionsStackView.addArrangedSubview(cancelButton)
    actionsStackView.addArrangedSubview(confirmButton)
    cancelButton.accessibilityIdentifier = "reset.cancel"
    confirmButton.accessibilityIdentifier = "reset.confirm"
    [cancelButton, confirmButton].forEach {
      $0.titleLabel?.adjustsFontForContentSizeCategory = true
      $0.setContentCompressionResistancePriority(.required, for: .vertical)
      $0.snp.makeConstraints { $0.height.greaterThanOrEqualTo(52) }
    }
    footer.addSubview(actionsStackView)
    footer.snp.makeConstraints { $0.horizontalEdges.bottom.equalToSuperview() }
    actionsStackView.snp.makeConstraints { $0.edges.equalToSuperview().inset(Layout.actionsInset) }
    scrollView.snp.makeConstraints {
      $0.top.equalTo(headerDivider.snp.bottom)
      $0.horizontalEdges.equalToSuperview()
      $0.bottom.equalTo(footer.snp.top)
      $0.height.greaterThanOrEqualTo(44)
    }
    updateTextLayout(for: view.bounds.width)
    updateColors()
  }

  private func configureWarning() {
    warningView.backgroundColor = AccountResetColors.warningBackground
    warningView.layer.cornerRadius = 16
    warningView.layer.cornerCurve = .continuous
    warningView.layer.borderWidth = 1
    warningLabel.text = FuturesText.text("more_reset_warning")
    warningLabel.textColor = AccountResetColors.warningText
    warningLabel.accessibilityIdentifier = "reset.warning"
    // 색상 외에도 경고 아이콘으로 삭제 동작임을 구분한다.
    let warningIcon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
    warningIcon.tintColor = AccountResetColors.accent
    warningIcon.contentMode = .scaleAspectFit
    warningIcon.snp.makeConstraints { $0.width.height.equalTo(16) }
    // 긴 안내는 아이콘과 독립적으로 카드 높이를 늘린다.
    let warningStackView = UIStackView(arrangedSubviews: [warningIcon, warningLabel])
    warningStackView.alignment = .top
    warningStackView.spacing = 10
    warningView.addSubview(warningStackView)
    warningStackView.snp.makeConstraints { $0.edges.equalToSuperview().inset(16) }
  }

  private func bindActions() {
    closeButton.addTarget(self, action: #selector(cancel(_:)), for: .touchUpInside)
    cancelButton.addTarget(self, action: #selector(cancel(_:)), for: .touchUpInside)
    confirmButton.addTarget(self, action: #selector(confirm), for: .touchUpInside)
    retryButton.addAction(UIAction { [weak self] _ in
      guard let self, self.confirmButton.isEnabled, !self.isBeingDismissed else { return }
      MobitAnalyticsUtil.sendClickEvent(
        location: "더보기_화면",
        stepDepth01: "더보기_초기화",
        stepDepth02: "초기화_잔고_재시도",
        account: self.selectedAccount,
        extraParameters: ["retry_scope": "전체_계좌"]
      )
      self.reloadBalances.onNext(())
    }, for: .touchUpInside)
  }

  private func bindBalances() {
    reloadBalances.startWith(())
      .flatMapLatest { [accountsUseCase] in accountsUseCase.fetchBalances().asObservable() }
      .observe(on: MainScheduler.instance)
      .subscribe(onNext: { [weak self] balances in
        guard let self else { return }
        for row in self.accountRows {
          row.render(balance: balances.first { $0.account == row.account }?.availableBalance)
        }
        self.errorStackView.isHidden = !balances.contains { $0.availableBalance == nil }
        self.view.setNeedsLayout()
      }).disposed(by: disposeBag)
  }

  private func selectAccount(_ account: TradingAccountID) {
    guard confirmButton.isEnabled, !isBeingDismissed, MoreAccountsUseCase.accounts.contains(account) else { return }
    if selectedAccount != account {
      MobitAnalyticsUtil.sendClickEvent(
        location: "더보기_화면",
        stepDepth01: "더보기_초기화",
        stepDepth02: "초기화_대상_선택",
        account: account
      )
    }
    selectedAccount = account
    accountRows.forEach { $0.isSelected = $0.account == account }
  }

  @objc private func cancel(_ sender: UIButton) {
    guard confirmButton.isEnabled, !isBeingDismissed else { return }
    confirmButton.isEnabled = false
    sendCancelEvent(reason: sender === closeButton ? "닫기_버튼" : "취소_버튼")
    dismiss(animated: true)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    guard confirmButton.isEnabled else { return }
    confirmButton.isEnabled = false
    sendCancelEvent(reason: "스와이프_닫기")
  }

  private func sendCancelEvent(reason: String) {
    MobitAnalyticsUtil.sendClickEvent(
      location: "더보기_화면",
      stepDepth01: "더보기_초기화",
      stepDepth02: "초기화_시트_취소",
      stepDepth03: reason,
      account: selectedAccount
    )
  }

  @objc private func confirm() {
    guard confirmButton.isEnabled, !isBeingDismissed else { return }
    // 애니메이션 도중의 연속 탭이 초기화를 중복 실행하지 않게 한다.
    confirmButton.isEnabled = false
    // 닫히는 동안 외부 상태가 변해도 사용자가 선택한 계좌를 전달한다.
    let account = selectedAccount
    MobitAnalyticsUtil.sendClickEvent(
      location: "더보기_화면",
      stepDepth01: "더보기_초기화",
      stepDepth02: "초기화_확인_요청",
      account: account
    )
    // 시트 해제와 무관하게 초기화 요청을 한 번 실행한다.
    let callBack = callBack
    dismiss(animated: true) { callBack(account) }
  }

  private func updateTextLayout(for width: CGFloat) {
    // 큰 글자에서는 헤더 문구를 스크롤하고 하단 동작을 세로로 배치한다.
    let largeText = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    updateIntroLayout(scrolling: largeText)
    actionsWidthConstraint.isActive = !largeText
    actionsStackView.axis = largeText ? .vertical : .horizontal
    titleLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 22, weight: .bold), compatibleWith: traitCollection)
    resetBadgeLabel.updateFont(in: traitCollection)
    [descriptionLabel, errorLabel, warningLabel].forEach {
      $0.font = .preferredFont(forTextStyle: .footnote, compatibleWith: traitCollection)
    }
    retryButton.titleLabel?.font = .preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
    configureActionButton(cancelButton, title: "common_cancel", primary: false)
    configureActionButton(confirmButton, title: "more_reset_selected_account", primary: true)
    accountRows.forEach { $0.updateTextLayout(for: width - Layout.contentInset * 2) }
  }

  private func updateIntroLayout(scrolling: Bool) {
    if scrolling {
      if titleLabel.superview !== bodyIntroStackView {
        titleStackView.removeArrangedSubview(titleLabel)
        titleLabel.removeFromSuperview()
        bodyIntroStackView.insertArrangedSubview(titleLabel, at: 0)
      }
      if resetBadgeLabel.superview !== bodyIntroStackView {
        titleStackView.removeArrangedSubview(resetBadgeLabel)
        resetBadgeLabel.removeFromSuperview()
        bodyIntroStackView.addArrangedSubview(resetBadgeLabel)
      }
      if descriptionLabel.superview !== bodyIntroStackView {
        headerTextStackView.removeArrangedSubview(descriptionLabel)
        descriptionLabel.removeFromSuperview()
        bodyIntroStackView.addArrangedSubview(descriptionLabel)
      }
    } else {
      if titleLabel.superview !== titleStackView {
        bodyIntroStackView.removeArrangedSubview(titleLabel)
        titleLabel.removeFromSuperview()
        titleStackView.insertArrangedSubview(titleLabel, at: 0)
      }
      if resetBadgeLabel.superview !== titleStackView {
        bodyIntroStackView.removeArrangedSubview(resetBadgeLabel)
        resetBadgeLabel.removeFromSuperview()
        titleStackView.insertArrangedSubview(resetBadgeLabel, at: 1)
      }
      if descriptionLabel.superview !== headerTextStackView {
        bodyIntroStackView.removeArrangedSubview(descriptionLabel)
        descriptionLabel.removeFromSuperview()
        headerTextStackView.addArrangedSubview(descriptionLabel)
      }
    }
    bodyIntroStackView.isHidden = !scrolling
  }

  private func configureActionButton(_ button: UIButton, title: String, primary: Bool) {
    // 현재 시트의 글자 크기로 버튼 높이를 계산한다.
    let font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 16, weight: .semibold), compatibleWith: traitCollection)
    // 두 줄 이상인 번역과 접근성 글자를 줄이지 않고 표시한다.
    var configuration = UIButton.Configuration.filled()
    configuration.title = FuturesText.text(title)
    configuration.titleLineBreakMode = .byWordWrapping
    configuration.titleAlignment = .center
    configuration.baseBackgroundColor = primary ? AccountResetColors.button : AccountResetColors.controlBackground
    configuration.baseForegroundColor = primary ? .white : .mobitColors(.textPrimary)
    configuration.cornerStyle = .fixed
    configuration.background.cornerRadius = 16
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12)
    if primary {
      configuration.image = UIImage(systemName: "trash")
      configuration.imagePadding = 6
    }
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      // 버튼 상태가 변해도 화면에 맞춘 글꼴을 유지한다.
      var attributes = incoming
      attributes.font = font
      return attributes
    }
    button.configuration = configuration
  }

  private func updateColors() {
    warningView.layer.borderColor = AccountResetColors.warningBorder.resolvedColor(with: traitCollection).cgColor
  }

  private func updatePreferredSheetSize(for width: CGFloat) {
    guard width > Layout.contentInset * 2 else { return }
    // 헤더와 본문의 자연 높이는 현재 시트 폭을 기준으로 측정한다.
    let headerHeight = headerStackView.systemLayoutSizeFitting(
      CGSize(width: width - Layout.contentInset * 2, height: 0),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
    // 스크롤이 필요한 경우에도 전체 계좌 목록의 자연 높이를 보존한다.
    let bodyHeight = bodyStackView.systemLayoutSizeFitting(
      CGSize(width: width - Layout.contentInset * 2, height: 0),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
    // 접근성 글자에서 세로로 바뀐 버튼 높이도 시트 크기에 포함한다.
    let actionsHeight = actionsStackView.systemLayoutSizeFitting(
      CGSize(width: width - Layout.actionsInset * 2, height: 0),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
    // 안전 영역은 시스템 시트가 따로 계산한다.
    let padding = Layout.headerTop + Layout.bodyInset * 3 + Layout.actionsInset * 2 + 0.5
    // 동일한 측정값으로 시트가 반복 갱신되지 않게 한다.
    let size = CGSize(width: width, height: ceil(headerHeight + bodyHeight + actionsHeight + padding))
    guard preferredContentSize != size else { return }
    preferredContentSize = size
    sheetPresentationController?.invalidateDetents()
  }
}

private enum AccountResetColors {
  // 선택 테두리는 두 테마에서 보이는 장밋빛 한 줄로 표시한다.
  static let accent = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "#FB7185") : UIColor(hex: "#F43F5E") }
  // 흰 글자와 충분한 대비를 갖는 초기화 버튼 색상이다.
  static let button = UIColor(hex: "#E11D48")
  // 선택되지 않은 계좌를 시트 바탕과 구분한다.
  static let optionBackground = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "#202733") : UIColor(hex: "#F8FAFC") }
  // 취소와 닫기 버튼에 같은 옅은 배경을 사용한다.
  static let controlBackground = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "#272F3C") : UIColor(hex: "#F1F5F9") }
  // 주의 문구의 배경은 글자 대비를 방해하지 않게 한다.
  static let warningBackground = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "#351E29") : UIColor(hex: "#FFF1F3") }
  // 경고는 색이 옅은 배경 위에서도 읽을 수 있게 한다.
  static let warningText = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "#FDA4AF") : UIColor(hex: "#BE123C") }
  // 경고 카드의 테두리는 선택 테두리보다 옅게 표시한다.
  static let warningBorder = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "#733247") : UIColor(hex: "#FFE0E5") }
}

private final class AccountResetRow: UIButton {
  // 저장소 잔액과 초기화 대상을 연결하는 고정 계좌다.
  let account: TradingAccountID
  // 거래소 로고와 현재 계좌 표시점을 함께 배치한다.
  private let logoContainerView = UIView()
  // 시트를 열 때 사용 중인 계좌에만 표시한다.
  private let currentAccountDot = UIView()
  // 거래소 이름은 카드 안에서 가장 먼저 읽는다.
  private let exchangeLabel = AccountResetContentLabel(textStyle: .subheadline)
  // 현물과 선물을 이름 옆의 배지로 구분한다.
  private let productLabel = AccountResetBadgeLabel()
  // 선택 여부와 무관하게 현재 사용 중인 계좌를 안내한다.
  private let currentAccountLabel = AccountResetBadgeLabel()
  // 읽기 전이나 실패한 잔액은 대시로 표시한다.
  private let balanceLabel = FuturesText.label(style: .footnote)
  // 큰 글자에서 거래소명과 상품 배지를 세로로 배치한다.
  private let nameStackView = UIStackView()
  // 폭이 좁으면 현재 계좌 배지를 다음 줄로 내린다.
  private let headingStackView = UIStackView()
  // 제목과 배지를 늘리는 대신 가로 행 끝의 남는 공간을 채운다.
  private let headingSpacerView = UIView()
  // 장식과 독립적으로 이름과 잔액을 줄바꿈한다.
  private let detailsStackView = UIStackView()
  // 선택은 장밋빛 원과 접근성 선택 상태로 함께 나타낸다.
  private let radioView = UIView()

  // 선택 테두리와 라디오 표시를 같은 상태로 갱신한다.
  override var isSelected: Bool { didSet { updateSelection() } }
  // 누르는 동안 행 전체에 터치 피드백을 준다.
  override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.7 : 1 } }

  init(account: TradingAccountID, current: Bool, callBack: @escaping () -> Void) {
    self.account = account
    super.init(frame: .zero)
    layer.cornerRadius = 16
    layer.cornerCurve = .continuous
    layer.borderWidth = 1
    accessibilityIdentifier = "reset.account.\(account.exchange.rawValue).\(account.product.rawValue)"
    isAccessibilityElement = true
    // 기존 거래소 이미지를 재사용해 더보기의 카드와 연결한다.
    let logoView = UIImageView(image: UIImage(named: account.exchange == .upbit ? "upbit_logo" : "bithumb_logo"))
    logoView.contentMode = .scaleAspectFit
    logoView.layer.cornerRadius = 11
    logoView.clipsToBounds = true
    logoContainerView.addSubview(logoView)
    logoView.snp.makeConstraints { $0.edges.equalToSuperview() }
    logoContainerView.snp.makeConstraints { $0.width.height.equalTo(36) }
    currentAccountDot.backgroundColor = .mobitColors(.accentPrimary)
    currentAccountDot.layer.cornerRadius = 5
    currentAccountDot.layer.borderWidth = 2
    currentAccountDot.isHidden = !current
    logoContainerView.addSubview(currentAccountDot)
    currentAccountDot.snp.makeConstraints {
      $0.width.height.equalTo(10)
      $0.top.trailing.equalToSuperview().inset(-2)
    }
    exchangeLabel.text = FuturesText.text(account.exchange == .upbit ? "futures_upbit" : "futures_bithumb")
    exchangeLabel.setContentHuggingPriority(.required, for: .horizontal)
    // 이름과 상품 배지를 나란히 둘 때도 스택의 절반 폭 제약보다 자연 폭을 우선한다.
    exchangeLabel.setContentCompressionResistancePriority(UILayoutPriority(999), for: .horizontal)
    productLabel.text = FuturesText.text(account.product == .spot ? "futures_spot" : "futures_product")
    productLabel.backgroundColor = account.product == .spot ? AccountResetColors.controlBackground : UIColor.mobitColors(.accentPrimary).withAlphaComponent(0.14)
    productLabel.textColor = account.product == .spot ? .mobitColors(.textSecondary) : .mobitColors(.accentPrimary)
    currentAccountLabel.text = FuturesText.text("more_current_account")
    currentAccountLabel.textColor = .mobitColors(.accentPrimary)
    currentAccountLabel.backgroundColor = UIColor.mobitColors(.accentPrimary).withAlphaComponent(0.08)
    currentAccountLabel.isHidden = !current
    currentAccountLabel.accessibilityIdentifier = "reset.account.badge.current.\(account.exchange.rawValue).\(account.product.rawValue)"
    nameStackView.addArrangedSubview(exchangeLabel)
    nameStackView.addArrangedSubview(productLabel)
    nameStackView.spacing = 6
    headingStackView.addArrangedSubview(nameStackView)
    headingStackView.addArrangedSubview(currentAccountLabel)
    headingStackView.addArrangedSubview(headingSpacerView)
    headingStackView.spacing = 6
    headingSpacerView.snp.makeConstraints {
      $0.height.equalTo(0)
      $0.width.greaterThanOrEqualTo(0)
    }
    balanceLabel.text = "—"
    balanceLabel.textColor = .mobitColors(.textSecondary)
    balanceLabel.accessibilityIdentifier = "reset.balance.\(account.exchange.rawValue).\(account.product.rawValue)"
    detailsStackView.addArrangedSubview(headingStackView)
    detailsStackView.addArrangedSubview(balanceLabel)
    detailsStackView.axis = .vertical
    detailsStackView.spacing = 4
    radioView.layer.cornerRadius = 10
    radioView.snp.makeConstraints { $0.width.height.equalTo(20) }
    // 행 전체를 버튼으로 처리해 작은 라디오도 같은 터치 영역을 사용한다.
    let rowStackView = UIStackView(arrangedSubviews: [logoContainerView, detailsStackView, radioView])
    rowStackView.alignment = .center
    rowStackView.spacing = 12
    rowStackView.isUserInteractionEnabled = false
    addSubview(rowStackView)
    rowStackView.snp.makeConstraints { $0.edges.equalToSuperview().inset(14) }
    snp.makeConstraints { $0.height.greaterThanOrEqualTo(70) }
    addAction(UIAction { _ in callBack() }, for: .touchUpInside)
    updateTextLayout(for: 0)
    updateSelection()
    updateAccessibility()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    updateTextLayout(for: bounds.width)
    updateSelection()
  }

  func updateTextLayout(for width: CGFloat) {
    // 접근성 글자와 좁은 폭에서는 배지끼리 밀어내거나 잘리지 않게 한다.
    let largeText = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    nameStackView.axis = largeText ? .vertical : .horizontal
    nameStackView.alignment = largeText ? .leading : .center
    updateWidthLayout(for: width)
    exchangeLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 16, weight: .bold), compatibleWith: traitCollection)
    balanceLabel.font = .preferredFont(forTextStyle: .footnote, compatibleWith: traitCollection)
    productLabel.updateFont(in: traitCollection)
    currentAccountLabel.updateFont(in: traitCollection)
  }

  func updateWidthLayout(for width: CGFloat) {
    // 영어 현재 계좌 배지까지 들어갈 공간이 부족하면 다음 줄을 사용한다.
    let vertical = traitCollection.preferredContentSizeCategory.isAccessibilityCategory || (width > 0 && width < 310)
    headingStackView.axis = vertical ? .vertical : .horizontal
    headingStackView.alignment = vertical ? .leading : .center
    headingSpacerView.isHidden = vertical
  }

  func render(balance: Decimal?) {
    balanceLabel.text = balance.map { String(format: FuturesText.text("more_reset_balance"), TradingNumberFormat.string($0)) } ?? "—"
    updateAccessibility()
  }

  private func updateSelection() {
    backgroundColor = isSelected ? .mobitColors(.surfaceElevated) : AccountResetColors.optionBackground
    // 중첩된 강조 테두리를 두지 않고 한 줄의 1포인트 테두리만 사용한다.
    layer.borderColor = (isSelected ? AccountResetColors.accent : UIColor.mobitColors(.borderPrimary).withAlphaComponent(0.45)).resolvedColor(with: traitCollection).cgColor
    radioView.backgroundColor = .mobitColors(.surfaceElevated)
    radioView.layer.borderWidth = isSelected ? 6 : 2
    radioView.layer.borderColor = (isSelected ? AccountResetColors.accent : UIColor.mobitColors(.textTertiary)).resolvedColor(with: traitCollection).cgColor
    currentAccountDot.layer.borderColor = UIColor.mobitColors(.surfaceElevated).resolvedColor(with: traitCollection).cgColor
    balanceLabel.textColor = .mobitColors(isSelected ? .textPrimary : .textSecondary)
    accessibilityTraits = isSelected ? [.button, .selected] : .button
  }

  private func updateAccessibility() {
    accessibilityLabel = [exchangeLabel.text, productLabel.text].compactMap { $0 }.joined(separator: ", ")
    accessibilityValue = [balanceLabel.text, currentAccountLabel.isHidden ? nil : currentAccountLabel.text].compactMap { $0 }.joined(separator: ", ")
  }
}

private class AccountResetContentLabel: UILabel {
  convenience init(textStyle: UIFont.TextStyle) {
    self.init(frame: .zero)
    font = .preferredFont(forTextStyle: textStyle)
    adjustsFontForContentSizeCategory = true
    numberOfLines = 0
    textColor = .mobitColors(.textPrimary)
  }

  // 숨긴 배지가 제목의 공간을 차지하지 않게 한다.
  override var isHidden: Bool {
    didSet { invalidateIntrinsicContentSize() }
  }

  // 가로 자연 폭과 실제 줄바꿈 높이를 함께 제공한다.
  override var intrinsicContentSize: CGSize {
    guard !isHidden else { return .zero }
    // 이전 줄바꿈 폭과 무관하게 현재 글꼴의 한 줄 폭을 사용한다.
    guard let font else { return super.intrinsicContentSize }
    // 좁은 폭에서 측정한 textRect가 제목을 다시 줄바꿈하지 않게 한다.
    let naturalWidth = (text ?? "").size(withAttributes: [.font: font]).width
    return CGSize(width: ceil(naturalWidth), height: super.intrinsicContentSize.height)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if preferredMaxLayoutWidth != bounds.width {
      preferredMaxLayoutWidth = bounds.width
    }
  }
}

private final class AccountResetBadgeLabel: AccountResetContentLabel {
  // 배지 텍스트가 모서리와 닿지 않도록 내측 여백을 유지한다.
  private let textInsets = UIEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)

  // 배지 안쪽 여백을 포함한 콘텐츠 크기를 제공한다.
  override var intrinsicContentSize: CGSize {
    guard !isHidden else { return .zero }
    // 본문의 자연 폭에 배지 안쪽 여백만 더한다.
    let size = super.intrinsicContentSize
    return CGSize(width: size.width + textInsets.left + textInsets.right, height: size.height)
  }

  init() {
    super.init(frame: .zero)
    numberOfLines = 0
    adjustsFontForContentSizeCategory = true
    textAlignment = .center
    layer.cornerRadius = 5
    clipsToBounds = true
    setContentHuggingPriority(.required, for: .horizontal)
    // 스택의 내부 줄바꿈 제약보다 배지의 자연 폭을 우선해 짧은 상품명이 세로로 쪼개지지 않게 한다.
    setContentCompressionResistancePriority(UILayoutPriority(999), for: .horizontal)
    updateFont(in: traitCollection)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func updateFont(in traits: UITraitCollection) {
    font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 11, weight: .semibold), compatibleWith: traits)
  }

  override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
    // 내측 여백도 배지의 고유 크기와 여러 줄 높이에 포함한다.
    let rect = super.textRect(forBounds: bounds.inset(by: textInsets), limitedToNumberOfLines: numberOfLines)
    return rect.inset(by: UIEdgeInsets(top: -textInsets.top, left: -textInsets.left, bottom: -textInsets.bottom, right: -textInsets.right))
  }

  override func drawText(in rect: CGRect) {
    super.drawText(in: rect.inset(by: textInsets))
  }
}
