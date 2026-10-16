//
//  PNLTableViewCell.swift
//  Mobit
//
//  Created by 조성재 on 7/29/25.
//

import UIKit

class PNLTableViewCell: UITableViewCell {
  
  @IBOutlet weak var marketNameLabel: UILabel!
  @IBOutlet weak var pnlLabel: UILabel!
  @IBOutlet weak var quantityLabel: UILabel!
  // 현물·선물 손익 내역에 공통으로 표시하는 체결 수량 제목이다.
  @IBOutlet private weak var quantityTitle: UILabel!
  @IBOutlet weak var entryPriceLabel: UILabel!
  @IBOutlet weak var exitPriceLabel: UILabel!
  @IBOutlet weak var transactionDateLabel: UILabel!
  @IBOutlet weak var entryTitle: UILabel!
  @IBOutlet weak var exitTitle: UILabel!
  @IBOutlet weak var dateTitle: UILabel!
  @IBOutlet weak var metricsStackView: UIStackView!
  
  var shareCallBack: (() -> ())? = nil
  private var currentPNL: Double?
  
  deinit {
	print("deinit : " + String(describing: type(of: self)))
  }
  
  override func awakeFromNib() {
	super.awakeFromNib()
	quantityTitle.text = FuturesText.text("trade_executed_quantity") + " :"
	updateThemeColors()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
	updateThemeColors()
  }

  private func updateThemeColors() {
	self.backgroundColor = .mobitColors(.backgroundPrimary)
	self.contentView.backgroundColor = .mobitColors(.backgroundPrimary)
	if let currentPNL {
	  self.pnlLabel.textColor = MarketColorPalette.color(forSignedValue: currentPNL)
	}
  }

  override func setSelected(_ selected: Bool, animated: Bool) {
	super.setSelected(selected, animated: animated)
	
  }
  
  func configure(pnlHistory: UserPNLHistoryModel) {
    transactionDateLabel.numberOfLines = 1
    marketNameLabel.numberOfLines = 1
    marketNameLabel.adjustsFontSizeToFitWidth = false
    marketNameLabel.minimumScaleFactor = 1
    dateTitle.text = FuturesText.text("investment_execution_time") + " :"
    entryTitle.text = FuturesText.text("investment_entry_price") + " :"
    exitTitle.text = FuturesText.text("investment_exit_price") + " :"
	let currency = pnlHistory.settlementCurrency
	let realizedKRW = pnlHistory.realizedProfitLossKRW.map(PortfolioCalculator.double)
	  ?? (currency == .krw ? pnlHistory.pnl : nil)
	self.currentPNL = realizedKRW

	self.marketNameLabel.text = pnlHistory.exchangePairID.displayMarket
	self.pnlLabel.text = realizedKRW.map {
	  $0.formatTradingValue().addComma() + " 원"
	} ?? "-"
	self.pnlLabel.adjustsFontSizeToFitWidth = false
	self.quantityLabel.text = "\(pnlHistory.orderQuantity.formatTradingValue())".addComma()
	self.entryPriceLabel.text = "\(pnlHistory.entryPrice.formatTradingValue())".addComma() + (currency == .krw ? "" : " " + currency.rawValue)
	self.exitPriceLabel.text = "\(pnlHistory.exitPrice.formatTradingValue())".addComma() + (currency == .krw ? "" : " " + currency.rawValue)
	self.transactionDateLabel.text = "\(pnlHistory.transactionDate)"
	
	self.pnlLabel.textColor = realizedKRW.map { MarketColorPalette.color(forSignedValue: $0) }
	  ?? .mobitColors(.textSecondary)
	
	self.layer.cornerRadius = 8
  }
  
  func configure(record: FuturesTransactionRecord, position: FuturesPosition) {
    // 실현손익의 종료 결과 문구를 주문 동작·일반 거래내역 문구와 구분한다.
    let statusKey: String
    switch record.kind {
    case .closing: statusKey = "futures_pnl_closed"
    case .liquidation: statusKey = "futures_pnl_liquidated"
    default: statusKey = "futures_" + record.kind.rawValue
    }
    marketNameLabel.text = "\(FuturesText.symbol(record.instrument)) · \(FuturesText.side(record.side)) \(record.leverage)× · \(FuturesText.text(statusKey))"
    // 종료 유형을 포함한 제목을 한 줄 안에서 원래 글자 크기의 55%까지 축소한다.
    marketNameLabel.numberOfLines = 1
    marketNameLabel.adjustsFontSizeToFitWidth = true
    marketNameLabel.minimumScaleFactor = 0.55
    entryTitle.text = FuturesText.text("futures_entry_price") + " :"
    exitTitle.text = FuturesText.text(record.kind == .liquidation ? "futures_liquidation_exit_price" : "futures_exit_price") + " :"
    quantityLabel.text = FuturesText.number(record.quantity)
    entryPriceLabel.text = FuturesText.number(try? record.entryPrice ?? position.averageEntryPrice)
    exitPriceLabel.text = FuturesText.number(record.price)
    pnlLabel.text = FuturesText.number(record.realizedPnL) + " \(FuturesText.text("currency_krw_unit"))"
    currentPNL = record.realizedPnL.map { NSDecimalNumber(decimal: $0).doubleValue }
    pnlLabel.textColor = currentPNL.map { MarketColorPalette.color(forSignedValue: $0) } ?? .mobitColors(.textSecondary)
    dateTitle.text = FuturesText.text("investment_execution_time") + " :"
    transactionDateLabel.text = FuturesText.occurrenceDate(record)
    transactionDateLabel.numberOfLines = 1
    layer.cornerRadius = 8
  }

  @IBAction func tapOnShareButton(_ sender: UIButton) {
	self.shareCallBack?()
  }
}
