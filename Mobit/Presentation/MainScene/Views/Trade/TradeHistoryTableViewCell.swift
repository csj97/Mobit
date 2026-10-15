//
//  TradeHistoryTableViewCell.swift
//  Mobit
//
//  Created by 조성재 on 2/11/25.
//

import UIKit

enum TradeHistoryCellLayout {
  // 현물·선물 내역의 각 상세 행 사이에 같은 간격을 둔다.
  static let rowSpacing: CGFloat = 5
  // 체결 방향·시각 헤더와 상세 정보 사이의 간격이다.
  static let headerSpacing: CGFloat = 10
  // 구분선 앞뒤로 각 내역의 위아래 여백을 맞춘다.
  static let verticalPadding: CGFloat = 12
}

class TradeHistoryTableViewCell: UITableViewCell {
  
  @IBOutlet weak var orderTypeLabel: UILabel!	// 매수 or 매도
  @IBOutlet weak var tradeDate: UILabel!        // 거래일자
  @IBOutlet weak var marketName: UILabel!       // 마켓명
  @IBOutlet weak var tradeCryptoPrice: UILabel! //  체결가격
  @IBOutlet weak var tradeAmount: UILabel!      // 체결수량
  @IBOutlet weak var tradeTotalPrice: UILabel!  // 체결금액
  // XIB의 상단 여백도 선물 내역과 같은 기준을 사용한다.
  @IBOutlet private weak var contentTopConstraint: NSLayoutConstraint!
  private var currentOrderType: OrderType?
  private var currentRecordType: TransactionRecordType = .userOrder
  
  override func awakeFromNib() {
    super.awakeFromNib()
	contentTopConstraint.constant = TradeHistoryCellLayout.verticalPadding
	updateTextLayout()
	applyThemeColors()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	// 초기 XIB 로딩은 awakeFromNib에서 구성해 연결 전 아웃렛 접근을 피한다.
	guard let previousTraitCollection else { return }
	if previousTraitCollection.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
	  updateTextLayout()
	}
	if previousTraitCollection.hasDifferentColorAppearance(comparedTo: traitCollection) {
	  applyThemeColors()
	}
  }

  private func updateTextLayout() {
	// 접근성 글자 크기에서는 제목과 값을 각각 한 줄 영역에 배치한다.
	let vertical = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
	orderTypeLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
	  for: .systemFont(ofSize: 14, weight: .bold),
	  compatibleWith: traitCollection
	)
	tradeDate.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(
	  for: .monospacedDigitSystemFont(ofSize: 11, weight: .regular),
	  compatibleWith: traitCollection
	)
	// 숫자 값은 선물 거래내역과 같은 크기와 숫자 폭을 사용한다.
	let valueLabels: [UILabel] = [marketName, tradeCryptoPrice, tradeAmount, tradeTotalPrice]
	// 마켓명과 체결금액을 가격·수량보다 굵게 표시한다.
	for valueLabel in valueLabels {
	  // 동일한 값 유형에 화면 간 같은 강조 수준을 적용한다.
	  let weight: UIFont.Weight = valueLabel === marketName || valueLabel === tradeTotalPrice ? .semibold : .regular
	  valueLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
		for: .monospacedDigitSystemFont(ofSize: 13, weight: weight),
		compatibleWith: traitCollection
	  )
	  valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
	  // 기존 XIB의 항목 행을 재사용해 새 아웃렛 없이 글자 확대에 대응한다.
	  guard let row = valueLabel.superview as? UIStackView else { continue }
	  // 각 행의 첫 라벨은 기존 14pt 보조 제목이다.
	  guard let title = row.arrangedSubviews.first as? UILabel else { continue }
	  title.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
		for: .systemFont(ofSize: 14, weight: .regular),
		compatibleWith: traitCollection
	  )
	  title.textColor = .mobitColors(.tradeTextSecondary)
	  title.adjustsFontForContentSizeCategory = true
	  title.numberOfLines = 0
	  title.lineBreakMode = .byWordWrapping
	  row.axis = vertical ? .vertical : .horizontal
	  row.alignment = vertical ? .fill : .firstBaseline
	  row.spacing = vertical ? 4 : 10
	}
	// 긴 날짜와 숫자를 생략하지 않고 셀 높이를 콘텐츠에 맞춘다.
	for label in [orderTypeLabel, tradeDate].compactMap({ $0 }) + valueLabels {
	  label.adjustsFontForContentSizeCategory = true
	  label.numberOfLines = 0
	  label.lineBreakMode = .byWordWrapping
	}
	orderTypeLabel.setContentHuggingPriority(vertical ? .defaultHigh : .required, for: .horizontal)
	orderTypeLabel.setContentCompressionResistancePriority(vertical ? .defaultHigh : .required, for: .horizontal)
	tradeDate.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
	// 매수·매도와 날짜도 본문과 같은 글자 확대 배치를 따른다.
	guard let header = orderTypeLabel.superview as? UIStackView else { return }
	header.axis = vertical ? .vertical : .horizontal
	header.alignment = vertical ? .fill : .firstBaseline
	header.spacing = vertical ? 4 : 10
	// 행 간격은 고정하고 셀 높이 반올림 여분은 구분선 앞 여백에서 흡수한다.
	if let fields = header.superview as? UIStackView,
	   let content = fields.superview as? UIStackView {
	  fields.distribution = .fill
	  fields.spacing = TradeHistoryCellLayout.rowSpacing
	  fields.setCustomSpacing(TradeHistoryCellLayout.headerSpacing, after: header)
	  content.distribution = .equalSpacing
	  content.spacing = TradeHistoryCellLayout.verticalPadding
	}
  }

  private func applyThemeColors() {
	self.backgroundColor = .mobitColors(.tradeBackground)
	self.contentView.backgroundColor = .mobitColors(.tradeBackground)
	self.tradeDate.textColor = .mobitColors(.tradeTextSecondary)
	[
	  self.marketName,
	  self.tradeCryptoPrice,
	  self.tradeAmount,
	  self.tradeTotalPrice
	].forEach { $0?.textColor = .mobitColors(.tradeTextPrimary) }
	self.applyOrderTypeStyle()
  }

  private func applyOrderTypeStyle() {
	if currentRecordType == .legacyBTCSettlement {
	  self.orderTypeLabel.text = "시스템 정산"
	  self.orderTypeLabel.textColor = .mobitColors(.tradeTextSecondary)
	  return
	}
	guard let currentOrderType else { return }
	self.orderTypeLabel.text = currentOrderType == .ask ? "매도" : "매수"
	self.orderTypeLabel.textColor = currentOrderType == .ask
	  ? MarketColorPalette.fallColor
	  : MarketColorPalette.riseColor
  }

  
  func configure(
	marketName: String,
	transactionInfo: TransactionInfo
  ) {
	self.currentOrderType = transactionInfo.orderType
	self.currentRecordType = transactionInfo.recordType
	self.applyOrderTypeStyle()
	self.tradeDate.text = transactionInfo.executedDate
	self.marketName.text = marketName
	// 체결 기록은 주문 당시 통화 그대로 보여준다. 원화 마켓은 기존 표기를 유지한다.
	let currency = transactionInfo.settlementCurrency
	let priceUnit = currency == .krw ? "" : " " + currency.rawValue
	let amountUnit = transactionInfo.recordType == .legacyBTCSettlement ? " \(FuturesText.text("currency_krw_unit"))" : priceUnit

	self.tradeCryptoPrice.text = transactionInfo.executedPrice.formatTradingValue() + priceUnit
	self.tradeAmount.text = String(transactionInfo.executedQuantity.formatTradingValue())
	let executedAmount = transactionInfo.executedAmount.formatTradingValue() + amountUnit
	if let exchangeProfit = transactionInfo.settlementProfitLossKRW {
	  let profit = PortfolioCalculator.double(exchangeProfit)
	  let sign = profit > 0 ? "+" : ""
	  let profitText = sign + profit.formatTradingValue()
	  self.tradeTotalPrice.text = "\(executedAmount)\nBTC 교환손익 \(profitText)원"
	} else {
	  self.tradeTotalPrice.text = executedAmount
	}
  }

  
  override func setSelected(_ selected: Bool, animated: Bool) {
    super.setSelected(selected, animated: animated)
    
    // Configure the view for the selected state
  }
  
}
