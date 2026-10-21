//
//  InvestmentTableViewCell.swift
//  Mobit
//
//  Created by 조성재 on 4/9/25.
//

import UIKit

final class InvestmentTableViewCell: UITableViewCell {
  @IBOutlet weak var cryptoName: UILabel!
  @IBOutlet weak var cryptoAmount: UILabel!
  @IBOutlet weak var cryptoEvalPrice: UILabel!
  @IBOutlet weak var cryptoEvalLoss: UILabel!
  @IBOutlet weak var cryptoAveragePrice: UILabel!
  @IBOutlet weak var cryptoBuyPrice: UILabel!
  @IBOutlet weak var cryptoProfitRate: UILabel!
  @IBOutlet weak var bgView: UIView!
  @IBOutlet weak var dividerView: UIView!
  @IBOutlet weak var metricsStackView: UIStackView!
  @IBOutlet weak var amountTitle: UILabel!
  @IBOutlet weak var averagePriceTitle: UILabel!
  @IBOutlet weak var buyPriceTitle: UILabel!
  @IBOutlet weak var profitRateTitle: UILabel!
  // 종목명 아래에서 거래 마켓과 결제 통화를 확인한다.
  @IBOutlet weak var marketSymbolLabel: UILabel!
  // 손익 수치의 의미를 헤더 우측에 표시한다.
  @IBOutlet private weak var evaluationTitle: UILabel!
  // 현물과 선물에 공통으로 평가금액 제목을 표시한다.
  @IBOutlet private weak var evaluationAmountTitle: UILabel!
  // 종목 헤더와 보유 지표를 구분한다.
  @IBOutlet private weak var headerDividerView: UIView!
  // 미지원 안내까지 포함해 셀 높이를 콘텐츠에 맞춘다.
  @IBOutlet private weak var bodyStackView: UIStackView!
  // 종목명, 마켓, 포지션 배지를 한 묶음으로 배치한다.
  @IBOutlet private weak var identityStackView: UIStackView!
  // 현물에서는 숨기고 선물의 방향과 레버리지만 표시한다.
  @IBOutlet private weak var positionBadgesStackView: UIStackView!
  // 포지션 방향을 색상 외에 텍스트로도 구분한다.
  @IBOutlet private weak var sideBadgeView: UIView!
  // 현재 포지션의 롱 또는 숏 방향을 표시한다.
  @IBOutlet weak var sideBadgeLabel: UILabel!
  // 방향과 별도로 레버리지 배경을 표시한다.
  @IBOutlet private weak var leverageBadgeView: UIView!
  // 현재 포지션의 레버리지를 표시한다.
  @IBOutlet weak var leverageBadgeLabel: UILabel!
  // 수량의 기초자산 심볼을 숫자와 분리한다.
  @IBOutlet private weak var quantityUnitLabel: UILabel!
  // 매수평균가의 결제 통화를 구분한다.
  @IBOutlet private weak var averagePriceUnitLabel: UILabel!
  // 평가금액이 원화 기준임을 표시한다.
  @IBOutlet private weak var evaluationUnitLabel: UILabel!
  // 매수금액 또는 증거금의 원화 단위를 표시한다.
  @IBOutlet private weak var purchaseUnitLabel: UILabel!
  // 손익 숫자 옆에 로컬라이즈된 원화 단위를 표시한다.
  @IBOutlet private weak var profitLossUnitLabel: UILabel!
  private var currentProfitRate: Double?
  // 테마 변경 시 포지션 배지의 방향 색상을 다시 반영한다.
  private var currentSide: FuturesSide?
  private let unsupportedBadgeView = UIView()
  private let unsupportedBadgeIcon = UIImageView()
  private let unsupportedBadgeLabel = UILabel()
  private let unsupportedNoticeView = UIView()
  private let unsupportedNoticeDot = UIView()
  private let unsupportedNoticeLabel = UILabel()

  override func awakeFromNib() {
    super.awakeFromNib()
    setupUnsupportedStatusViews()
    evaluationTitle.text = FuturesText.text("investment_valuation_gain_loss")
    evaluationAmountTitle.text = FuturesText.text("investment_evaluation_amount")
    profitLossUnitLabel.text = FuturesText.text("currency_krw_unit")
    evaluationUnitLabel.text = SettlementCurrency.krw.rawValue
    purchaseUnitLabel.text = SettlementCurrency.krw.rawValue
    marketSymbolLabel.accessibilityIdentifier = "investment.cell.market"
    sideBadgeLabel.accessibilityIdentifier = "investment.cell.side"
    leverageBadgeLabel.accessibilityIdentifier = "investment.cell.leverage"
    sideBadgeView.layer.cornerRadius = 6
    leverageBadgeView.layer.cornerRadius = 6
    positionBadgesStackView.isHidden = true
    updateThemeColors()
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    currentSide = nil
    positionBadgesStackView.isHidden = true
    sideBadgeLabel.text = nil
    leverageBadgeLabel.text = nil
    setTradingUnsupported(false)
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true {
      updateThemeColors()
    }
  }

  func configure(
    crypto: CryptoTransactionDataModel,
    isLast: Bool,
    isTradingUnsupported: Bool = false
  ) {
    // BTC 마켓의 평균가는 BTC 단위를 유지하고 평가금액만 기존 원화 환산을 사용한다.
    let valuation = PortfolioCalculator.valuation(
      of: crypto,
      btcKRWPrice: AppDataManager.shared.lastBTCKRWPrice(for: crypto.staticData.exchange)
    )
    // 수량과 마켓 표시에 동일한 기초자산 심볼을 사용한다.
    let market = crypto.staticData.marketName
    cryptoName.text = crypto.staticData.cryptoName.flatMap { $0.isEmpty ? nil : $0 } ?? market
    marketSymbolLabel.text = market
    amountTitle.text = FuturesText.text("investment_quantity")
    averagePriceTitle.text = FuturesText.text("investment_average_price")
    buyPriceTitle.text = FuturesText.text("investment_buy_amount")
    profitRateTitle.text = FuturesText.text("investment_profit_rate")
    cryptoAmount.text = crypto.staticData.holdingQuantity.formatTradingValue()
    quantityUnitLabel.text = market.split(separator: "/").first.map(String.init)
    averagePriceUnitLabel.text = crypto.settlementCurrency.rawValue
    if crypto.settlementCurrency == .btc {
      cryptoAveragePrice.text = crypto.staticData.averageBuyPrice.formatTradingValue()
    } else {
      cryptoAveragePrice.text = Self.krwText(valuation.averagePriceKRW)
    }
    cryptoBuyPrice.text = Self.krwText(valuation.costBasisKRW)
    cryptoEvalPrice.text = Self.krwText(valuation.evaluationKRW)
    cryptoEvalLoss.text = valuation.profitLossKRW.map {
      Self.signed($0.formatTradingValue(), isPositive: $0 > 0)
    } ?? "—"
    cryptoProfitRate.text = valuation.profitRate.map {
      Self.signed($0.formatSignificantDigits(digits: 2), isPositive: $0 > 0) + "%"
    } ?? "—"
    currentProfitRate = valuation.profitLossKRW
    currentSide = nil
    positionBadgesStackView.isHidden = true
    sideBadgeLabel.text = nil
    leverageBadgeLabel.text = nil
    setTradingUnsupported(isTradingUnsupported)
    dividerView.isHidden = isLast
    updateThemeColors()
  }

  func configure(position: FuturesPosition, valuation: FuturesValuation?, isLast: Bool) {
    // 거래소 선택 상태가 바뀌어도 포지션에 저장된 마켓을 표시한다.
    let market = MarketFormat.displayMarket(
      fromAPIMarket: position.order.instrument.rawSymbol,
      exchange: position.order.instrument.exchange
    )
    // 선물 모델에는 이름이 없어 심볼을 제목으로 사용한다.
    let symbol = market.split(separator: "/").first.map(String.init) ?? market
    // 원시 손실 대신 기존 청산 표시 범위를 적용한 손익을 사용한다.
    let profitLoss = try? valuation?.displayedPnL
    cryptoName.text = symbol
    marketSymbolLabel.text = market
    amountTitle.text = FuturesText.text("futures_position_quantity")
    averagePriceTitle.text = FuturesText.text("futures_entry")
    buyPriceTitle.text = FuturesText.text("futures_margin")
    profitRateTitle.text = FuturesText.text("futures_roe") + " (ROE)"
    cryptoAmount.text = FuturesText.number(position.quantity)
    quantityUnitLabel.text = symbol
    averagePriceUnitLabel.text = SettlementCurrency.krw.rawValue
    cryptoAveragePrice.text = FuturesText.number(try? position.averageEntryPrice)
    cryptoBuyPrice.text = FuturesText.number(try? position.margin)
    cryptoEvalPrice.text = FuturesText.number(valuation?.displayedEquity)
    cryptoEvalLoss.text = profitLoss.map {
      Self.signed(FuturesText.number($0), isPositive: $0 > 0)
    } ?? "—"
    cryptoProfitRate.text = valuation.map {
      Self.signed(FuturesText.number($0.displayedROEPercent, digits: 2), isPositive: $0.displayedROEPercent > 0) + "%"
    } ?? "—"
    currentProfitRate = profitLoss.map { NSDecimalNumber(decimal: $0).doubleValue }
    currentSide = position.order.side
    sideBadgeLabel.text = FuturesText.side(position.order.side)
    leverageBadgeLabel.text = "\(position.order.leverage)×"
    positionBadgesStackView.isHidden = false
    setTradingUnsupported(false)
    dividerView.isHidden = isLast
    updateThemeColors()
  }

  private func updateThemeColors() {
    backgroundColor = .mobitColors(.investmentBackground)
    contentView.backgroundColor = .mobitColors(.investmentBackground)
    bgView.backgroundColor = .mobitColors(.investmentBackground)
    dividerView.backgroundColor = Self.cellDividerColor
    headerDividerView.backgroundColor = .mobitColors(.investmentSeparator)
    [cryptoName, cryptoAmount, cryptoEvalPrice, cryptoAveragePrice, cryptoBuyPrice].forEach {
      $0?.textColor = .mobitColors(.investmentTextPrimary)
    }
    [
      marketSymbolLabel, evaluationTitle, evaluationAmountTitle, amountTitle, averagePriceTitle,
      buyPriceTitle, quantityUnitLabel, averagePriceUnitLabel, evaluationUnitLabel, purchaseUnitLabel
    ].forEach { $0?.textColor = .mobitColors(.investmentTextSecondary) }
    // 시세 색상 설정을 손익 숫자와 원화 단위, 수익률에 함께 적용한다.
    let profitColor = currentProfitRate.map { MarketColorPalette.color(forSignedValue: $0) }
      ?? UIColor.mobitColors(.investmentTextSecondary)
    [cryptoEvalLoss, profitLossUnitLabel, cryptoProfitRate, profitRateTitle].forEach { $0?.textColor = profitColor }
    // 롱과 숏도 앱의 상승·하락 색상 설정을 따른다.
    let sideColor = currentSide == .long ? MarketColorPalette.riseColor : MarketColorPalette.fallColor
    sideBadgeView.backgroundColor = sideColor.withAlphaComponent(0.09)
    sideBadgeLabel.textColor = sideColor
    leverageBadgeView.backgroundColor = .mobitColors(.investmentSurface)
    leverageBadgeLabel.textColor = .mobitColors(.investmentTextSecondary)
    unsupportedBadgeView.backgroundColor = Self.unsupportedBadgeBackgroundColor
    unsupportedBadgeView.layer.borderColor = Self.unsupportedBadgeBorderColor.resolvedColor(with: traitCollection).cgColor
    unsupportedBadgeIcon.tintColor = Self.unsupportedBadgeTextColor
    unsupportedBadgeLabel.textColor = Self.unsupportedBadgeTextColor
    unsupportedNoticeView.backgroundColor = Self.unsupportedNoticeBackgroundColor
    unsupportedNoticeView.layer.borderColor = Self.unsupportedNoticeBorderColor.resolvedColor(with: traitCollection).cgColor
    unsupportedNoticeDot.backgroundColor = Self.unsupportedNoticeTextColor
    unsupportedNoticeLabel.textColor = Self.unsupportedNoticeTextColor
  }

  private func setupUnsupportedStatusViews() {
    unsupportedBadgeView.layer.cornerRadius = 6
    unsupportedBadgeView.layer.borderWidth = 1
    unsupportedBadgeView.isAccessibilityElement = true
    unsupportedBadgeView.accessibilityLabel = FuturesText.text("investment_unsupported_badge")
    unsupportedBadgeIcon.translatesAutoresizingMaskIntoConstraints = false
    unsupportedBadgeIcon.image = UIImage(systemName: "exclamationmark.triangle")
    unsupportedBadgeIcon.contentMode = .scaleAspectFit
    unsupportedBadgeLabel.text = FuturesText.text("investment_unsupported_badge")
    unsupportedBadgeLabel.font = .preferredFont(forTextStyle: .caption2)
    unsupportedBadgeLabel.adjustsFontForContentSizeCategory = true
    unsupportedBadgeLabel.numberOfLines = 0
    // 지원 종료 배지를 종목 영역에 포함해 긴 이름과 겹치지 않게 한다.
    let badgeStack = UIStackView(arrangedSubviews: [unsupportedBadgeIcon, unsupportedBadgeLabel])
    badgeStack.translatesAutoresizingMaskIntoConstraints = false
    badgeStack.alignment = .center
    badgeStack.spacing = 4
    unsupportedBadgeView.addSubview(badgeStack)
    identityStackView.addArrangedSubview(unsupportedBadgeView)
    unsupportedNoticeView.layer.cornerRadius = 10
    unsupportedNoticeView.layer.borderWidth = 1
    unsupportedNoticeView.isAccessibilityElement = true
    unsupportedNoticeView.accessibilityLabel = FuturesText.text("investment_unsupported_notice")
    unsupportedNoticeDot.translatesAutoresizingMaskIntoConstraints = false
    unsupportedNoticeDot.layer.cornerRadius = 3
    unsupportedNoticeLabel.translatesAutoresizingMaskIntoConstraints = false
    unsupportedNoticeLabel.text = FuturesText.text("investment_unsupported_notice")
    unsupportedNoticeLabel.font = .preferredFont(forTextStyle: .caption1)
    unsupportedNoticeLabel.adjustsFontForContentSizeCategory = true
    unsupportedNoticeLabel.numberOfLines = 0
    unsupportedNoticeView.addSubview(unsupportedNoticeDot)
    unsupportedNoticeView.addSubview(unsupportedNoticeLabel)
    bodyStackView.addArrangedSubview(unsupportedNoticeView)
    // 숨겨진 arrangedSubview의 높이 0 제약과 내부 여백이 충돌하지 않게 한다.
    let badgeBottomConstraint = badgeStack.bottomAnchor.constraint(equalTo: unsupportedBadgeView.bottomAnchor, constant: -4)
    badgeBottomConstraint.priority = UILayoutPriority(999)
    // 미지원 안내를 감추면 내부 높이보다 UIStackView의 접힘 제약을 우선한다.
    let noticeBottomConstraint = unsupportedNoticeLabel.bottomAnchor.constraint(equalTo: unsupportedNoticeView.bottomAnchor, constant: -12)
    noticeBottomConstraint.priority = UILayoutPriority(999)
    NSLayoutConstraint.activate([
      badgeStack.leadingAnchor.constraint(equalTo: unsupportedBadgeView.leadingAnchor, constant: 6),
      badgeStack.trailingAnchor.constraint(equalTo: unsupportedBadgeView.trailingAnchor, constant: -6),
      badgeStack.topAnchor.constraint(equalTo: unsupportedBadgeView.topAnchor, constant: 4),
      badgeBottomConstraint,
      unsupportedBadgeView.widthAnchor.constraint(lessThanOrEqualTo: identityStackView.widthAnchor),
      unsupportedBadgeIcon.widthAnchor.constraint(equalToConstant: 12),
      unsupportedBadgeIcon.heightAnchor.constraint(equalToConstant: 12),
      unsupportedNoticeDot.leadingAnchor.constraint(equalTo: unsupportedNoticeView.leadingAnchor, constant: 12),
      unsupportedNoticeDot.centerYAnchor.constraint(equalTo: unsupportedNoticeView.centerYAnchor),
      unsupportedNoticeDot.widthAnchor.constraint(equalToConstant: 6),
      unsupportedNoticeDot.heightAnchor.constraint(equalToConstant: 6),
      unsupportedNoticeLabel.leadingAnchor.constraint(equalTo: unsupportedNoticeDot.trailingAnchor, constant: 8),
      unsupportedNoticeLabel.trailingAnchor.constraint(equalTo: unsupportedNoticeView.trailingAnchor, constant: -12),
      unsupportedNoticeLabel.topAnchor.constraint(equalTo: unsupportedNoticeView.topAnchor, constant: 12),
      noticeBottomConstraint
    ])
    setTradingUnsupported(false)
  }

  private func setTradingUnsupported(_ isUnsupported: Bool) {
    unsupportedBadgeView.isHidden = !isUnsupported
    unsupportedNoticeView.isHidden = !isUnsupported
  }

  private static func signed(_ value: String, isPositive: Bool) -> String {
    isPositive && value != "0" ? "+" + value : value
  }

  // 셀 사이만 내부 지표 구분선보다 진하게 표시하고 다크 테마는 유지한다.
  private static var cellDividerColor: UIColor {
    UIColor {
      $0.userInterfaceStyle == .dark
        ? UIColor.mobitColors(.investmentSeparator).resolvedColor(with: $0)
        : UIColor(red: 214 / 255, green: 222 / 255, blue: 233 / 255, alpha: 1)
    }
  }

  private static var unsupportedBadgeBackgroundColor: UIColor {
    UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.29, green: 0.06, blue: 0.08, alpha: 1) : UIColor(red: 1, green: 0.95, blue: 0.96, alpha: 1) }
  }

  private static var unsupportedBadgeBorderColor: UIColor {
    UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.70, green: 0.16, blue: 0.17, alpha: 1) : UIColor(red: 1, green: 0.77, blue: 0.81, alpha: 1) }
  }

  private static var unsupportedBadgeTextColor: UIColor {
    UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1, green: 0.64, blue: 0.68, alpha: 1) : UIColor(red: 0.93, green: 0.12, blue: 0.27, alpha: 1) }
  }

  private static var unsupportedNoticeBackgroundColor: UIColor {
    UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.14, green: 0.07, blue: 0.09, alpha: 1) : UIColor(red: 1, green: 0.97, blue: 0.97, alpha: 1) }
  }

  private static var unsupportedNoticeBorderColor: UIColor {
    UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.20, green: 0.09, blue: 0.11, alpha: 1) : UIColor(red: 1, green: 0.84, blue: 0.86, alpha: 1) }
  }

  private static var unsupportedNoticeTextColor: UIColor {
    UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1, green: 0.59, blue: 0.62, alpha: 1) : UIColor(red: 0.82, green: 0.08, blue: 0.20, alpha: 1) }
  }

  private static func krwText(_ amount: Double?) -> String {
    amount.map { $0.formatTradingValue() } ?? "—"
  }
}
