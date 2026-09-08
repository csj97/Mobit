//
//  InvestmentTableViewCell.swift
//  Mobit
//
//  Created by 조성재 on 4/9/25.
//

import UIKit

class InvestmentTableViewCell: UITableViewCell {
  
  @IBOutlet weak var cryptoName: UILabel!
  @IBOutlet weak var cryptoAmount: UILabel!
  @IBOutlet weak var cryptoEvalPrice: UILabel!
  @IBOutlet weak var cryptoEvalLoss: UILabel!
  @IBOutlet weak var cryptoAveragePrice: UILabel!
  @IBOutlet weak var cryptoBuyPrice: UILabel!
  @IBOutlet weak var cryptoProfitRate: UILabel!
  @IBOutlet weak var bgView: UIView!
  @IBOutlet weak var dividerView: UIView!
  private var currentProfitRate: Double?
    
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
	self.backgroundColor = .mobitColors(.investmentBackground)
	self.contentView.backgroundColor = .mobitColors(.investmentBackground)
	self.bgView.backgroundColor = .mobitColors(.investmentBackground)
	self.dividerView.backgroundColor = .mobitColors(.investmentSeparator)
	[
	  self.cryptoName,
	  self.cryptoAmount,
	  self.cryptoEvalPrice,
	  self.cryptoAveragePrice,
	  self.cryptoBuyPrice
	].forEach { $0?.textColor = .mobitColors(.investmentTextPrimary) }
	if let currentProfitRate {
	  let pnlColor = MarketColorPalette.color(forSignedValue: currentProfitRate)
	  self.cryptoProfitRate.textColor = pnlColor
	  self.cryptoEvalLoss.textColor = pnlColor
	}
  }
  
  override func setSelected(_ selected: Bool, animated: Bool) {
	super.setSelected(selected, animated: animated)
	
	// Configure the view for the selected state
  }
  
  func configure(crypto: CryptoTransactionDataModel, isLast: Bool) {
	self.cryptoName.text = "\(crypto.staticData.marketName)"
	self.cryptoAmount.text = "\(crypto.staticData.holdingQuantity.formatSignificantDigits())"
	self.cryptoAveragePrice.text = "\(crypto.staticData.averageBuyPrice.formatSignificantDigits(digits: 4))"
	self.cryptoBuyPrice.text = "\(crypto.staticData.buyAmount.formatSignificantDigits())"
	
	self.cryptoEvalPrice.text = "\(crypto.dynamicData.evaluationPrice.formatSignificantDigits())"
	self.cryptoEvalLoss.text = "\(crypto.dynamicData.evaluationProfitLoss.formatSignificantDigits(digits: 0))"
	self.cryptoProfitRate.text = "\(crypto.dynamicData.profitRate.formatSignificantDigits(digits: 2))" + " %"
	self.currentProfitRate = crypto.dynamicData.profitRate
	
	let pnlColor = MarketColorPalette.color(forSignedValue: crypto.dynamicData.profitRate)
	self.cryptoProfitRate.textColor = pnlColor
	self.cryptoEvalLoss.textColor = pnlColor
	
	self.dividerView.isHidden = isLast

  }

}
