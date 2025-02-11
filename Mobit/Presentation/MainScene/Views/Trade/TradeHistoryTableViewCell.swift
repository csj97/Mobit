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
  
  func configure(tradeInfo: TradeHistoryInformation) {
	self.tradeDate.text = tradeInfo.tradeDate
	self.marketName.text = tradeInfo.marketName
	self.tradeCryptoPrice.text = String(tradeInfo.tradeCryptoPrice)
	self.tradeAmount.text = String(tradeInfo.tradeAmount)
	self.tradeTotalPrice.text = String(tradeInfo.tradeTotalPrice)
  }
  
  override func setSelected(_ selected: Bool, animated: Bool) {
    super.setSelected(selected, animated: animated)
    
    // Configure the view for the selected state
  }
  
}
