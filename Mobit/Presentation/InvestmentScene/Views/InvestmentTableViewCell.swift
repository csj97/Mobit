//
//  InvestmentTableViewCell.swift
//  Mobit
//
//  Created by 조성재 on 4/9/25.
//

import UIKit

final class InvestmentTableViewCell: UITableViewCell {
  // 종료 자산의 배경 내용이 흐릿하게 비치도록 블러 강도를 조절한다.
  private static let unsupportedBlurFraction: CGFloat = 0.3

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
  // 거래지원 종료 시 보유 내역을 흐리게 가리는 영역이다.
  @IBOutlet weak var unsupportedOverlayView: UIVisualEffectView!
  // 거래지원 종료 상태를 안내한다.
  @IBOutlet weak var unsupportedNoticeLabel: UILabel!
  // 거래지원 종료 자산의 정산 확인을 연다.
  @IBOutlet weak var unsupportedSettlementButton: UIButton!
  // 종목명 아래에서 거래 마켓과 결제 통화를 확인한다.
  @IBOutlet weak var marketSymbolLabel: UILabel!
  // 손익 수치의 의미를 헤더 우측에 표시한다.
  @IBOutlet private weak var evaluationTitle: UILabel!
  // 현물과 선물에 공통으로 평가금액 제목을 표시한다.
  @IBOutlet private weak var evaluationAmountTitle: UILabel!
  // 종목 헤더와 보유 지표를 구분한다.
  @IBOutlet private weak var headerDividerView: UIView!
  // 셀의 본문을 콘텐츠에 맞춰 배치한다.
  @IBOutlet private weak var bodyStackView: UIStackView!
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
  // 거래지원 종료 자산의 정산 확인 동작을 화면에 전달한다.
  var unsupportedSettlementCallBack: (() -> Void)?
  // XIB에서 지정한 블러 효과를 원래 강도보다 약하게 적용할 때 사용한다.
  private var unsupportedBlurEffect: UIVisualEffect?
  // 효과의 진행 정도를 유지해 안내와 버튼을 선명하게 표시한다.
  private var unsupportedBlurAnimator: UIViewPropertyAnimator?

  override func awakeFromNib() {
    super.awakeFromNib()
    unsupportedBlurEffect = unsupportedOverlayView.effect
    unsupportedNoticeLabel.text = FuturesText.text("investment_unsupported_notice")
    unsupportedNoticeLabel.accessibilityIdentifier = "investment.unsupported.notice"
    unsupportedSettlementButton.setTitle(FuturesText.text("investment_unsupported_settlement"), for: .normal)
    unsupportedSettlementButton.accessibilityIdentifier = "investment.unsupported.settle"
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
    unsupportedSettlementCallBack = nil
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard window != nil, unsupportedOverlayView != nil, !unsupportedOverlayView.isHidden else { return }
    updateUnsupportedBlur()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true {
      updateThemeColors()
      updateMetricUnitColors()
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
      Self.signed(TradingNumberFormat.string($0), isPositive: $0 > 0)
    } ?? "—"
    cryptoProfitRate.text = valuation.profitRate.map {
      Self.signed($0.formatSignificantDigits(digits: 2), isPositive: $0 > 0) + "%"
    } ?? "—"
    currentProfitRate = valuation.profitLossKRW.map { $0 > 0 ? 1 : ($0 < 0 ? -1 : 0) }
    currentSide = nil
    positionBadgesStackView.isHidden = true
    sideBadgeLabel.text = nil
    leverageBadgeLabel.text = nil
    setTradingUnsupported(isTradingUnsupported)
    dividerView.isHidden = isLast
    updateThemeColors()
    updateMetricValues()
  }

  func configure(
    position: FuturesPosition,
    valuation: FuturesValuation?,
    isLast: Bool,
    cryptoName: String? = nil
  ) {
    // 거래소 선택 상태가 바뀌어도 포지션에 저장된 마켓을 표시한다.
    let market = MarketFormat.displayMarket(
      fromAPIMarket: position.order.instrument.rawSymbol,
      exchange: position.order.instrument.exchange
    )
    // 종목명을 받지 못한 경우에는 기초자산 심볼을 표시한다.
    let symbol = market.split(separator: "/").first.map(String.init) ?? market
    // 저장된 이름을 우선하고 없는 경우에만 시세 목록의 이름을 사용한다.
    let savedName = position.cryptoName?.trimmingCharacters(in: .whitespacesAndNewlines)
    // 공백뿐인 이름도 없는 이름으로 취급한다.
    let marketName = cryptoName?.trimmingCharacters(in: .whitespacesAndNewlines)
    // 원시 손실 대신 기존 청산 표시 범위를 적용한 손익을 사용한다.
    let profitLoss = try? valuation?.displayedPnL
    self.cryptoName.text = [savedName, marketName].compactMap { $0 }.first { !$0.isEmpty } ?? symbol
    marketSymbolLabel.text = market
    amountTitle.text = FuturesText.text("futures_position_quantity")
    averagePriceTitle.text = FuturesText.text("futures_entry")
    buyPriceTitle.text = FuturesText.text("futures_margin")
    profitRateTitle.text = FuturesText.text("futures_roe")
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
    updateMetricValues()
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
  }

  private func updateMetricValues() {
    // 숫자와 단위를 같은 레이블에 넣어 한 줄에 표시한다.
    let metrics: [(UILabel, UILabel)] = [
      (cryptoAmount, quantityUnitLabel), (cryptoAveragePrice, averagePriceUnitLabel),
      (cryptoEvalPrice, evaluationUnitLabel), (cryptoBuyPrice, purchaseUnitLabel)
    ]
    for (valueLabel, unitLabel) in metrics {
      // 접근성에는 생략되기 전의 원문을 전달한다.
      let value = valueLabel.text ?? ""
      // 마켓에 따라 달라지는 원래 단위를 그대로 사용한다.
      let unit = unitLabel.text ?? ""
      // 단위가 없는 경우에는 불필요한 공백을 넣지 않는다.
      let separator = unit.isEmpty ? "" : " "
      // 숫자와 단위의 기존 글꼴·색상을 하나의 레이블에 유지한다.
      let styledText = NSMutableAttributedString(
        string: value + separator + unit,
        attributes: [.font: valueLabel.font ?? UIFont.systemFont(ofSize: 14)]
      )
      if !unit.isEmpty, let unitFont = unitLabel.font {
        // 단위 서식은 표시 문자열의 끝 범위에 적용한다.
        let unitRange = NSRange(location: ((value + separator) as NSString).length, length: (unit as NSString).length)
        styledText.addAttributes(
          [.font: unitFont, .foregroundColor: UIColor.mobitColors(.investmentTextSecondary)],
          range: unitRange
        )
      }
      valueLabel.attributedText = styledText
      valueLabel.accessibilityLabel = value + separator + unit
    }
  }

  private func updateMetricUnitColors() {
    // 테마 전환 후 같은 화면의 통화·종목 단위 색상을 다시 반영한다.
    let metrics: [(UILabel, UILabel)] = [
      (cryptoAmount, quantityUnitLabel), (cryptoAveragePrice, averagePriceUnitLabel),
      (cryptoEvalPrice, evaluationUnitLabel), (cryptoBuyPrice, purchaseUnitLabel)
    ]
    for (valueLabel, unitLabel) in metrics {
      guard let unit = unitLabel.text, !unit.isEmpty,
            let text = valueLabel.attributedText,
            text.string.hasSuffix(" " + unit) else { continue }
      // 현재 표시 문자열의 단위 범위만 바꾸어 숫자의 기존 색을 유지한다.
      let unitRange = NSRange(location: text.length - (unit as NSString).length, length: (unit as NSString).length)
      // UILabel의 attributedText는 변경 가능한 복사본으로 갱신한다.
      let styledText = NSMutableAttributedString(attributedString: text)
      styledText.addAttribute(.foregroundColor, value: UIColor.mobitColors(.investmentTextSecondary), range: unitRange)
      valueLabel.attributedText = styledText
    }
  }

  private func setTradingUnsupported(_ isUnsupported: Bool) {
    if isUnsupported, unsupportedOverlayView.isHidden {
      updateUnsupportedBlur()
    } else if !isUnsupported {
      unsupportedBlurAnimator?.stopAnimation(true)
      unsupportedBlurAnimator = nil
    }
    unsupportedOverlayView.isHidden = !isUnsupported
    bodyStackView.accessibilityElementsHidden = isUnsupported
    if isUnsupported {
      // 흐림 처리된 셀에서도 정산할 종목을 구분할 수 있게 한다.
      let market = marketSymbolLabel.text ?? ""
      // 거래지원 종료 상태를 마켓명과 함께 표시한다.
      let notice = FuturesText.text("investment_unsupported_notice")
      unsupportedNoticeLabel.text = market.isEmpty ? notice : market + " · " + notice
      unsupportedNoticeLabel.accessibilityLabel = market.isEmpty ? notice : market + ", " + notice
    }
  }

  private func updateUnsupportedBlur() {
    guard let unsupportedBlurEffect else { return }
    unsupportedBlurAnimator?.stopAnimation(true)
    unsupportedOverlayView.effect = nil
    // 블러 뷰의 alpha를 변경하면 안내와 버튼까지 반투명해져 효과 진행률만 조절한다.
    let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
      self?.unsupportedOverlayView.effect = unsupportedBlurEffect
    }
    animator.fractionComplete = Self.unsupportedBlurFraction
    unsupportedBlurAnimator = animator
  }

  @IBAction private func tapUnsupportedSettlement(_ sender: UIButton) {
    unsupportedSettlementCallBack?()
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

  private static func krwText(_ amount: Decimal?) -> String {
    TradingNumberFormat.string(amount)
  }
}
