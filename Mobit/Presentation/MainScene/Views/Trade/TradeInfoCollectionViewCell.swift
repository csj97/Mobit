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
	applyThemeColors()
  }
  
  func configure(tag: String) {
	self.layer.cornerRadius = 16
	self.layer.borderWidth = 1
	self.layer.masksToBounds = true
	applyThemeColors()
	self.cryptoTagLabel.text = tag
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
	applyThemeColors()
  }

  private func applyThemeColors() {
	self.backgroundColor = .clear
	self.contentView.backgroundColor = .mobitColors(.tradeControlSurface)
	self.cryptoTagLabel.backgroundColor = .clear
	self.cryptoTagLabel.textColor = .mobitColors(.tradeTextSecondary)
	updateResolvedColors()
  }

  private func updateResolvedColors() {
	self.layer.borderColor = UIColor.mobitColors(.tradeSeparator).resolvedColor(with: traitCollection).cgColor
  }
}
