//
//  TradeHistoryTableViewCell.swift
//  Mobit
//
//  Created by 조성재 on 2/11/25.
//

import UIKit

class TradeHistoryTableViewCell: UITableViewCell {
  
  @IBOutlet weak var tradeDate: UILabel!        // 거래일자
  @IBOutlet weak var marketName: UILabel!       // 마켓명
  @IBOutlet weak var tradeCryptoPrice: UILabel! //  체결가격
  @IBOutlet weak var tradeAmount: UILabel!      // 체결수량
  @IBOutlet weak var tradeTotalPrice: UILabel!  // 체결금액
  
  override func awakeFromNib() {
    super.awakeFromNib()
    // Initialization code
  }
  
  func configure(
	marketName: String,
	transactionInfo: CryptoTransactionDataModel.CryptoTransactionStaticData.TransactionInfo
  ) {
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
