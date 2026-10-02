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
	let priceDigits = currency == .krw ? 2 : 8
	let realizedKRW = pnlHistory.realizedProfitLossKRW.map(PortfolioCalculator.double)
	  ?? (currency == .krw ? pnlHistory.pnl : nil)
	self.currentPNL = realizedKRW

	self.marketNameLabel.text = pnlHistory.exchangePairID.displayMarket
	self.pnlLabel.text = realizedKRW.map {
	  $0.formatSignificantDigits(digits: 2).addComma() + " 원"
	} ?? "-"
	self.pnlLabel.adjustsFontSizeToFitWidth = false
	self.quantityLabel.text = "\(pnlHistory.orderQuantity.formatSignificantDigits(digits: 2))".addComma()
	self.entryPriceLabel.text = "\(pnlHistory.entryPrice.formatSignificantDigits(digits: priceDigits))".addComma() + (currency == .krw ? "" : " " + currency.rawValue)
	self.exitPriceLabel.text = "\(pnlHistory.exitPrice.formatSignificantDigits(digits: priceDigits))".addComma() + (currency == .krw ? "" : " " + currency.rawValue)
	self.transactionDateLabel.text = "\(pnlHistory.transactionDate)"
	
	self.pnlLabel.textColor = realizedKRW.map { MarketColorPalette.color(forSignedValue: $0) }
	  ?? .mobitColors(.textSecondary)
	
	self.layer.cornerRadius = 8
  }
  
  func configure(record: FuturesTransactionRecord, position: FuturesPosition) {
    marketNameLabel.text = "\(FuturesText.symbol(record.instrument)) · \(FuturesText.side(record.side)) \(record.leverage)× · \(FuturesText.text("futures_" + record.kind.rawValue))"
    marketNameLabel.numberOfLines = 0
    entryTitle.text = FuturesText.text("futures_entry") + " :"
    exitTitle.text = FuturesText.text(record.kind == .liquidation ? "futures_liquidation_price" : "futures_exit_price") + " :"
    quantityLabel.text = FuturesText.number(record.quantity, digits: 8)
    entryPriceLabel.text = FuturesText.number(try? position.averageEntryPrice, digits: 4)
    exitPriceLabel.text = FuturesText.number(record.price, digits: 4)
    pnlLabel.text = FuturesText.number(record.realizedPnL) + " KRW"
    currentPNL = record.realizedPnL.map { NSDecimalNumber(decimal: $0).doubleValue }
    pnlLabel.textColor = currentPNL.map { MarketColorPalette.color(forSignedValue: $0) } ?? .mobitColors(.textSecondary)
    if let dateRow = transactionDateLabel.superview as? UIStackView,
       let priceRow = dateRow.superview as? UIStackView, priceRow !== metricsStackView {
      priceRow.removeArrangedSubview(dateRow)
      metricsStackView.addArrangedSubview(dateRow)
      priceRow.distribution = .fill
      metricsStackView.distribution = .fill
      dateRow.axis = .vertical
      dateRow.spacing = 4
    }
    dateTitle.text = FuturesText.text("futures_occurrence") + " :"
    var dates = FuturesText.date(Date(timeIntervalSince1970: Double(record.intervalStart) / 1000))
    if let end = record.intervalEndExclusive {
      dates += " ~\n" + FuturesText.date(Date(timeIntervalSince1970: Double(end) / 1000))
    }
    transactionDateLabel.text = dates + "\n" + FuturesText.text("futures_settled") + " " + FuturesText.date(record.recordedAt)
    transactionDateLabel.numberOfLines = 0
    layer.cornerRadius = 8
  }

  @IBAction func tapOnShareButton(_ sender: UIButton) {
	self.shareCallBack?()
  }
}
