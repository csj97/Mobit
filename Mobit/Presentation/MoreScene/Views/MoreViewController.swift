//
//  MoreViewController.swift
//  Mobit
//
//  Created by 조성재 on 5/18/25.
//

import RxCocoa
import RxSwift
import SnapKit
import UIKit

class MoreViewController: MobitBaseViewController {
  // 화면 구조와 정적인 메뉴는 XIB에 명시적으로 연결한다.
  @IBOutlet private weak var headerTitleLabel: UILabel! // 로그인 정보 없이 더보기 화면 제목을 표시한다.
  @IBOutlet private weak var headerSettingsButton: UIButton! // 상단에서도 기존 테마·시세 설정을 열 수 있게 한다.
  @IBOutlet private weak var accountsStackView: UIStackView! // 거래소별 현물·선물 카드의 높이를 콘텐츠에 맞춘다.
  @IBOutlet private weak var accountsErrorView: UIStackView! // 저장소 읽기 실패가 있을 때만 오류·재시도를 표시한다.
  @IBOutlet private weak var accountsErrorLabel: UILabel! // 정상 갱신 안내 대신 실제 읽기 실패만 전달한다.
  @IBOutlet private weak var accountsRetryButton: UIButton! // 저장 실패 후 잔고 읽기를 사용자가 다시 요청한다.
  @IBOutlet private weak var rewardBanner: MoreRewardView! // 기존 광고 지급 조건을 시안의 강조 카드에 표시한다.
  @IBOutlet private weak var investmentTitleLabel: UILabel! // 초기화와 설정 메뉴를 투자 관리 그룹으로 묶는다.
  @IBOutlet private weak var communityTitleLabel: UILabel! // 커뮤니티와 모의투자 안내 메뉴의 그룹 제목이다.
  @IBOutlet private weak var investInitButton: MoreMenuButton! // 현물 초기화의 기존 확인 흐름을 연결한다.
  @IBOutlet private weak var settingsButton: MoreMenuButton! // 아이콘과 설명을 포함한 행 전체에서 설정을 연다.
  @IBOutlet private weak var communityButton: MoreMenuButton! // 기존 Coordinator의 커뮤니티 이동을 연결한다.
  @IBOutlet private weak var userNoticeButton: MoreMenuButton! // 모의투자 유의사항의 기존 안내 흐름을 연결한다.
  @IBOutlet private weak var versionLabel: UILabel! // 현재 설치한 앱 버전을 스크롤 마지막에 표시한다.

  weak var coordinator: MoreCoordinator?
  // 현물·선물의 저장 완료된 KRW 잔고를 읽는 사용 사례다.
  private let accountsUseCase: MoreAccountsUseCase
  // 확인한 계좌를 광고 시작 시점까지 고정해 전달한다.
  private let presentRewardedAd: @MainActor (MobitBaseViewController, TradingAccountID) -> Void
  // 화면 진입·보상 정산·재시도의 읽기 요청을 한 구독으로 합친다.
  private let reloadAccounts = PublishSubject<Void>()
  // 화면 해제 시 잔고 읽기와 알림 구독을 함께 종료한다.
  private let disposeBag = DisposeBag()
  // 재조회 때 카드를 재생성하지 않고 금액과 현재 선택 표시만 바꾼다.
  private lazy var accountRows = MoreAccountsUseCase.accounts.map { account in
    MoreAccountRow(account: account) { [weak self] in self?.requestCharge(for: account) }
  }

  init(
    accountsUseCase: MoreAccountsUseCase = MoreAccountsUseCase(),
    presentRewardedAd: @escaping @MainActor (MobitBaseViewController, TradingAccountID) -> Void = { RewardedAdManager.shared.showAd(from: $0, account: $1) }
  ) {
    self.accountsUseCase = accountsUseCase
    self.presentRewardedAd = presentRewardedAd
    super.init(nibName: "MoreViewController", bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    setUI()
    bindAccounts()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(true, animated: animated)
    reloadAccounts.onNext(())
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    reloadAccounts.onNext(())
  }

  func setUI() {
    view.backgroundColor = UIColor { traits in
      traits.userInterfaceStyle == .dark ? .mobitColors(.backgroundPrimary) : .systemGroupedBackground
    }
    headerTitleLabel.text = FuturesText.text("common_more")
    headerTitleLabel.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: .systemFont(ofSize: 30, weight: .bold))
    headerTitleLabel.adjustsFontForContentSizeCategory = true
    headerSettingsButton.accessibilityLabel = FuturesText.text("more_settings_title")
    headerSettingsButton.accessibilityIdentifier = "more.header.settings"
    headerSettingsButton.tintColor = .mobitColors(.textSecondary)
    headerSettingsButton.backgroundColor = .mobitColors(.surfacePrimary)
    headerSettingsButton.layer.cornerRadius = 22
    accountsErrorLabel.text = FuturesText.text("more_accounts_read_error")
    accountsErrorLabel.textColor = .systemRed
    accountsErrorLabel.font = .preferredFont(forTextStyle: .footnote)
    accountsErrorLabel.accessibilityIdentifier = "more.accounts.error"
    accountsErrorView.isHidden = true
    accountsRetryButton.setTitle(FuturesText.text("data_retry"), for: .normal)
    accountsRetryButton.accessibilityIdentifier = "more.accounts.retry"
    accountsRetryButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
    accountsRetryButton.titleLabel?.adjustsFontForContentSizeCategory = true
    accountsRetryButton.tintColor = .mobitColors(.accentPrimary)
    investmentTitleLabel.text = FuturesText.text("more_investment_title")
    communityTitleLabel.text = FuturesText.text("more_community_title")
    [investmentTitleLabel, communityTitleLabel].forEach {
      $0?.font = .preferredFont(forTextStyle: .subheadline)
    }
    [accountsErrorLabel, investmentTitleLabel, communityTitleLabel, versionLabel].forEach {
      $0?.adjustsFontForContentSizeCategory = true
      $0?.numberOfLines = 0
    }
    for exchange in [Exchange.upbit, .bithumb] {
      accountsStackView.addArrangedSubview(MoreAccountGroupView(exchange: exchange, rows: accountRows.filter { $0.account.exchange == exchange }))
    }
    rewardBanner.configure()
    investInitButton.configure(title: "futures_spot_reset", subtitle: "more_reset_description", icon: "arrow.clockwise", color: .systemRed, badge: "more_caution")
    settingsButton.configure(title: "more_settings_title", subtitle: "more_settings_description", icon: "slider.horizontal.3", color: .systemBlue)
    communityButton.configure(title: "more_mobit_community", subtitle: "more_community_description", icon: "person.3.fill", color: .systemPurple)
    userNoticeButton.configure(title: "more_user", subtitle: "more_notice_description", icon: "info.circle", color: .systemOrange)
    investInitButton.accessibilityIdentifier = "more.reset"
    settingsButton.accessibilityIdentifier = "more.settings"
    communityButton.accessibilityIdentifier = "more.community"
    userNoticeButton.accessibilityIdentifier = "more.notice"
    updateVersionLabel()
  }

  private func bindAccounts() {
    // 광고 보상과 현물 주문의 현금 변경은 현재 선택과 무관하게 전체 계좌에 반영한다.
    let changes = Observable.merge(
      UserDataManager.userAvailableBalanceObservable.skip(1).map { _ in () },
      NotificationCenter.default.rx.notification(.futuresAccountDidChange).map { _ in () },
      NotificationCenter.default.rx.notification(UIApplication.didBecomeActiveNotification).map { _ in () }
    )
      .filter { [weak self] in self?.viewIfLoaded?.window != nil && UIApplication.shared.applicationState != .background }
    Observable.merge(reloadAccounts.asObservable(), changes)
      .startWith(())
      .debounce(.milliseconds(30), scheduler: MainScheduler.instance)
      .flatMapLatest { [accountsUseCase] in accountsUseCase.fetchBalances().asObservable() }
      .observe(on: MainScheduler.instance)
      .subscribe(onNext: { [weak self] balances in
        guard let self else { return }
        for row in self.accountRows {
          row.render(
            balance: balances.first { $0.account == row.account }?.availableBalance,
            selected: row.account.exchange == ExchangeSelectionStore.currentExchange && row.account.product == ExchangeSelectionStore.currentProduct
          )
        }
        self.accountsErrorView.isHidden = !balances.contains { $0.availableBalance == nil }
      }).disposed(by: disposeBag)
  }

  @IBAction private func tapOnAccountsRetry(_ sender: UIButton) { reloadAccounts.onNext(()) }

  private func requestCharge(for account: TradingAccountID) {
    guard presentedViewController == nil, MoreAccountsUseCase.accounts.contains(account) else { return }
    MobitAnalyticsUtil.sendClickEvent(event: .more_charge)
    // 확인창과 광고 보상은 버튼을 누른 계좌를 사용하며 모드 전환을 하지 않는다.
    let name = "\(MoreAccountGroupView.exchangeName(account.exchange)) · \(FuturesText.text(account.product == .spot ? "futures_spot" : "futures_product"))"
    // 지급 금액은 기존 보상 정책에서 읽어 시안의 예시 금액과 혼동하지 않게 한다.
    let amount = TradingNumberFormat.string(TradingFundingPolicy.advertisementReward(for: account))
    show(
      alertType: .canCancel,
      title: String(format: FuturesText.text("more_charge_account_title"), name),
      content: String(format: FuturesText.text("more_charge_account_note"), name, amount)
    ) { [weak self] confirmed in
      guard let self else { return }
      MobitAnalyticsUtil.sendClickEvent(event: confirmed ? .ad_click_confirm : .ad_click_cancel)
      if confirmed { self.presentRewardedAd(self, account) }
    }
  }

  @IBAction func tapOnUserNoticeButton(_ sender: UIButton) {
    MobitAnalyticsUtil.sendClickEvent(event: .more_notice)
    show(
      alertType: .onlyConfirm,
      title: FuturesText.text("more_user"),
      content: FuturesText.text("more_notice_content"),
      callBack: nil
    )
  }

  @IBAction func tapOnInvestInitButton(_ sender: UIButton) {
    MobitAnalyticsUtil.sendClickEvent(event: .more_init_data)
    show(
      alertType: .canCancel,
      title: FuturesText.text("futures_spot_reset"),
      content: FuturesText.text("futures_spot_reset_note")
    ) { [weak self] confirmed in
      guard let self, confirmed else { return }
      RewardedAdManager.shared.resetSpotInvestment(from: self)
      self.reloadAccounts.onNext(())
    }
  }

  @IBAction func tapOnSettingsButton(_ sender: UIButton) {
    guard presentedViewController == nil else { return }
    MobitAnalyticsUtil.sendClickEvent(location: "더보기_화면", stepDepth01: "더보기_탭", stepDepth02: "설정_버튼_클릭")
    // 기존 설정·테마 적용 동작을 메뉴와 상단 버튼에서 공유한다.
    let settings = AppSettingsViewController()
    settings.modalPresentationStyle = .pageSheet
    settings.sheetPresentationController?.detents = [
      .custom(identifier: .init("settings.content")) { [weak settings] context in
        // 실제 콘텐츠 높이가 준비되기 전에는 시스템 최대 높이를 사용한다.
        guard let height = settings?.preferredContentSize.height, height > 0 else { return context.maximumDetentValue }
        return min(height, context.maximumDetentValue)
      }
    ]
    settings.sheetPresentationController?.prefersGrabberVisible = true
    settings.sheetPresentationController?.preferredCornerRadius = 32
    settings.sheetPresentationController?.prefersEdgeAttachedInCompactHeight = true
    settings.prepareSheet(for: view.safeAreaLayoutGuide.layoutFrame.width)
    present(settings, animated: true)
  }

  @IBAction func tapOnCommunity(_ sender: UIButton) {
    MobitAnalyticsUtil.sendClickEvent(event: .more_community)
    coordinator?.pushMobitCommunityViewController()
  }

  private func updateVersionLabel() {
    // 기존 두 자리 버전도 세 자리 표기와 맞춘다.
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    versionLabel.text = String(format: FuturesText.text("more_app_version"), version.split(separator: ".").count == 2 ? version + ".0" : version)
    versionLabel.font = .preferredFont(forTextStyle: .footnote)
  }
}

// XIB의 카드 배경과 테두리가 런타임 테마 변경에도 같은 기준을 사용한다.
class MoreCardView: UIView {
  override init(frame: CGRect) { super.init(frame: frame); configure() }
  required init?(coder: NSCoder) { super.init(coder: coder); configure() }

  private func configure() {
    backgroundColor = .mobitColors(.surfacePrimary)
    layer.cornerRadius = 24
    layer.cornerCurve = .continuous
    layer.borderWidth = 1
    updateColors()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    updateColors()
  }

  private func updateColors() {
    layer.borderColor = UIColor.mobitColors(.borderPrimary).withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.45 : 0.25).resolvedColor(with: traitCollection).cgColor
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0 : 0.035
    layer.shadowOffset = CGSize(width: 0, height: 3)
    layer.shadowRadius = 8
  }
}

private class MoreContentLabel: UILabel {
  convenience init(textStyle: UIFont.TextStyle) {
    self.init(frame: .zero)
    font = .preferredFont(forTextStyle: textStyle)
    adjustsFontForContentSizeCategory = true
    numberOfLines = 0
    textColor = .mobitColors(.textPrimary)
  }

  override var isHidden: Bool {
    didSet { invalidateIntrinsicContentSize() }
  }

  override var intrinsicContentSize: CGSize {
    guard !isHidden else { return .zero }
    // 줄바꿈한 폭을 자연폭으로 재사용해 제목과 배지가 좁아지는 것을 막는다.
    let naturalSize = textRect(
      forBounds: CGRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
      limitedToNumberOfLines: 1
    ).size
    return CGSize(width: ceil(naturalSize.width), height: super.intrinsicContentSize.height)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if preferredMaxLayoutWidth != bounds.width {
      preferredMaxLayoutWidth = bounds.width
    }
  }
}

private final class MoreBadgeLabel: MoreContentLabel {
  enum Style {
    case currentAccount
    case caution
  }

  // 글자 크기가 커져도 배경과 텍스트 사이 여백을 유지한다.
  private let textInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

  init(style: Style) {
    super.init(frame: .zero)
    font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 11, weight: .medium))
    adjustsFontForContentSizeCategory = true
    numberOfLines = 0
    textAlignment = .center
    layer.cornerRadius = 7
    layer.cornerCurve = .continuous
    clipsToBounds = true
    textColor = UIColor { traits in
      switch style {
      case .currentAccount:
        return UIColor(hex: traits.userInterfaceStyle == .dark ? "#A5C9ED" : "#416B96")
      case .caution:
        return UIColor(hex: traits.userInterfaceStyle == .dark ? "#F6CA85" : "#9A5A09")
      }
    }
    backgroundColor = UIColor { traits in
      switch style {
      case .currentAccount:
        return UIColor(hex: traits.userInterfaceStyle == .dark ? "#23374C" : "#EAF2FB")
      case .caution:
        return UIColor(hex: traits.userInterfaceStyle == .dark ? "#3C301E" : "#FFF1DA")
      }
    }
    setContentHuggingPriority(.required, for: .horizontal)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func textRect(
    forBounds bounds: CGRect,
    limitedToNumberOfLines numberOfLines: Int
  ) -> CGRect {
    // UILabel의 줄바꿈 계산과 배경 크기에 같은 여백을 반영한다.
    let textRect = super.textRect(
      forBounds: bounds.inset(by: textInsets),
      limitedToNumberOfLines: numberOfLines
    )
    return CGRect(
      x: textRect.minX - textInsets.left,
      y: textRect.minY - textInsets.top,
      width: textRect.width + textInsets.left + textInsets.right,
      height: textRect.height + textInsets.top + textInsets.bottom
    )
  }

  override func drawText(in rect: CGRect) {
    super.drawText(in: rect.inset(by: textInsets))
  }
}

private func makeMoreBadgeHeading(
  titleLabel: UILabel,
  badgeLabel: UILabel
) -> UIView {
  titleLabel.setContentHuggingPriority(.required, for: .horizontal)
  // 스택의 라벨 폭 보정 없이 제목과 배지의 콘텐츠 크기를 유지한다.
  let heading = UIView()
  heading.addSubview(titleLabel)
  heading.addSubview(badgeLabel)
  // 고정 높이 대신 두 문구를 담는 최소 높이를 선택한다.
  heading.snp.makeConstraints {
    $0.height.equalTo(0).priority(UILayoutPriority.fittingSizeLevel.rawValue)
  }
  titleLabel.snp.makeConstraints {
    $0.leading.centerY.equalToSuperview()
    $0.top.greaterThanOrEqualToSuperview()
    $0.bottom.lessThanOrEqualToSuperview()
  }
  badgeLabel.snp.makeConstraints {
    $0.leading.equalTo(titleLabel.snp.trailing).offset(8)
    $0.trailing.lessThanOrEqualToSuperview()
    $0.centerY.equalToSuperview()
    $0.top.greaterThanOrEqualToSuperview()
    $0.bottom.lessThanOrEqualToSuperview()
  }
  return heading
}

private final class MoreAccountGroupView: MoreCardView {
  // 글자 크기 변경 시에도 거래소명에 같은 강조를 적용한다.
  private let exchange: Exchange
  // 거래소명과 잔액 설명을 서로 다른 글꼴과 색상으로 표시한다.
  private let titleLabel = FuturesText.label(style: .headline)

  init(exchange: Exchange, rows: [MoreAccountRow]) {
    self.exchange = exchange
    super.init(frame: .zero)
    // 2개 상품의 충전 계좌가 어느 거래소 소속인지 먼저 보여준다.
    let logo = UIImageView(image: UIImage(named: exchange == .upbit ? "upbit_logo" : "bithumb_logo"))
    logo.contentMode = .scaleAspectFit
    logo.layer.cornerRadius = 6
    logo.clipsToBounds = true
    logo.snp.makeConstraints { $0.width.height.equalTo(26) }
    updateTitleStyle()
    // 거래소 이름 옆의 남은 공간을 자산 행과 동일하게 확보한다.
    let heading = UIStackView(arrangedSubviews: [logo, titleLabel])
    heading.alignment = .center
    heading.spacing = 10
    // 계좌 행과 구분선을 카드 안에서 함께 늘어나게 배치한다.
    let stack = UIStackView(arrangedSubviews: [heading])
    stack.axis = .vertical
    stack.spacing = 8
    for row in rows {
      // 현물·선물의 별도 잔고를 시각적으로 분리한다.
      let separator = UIView()
      separator.backgroundColor = .mobitColors(.borderPrimary).withAlphaComponent(0.45)
      separator.snp.makeConstraints { $0.height.equalTo(1) }
      stack.addArrangedSubview(separator)
      stack.addArrangedSubview(row)
    }
    addSubview(stack)
    stack.snp.makeConstraints {
      $0.horizontalEdges.equalToSuperview().inset(18)
      $0.verticalEdges.equalToSuperview().inset(14)
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
      updateTitleStyle()
    }
  }

  private func updateTitleStyle() {
    // 번역 문장 안에서 거래소명만 제목 크기로 유지한다.
    let name = Self.exchangeName(exchange)
    // 괄호 안내는 작은 보조 글꼴과 테마에 맞는 색상을 사용한다.
    let title = NSMutableAttributedString(
      string: String(format: FuturesText.text("more_account_group_title"), name),
      attributes: [
        .font: UIFont.preferredFont(forTextStyle: .footnote, compatibleWith: traitCollection),
        .foregroundColor: UIColor.mobitColors(.textSecondary)
      ]
    )
    title.addAttributes(
      [
        .font: UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traitCollection),
        .foregroundColor: UIColor.mobitColors(.textPrimary)
      ],
      range: (title.string as NSString).range(of: name)
    )
    titleLabel.attributedText = title
  }

  static func exchangeName(_ exchange: Exchange) -> String {
    FuturesText.text(exchange == .upbit ? "futures_upbit" : "futures_bithumb")
  }
}

private final class MoreAccountRow: UIView {
  // 버튼 선택·금액 갱신 모두 같은 고정 계좌 ID를 사용한다.
  let account: TradingAccountID
  // 현물·선물 이름과 현재 선택 배지를 함께 표시한다.
  private let productLabel = MoreContentLabel(textStyle: .subheadline)
  // 계좌 선택을 바꾸지 않고 사용 중인 계좌만 구분한다.
  private let selectedLabel = MoreBadgeLabel(style: .currentAccount)
  // 저장 실패는 대시로 표시하며 원본 금액은 접근성 값에 보존한다.
  private let balanceLabel = FuturesText.label(style: .title3)
  // VoiceOver가 계좌 이름과 잔고를 한 번에 읽는 컨테이너다.
  private let accountDetails = UIStackView()
  // 큰 글씨에서는 충전 버튼을 금액 아래로 내려 가로 공간을 확보한다.
  private let contentStackView = UIStackView()
  // 광고를 볼 계좌를 행 자체에서 명확히 선택한다.
  private let chargeButton = UIButton(type: .system)

  init(account: TradingAccountID, callBack: @escaping () -> Void) {
    self.account = account
    super.init(frame: .zero)
    productLabel.text = FuturesText.text(account.product == .spot ? "futures_spot" : "futures_product")
    selectedLabel.text = FuturesText.text("more_current_account")
    selectedLabel.isHidden = true
    productLabel.setContentCompressionResistancePriority(UILayoutPriority(751), for: .horizontal)
    // 긴 번역에서는 현재 선택 배지도 줄바꿈할 수 있다.
    let heading = makeMoreBadgeHeading(titleLabel: productLabel, badgeLabel: selectedLabel)
    balanceLabel.font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: .systemFont(ofSize: 20, weight: .semibold))
    balanceLabel.numberOfLines = 1
    balanceLabel.adjustsFontSizeToFitWidth = true
    balanceLabel.minimumScaleFactor = 0.55
    balanceLabel.text = "—"
    balanceLabel.accessibilityIdentifier = "more.balance.\(account.exchange.rawValue).\(account.product.rawValue)"
    // 계좌 이름과 잔고는 하나의 영역에서 읽고 충전 버튼은 독립적으로 접근한다.
    accountDetails.addArrangedSubview(heading)
    accountDetails.addArrangedSubview(balanceLabel)
    accountDetails.axis = .vertical
    accountDetails.spacing = 3
    accountDetails.isAccessibilityElement = true
    accountDetails.accessibilityLabel = "\(MoreAccountGroupView.exchangeName(account.exchange)) · \(productLabel.text ?? "")"
    accountDetails.accessibilityIdentifier = "more.account.\(account.exchange.rawValue).\(account.product.rawValue)"
    // 실제 화면의 지원 계좌마다 동일한 짧은 충전 버튼을 사용한다.
    var configuration = UIButton.Configuration.filled()
    configuration.title = FuturesText.text("investment_recharge")
    configuration.baseBackgroundColor = .mobitColors(.accountAction)
    configuration.baseForegroundColor = .white
    configuration.background.cornerRadius = 10
    // 터치 영역은 유지하면서 배경만 세로 중앙에서 작게 표시한다.
    configuration.background.backgroundInsets = NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
    chargeButton.configuration = configuration
    chargeButton.titleLabel?.adjustsFontForContentSizeCategory = true
    chargeButton.accessibilityLabel = "\(accountDetails.accessibilityLabel ?? "") \(FuturesText.text("investment_recharge"))"
    chargeButton.accessibilityIdentifier = "more.charge.\(account.exchange.rawValue).\(account.product.rawValue)"
    chargeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    chargeButton.setContentHuggingPriority(.required, for: .horizontal)
    chargeButton.addAction(UIAction { _ in callBack() }, for: .touchUpInside)
    contentStackView.addArrangedSubview(accountDetails)
    contentStackView.addArrangedSubview(chargeButton)
    contentStackView.spacing = 12
    addSubview(contentStackView)
    contentStackView.snp.makeConstraints { $0.edges.equalToSuperview() }
    chargeButton.snp.makeConstraints {
      $0.width.height.greaterThanOrEqualTo(44)
    }
    updateTextLayout()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    updateTextLayout()
  }

  private func updateTextLayout() {
    contentStackView.axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
    contentStackView.alignment = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .fill : .center
    // 해당 화면의 글자 크기를 사용해 버튼도 접근성 글씨에 맞춰 늘어난다.
    let font = UIFont.preferredFont(forTextStyle: .footnote, compatibleWith: traitCollection)
    chargeButton.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      // UIConfiguration의 폰트를 상태 변경에도 같은 기준으로 유지한다.
      var attributes = incoming
      attributes.font = font
      return attributes
    }
  }

  func render(balance: Decimal?, selected: Bool) {
    balanceLabel.text = balance.map { "\(TradingNumberFormat.string($0)) \(FuturesText.text("currency_krw_unit"))" } ?? "—"
    selectedLabel.isHidden = !selected
    balanceLabel.textColor = .mobitColors(.textPrimary)
    accountDetails.accessibilityValue = [balanceLabel.text, selected ? FuturesText.text("more_current_account") : nil].compactMap { $0 }.joined(separator: ", ")
  }
}

// XIB에 연결된 메뉴 행이 아이콘부터 설명까지 하나의 터치 영역을 제공한다.
final class MoreMenuButton: UIButton {
  // 작은 화면과 긴 번역에서 여러 줄로 늘어나는 메뉴 제목이다.
  private let menuTitle = MoreContentLabel(textStyle: .headline)
  // 메뉴를 열기 전 실제 기능의 범위를 설명한다.
  private let menuSubtitleLabel = FuturesText.label(style: .footnote)
  // 초기화처럼 주의가 필요한 기능의 문구 배지다.
  private let badgeLabel = MoreBadgeLabel(style: .caution)
  // 카드의 메뉴 종류를 구분하는 색상 아이콘이다.
  private let iconView = UIImageView()
  // 아이콘의 옅은 배경을 카드와 분리한다.
  private let iconBackground = UIView()

  override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.6 : 1 } }
  override init(frame: CGRect) { super.init(frame: frame); configureLayout() }
  required init?(coder: NSCoder) { super.init(coder: coder); configureLayout() }

  private func configureLayout() {
    backgroundColor = .clear
    iconBackground.layer.cornerRadius = 14
    iconView.contentMode = .scaleAspectFit
    iconBackground.addSubview(iconView)
    iconView.snp.makeConstraints { $0.edges.equalToSuperview().inset(10) }
    iconBackground.snp.makeConstraints { $0.width.height.equalTo(42) }
    menuSubtitleLabel.textColor = .mobitColors(.textSecondary)
    badgeLabel.setContentCompressionResistancePriority(UILayoutPriority(751), for: .horizontal)
    // 제목과 주의 배지도 텍스트 확대에 맞춰 행 높이를 결정한다.
    let heading = makeMoreBadgeHeading(titleLabel: menuTitle, badgeLabel: badgeLabel)
    // 설명을 제목 바로 아래에 붙여 기능 그룹의 정보 밀도를 유지한다.
    let text = UIStackView(arrangedSubviews: [heading, menuSubtitleLabel])
    text.axis = .vertical
    text.spacing = 5
    // 메뉴 이동을 표현하는 장식 아이콘이다.
    let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
    chevron.tintColor = .mobitColors(.textTertiary)
    chevron.contentMode = .scaleAspectFit
    chevron.snp.makeConstraints { $0.width.equalTo(10); $0.height.equalTo(16) }
    // 전체 행을 UIButton이 처리하므로 내부 장식이 터치를 가로채지 않는다.
    let row = UIStackView(arrangedSubviews: [iconBackground, text, chevron])
    row.alignment = .center
    row.spacing = 12
    row.isUserInteractionEnabled = false
    addSubview(row)
    row.snp.makeConstraints { $0.edges.equalToSuperview().inset(UIEdgeInsets(top: 18, left: 0, bottom: 18, right: 0)) }
    snp.makeConstraints { $0.height.greaterThanOrEqualTo(82) }
    isAccessibilityElement = true
  }

  func configure(title: String, subtitle: String, icon: String, color: UIColor, badge: String? = nil) {
    menuTitle.text = FuturesText.text(title)
    menuSubtitleLabel.text = FuturesText.text(subtitle)
    badgeLabel.text = badge.map(FuturesText.text)
    badgeLabel.isHidden = badge == nil
    iconView.image = UIImage(systemName: icon)
    iconView.tintColor = color
    iconBackground.backgroundColor = color.withAlphaComponent(0.12)
    accessibilityLabel = [menuTitle.text, menuSubtitleLabel.text, badgeLabel.text].compactMap { $0 }.joined(separator: ". ")
  }
}

// 시안의 보상 카드는 실제 지급 조건을 설명하며 충전 대상은 각 계좌 행에서 선택한다.
final class MoreRewardView: UIView {
  override class var layerClass: AnyClass { CAGradientLayer.self }

  func configure() {
    layer.cornerRadius = 24
    layer.cornerCurve = .continuous
    // 두 테마에서 흰 문구 대비를 유지하는 보상 카드 전용 배경이다.
    let gradient = layer as? CAGradientLayer
    gradient?.colors = [UIColor(hex: "#2563EB").cgColor, UIColor(hex: "#7C3AED").cgColor]
    gradient?.startPoint = CGPoint(x: 0, y: 0)
    gradient?.endPoint = CGPoint(x: 1, y: 1)
    // 실제 광고 완료 조건을 함께 보여주는 시안의 강조 제목이다.
    let title = FuturesText.label(style: .headline)
    title.text = FuturesText.text("more_reward_title")
    title.textColor = .white
    // USDT 예시 대신 기존 KRW 보상 정책에서 금액을 읽는다.
    let note = FuturesText.label(style: .footnote)
    note.text = String(format: FuturesText.text("more_reward_description"), TradingNumberFormat.string(TradingFundingPolicy.advertisementReward(for: .spot(for: .upbit))))
    note.textColor = .white
    // 제목과 조건을 한 묶음으로 읽는다.
    let text = UIStackView(arrangedSubviews: [title, note])
    text.axis = .vertical
    text.spacing = 8
    // 계좌 행에서 받을 광고 보상을 나타내는 장식 아이콘이다.
    let icon = UIImageView(image: UIImage(systemName: "gift.fill"))
    icon.tintColor = .white
    icon.contentMode = .scaleAspectFit
    icon.snp.makeConstraints { $0.width.height.equalTo(44) }
    // 강조 카드도 작은 화면·텍스트 확대에서 내용 높이를 따른다.
    let row = UIStackView(arrangedSubviews: [text, icon])
    row.spacing = 14
    row.alignment = .center
    addSubview(row)
    row.snp.makeConstraints { $0.edges.equalToSuperview().inset(20) }
    isAccessibilityElement = true
    accessibilityLabel = [title.text, note.text].compactMap { $0 }.joined(separator: ". ")
  }
}

private enum MoreSettingsColors {
  // 어두운 배경에서도 섹션 안내와 선택 테두리를 읽을 수 있게 한다.
  static let accent = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "#92B3FF") : UIColor(hex: "#2563EB") }
  // 적용 버튼은 두 테마에서 흰 글자의 대비를 유지한다.
  static let button = UIColor(hex: "#2563EB")
  // 테마 선택과 취소 버튼의 옅은 배경이다.
  static let controlBackground = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "#272F3C") : UIColor(hex: "#F1F5F9") }
  // 설정 옵션을 시트 배경과 부드럽게 구분한다.
  static let optionBackground = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "#202733") : UIColor(hex: "#FAFBFD") }
  // 시안의 청회색 보조 문구를 두 테마에서 읽을 수 있게 한다.
  static let secondaryText = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "#A4AFBF") : UIColor(hex: "#64748B") }
}

private final class AppSettingsViewController: UIViewController {
  private enum Layout {
    // 손잡이 아래 제목이 시작되는 여백이다.
    static let headerTop: CGFloat = 28
    // 헤더와 스크롤 본문의 간격이다.
    static let bodyTop: CGFloat = 8
    // 본문 좌우와 마지막 항목 아래에 같은 여백을 둔다.
    static let contentInset: CGFloat = 24
    // 고정 버튼 위의 여백이다.
    static let actionsTop: CGFloat = 12
    // 버튼 좌우와 아래에 같은 여백을 둔다.
    static let actionsInset: CGFloat = 20
  }

  // 적용 전에는 저장된 캔들 색상을 변경하지 않는다.
  private var pendingTheme: UserDataManager.MarketColorTheme = UserDataManager.marketColorTheme
  // 취소하면 버릴 앱 테마 선택값이다.
  private var pendingAppTheme: UserDataManager.AppTheme = UserDataManager.appTheme
  // 시스템 시트 안에서 설정 콘텐츠와 고정 버튼을 배치한다.
  private let containerView = UIView()
  // 닫기 버튼과 함께 고정된 시트 제목이다.
  private let titleLabel = FuturesText.label(style: .title2)
  // 제목 영역의 자연 높이를 시스템 시트 높이에 반영한다.
  private let headerStackView = UIStackView()
  // 스크롤 본문에서 설정의 범위를 안내한다.
  private let subtitleLabel = FuturesText.label(style: .footnote)
  // 화면 높이를 넘는 설정 항목만 스크롤한다.
  private let scrollView = UIScrollView()
  // 모든 설정 섹션의 콘텐츠 높이를 결정한다.
  private let bodyStackView = UIStackView()
  // 시스템 테마 안내를 제목 옆에 표시한다.
  private let appThemeHeaderStackView = UIStackView()
  // 시스템 모드에서만 기기 설정을 따르는 의미를 보여준다.
  private let automaticThemeLabel = FuturesText.label(style: .caption1)
  // 세 테마 선택 버튼을 기본 크기에서는 가로로 묶는다.
  private let appThemeStackView = UIStackView()
  // 선택 상태를 저장 전 임시 테마와 동기화한다.
  private let appThemeButtons = (0..<3).map { _ in UIButton(type: .system) }
  // 캔들 색상의 의미를 섹션 제목과 함께 설명한다.
  private let candleHeaderStackView = UIStackView()
  // 한국형과 글로벌 색상 옵션을 콘텐츠 높이로 배치한다.
  private let optionsStackView = UIStackView()
  // 시세 배경 표시 설정을 독립된 카드로 묶는다.
  private let tintRow = UIView()
  // 적용하기 전 토글 선택값을 유지한다.
  private let tintSwitch = UISwitch()
  // 닫기는 취소와 동일하게 변경을 버린다.
  private let closeButton = UIButton(type: .system)
  // 스크롤 위치와 관계없이 변경을 취소한다.
  private let cancelButton = UIButton(type: .system)
  // 선택한 세 설정을 한 번에 적용한다.
  private let confirmButton = UIButton(type: .system)
  // 큰 글자에서는 하단 버튼을 세로로 바꾼다.
  private let actionsStackView = UIStackView()

  // 저장된 색상 정책을 유지하면서 시안의 두 선택지를 표시한다.
  private lazy var optionViews: [MarketColorThemeOptionView] = [
    MarketColorThemeOptionView(
      title: FuturesText.text("settings_palette_korean"),
      riseColorName: FuturesText.text("settings_color_red"),
      fallColorName: FuturesText.text("settings_color_blue"),
      riseColor: MarketColorPalette.riseRedFallBlueRiseColor,
      fallColor: MarketColorPalette.riseRedFallBlueFallColor,
      theme: .riseRedFallBlue
    ),
    MarketColorThemeOptionView(
      title: FuturesText.text("settings_palette_global"),
      riseColorName: FuturesText.text("settings_color_green"),
      fallColorName: FuturesText.text("settings_color_red"),
      riseColor: MarketColorPalette.riseGreenFallRedRiseColor,
      fallColor: MarketColorPalette.riseGreenFallRedFallColor,
      theme: .riseGreenFallRed
    )
  ]

  init() {
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    configureUI()
    bindActions()
    updateSelectionUI()
    sendSettingsViewEvent()
  }

  func prepareSheet(for width: CGFloat) {
    loadViewIfNeeded()
    updatePreferredSheetSize(for: width)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updatePreferredSheetSize(for: containerView.bounds.width)
  }

  private func updatePreferredSheetSize(for width: CGFloat) {
    guard width > Layout.contentInset * 2 else { return }
    // 현재 폭에서 콘텐츠가 요구하는 높이만 측정해 화면 크기를 가정하지 않는다.
    let headerHeight = headerStackView.systemLayoutSizeFitting(
      CGSize(width: width - Layout.contentInset * 2, height: 0),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
    // 스크롤의 현재 높이와 독립적으로 모든 설정 항목의 높이를 구한다.
    let bodyHeight = bodyStackView.systemLayoutSizeFitting(
      CGSize(width: width - Layout.contentInset * 2, height: 0),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
    // 큰 글자에서 세로로 바뀐 버튼 높이도 함께 반영한다.
    let actionsHeight = actionsStackView.systemLayoutSizeFitting(
      CGSize(width: width - Layout.actionsInset * 2, height: 0),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
    // 홈 표시기 영역은 시스템 시트가 별도로 계산한다.
    let padding = Layout.headerTop + Layout.bodyTop + Layout.contentInset + Layout.actionsTop + Layout.actionsInset
    // 같은 측정 결과로 시트 레이아웃이 반복되지 않게 한다.
    let size = CGSize(width: width, height: ceil(headerHeight + bodyHeight + actionsHeight + padding))
    guard preferredContentSize != size else { return }
    preferredContentSize = size
    sheetPresentationController?.invalidateDetents()
  }

  private func configureUI() {
    view.backgroundColor = .mobitColors(.surfaceElevated)
    containerView.accessibilityIdentifier = "settings.card"
    containerView.backgroundColor = .mobitColors(.surfaceElevated)
    view.addSubview(containerView)

    titleLabel.text = FuturesText.text("settings_title")
    titleLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 22, weight: .bold))
    titleLabel.accessibilityTraits.insert(.header)
    closeButton.accessibilityIdentifier = "settings.close"
    closeButton.accessibilityLabel = FuturesText.text("settings_close")
    closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)), for: .normal)
    closeButton.tintColor = MoreSettingsColors.secondaryText
    closeButton.backgroundColor = MoreSettingsColors.controlBackground
    closeButton.layer.cornerRadius = 22
    closeButton.snp.makeConstraints { $0.width.height.equalTo(44) }
    headerStackView.addArrangedSubview(titleLabel)
    headerStackView.addArrangedSubview(closeButton)
    headerStackView.alignment = .center
    headerStackView.spacing = 12
    containerView.addSubview(headerStackView)

    subtitleLabel.text = FuturesText.text("settings_description")
    subtitleLabel.textColor = MoreSettingsColors.secondaryText
    bodyStackView.axis = .vertical
    bodyStackView.spacing = 24
    bodyStackView.addArrangedSubview(subtitleLabel)
    scrollView.accessibilityIdentifier = "settings.scroll"
    scrollView.showsVerticalScrollIndicator = false
    scrollView.alwaysBounceVertical = false
    containerView.addSubview(scrollView)
    scrollView.addSubview(bodyStackView)

    appThemeHeaderStackView.addArrangedSubview(sectionLabel("settings_app_theme"))
    automaticThemeLabel.text = FuturesText.text("settings_theme_automatic")
    automaticThemeLabel.textColor = MoreSettingsColors.accent
    automaticThemeLabel.textAlignment = .right
    appThemeHeaderStackView.addArrangedSubview(automaticThemeLabel)
    configureSectionHeader(appThemeHeaderStackView)
    appThemeStackView.spacing = 4
    appThemeStackView.distribution = .fillEqually
    appThemeStackView.isLayoutMarginsRelativeArrangement = true
    appThemeStackView.layoutMargins = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
    appThemeStackView.backgroundColor = MoreSettingsColors.controlBackground
    appThemeStackView.layer.cornerRadius = 16
    for (index, button) in appThemeButtons.enumerated() {
      button.tag = index
      button.layer.cornerRadius = 12
      button.layer.cornerCurve = .continuous
      button.clipsToBounds = true
      button.titleLabel?.adjustsFontForContentSizeCategory = true
      button.snp.makeConstraints { $0.height.greaterThanOrEqualTo(44) }
      appThemeStackView.addArrangedSubview(button)
    }
    // 앱 테마 선택은 본문 안에서 독립된 섹션을 이룬다.
    let appThemeSection = UIStackView(arrangedSubviews: [appThemeHeaderStackView, appThemeStackView])
    appThemeSection.axis = .vertical
    appThemeSection.spacing = 12
    bodyStackView.addArrangedSubview(appThemeSection)

    candleHeaderStackView.addArrangedSubview(sectionLabel("settings_candle_color"))
    // 실제 차트의 상승·하락 색상 기준을 설명한다.
    let candleHint = FuturesText.label(style: .caption1)
    candleHint.text = FuturesText.text("settings_candle_hint")
    candleHint.textColor = MoreSettingsColors.secondaryText
    candleHint.textAlignment = .right
    candleHeaderStackView.addArrangedSubview(candleHint)
    configureSectionHeader(candleHeaderStackView)
    optionsStackView.axis = .vertical
    optionsStackView.spacing = 12
    optionViews.forEach { optionsStackView.addArrangedSubview($0) }
    // 캔들 옵션은 저장값을 초기 선택으로 사용한다.
    let candleSection = UIStackView(arrangedSubviews: [candleHeaderStackView, optionsStackView])
    candleSection.axis = .vertical
    candleSection.spacing = 12
    bodyStackView.addArrangedSubview(candleSection)
    configureTintRow()
    bodyStackView.addArrangedSubview(tintRow)

    // 하단 버튼은 본문 길이와 관계없이 시트 아래에 남는다.
    let footer = UIView()
    containerView.addSubview(footer)
    // 본문과 고정 버튼 사이의 경계를 옅게 표시한다.
    let footerDivider = UIView()
    footerDivider.backgroundColor = .mobitColors(.borderPrimary).withAlphaComponent(0.45)
    footer.addSubview(footerDivider)
    actionsStackView.accessibilityIdentifier = "settings.actions"
    actionsStackView.spacing = 12
    actionsStackView.distribution = .fillEqually
    actionsStackView.addArrangedSubview(cancelButton)
    actionsStackView.addArrangedSubview(confirmButton)
    footer.addSubview(actionsStackView)
    cancelButton.accessibilityIdentifier = "settings.cancel"
    confirmButton.accessibilityIdentifier = "settings.apply"
    [cancelButton, confirmButton].forEach {
      $0.titleLabel?.adjustsFontForContentSizeCategory = true
      $0.layer.cornerRadius = 16
      $0.layer.cornerCurve = .continuous
      $0.clipsToBounds = true
      $0.snp.makeConstraints { $0.height.greaterThanOrEqualTo(52) }
    }

    containerView.snp.makeConstraints {
      $0.edges.equalTo(view.safeAreaLayoutGuide)
    }
    headerStackView.snp.makeConstraints {
      $0.top.equalToSuperview().inset(Layout.headerTop)
      $0.horizontalEdges.equalToSuperview().inset(Layout.contentInset)
    }
    scrollView.snp.makeConstraints {
      $0.top.equalTo(headerStackView.snp.bottom).offset(Layout.bodyTop)
      $0.horizontalEdges.equalToSuperview()
      $0.bottom.equalTo(footer.snp.top)
      $0.height.greaterThanOrEqualTo(44)
    }
    bodyStackView.snp.makeConstraints {
      $0.edges.equalTo(scrollView.contentLayoutGuide).inset(UIEdgeInsets(top: 0, left: Layout.contentInset, bottom: Layout.contentInset, right: Layout.contentInset))
      $0.width.equalTo(scrollView.frameLayoutGuide).offset(-Layout.contentInset * 2)
    }
    footer.snp.makeConstraints { $0.horizontalEdges.bottom.equalToSuperview() }
    footerDivider.snp.makeConstraints {
      $0.horizontalEdges.top.equalToSuperview()
      $0.height.equalTo(0.5)
    }
    actionsStackView.snp.makeConstraints {
      $0.edges.equalToSuperview().inset(UIEdgeInsets(top: Layout.actionsTop, left: Layout.actionsInset, bottom: Layout.actionsInset, right: Layout.actionsInset))
    }
    updateTextLayout()
    updateColors()
  }

  private func configureTintRow() {
    tintRow.layer.cornerRadius = 16
    tintRow.layer.cornerCurve = .continuous
    tintRow.layer.borderWidth = 1
    tintRow.backgroundColor = MoreSettingsColors.optionBackground
    // 보조 설명까지 함께 줄바꿈해 작은 화면에서도 토글을 누를 수 있게 한다.
    let tintTitle = FuturesText.label(style: .subheadline)
    tintTitle.text = FuturesText.text("settings_price_tint")
    tintTitle.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
    // 실제로 배경 강조가 적용되는 시세 목록만 안내한다.
    let tintDescription = FuturesText.label(style: .footnote)
    tintDescription.text = FuturesText.text("settings_price_tint_description")
    tintDescription.textColor = MoreSettingsColors.secondaryText
    // 두 문구가 토글 높이와 독립적으로 카드 높이를 늘린다.
    let text = UIStackView(arrangedSubviews: [tintTitle, tintDescription])
    text.axis = .vertical
    text.spacing = 4
    tintSwitch.accessibilityIdentifier = "settings.priceTint"
    tintSwitch.accessibilityLabel = FuturesText.text("settings_price_tint")
    tintSwitch.accessibilityHint = FuturesText.text("settings_price_tint_description")
    tintSwitch.onTintColor = MoreSettingsColors.button
    tintSwitch.isOn = UserDataManager.marketCellTintEnabled
    tintSwitch.setContentHuggingPriority(.required, for: .horizontal)
    tintSwitch.setContentCompressionResistancePriority(.required, for: .horizontal)
    // 표준 스위치의 조작 영역을 포함해 카드 내용을 정렬한다.
    let row = UIStackView(arrangedSubviews: [text, tintSwitch])
    row.alignment = .center
    row.spacing = 12
    tintRow.addSubview(row)
    row.snp.makeConstraints { $0.edges.equalToSuperview().inset(16) }
  }

  private func sectionLabel(_ key: String) -> UILabel {
    // 각 설정 항목을 접근성 제목으로 읽는다.
    let label = FuturesText.label(style: .subheadline)
    label.text = FuturesText.text(key)
    label.textColor = MoreSettingsColors.secondaryText
    label.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 12, weight: .semibold))
    label.accessibilityTraits.insert(.header)
    return label
  }

  private func configureSectionHeader(_ stack: UIStackView) {
    stack.alignment = .firstBaseline
    stack.distribution = .fillEqually
    stack.spacing = 8
  }

  private func configureActionButton(_ button: UIButton, title: String, primary: Bool) {
    // 큰 글자에서도 현재 화면의 글자 크기를 사용한다.
    let font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 16, weight: .semibold), compatibleWith: traitCollection)
    // 제목 줄바꿈과 여백을 버튼 높이 계산에 포함한다.
    var configuration = UIButton.Configuration.filled()
    configuration.title = FuturesText.text(title)
    configuration.baseBackgroundColor = primary ? MoreSettingsColors.button : MoreSettingsColors.controlBackground
    configuration.baseForegroundColor = primary ? .white : .mobitColors(.textSecondary)
    configuration.titleLineBreakMode = .byWordWrapping
    configuration.titleAlignment = .center
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
    configuration.cornerStyle = .fixed
    configuration.background.cornerRadius = 16
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      // 선택 상태가 바뀌어도 설정한 글꼴을 유지한다.
      var attributes = incoming
      attributes.font = font
      return attributes
    }
    button.configuration = configuration
  }

  private func updateTextLayout() {
    // 큰 글자에서는 가로로 압축하지 않고 본문을 스크롤한다.
    let largeText = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    appThemeStackView.axis = largeText ? .vertical : .horizontal
    actionsStackView.axis = largeText ? .vertical : .horizontal
    [appThemeHeaderStackView, candleHeaderStackView].forEach {
      $0.axis = largeText ? .vertical : .horizontal
      $0.alignment = largeText ? .fill : .firstBaseline
      $0.distribution = largeText ? .fill : .fillEqually
      $0.arrangedSubviews.compactMap { $0 as? UILabel }.last?.textAlignment = largeText ? .left : .right
    }
    configureActionButton(cancelButton, title: "settings_cancel", primary: false)
    configureActionButton(confirmButton, title: "settings_apply", primary: true)
    updateThemeButtons()
  }

  private func updateThemeButtons() {
    // 시스템을 선택했을 때만 자동 전환의 의미를 안내한다.
    automaticThemeLabel.isHidden = pendingAppTheme != .system
    for (index, button) in appThemeButtons.enumerated() {
      // 기존 저장값과 같은 순서로 테마를 구분한다.
      let theme = appTheme(for: index)
      // 모드의 의미는 아이콘으로, 선택 여부는 배경으로도 구분한다.
      let symbol = index == 0 ? "display" : index == 1 ? "sun.max" : "moon"
      // 버튼 문구는 기존 번역 테이블에서 읽는다.
      let titleKey = index == 0 ? "settings_theme_system" : index == 1 ? "settings_theme_light" : "settings_theme_dark"
      // 접근성과 테스트에서 각 테마를 구분한다.
      let identifier = index == 0 ? "system" : index == 1 ? "light" : "dark"
      // 낮과 밤을 나타내는 아이콘 색은 글자색과 구분한다.
      let iconColor: UIColor = index == 0 ? MoreSettingsColors.accent : index == 1 ? .systemOrange : .systemPurple
      // 현재 화면의 글자 크기에 맞춰 테마 버튼 글꼴을 계산한다.
      let font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 13, weight: .semibold), compatibleWith: traitCollection)
      // 기본 선택 효과가 시안의 카드 배경을 회색으로 덮지 않게 한다.
      let backgroundColor: UIColor = theme == pendingAppTheme ? .mobitColors(.surfaceElevated) : .clear
      // 아이콘과 문구를 포함해 버튼 높이가 자연스럽게 늘어난다.
      var configuration = UIButton.Configuration.plain()
      configuration.title = FuturesText.text(titleKey)
      configuration.image = UIImage(systemName: symbol)
      configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
      configuration.imageColorTransformer = UIConfigurationColorTransformer { _ in iconColor }
      configuration.imagePadding = 6
      configuration.titleAlignment = .center
      configuration.titleLineBreakMode = .byWordWrapping
      configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 4, bottom: 10, trailing: 4)
      configuration.cornerStyle = .fixed
      configuration.background.cornerRadius = 12
      configuration.background.backgroundColor = backgroundColor
      configuration.background.backgroundColorTransformer = UIConfigurationColorTransformer { _ in backgroundColor }
      configuration.baseForegroundColor = theme == pendingAppTheme ? .mobitColors(.textPrimary) : .mobitColors(.textSecondary)
      configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        // 선택이 바뀌어도 글자 확대 비율을 유지한다.
        var attributes = incoming
        attributes.font = font
        return attributes
      }
      button.configuration = configuration
      button.backgroundColor = .clear
      button.isSelected = theme == pendingAppTheme
      button.accessibilityIdentifier = "settings.theme.\(identifier)"
      button.accessibilityTraits = theme == pendingAppTheme ? [.button, .selected] : .button
    }
  }

  private func updateColors() {
    tintRow.layer.borderColor = UIColor.mobitColors(.borderPrimary).resolvedColor(with: traitCollection).cgColor
  }

  private func bindActions() {
    closeButton.addTarget(self, action: #selector(tapOnCancelButton), for: .touchUpInside)
    cancelButton.addTarget(self, action: #selector(tapOnCancelButton), for: .touchUpInside)
    confirmButton.addTarget(self, action: #selector(tapOnConfirmButton), for: .touchUpInside)
    appThemeButtons.forEach { $0.addTarget(self, action: #selector(didChangeAppTheme(_:)), for: .touchUpInside) }
    tintSwitch.addTarget(self, action: #selector(didChangeTintSwitch(_:)), for: .valueChanged)
    optionViews.forEach { $0.addTarget(self, action: #selector(tapOnOptionView(_:)), for: .touchUpInside) }
  }

  private func updateSelectionUI() {
    optionViews.forEach { $0.isSelectedTheme = $0.theme == pendingTheme }
    updateThemeButtons()
  }

  @objc private func tapOnCancelButton() {
	self.dismiss(animated: true)
  }
  
  @objc private func tapOnConfirmButton() {
	let previousTheme = UserDataManager.marketColorTheme
	let previousTintEnabled = UserDataManager.marketCellTintEnabled
	let previousAppTheme = UserDataManager.appTheme
	let changeStatus = previousTheme == self.pendingTheme &&
	  previousAppTheme == self.pendingAppTheme &&
	  previousTintEnabled == self.tintSwitch.isOn
	  ? "변경없음" : "변경있음"

	MobitAnalyticsUtil.sendClickEvent(
	  location: "더보기_화면",
	  stepDepth01: "더보기_설정",
	  stepDepth02: "설정_적용",
	  stepDepth03: self.analyticsThemeName(self.pendingTheme),
	  extraParameters: [
		"selected_app_theme": self.analyticsAppThemeName(self.pendingAppTheme),
		"selected_theme": self.analyticsThemeName(self.pendingTheme),
		"background_tint": self.tintSwitch.isOn ? "켜짐" : "꺼짐",
		"previous_app_theme": self.analyticsAppThemeName(previousAppTheme),
		"previous_theme": self.analyticsThemeName(previousTheme),
		"previous_background_tint": previousTintEnabled ? "켜짐" : "꺼짐",
		"change_status": changeStatus
	  ]
	)
	UserDataManager.appTheme = self.pendingAppTheme
	UserDataManager.marketColorTheme = self.pendingTheme
	UserDataManager.marketCellTintEnabled = self.tintSwitch.isOn
	self.applyAppTheme(self.pendingAppTheme)
	self.dismiss(animated: true)
  }

  @objc private func didChangeAppTheme(_ sender: UIButton) {
	guard self.appTheme(for: sender.tag) != self.pendingAppTheme else { return }
	self.pendingAppTheme = self.appTheme(for: sender.tag)
	self.updateThemeButtons()
	MobitAnalyticsUtil.sendClickEvent(
	  location: "더보기_화면",
	  stepDepth01: "더보기_설정",
	  stepDepth02: "앱_테마_선택",
	  stepDepth03: self.analyticsAppThemeName(self.pendingAppTheme),
	  extraParameters: [
		"selected_app_theme": self.analyticsAppThemeName(self.pendingAppTheme),
		"selected_theme": self.analyticsThemeName(self.pendingTheme),
		"background_tint": self.tintSwitch.isOn ? "켜짐" : "꺼짐"
	  ]
	)
  }
  
  @objc private func tapOnOptionView(_ sender: MarketColorThemeOptionView) {
	self.pendingTheme = sender.theme
	self.updateSelectionUI()
	MobitAnalyticsUtil.sendClickEvent(
	  location: "더보기_화면",
	  stepDepth01: "더보기_설정",
	  stepDepth02: "캔들_테마_선택",
	  stepDepth03: self.analyticsThemeName(sender.theme),
	  extraParameters: [
		"selected_theme": self.analyticsThemeName(sender.theme),
		"background_tint": self.tintSwitch.isOn ? "켜짐" : "꺼짐"
	  ]
	)
  }

  @objc private func didChangeTintSwitch(_ sender: UISwitch) {
	MobitAnalyticsUtil.sendClickEvent(
	  location: "더보기_화면",
	  stepDepth01: "더보기_설정",
	  stepDepth02: "배경색_토글_변경",
	  stepDepth03: sender.isOn ? "켜짐" : "꺼짐",
	  extraParameters: [
		"selected_app_theme": self.analyticsAppThemeName(self.pendingAppTheme),
		"background_tint": sender.isOn ? "켜짐" : "꺼짐",
		"selected_theme": self.analyticsThemeName(self.pendingTheme)
	  ]
	)
  }

  private func sendSettingsViewEvent() {
	MobitAnalyticsUtil.sendClickEvent(
	  location: "더보기_화면",
	  stepDepth01: "더보기_설정",
	  stepDepth02: "설정_화면_노출",
	  stepDepth03: self.analyticsThemeName(self.pendingTheme),
	  extraParameters: [
		"selected_app_theme": self.analyticsAppThemeName(self.pendingAppTheme),
		"selected_theme": self.analyticsThemeName(self.pendingTheme),
		"background_tint": self.tintSwitch.isOn ? "켜짐" : "꺼짐"
	  ]
	)
  }

  private func analyticsThemeName(_ theme: UserDataManager.MarketColorTheme) -> String {
	switch theme {
	case .riseRedFallBlue:
	  return "한국형"
	case .riseGreenFallRed:
	  return "글로벌"
	}
  }

  private func appTheme(for index: Int) -> UserDataManager.AppTheme {
	switch index {
	case 1:
	  return .light
	case 2:
	  return .dark
	default:
	  return .system
	}
  }

  private func analyticsAppThemeName(_ theme: UserDataManager.AppTheme) -> String {
	switch theme {
	case .system:
	  return "시스템"
	case .light:
	  return "라이트"
	case .dark:
	  return "다크"
	}
  }

  private func applyAppTheme(_ theme: UserDataManager.AppTheme) {
	UIApplication.shared.connectedScenes
	  .compactMap { $0 as? UIWindowScene }
	  .flatMap { $0.windows }
	  .forEach { $0.overrideUserInterfaceStyle = theme.userInterfaceStyle }
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
      updateTextLayout()
    }
    if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true {
      updateThemeButtons()
      updateColors()
    }
  }
}

private final class MarketColorThemeOptionView: UIControl {
  // 저장값과 선택 카드가 같은 색상 정책을 사용한다.
  let theme: UserDataManager.MarketColorTheme
  // 선택 테두리와 옅은 배경을 표시한다.
  private let cardView = UIView()
  // 기본 크기에서는 아이콘·문구·선택 표시를 가로로 묶는다.
  private let contentStackView = UIStackView()
  // 큰 글자에서는 색상 아이콘과 라디오를 문구 위로 옮긴다.
  private let iconHeaderStackView = UIStackView()
  // 팔레트 두 색을 겹친 원으로 표시한다.
  private let paletteView = UIView()
  // 상승 색상을 방향 아이콘과 함께 표시한다.
  private let firstPaletteView = UIView()
  // 하락 색상을 방향 아이콘과 함께 표시한다.
  private let secondPaletteView = UIView()
  // 제목과 설명을 콘텐츠 높이에 맞춘다.
  private let textStackView = UIStackView()
  // 긴 번역과 큰 글자에서도 제목을 줄바꿈한다.
  private let titleLabel = MoreContentLabel(textStyle: .headline)
  // 글로벌 색상 선택에 시안의 보조 배지를 붙인다.
  private let recommendedLabel = MoreBadgeLabel(style: .currentAccount)
  // 상승·하락 의미를 글자와 색으로 함께 설명한다.
  private let descriptionLabel = FuturesText.label(style: .footnote)
  // 선택 여부를 색상 이외의 형태로 구분한다.
  private let radioOuterView = UIView()
  // 선택된 옵션의 안쪽 점이다.
  private let radioInnerView = UIView()

  // 저장 전 임시 선택만 카드 스타일에 반영한다.
  var isSelectedTheme: Bool = false {
    didSet { updateSelectionStyle() }
  }

  init(
    title: String,
    riseColorName: String,
    fallColorName: String,
    riseColor: UIColor,
    fallColor: UIColor,
    theme: UserDataManager.MarketColorTheme
  ) {
    self.theme = theme
    super.init(frame: .zero)
    configureUI(
      title: title,
      riseColorName: riseColorName,
      fallColorName: fallColorName,
      riseColor: riseColor,
      fallColor: fallColor
    )
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func configureUI(
    title: String,
    riseColorName: String,
    fallColorName: String,
    riseColor: UIColor,
    fallColor: UIColor
  ) {
    accessibilityIdentifier = "settings.palette.\(theme.rawValue)"
    isAccessibilityElement = true
    addSubview(cardView)
    cardView.layer.cornerRadius = 16
    cardView.layer.cornerCurve = .continuous
    cardView.isUserInteractionEnabled = false
    cardView.addSubview(contentStackView)
    contentStackView.spacing = 12
    cardView.snp.makeConstraints { $0.edges.equalToSuperview() }
    contentStackView.snp.makeConstraints { $0.edges.equalToSuperview().inset(16) }
    snp.makeConstraints { $0.height.greaterThanOrEqualTo(72) }

    paletteView.addSubview(firstPaletteView)
    paletteView.addSubview(secondPaletteView)
    configurePaletteView(firstPaletteView, color: riseColor, symbol: "arrowtriangle.up.fill")
    configurePaletteView(secondPaletteView, color: fallColor, symbol: "arrowtriangle.down.fill")
    paletteView.snp.makeConstraints { $0.width.equalTo(42); $0.height.equalTo(24) }
    firstPaletteView.snp.makeConstraints { $0.leading.top.bottom.equalToSuperview(); $0.width.equalTo(24) }
    secondPaletteView.snp.makeConstraints { $0.trailing.top.bottom.equalToSuperview(); $0.width.equalTo(24) }
    radioOuterView.layer.cornerRadius = 10
    radioOuterView.layer.borderWidth = 2
    radioOuterView.clipsToBounds = true
    radioInnerView.layer.cornerRadius = 5
    radioInnerView.clipsToBounds = true
    radioOuterView.addSubview(radioInnerView)
    radioOuterView.snp.makeConstraints { $0.width.height.equalTo(20) }
    radioInnerView.snp.makeConstraints { $0.center.equalToSuperview(); $0.width.height.equalTo(10) }
    // 큰 글자에서도 방향 아이콘과 선택 표시 사이 여유를 유지한다.
    let headerSpace = UIView()
    headerSpace.snp.makeConstraints { $0.height.equalTo(0) }
    iconHeaderStackView.addArrangedSubview(headerSpace)
    iconHeaderStackView.alignment = .center

    titleLabel.text = title
    recommendedLabel.text = FuturesText.text("settings_palette_recommended")
    recommendedLabel.isHidden = theme != .riseGreenFallRed
    titleLabel.setContentCompressionResistancePriority(UILayoutPriority(751), for: .horizontal)
    textStackView.axis = .vertical
    textStackView.spacing = 5
    textStackView.addArrangedSubview(makeMoreBadgeHeading(titleLabel: titleLabel, badgeLabel: recommendedLabel))
    textStackView.addArrangedSubview(descriptionLabel)
    // 번역 문장의 순서를 유지하면서 색상 이름만 실제 팔레트로 강조한다.
    let description = String(format: FuturesText.text("settings_palette_description"), riseColorName, fallColorName)
    // 글꼴은 라벨에 맡겨 Dynamic Type 변경 시에도 크기를 갱신한다.
    let styledDescription = NSMutableAttributedString(string: description)
    styledDescription.addAttribute(.foregroundColor, value: riseColor, range: (description as NSString).range(of: riseColorName))
    styledDescription.addAttribute(.foregroundColor, value: fallColor, range: (description as NSString).range(of: fallColorName, options: .backwards))
    descriptionLabel.textColor = MoreSettingsColors.secondaryText
    descriptionLabel.attributedText = styledDescription
    accessibilityLabel = [title, theme == .riseGreenFallRed ? FuturesText.text("settings_palette_recommended") : nil, description].compactMap { $0 }.joined(separator: ". ")
    updateTextLayout()
    updateSelectionStyle()
  }

  private func configurePaletteView(_ view: UIView, color: UIColor, symbol: String) {
    view.backgroundColor = color
    view.layer.cornerRadius = 12
    view.layer.borderWidth = 2
    view.clipsToBounds = true
    // 색상을 볼 수 없어도 상승·하락 방향을 알 수 있게 한다.
    let direction = UIImageView(image: UIImage(systemName: symbol))
    direction.tintColor = .white
    direction.contentMode = .scaleAspectFit
    view.addSubview(direction)
    direction.snp.makeConstraints { $0.edges.equalToSuperview().inset(6) }
  }

  private func updateTextLayout() {
    // 좁은 문구 열을 강제하지 않고 접근성 글씨에는 카드 전체 폭을 준다.
    let axis: NSLayoutConstraint.Axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
    guard contentStackView.axis != axis || contentStackView.arrangedSubviews.isEmpty else { return }
    contentStackView.arrangedSubviews.forEach {
      contentStackView.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    [paletteView, textStackView, radioOuterView].forEach { $0.removeFromSuperview() }
    contentStackView.axis = axis
    contentStackView.alignment = axis == .vertical ? .fill : .center
    if axis == .vertical {
      iconHeaderStackView.insertArrangedSubview(paletteView, at: 0)
      iconHeaderStackView.addArrangedSubview(radioOuterView)
      contentStackView.addArrangedSubview(iconHeaderStackView)
      contentStackView.addArrangedSubview(textStackView)
    } else {
      contentStackView.addArrangedSubview(paletteView)
      contentStackView.addArrangedSubview(textStackView)
      contentStackView.addArrangedSubview(radioOuterView)
    }
  }

  private func updateSelectionStyle() {
    cardView.layer.borderWidth = isSelectedTheme ? 2 : 1
    cardView.layer.borderColor = (isSelectedTheme ? MoreSettingsColors.accent : UIColor.mobitColors(.borderPrimary)).resolvedColor(with: traitCollection).cgColor
    cardView.backgroundColor = isSelectedTheme ? MoreSettingsColors.accent.withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.09 : 0.025) : MoreSettingsColors.optionBackground
    radioOuterView.layer.borderColor = (isSelectedTheme ? MoreSettingsColors.accent : UIColor.mobitColors(.borderPrimary)).resolvedColor(with: traitCollection).cgColor
    radioInnerView.backgroundColor = isSelectedTheme ? MoreSettingsColors.accent : .clear
    [firstPaletteView, secondPaletteView].forEach {
      $0.layer.borderColor = UIColor.mobitColors(.surfaceElevated).resolvedColor(with: traitCollection).cgColor
    }
    accessibilityTraits = isSelectedTheme ? [.button, .selected] : .button
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
      updateTextLayout()
    }
    if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true {
      updateSelectionStyle()
    }
  }
}
