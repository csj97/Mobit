//
//  TradeHistoryTableViewCell.swift
//  Mobit
//
//  Created by 조성재 on 2/11/25.
//

import UIKit

class TradeHistoryTableViewCell: UITableViewCell {
  
  @IBOutlet weak var orderTypeLabel: UILabel!	// 매수 or 매도
  @IBOutlet weak var tradeDate: UILabel!        // 거래일자
  @IBOutlet weak var marketName: UILabel!       // 마켓명
  @IBOutlet weak var tradeCryptoPrice: UILabel! //  체결가격
  @IBOutlet weak var tradeAmount: UILabel!      // 체결수량
  @IBOutlet weak var tradeTotalPrice: UILabel!  // 체결금액
  private var currentOrderType: OrderType?
  
  override func awakeFromNib() {
    super.awakeFromNib()
	applyThemeColors()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
	applyThemeColors()
  }

  private func applyThemeColors() {
	self.backgroundColor = .mobitColors(.tradeBackground)
	self.contentView.backgroundColor = .mobitColors(.tradeBackground)
	[
	  self.tradeDate,
	  self.marketName,
	  self.tradeCryptoPrice,
	  self.tradeAmount,
	  self.tradeTotalPrice
	].forEach { $0?.textColor = .mobitColors(.tradeTextPrimary) }
	if let currentOrderType {
	  self.orderTypeLabel.textColor = currentOrderType == .ask
		? MarketColorPalette.fallColor
		: MarketColorPalette.riseColor
	}
  }

  
  func configure(
	marketName: String,
	transactionInfo: TransactionInfo
  ) {
	self.currentOrderType = transactionInfo.orderType
	if transactionInfo.orderType == .ask {
	  self.orderTypeLabel.text = "매도"
	  self.orderTypeLabel.textColor = MarketColorPalette.fallColor
	} else {
	  self.orderTypeLabel.text = "매수"
	  self.orderTypeLabel.textColor = MarketColorPalette.riseColor
	}
	self.tradeDate.text = transactionInfo.executedDate
	self.marketName.text = marketName
	self.tradeCryptoPrice.text = String(transactionInfo.executedPrice.formatSignificantDigits())
	self.tradeAmount.text = String(transactionInfo.executedQuantity.formatSignificantDigits())
	self.tradeTotalPrice.text = String(transactionInfo.executedAmount.formatSignificantDigits())
  }

  
  override func setSelected(_ selected: Bool, animated: Bool) {
    super.setSelected(selected, animated: animated)
    
    // Configure the view for the selected state
  }
  
}
