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
    
  override func awakeFromNib() {
	super.awakeFromNib()
	self.backgroundColor = .mobitColors(.backgroundPrimary)
	self.contentView.backgroundColor = .mobitColors(.backgroundPrimary)
	self.bgView.backgroundColor = .mobitColors(.surfaceElevated)
	self.dividerView.backgroundColor = .mobitColors(.borderPrimary)
	self.applyTheme(to: self.bgView)
	[
	  self.cryptoName,
	  self.cryptoAmount,
	  self.cryptoEvalPrice,
	  self.cryptoAveragePrice,
	  self.cryptoBuyPrice
	].forEach { $0?.textColor = .mobitColors(.textPrimary) }
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
	
	let pnlColor = MarketColorPalette.color(forSignedValue: crypto.dynamicData.profitRate)
	self.cryptoProfitRate.textColor = pnlColor
	self.cryptoEvalLoss.textColor = pnlColor
	
	self.dividerView.isHidden = isLast

  }

  private func applyTheme(to view: UIView) {
	if view !== self.bgView && view.backgroundColor != .clear {
	  view.backgroundColor = .mobitColors(.surfaceElevated)
	}

	if let label = view as? UILabel {
	  label.textColor = self.isValueLabel(label)
		? .mobitColors(.textPrimary)
		: .mobitColors(.textSecondary)
	}

	view.subviews.forEach { self.applyTheme(to: $0) }
  }

  private func isValueLabel(_ label: UILabel) -> Bool {
	return label === self.cryptoName
	  || label === self.cryptoAmount
	  || label === self.cryptoEvalPrice
	  || label === self.cryptoEvalLoss
	  || label === self.cryptoAveragePrice
	  || label === self.cryptoBuyPrice
	  || label === self.cryptoProfitRate
  }
}
