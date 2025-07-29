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
	self.pnlLabel.text = "\(pnlHistory.pnl)"
	self.quantityLabel.text = "\(pnlHistory.orderQuantity)"
	self.entryPriceLabel.text = "\(pnlHistory.entryPrice)"
	self.exitPriceLabel.text = "\(pnlHistory.exitPrice)"
	self.transactionDateLabel.text = "\(pnlHistory.transactionDate)"
	
	self.layer.cornerRadius = 8
  }
}
