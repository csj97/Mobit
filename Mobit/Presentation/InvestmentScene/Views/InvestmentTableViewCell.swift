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
	// Initialization code
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
	self.cryptoEvalLoss.text = "\(crypto.dynamicData.evaluationProfitLoss.formatSignificantDigits(digits: 2))" + " ₩"
	self.cryptoProfitRate.text = "\(crypto.dynamicData.profitRate.formatSignificantDigits(digits: 2))" + " %"
	
	if crypto.dynamicData.profitRate > 0 {
	  // self.bgView.backgroundColor = .systemGreen.withAlphaComponent(0.05)
	  self.cryptoProfitRate.textColor = .systemGreen
	  self.cryptoEvalLoss.textColor = .systemGreen
	} else if crypto.dynamicData.profitRate == 0 {
	  // self.bgView.backgroundColor = .white
	  self.cryptoProfitRate.textColor = .black
	  self.cryptoEvalLoss.textColor = .black
	} else {
	  self.cryptoProfitRate.textColor = .systemRed
	  self.cryptoEvalLoss.textColor = .systemRed
	  // self.bgView.backgroundColor = .systemRed.withAlphaComponent(0.05)
	}
	
	if isLast { self.dividerView.isHidden = true }
  }
}
