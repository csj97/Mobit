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
	// 체결 기록은 주문 당시 통화 그대로 보여준다. 원화 마켓은 기존 표기를 유지한다.
	let currency = transactionInfo.settlementCurrency
	let unit = currency == .krw ? "" : " " + currency.rawValue

	self.tradeCryptoPrice.text = transactionInfo.executedPrice.formatSignificantDigits() + unit
	self.tradeAmount.text = String(transactionInfo.executedQuantity.formatSignificantDigits())
	let executedAmount = transactionInfo.executedAmount.formatSignificantDigits() + unit
	if let exchangeProfit = transactionInfo.settlementProfitLossKRW {
	  let profit = PortfolioCalculator.double(exchangeProfit)
	  let sign = profit > 0 ? "+" : ""
	  self.tradeTotalPrice.numberOfLines = 2
	  let profitText = sign + profit.formatSignificantDigits(digits: 0)
	  self.tradeTotalPrice.text = "\(executedAmount)\nBTC 교환손익 \(profitText)원"
	} else {
	  self.tradeTotalPrice.numberOfLines = 1
	  self.tradeTotalPrice.text = executedAmount
	}
  }

  
  override func setSelected(_ selected: Bool, animated: Bool) {
    super.setSelected(selected, animated: animated)
    
    // Configure the view for the selected state
  }
  
}
