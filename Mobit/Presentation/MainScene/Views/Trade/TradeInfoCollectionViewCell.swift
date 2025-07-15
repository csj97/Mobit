//
//  TradeInfoCollectionViewCell.swift
//  Mobit
//
//  Created by 조성재 on 7/14/25.
//

import UIKit

class TradeInfoCollectionViewCell: UICollectionViewCell {
  
  @IBOutlet weak var cryptoTagLabel: UILabel!
  
  override func awakeFromNib() {
	super.awakeFromNib()
	
  }
  
  func configure(tag: String) {
	self.layer.cornerRadius = 18
	self.layer.borderWidth = 1
	self.layer.borderColor = UIColor.lightGray.cgColor
	self.layer.masksToBounds = true
	
	self.cryptoTagLabel.textColor = .systemGray
	self.cryptoTagLabel.text = tag
  }
}
