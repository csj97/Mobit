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
  
  @IBAction func tapOnShareButton(_ sender: UIButton) {
	self.shareCallBack?()
  }
}
