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
  
  let spaceView: UIView = UIView().then {
    $0.backgroundColor = .white
  }
  
  let obPrice: UILabel = UILabel().then {
    $0.text = "0"
    $0.textAlignment = .right
    $0.font = UIFont.systemFont(ofSize: 12)
    $0.adjustsFontSizeToFitWidth = true
    $0.minimumScaleFactor = 0.3
  }
  
  let obChangeRate: UILabel = UILabel().then {
    $0.text = "0.0%"
    $0.textAlignment = .right
    $0.font = UIFont.systemFont(ofSize: 12)
    $0.adjustsFontSizeToFitWidth = true
    $0.minimumScaleFactor = 0.5
  }
  
  let obSizeLabel: UILabel = UILabel().then {
    $0.text = "0.0"
    $0.textAlignment = .left
    $0.font = UIFont.systemFont(ofSize: 10)
    $0.adjustsFontSizeToFitWidth = true
    $0.minimumScaleFactor = 0.5
  }
  
  // 잔량 수에 따른 막대 바
  let obBarView: UIView = UIView().then {
    $0.backgroundColor = .blue.withAlphaComponent(0.5)
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
			.margin(0, 4)
          flex.addItem(self.obChangeRate)
			.margin(0, 4)
        }.width(64%)
      
      flex.addItem(
        self.spaceView
      ).grow(1)
      
      flex.addItem()
        .direction(.column)
        .justifyContent(.center)
        .define { flex in
          flex.addItem(self.obBarView)
            .height(50%)
          
          flex.addItem(self.obSizeLabel)
            .position(.absolute)
			.left(4).right(4)
			.alignSelf(.center)
        }.width(35%)
    }
  }
  
  func updateObBar(maxSize: Double, currentSize: Double) {
	let parentViewSize = self.obBarView.superview?.frame
	let newObBarWidthRatio = (currentSize / maxSize) * 100
	
	self.obBarView.flex.width(newObBarWidthRatio%)
	self.rootFlexContainer.flex.markDirty()
	self.rootFlexContainer.flex.layout(mode: .adjustWidth)
  }
  
  func configure(
    changeRate: Double?,
    obType: OrderType,
    obPrice: Double,
    obSize: Double,
	askMaxSize: Double,
	bidMaxSize: Double
  ) {
    let numberFormatter = NumberFormatter()
    numberFormatter.numberStyle = .decimal
    if obPrice < 1 {
      self.obPrice.text = formatOrderPrice(obPrice)
    } else {
      self.obPrice.text = numberFormatter.string(
        from: NSNumber(value: obPrice)
      )
    }
	self.obSizeLabel.text = String(obSize.formatSignificantDigits(digits: 10))
    switch obType {
    case .ask:
      self.backgroundColor = .mobitColors(.askLightBlue)
      self.obBarView.backgroundColor = .mobitColors(.askDeepBlue)
	  self.updateObBar(maxSize: askMaxSize, currentSize: obSize)
    case .bid:
      self.backgroundColor = .mobitColors(.bidLightRed)
      self.obBarView.backgroundColor = .mobitColors(.bidDeepRed)
	  self.updateObBar(maxSize: bidMaxSize, currentSize: obSize)
    }
    
    guard let changeRate = changeRate else { return }
    self.obChangeRate.text = "\(changeRate)%"
  }
  
  func formatOrderPrice(_ obPrice: Double?, precision: Int = 8) -> String {
    guard let price = obPrice else {
      return "N/A"  // 값이 없을 때 반환할 기본 문자열
    }
    return String(format: "%.\(precision)f", price)
  }
}
