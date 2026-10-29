//
//  PNLTableViewCell.swift
//  Mobit
//
//  Created by 조성재 on 7/29/25.
//

import UIKit

class PNLTableViewCell: UITableViewCell {

  // 거래 내역을 감싸는 카드 표면이다.
  @IBOutlet weak var cardView: UIView!
  // 거래 종목을 방향·종료 상태와 분리해서 표시한다.
  @IBOutlet weak var marketNameLabel: UILabel!
  // 선물 방향과 배율에 옅은 배경을 적용한다.
  @IBOutlet weak var positionBadgeView: UIView!
  // 선물 내역의 롱·숏과 체결 배율을 표시한다.
  @IBOutlet weak var positionBadgeLabel: UILabel!
  // 포지션 종료와 강제 청산을 구분한다.
  @IBOutlet weak var statusLabel: UILabel!
  // 실현손익 항목의 번역 제목이다.
  @IBOutlet private weak var pnlTitle: UILabel!
  // 원화로 정산한 실현손익을 표시한다.
  @IBOutlet weak var pnlLabel: UILabel!
  // 수익률 항목의 번역 제목이다.
  @IBOutlet private weak var roiTitle: UILabel!
  // 해당 체결의 원가 또는 증거금 기준 수익률이다.
  @IBOutlet weak var roiLabel: UILabel!
  // 체결 수량의 원래 표시 정밀도를 유지한다.
  @IBOutlet weak var quantityLabel: UILabel!
  // 체결수량의 종목 단위에 적용할 XIB 글꼴을 보관한다.
  @IBOutlet private weak var quantityUnitStyleLabel: UILabel!
  // 현물·선물 손익 내역에 공통으로 표시하는 체결 수량 제목이다.
  @IBOutlet private weak var quantityTitle: UILabel!
  // 현물 매수 가격 또는 선물 진입 가격이다.
  @IBOutlet weak var entryPriceLabel: UILabel!
  // 현물 매도 가격 또는 선물 종료 가격이다.
  @IBOutlet weak var exitPriceLabel: UILabel!
  // 실제 체결 또는 청산 발생 시각을 표시한다.
  @IBOutlet weak var transactionDateLabel: UILabel!
  // 상품에 맞는 진입 가격 제목이다.
  @IBOutlet weak var entryTitle: UILabel!
  // 일반 종료와 청산을 구분하는 종료 가격 제목이다.
  @IBOutlet weak var exitTitle: UILabel!
  // 현물에서는 숨기는 선물 체결 증거금 영역이다.
  @IBOutlet weak var marginView: UIStackView!
  // 증거금 항목의 번역 제목이다.
  @IBOutlet private weak var marginTitle: UILabel!
  // 전체 잔여 포지션 대신 해당 종료 체결의 증거금을 표시한다.
  @IBOutlet weak var marginLabel: UILabel!
  // XIB에서 항목별 행으로 구성한 상세 정보 영역이다.
  @IBOutlet weak var metricsStackView: UIStackView!
  // 기존 손익 공유 화면을 여는 버튼이다.
  @IBOutlet weak var shareButton: UIButton!

  var shareCallBack: (() -> ())? = nil
  private var currentPNL: Double?
  // 테마 전환 시 방향 배지의 색상을 복원한다.
  private var currentSide: FuturesSide?

  deinit {
    print("deinit : " + String(describing: type(of: self)))
  }

  override func awakeFromNib() {
    super.awakeFromNib()
    quantityTitle.text = FuturesText.text("trade_executed_quantity")
    pnlTitle.text = FuturesText.text("futures_realized")
    roiTitle.text = FuturesText.text("investment_return_rate")
    marginTitle.text = FuturesText.text("futures_margin")
    shareButton.setTitle(FuturesText.text("media_share"), for: .normal)
    transactionDateLabel.accessibilityLabel = FuturesText.text("investment_execution_time")
    updateThemeColors()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
    updateThemeColors()
  }

  private func updateThemeColors() {
    backgroundColor = .mobitColors(.investmentSurface)
    contentView.backgroundColor = .mobitColors(.investmentSurface)
    cardView.layer.borderColor = UIColor.mobitColors(.investmentSeparator).resolvedColor(with: traitCollection).cgColor
    shareButton.layer.borderColor = UIColor.mobitColors(.investmentSeparator).resolvedColor(with: traitCollection).cgColor
    // 손익을 알 수 없는 재사용 셀에도 이전 손익 색상을 남기지 않는다.
    let profitColor = currentPNL.map { MarketColorPalette.color(forSignedValue: $0) }
      ?? .mobitColors(.textSecondary)
    pnlLabel.textColor = profitColor
    roiLabel.textColor = profitColor
    if let currentSide {
      // 사용자 상승·하락 색상 설정을 방향 배지에도 동일하게 적용한다.
      let sideColor = currentSide == .long ? MarketColorPalette.riseColor : MarketColorPalette.fallColor
      positionBadgeLabel.textColor = sideColor
      positionBadgeView.backgroundColor = sideColor.withAlphaComponent(0.08)
    }
    updateDetailTextStyle()
  }

  override func setSelected(_ selected: Bool, animated: Bool) {
    super.setSelected(selected, animated: animated)
  }

  func configure(pnlHistory: UserPNLHistoryModel) {
    // 현물로 재사용할 때 선물에만 있는 정보가 남지 않게 한다.
    currentSide = nil
    positionBadgeView.isHidden = true
    positionBadgeLabel.text = nil
    statusLabel.isHidden = true
    statusLabel.text = nil
    marginView.isHidden = true
    marginLabel.text = nil
    marginLabel.accessibilityLabel = nil
    // 투자내역과 같은 마켓 표기에서 수량의 종목 단위를 구한다.
    let market = pnlHistory.exchangePairID.displayMarket
    // 결제 통화 대신 실제 체결한 종목을 수량 단위로 표시한다.
    let quantityUnit = market.split(separator: "/").first.map(String.init) ?? market
    marketNameLabel.text = market
    entryTitle.text = FuturesText.text("investment_entry_price")
    exitTitle.text = FuturesText.text("investment_exit_price")
    // BTC 마켓도 저장된 원화 정산값이 있을 때만 원화 손익으로 표시한다.
    let currency = pnlHistory.settlementCurrency
    // 원화는 다른 손익 항목과 같은 번역 단위로 표시한다.
    let currencyUnit = currency == .krw ? FuturesText.text("currency_krw_unit") : currency.rawValue
    // 레거시 KRW 거래는 기존 손익값을 그대로 사용한다.
    let realizedKRW = pnlHistory.realizedProfitLossKRW
      ?? (currency == .krw ? PortfolioCalculator.decimal(pnlHistory.pnl) : nil)
    // 원화 원가가 있으면 공유 화면과 같은 원화 기준 수익률을 사용한다.
    let rate: Decimal?
    if let cost = pnlHistory.costBasisKRW, let realized = pnlHistory.realizedProfitLossKRW,
       pnlHistory.orderQuantity > 0, cost > 0 {
      rate = realized / cost * 100
    } else {
      // 레거시 가격 차이도 십진수에서 계산해 소수점 내림 오차를 줄인다.
      let entry = PortfolioCalculator.decimal(pnlHistory.entryPrice)
      // 매도 가격이 유효하지 않으면 기존처럼 수익률을 표시하지 않는다.
      let exit = PortfolioCalculator.decimal(pnlHistory.exitPrice)
      rate = pnlHistory.entryPrice > 0 && !entry.isNaN && !exit.isNaN
        ? (exit - entry) / entry * 100 : nil
    }
    quantityLabel.text = pnlHistory.orderQuantity.formatTradingValue().addComma() + " " + quantityUnit
    entryPriceLabel.text = pnlHistory.entryPrice.formatTradingValue().addComma() + " " + currencyUnit
    exitPriceLabel.text = pnlHistory.exitPrice.formatTradingValue().addComma() + " " + currencyUnit
    transactionDateLabel.text = pnlHistory.transactionDate
    transactionDateLabel.accessibilityValue = transactionDateLabel.text
    updateProfitLoss(
      amount: realizedKRW,
      rate: realizedKRW == nil ? nil : rate
    )
  }

  func configure(record: FuturesTransactionRecord, position: FuturesPosition) {
    // 실현손익의 종료 결과 문구를 주문 동작·일반 거래내역 문구와 구분한다.
    let statusKey: String
    switch record.kind {
    case .closing: statusKey = "futures_pnl_closed"
    case .liquidation: statusKey = "futures_pnl_liquidated"
    default: statusKey = "futures_" + record.kind.rawValue
    }
    // 종료 내역에 저장된 종목을 헤더와 수량 단위에 함께 사용한다.
    let market = FuturesText.symbol(record.instrument)
    // 현물과 같은 기초자산 심볼을 선물 체결 수량에도 붙인다.
    let quantityUnit = market.split(separator: "/").first.map(String.init) ?? market
    marketNameLabel.text = market
    currentSide = record.side
    positionBadgeView.isHidden = false
    positionBadgeLabel.text = "\(FuturesText.side(record.side)) \(record.leverage)×"
    statusLabel.isHidden = false
    statusLabel.text = FuturesText.text(statusKey)
    entryTitle.text = FuturesText.text("futures_entry_price")
    exitTitle.text = FuturesText.text(record.kind == .liquidation ? "futures_liquidation_exit_price" : "futures_exit_price")
    quantityLabel.text = FuturesText.number(record.quantity) + " " + quantityUnit
    // 가격 단위는 체결에 사용한 마켓의 결제 통화다.
    let currency = record.instrument.settlementCurrency
    // 가격과 증거금에 같은 결제 통화 단위를 사용한다.
    let currencyUnit = currency == .krw ? FuturesText.text("currency_krw_unit") : currency.rawValue
    entryPriceLabel.text = FuturesText.number(try? record.entryPrice ?? position.averageEntryPrice) + " " + currencyUnit
    exitPriceLabel.text = FuturesText.number(record.price) + " " + currencyUnit
    marginView.isHidden = false
    marginLabel.text = FuturesText.number(try? record.margin ?? position.margin) + " " + currencyUnit
    transactionDateLabel.text = FuturesText.occurrenceDate(record)
    transactionDateLabel.accessibilityValue = transactionDateLabel.text
    // 공유 화면과 같은 체결별 증거금 기준으로 수익률을 계산한다.
    let shareUnit = try? FuturesText.shareUnit(record, position: position)
    updateProfitLoss(
      amount: record.realizedPnL,
      rate: shareUnit?.roi
    )
  }

  private func updateProfitLoss(amount: Decimal?, rate: Decimal?) {
    currentPNL = amount.map { NSDecimalNumber(decimal: $0).doubleValue }
    pnlLabel.text = amount.map {
      ($0 > 0 ? "+" : "") + FuturesText.number($0) + " " + FuturesText.text("currency_krw_unit")
    } ?? "-"
    roiLabel.text = rate.map(PortfolioCalculator.double).flatMap { value in
      value.isFinite ? (value > 0 ? "+" : "") + value.formatSignificantDigits(digits: 2) + "%" : nil
    } ?? "-"
    updateThemeColors()
  }

  private func updateDetailTextStyle() {
    // 손익·수익률·수량·가격·증거금의 단위에 같은 서식을 적용한다.
    let detailLabels: [UILabel?] = [pnlLabel, roiLabel, quantityLabel, entryPriceLabel, exitPriceLabel, marginLabel]
    for label in detailLabels {
      // 비어 있는 현물 증거금은 이전 재사용 셀의 스타일을 적용하지 않는다.
      guard let label, let text = label.text else { continue }
      label.accessibilityLabel = text
      // 글꼴은 XIB 설정을 사용하고 단위의 색상만 구분한다.
      let styledText = NSMutableAttributedString(string: text)
      // 수익률의 끝 기호와 공백 뒤의 종목·통화 단위를 구분한다.
      let unitRange: NSRange?
      if text.hasSuffix("%") {
        unitRange = (text as NSString).range(of: "%", options: .backwards)
      } else if let separator = text.lastIndex(of: " ") {
        unitRange = NSRange(text.index(after: separator)..<text.endIndex, in: text)
      } else {
        unitRange = nil
      }
      if let unitRange {
        styledText.addAttribute(.foregroundColor, value: UIColor.mobitColors(.investmentTextTertiary), range: unitRange)
        if label === quantityLabel, let unitFont = quantityUnitStyleLabel.font {
          styledText.addAttribute(.font, value: unitFont, range: unitRange)
        }
      }
      label.attributedText = styledText
    }
  }

  @IBAction func tapOnShareButton(_ sender: UIButton) {
    shareCallBack?()
  }
}
