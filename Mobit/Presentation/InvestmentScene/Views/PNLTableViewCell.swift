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
	if let containerView = self.contentView.subviews.first {
	  containerView.backgroundColor = .mobitColors(.investmentSurface)
	}
	if let currentPNL {
	  self.pnlLabel.textColor = MarketColorPalette.color(forSignedValue: currentPNL)
	}
  }

  override func setSelected(_ selected: Bool, animated: Bool) {
	super.setSelected(selected, animated: animated)
	
  }
  
  func configure(pnlHistory: UserPNLHistoryModel) {
    if let dateRow = transactionDateLabel.superview as? UIStackView, dateRow.superview === metricsStackView,
       let priceRow = exitPriceLabel.superview?.superview as? UIStackView {
      metricsStackView.removeArrangedSubview(dateRow)
      priceRow.addArrangedSubview(dateRow)
      priceRow.distribution = .fillEqually
      metricsStackView.distribution = .fillEqually
      dateRow.axis = .horizontal
    }
    transactionDateLabel.numberOfLines = 1
    marketNameLabel.numberOfLines = 1
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
    marketNameLabel.text = "\(FuturesText.symbol(record.instrument)) · \(FuturesText.side(record.side)) \(record.leverage)× · \(FuturesText.text("futures_" + record.kind.rawValue))"
    marketNameLabel.numberOfLines = 0
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
