import UIKit

final class InvestmentSummaryView: UIView {
  // 작은 화면에서 두 금액에 적용하는 기본 글꼴 크기다.
  private static let compactBalanceFontSize: CGFloat = 18
  // 아이폰 미니를 포함해 금액 글꼴을 줄이는 화면 너비다.
  private static let compactBalanceMaximumWidth: CGFloat = 375
  // 요약과 목록의 제목을 현물·선물 계좌에 맞춰 표시한다.
  @IBOutlet private weak var holdingsTitle: UILabel!
  // 큰 글자에서는 자산 제목과 통화 단위를 별도 행으로 배치한다.
  @IBOutlet private weak var titleStack: UIStackView!
  // 세로 제목에서는 가로 여백용 뷰를 접는다.
  @IBOutlet private weak var titleSpace: UIView!
  // 요약 숫자에 공통으로 적용되는 통화 단위를 표시한다.
  @IBOutlet private weak var unitTitle: UILabel!
  // 사용 가능한 계좌 잔고의 단위를 표시한다.
  @IBOutlet private weak var availableTitle: UILabel!
  // 현금과 평가금액을 합산한 전체 자산임을 표시한다.
  @IBOutlet private weak var totalAssetsTitle: UILabel!
  // 현물 매수금액과 선물 증거금을 구분한다.
  @IBOutlet private weak var purchaseTitle: UILabel!
  // 현금과 구별되는 보유 코인·포지션 평가금액 제목이다.
  @IBOutlet private weak var evaluationTitle: UILabel!
  // 보유 자산의 미실현 손익 제목이다.
  @IBOutlet private weak var profitLossTitle: UILabel!
  // 선물에서는 증거금 기준 수익률임을 함께 표시한다.
  @IBOutlet private weak var rateTitle: UILabel!
  // 충전 배너에 계좌 자산 안내를 표시한다.
  @IBOutlet private weak var chargeNote: UILabel!
  // 현물 보유자산과 선물 보유 포지션을 구분한다.
  @IBOutlet private weak var listTitle: UILabel!
  // 현재 표시되는 종목 또는 포지션 개수다.
  @IBOutlet private weak var countLabel: UILabel!
  // 큰 글자에서는 목록 제목과 정렬을 별도 행으로 배치한다.
  @IBOutlet private weak var toolbarStack: UIStackView!
  // 세로 도구 모음에서는 가로 여백용 뷰를 접는다.
  @IBOutlet private weak var toolbarSpace: UIView!
  // 요약 계산 기준을 안내한다.
  @IBOutlet private weak var infoButton: UIButton!
  // 목록 정렬 버튼의 화살표와 접근성 제목을 설정한다.
  @IBOutlet private weak var sortButton: UIButton!
  // 충전 안내와 버튼을 담는 배너 표면이다.
  @IBOutlet private weak var chargeView: UIView!
  // 큰 글자에서도 충전 버튼이 안내 문구와 겹치지 않게 배치한다.
  @IBOutlet private weak var chargeStack: UIStackView!
  // 주문가능 금액과 총자산을 두 열로 배치한다.
  @IBOutlet private weak var balanceColumns: UIStackView!
  // 잔고를 세로로 배치할 때 중복 구분선을 감춘다.
  @IBOutlet private weak var balanceDivider: UIView!
  // 요약 상세 지표를 두 열로 배치한다.
  @IBOutlet private weak var metricColumns: UIStackView!
  // 글자 확대 시 라벨과 값을 세로로 배치한다.
  @IBOutlet private var metricRows: [UIStackView]!
  // 금액 숫자를 같은 폭의 숫자 글꼴로 표시한다.
  @IBOutlet private var valueLabels: [UILabel]!
  // 화면 너비에 따라 기본 글꼴 크기를 조정할 상단 금액이다.
  @IBOutlet private var balanceValueLabels: [UILabel]!
  // 현물 빈 목록 메시지를 현지화한다.
  @IBOutlet private weak var emptyMessageLabel: UILabel!
  // 요약 아래 남은 목록 공간을 빈 안내 영역으로 사용한다.
  @IBOutlet private weak var emptyMinimumHeight: NSLayoutConstraint!
  // XIB의 일반 화면 금액 글꼴을 크기 변경과 Dynamic Type 적용의 기준으로 보관한다.
  private var balanceBaseFont: UIFont?

  override func awakeFromNib() {
    super.awakeFromNib()
    valueLabels.forEach { label in
      label.font = .monospacedDigitSystemFont(ofSize: label.font.pointSize, weight: .bold)
    }
    balanceBaseFont = balanceValueLabels.first?.font
    prepareLabels(in: self)
    chargeView.layer.cornerRadius = 12
    chargeView.layer.cornerCurve = .continuous
    infoButton.setImage(UIImage(systemName: "info.circle"), for: .normal)
    infoButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 14), forImageIn: .normal)
    infoButton.accessibilityLabel = FuturesText.text("investment_assets_info")
    sortButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
    sortButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 12), forImageIn: .normal)
    sortButton.accessibilityLabel = FuturesText.text("sort_method")
    countLabel.textColor = .mobitColors(.accentPrimary)
    chargeNote.accessibilityIdentifier = "investment.chargeNote"
    holdingsTitle.setContentHuggingPriority(.required, for: .horizontal)
  }

  func configure(product: TradingProduct) {
    holdingsTitle.text = FuturesText.text("investment_my_assets")
    unitTitle.text = FuturesText.text("investment_unit_krw")
    availableTitle.text = FuturesText.text("investment_available_krw")
    totalAssetsTitle.text = FuturesText.text("investment_total_assets")
    purchaseTitle.text = FuturesText.text(product == .spot ? "investment_total_buy" : "investment_total_margin")
    evaluationTitle.text = FuturesText.text(product == .spot ? "futures_total_evaluation" : "investment_position_evaluation")
    profitLossTitle.text = FuturesText.text("investment_valuation_gain_loss")
    rateTitle.text = FuturesText.text("investment_return_rate")
    chargeNote.text = FuturesText.text("investment_charge_note")
    listTitle.text = FuturesText.text(product == .spot ? "investment_holdings" : "investment_positions")
    emptyMessageLabel.text = FuturesText.text(product == .spot ? "trade_no_coins" : "futures_no_position")
    applyThemeColors()
  }

  func updateCount(_ count: Int) {
    countLabel.text = String(count)
  }

  func applyThemeColors() {
    backgroundColor = .mobitColors(.investmentBackground)
    chargeView.backgroundColor = .mobitColors(.investmentSurface)
    infoButton.tintColor = .mobitColors(.investmentTextTertiary)
    sortButton.tintColor = .mobitColors(.investmentTextTertiary)
  }

  func updateLayout(in tableView: UITableView) {
    guard tableView.bounds.width > 0 else { return }
    if let balanceBaseFont {
      // XIB의 일반 크기와 작은 화면의 크기를 현재 글자 확대 설정에 맞춘다.
      let baseFont = tableView.bounds.width <= Self.compactBalanceMaximumWidth
        ? balanceBaseFont.withSize(Self.compactBalanceFontSize) : balanceBaseFont
      // 크기가 바뀐 경우에만 적용해 반복적인 레이아웃 갱신을 피한다.
      let scaledFont = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: baseFont, compatibleWith: traitCollection)
      for label in balanceValueLabels where label.font != scaledFont {
        label.font = scaledFont
      }
    }
    // 접근성 글자 크기에서는 두 열보다 원본 숫자를 모두 읽을 수 있는 배치를 우선한다.
    let expandedText = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    // 가로 배치의 원래 글자 폭은 유지하고 접근성 행에서는 전체 폭을 사용한다.
    let headingHugging: UILayoutPriority = expandedText ? .defaultLow : .required
    holdingsTitle.setContentHuggingPriority(headingHugging, for: .horizontal)
    unitTitle.setContentHuggingPriority(headingHugging, for: .horizontal)
    listTitle.setContentHuggingPriority(headingHugging, for: .horizontal)
    listTitle.numberOfLines = expandedText ? 0 : 1
    (sortButton.superview as? UIStackView)?.arrangedSubviews.first?
      .setContentHuggingPriority(headingHugging, for: .horizontal)
    titleStack.axis = expandedText ? .vertical : .horizontal
    titleStack.alignment = expandedText ? .fill : .center
    titleStack.spacing = expandedText ? 8 : 4
    titleSpace.isHidden = expandedText
    toolbarStack.axis = expandedText ? .vertical : .horizontal
    toolbarStack.alignment = .fill
    toolbarSpace.isHidden = expandedText
    balanceColumns.axis = expandedText ? .vertical : .horizontal
    balanceDivider.isHidden = expandedText
    metricColumns.axis = expandedText ? .vertical : .horizontal
    // 두 열의 번역 높이가 달라도 짧은 열의 행을 임의로 늘리지 않는다.
    metricColumns.alignment = expandedText ? .fill : .top
    metricColumns.distribution = expandedText ? .fill : .fillEqually
    chargeStack.axis = expandedText ? .vertical : .horizontal
    chargeStack.alignment = expandedText ? .leading : .center
    metricRows.forEach { row in
      row.axis = expandedText || tableView.bounds.width < 350 ? .vertical : .horizontal
      row.alignment = .fill
    }
    // 외부에서 제공하는 너비를 먼저 반영해 이전 기기 너비로 줄바꿈하지 않는다.
    frame.size.width = tableView.bounds.width
    emptyMinimumHeight.constant = 0
    // UITableView의 헤더 높이는 화면 추정값 대신 현재 너비에서 실제 콘텐츠로 계산한다.
    let fittingSize = systemLayoutSizeFitting(
      CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    )
    // 긴 요약은 계속 스크롤하고, 짧은 요약 아래에서는 남은 목록 영역을 채운다.
    var contentHeight = fittingSize.height
    // 현물과 선물이 공유하는 빈 목록 컨테이너만 확장한다.
    if let emptyView = emptyMessageLabel.superview, !emptyView.isHidden {
      // 빈 안내 자체의 최소 높이를 제외해 요약과 정렬 영역만 남긴다.
      let emptySize = emptyView.systemLayoutSizeFitting(
        CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
        withHorizontalFittingPriority: .required,
        verticalFittingPriority: .fittingSizeLevel
      )
      // 테이블의 실제 보이는 목록 영역에는 콘텐츠 바깥 여백을 포함하지 않는다.
      let viewportHeight = tableView.bounds.height - tableView.adjustedContentInset.top - tableView.adjustedContentInset.bottom
      emptyMinimumHeight.constant = max(0, viewportHeight - fittingSize.height + emptySize.height)
      contentHeight += max(0, emptyMinimumHeight.constant - emptySize.height)
    }
    // 정수 pt 올림이 만든 여유 높이 대신 실제 화면의 픽셀 경계에 맞춘다.
    let displayScale = traitCollection.displayScale
    guard displayScale > 0 else { return }
    // 같은 콘텐츠는 같은 높이를 사용해 테이블 헤더의 반복 재배치를 막는다.
    let fittedHeight = (contentHeight * displayScale).rounded() / displayScale
    guard frame.width != tableView.bounds.width || frame.height != fittedHeight else { return }
    frame.size = CGSize(width: tableView.bounds.width, height: fittedHeight)
    tableView.tableHeaderView = self
  }

  private func prepareLabels(in view: UIView) {
    // 공용 버튼은 자체적으로 글꼴을 조정하므로 이미 확대한 글꼴에 중복 적용하지 않는다.
    guard !(view is UIControl) else { return }
    view.subviews.forEach { subview in
      if let label = subview as? UILabel {
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: label.font)
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.required, for: .vertical)
      }
      prepareLabels(in: subview)
    }
  }

  static func configureNavigation(
    titleLabel: UILabel,
    historyButton: UIButton,
    exchangeButton: UIButton,
    account: TradingAccountID
  ) {
    titleLabel.text = FuturesText.text("investment_history")
    // 상단 제어 영역이 큰 글자에서 자산 목록을 밀어내지 않도록 확대 상한을 둔다.
    titleLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
      for: .systemFont(ofSize: 20, weight: .bold),
      maximumPointSize: 28
    )
    titleLabel.adjustsFontForContentSizeCategory = true
    historyButton.accessibilityLabel = FuturesText.text("investment_records")
    historyButton.accessibilityIdentifier = "investment.history"
    // 거래소 선택은 기존 Coordinator가 계좌와 소켓을 함께 전환한다.
    var exchangeStyle = UIButton.Configuration.plain()
    exchangeStyle.title = FuturesText.text(account.exchange == .bithumb ? "futures_bithumb" : "futures_upbit")
    // XIB의 기본 제목이 선택한 거래소 이름을 덮어쓰지 않도록 두 설정을 일치시킨다.
    exchangeButton.setTitle(exchangeStyle.title, for: .normal)
    exchangeStyle.image = exchangeIcon(for: account.exchange)
    exchangeButton.setImage(exchangeStyle.image, for: .normal)
    exchangeStyle.imagePlacement = .leading
    exchangeStyle.imagePadding = 6
    exchangeStyle.indicator = .popup
    exchangeStyle.baseForegroundColor = .mobitColors(.textPrimary)
    exchangeStyle.background.backgroundColor = UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? .mobitColors(.surfacePrimary)
        : .systemGray6
    }
    exchangeStyle.background.strokeWidth = 0
    exchangeStyle.background.cornerRadius = 18
    exchangeStyle.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 12)
    exchangeStyle.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      // 계좌 선택의 글자 크기도 시스템 확대 설정을 따른다.
      var updated = attributes
      updated.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
        for: .systemFont(ofSize: 13, weight: .semibold),
        maximumPointSize: 18
      )
      return updated
    }
    exchangeButton.configuration = exchangeStyle
    exchangeButton.tintColor = .mobitColors(.textSecondary)
    exchangeButton.imageView?.contentMode = .scaleAspectFit
    exchangeButton.layer.cornerCurve = .continuous
    exchangeButton.setContentHuggingPriority(.required, for: .horizontal)
    exchangeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    exchangeButton.accessibilityLabel = FuturesText.text("investment_select_exchange")
    exchangeButton.accessibilityIdentifier = "investment.exchange"
    exchangeButton.accessibilityValue = exchangeStyle.title
  }

  private static func exchangeIcon(for exchange: Exchange) -> UIImage {
    // 메인 거래소 화면과 같은 로고 자산을 사용한다.
    guard let image = UIImage(named: exchange == .upbit ? "upbit_logo" : "bithumb_logo") else { return UIImage() }
    // 기존 앱 로고를 작은 선택 버튼 크기로 맞춘다.
    let size = CGSize(width: 18, height: 18)
    return UIGraphicsImageRenderer(size: size).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }.withRenderingMode(.alwaysOriginal)
  }

}
