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
    
  override func awakeFromNib() {
	super.awakeFromNib()
	// Initialization code
  }
  
  override func setSelected(_ selected: Bool, animated: Bool) {
	super.setSelected(selected, animated: animated)
	
	// Configure the view for the selected state
  }
  
  func configure(crypto: CryptoTransactionDataModel) {
	self.cryptoName.text = "\(crypto.staticData.marketName)"
	self.cryptoAmount.text = "\(crypto.staticData.holdingQuantity)".addComma()
	self.cryptoAveragePrice.text = "\(crypto.staticData.averageBuyPrice)".addComma()
	self.cryptoBuyPrice.text = "\(crypto.staticData.buyAmount)".addComma()
	
	self.cryptoEvalPrice.text = "\(crypto.dynamicData.evaluationPrice)".addComma()
	self.cryptoEvalLoss.text = "\(crypto.dynamicData.evaluationProfitLoss)".addComma()
	self.cryptoProfitRate.text = "\(crypto.dynamicData.profitRate)".addComma()
	
	if crypto.dynamicData.profitRate > 0 {
	  self.bgView.backgroundColor = .systemGreen.withAlphaComponent(0.05)
	} else if crypto.dynamicData.profitRate == 0 {
	  self.bgView.backgroundColor = .white
	} else {
	  self.bgView.backgroundColor = .systemRed.withAlphaComponent(0.05)
	}
  }
}
