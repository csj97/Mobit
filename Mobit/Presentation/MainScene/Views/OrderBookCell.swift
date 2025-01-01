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
    $0.textAlignment = .left
  }
  
  // 잔량 수에 따른 막대 바
  let obBarView: UIView = UIView().then {
    $0.backgroundColor = .blue.withAlphaComponent(0.3)
  }
  
  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    setupViews()
  }
  
  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupViews()
  }
  
  override func layoutSubviews() {
    super.layoutSubviews()
    
    self.rootFlexContainer.pin.all()
    self.rootFlexContainer.flex.layout()
  }
  
  override func awakeFromNib() {
    super.awakeFromNib()
    
  }
  
  override func setSelected(_ selected: Bool, animated: Bool) {
    super.setSelected(selected, animated: animated)
  }
  
  func setupViews() {
    self.backgroundColor = .white
    self.isHighlighted = false
    self.addSubview(rootFlexContainer)
    
    self.rootFlexContainer.addSubview(obPrice)
    self.rootFlexContainer.addSubview(obChangeRate)
    self.rootFlexContainer.addSubview(obSizeLabel)
    self.rootFlexContainer.addSubview(obBarView)
    
    self.rootFlexContainer.flex.direction(.row).define { flex in
      flex.addItem()
        .direction(.column)
        .justifyContent(.center)
        .define { flex in
          flex.addItem(self.obPrice)
          flex.addItem(self.obChangeRate)
        }.width(64%)
      flex.addItem()
        .direction(.column)
        .define { flex in
          flex.addItem(self.obBarView)
            .justifyContent(.center)
            .height(80%)
          
          flex.addItem(self.obSizeLabel)
            .justifyContent(.center)
            .position(.absolute)
        }.width(35%).paddingLeft(2)
    }
  }
  
  func configure(changeRate: Double?, obPrice: Double, obSize: Double) {
    self.obPrice.text = String(obPrice)
    self.obSizeLabel.text = String(obSize)
    
    guard let changeRate = changeRate else { return }
    self.obChangeRate.text = "\(changeRate)"
  }
}
