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
  
  override func awakeFromNib() {
	super.awakeFromNib()
	// Initialization code
  }
  
  override func setSelected(_ selected: Bool, animated: Bool) {
	super.setSelected(selected, animated: animated)
	
  }
  
  func configure(pnlHistory: UserPNLHistoryModel) {
	self.marketNameLabel.text = pnlHistory.marketName
	self.pnlLabel.text = "\(pnlHistory.pnl.formatSignificantDigits(digits: 2))".addComma() + " ₩"
	self.quantityLabel.text = "\(pnlHistory.orderQuantity.formatSignificantDigits(digits: 2))".addComma()
	self.entryPriceLabel.text = "\(pnlHistory.entryPrice.formatSignificantDigits(digits: 2))".addComma() + " ₩"
	self.exitPriceLabel.text = "\(pnlHistory.exitPrice.formatSignificantDigits(digits: 2))".addComma() + " ₩"
	self.transactionDateLabel.text = "\(pnlHistory.transactionDate)"
	
	if pnlHistory.pnl > 0 {
	  self.pnlLabel.textColor = .systemGreen
	} else if pnlHistory.pnl < 0 {
	  self.pnlLabel.textColor = .systemRed
	} else {
	  self.pnlLabel.textColor = .black
	}
	
	self.layer.cornerRadius = 8
  }
}
