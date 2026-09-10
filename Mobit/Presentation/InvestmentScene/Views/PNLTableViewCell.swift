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
	let displayedPNL = pnlHistory.realizedProfitLossKRW.map(PortfolioCalculator.double) ?? pnlHistory.pnl
	self.currentPNL = displayedPNL
	// 신규 기록은 확정 원화 손익을 사용하고 환율 없는 과거 기록은 원래 통화를 유지한다.
	let currency = pnlHistory.settlementCurrency
	let priceDigits = currency == .krw ? 2 : 8
	let unit = pnlHistory.realizedProfitLossKRW != nil || currency == .krw ? " ₩" : " " + currency.rawValue

	self.marketNameLabel.text = "\(pnlHistory.marketName.marketSymbol) · \(currency.rawValue)"
	let krwPNLText = "\(displayedPNL.formatSignificantDigits(digits: pnlHistory.realizedProfitLossKRW != nil ? 2 : priceDigits))".addComma() + unit
	if currency == .btc, pnlHistory.realizedProfitLossKRW != nil {
	  let nativePNL = pnlHistory.pnl.formatSignificantDigits(digits: 8)
	  self.pnlLabel.text = "\(krwPNLText) · \(nativePNL) BTC"
	  self.pnlLabel.adjustsFontSizeToFitWidth = true
	  self.pnlLabel.minimumScaleFactor = 0.6
	} else {
	  self.pnlLabel.text = krwPNLText
	}
	self.quantityLabel.text = "\(pnlHistory.orderQuantity.formatSignificantDigits(digits: 2))".addComma()
	self.entryPriceLabel.text = "\(pnlHistory.entryPrice.formatSignificantDigits(digits: priceDigits))".addComma() + (currency == .krw ? "" : " " + currency.rawValue)
	self.exitPriceLabel.text = "\(pnlHistory.exitPrice.formatSignificantDigits(digits: priceDigits))".addComma() + (currency == .krw ? "" : " " + currency.rawValue)
	self.transactionDateLabel.text = "\(pnlHistory.transactionDate)"
	
	self.pnlLabel.textColor = MarketColorPalette.color(forSignedValue: displayedPNL)
	
	self.layer.cornerRadius = 8
  }
  
  @IBAction func tapOnShareButton(_ sender: UIButton) {
	self.shareCallBack?()
  }
}
