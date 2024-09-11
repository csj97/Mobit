//
//  OrderBookCell.swift
//  Mobit
//
//  Created by 조성재 on 8/25/24.
//

import UIKit
import FlexLayout
import PinLayout
import Then

class OrderBookCell: UITableViewCell {
  
  let rootFlexContainer = UIView()
  
  let obPrice: UILabel = UILabel().then {
    $0.text = "0"
    
  }
  
  let obChangeRate: UILabel = UILabel().then {
    $0.text = "0.0%"
  }
  
  let obSizeLabel: UILabel = UILabel().then {
    $0.text = "0.0"
  }
  
  // 잔량 수에 따른 막대 바
  let obBarView: UIView = UIView().then {
    $0.backgroundColor = .blue
  }
  
  override func awakeFromNib() {
    super.awakeFromNib()
    
  }
  
  override func setSelected(_ selected: Bool, animated: Bool) {
    super.setSelected(selected, animated: animated)
    
    
  }
  
  
  func configure(obTicker: Orderbook) {
    
  }
}
