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
	self.currentPNL = pnlHistory.pnl
	self.marketNameLabel.text = pnlHistory.marketName
	self.pnlLabel.text = "\(pnlHistory.pnl.formatSignificantDigits(digits: 2))".addComma() + " ₩"
	self.quantityLabel.text = "\(pnlHistory.orderQuantity.formatSignificantDigits(digits: 2))".addComma()
	self.entryPriceLabel.text = "\(pnlHistory.entryPrice.formatSignificantDigits(digits: 2))".addComma()
	self.exitPriceLabel.text = "\(pnlHistory.exitPrice.formatSignificantDigits(digits: 2))".addComma()
	self.transactionDateLabel.text = "\(pnlHistory.transactionDate)"
	
	self.pnlLabel.textColor = MarketColorPalette.color(forSignedValue: pnlHistory.pnl)
	
	self.layer.cornerRadius = 8
  }
  
  @IBAction func tapOnShareButton(_ sender: UIButton) {
	self.shareCallBack?()
  }
}
