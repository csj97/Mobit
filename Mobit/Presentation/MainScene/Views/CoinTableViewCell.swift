//
//  CoinTableViewCell.swift
//  Mobit
//
//  Created by openobject on 2024/07/18.
//

import UIKit
import FlexLayout
import PinLayout
import Then

enum MarketWarning: String {
  case noneValue = "NONE"
  case caution = "CAUTION"
}

class CoinTableViewCell: UITableViewCell {
  let rootFlexContainer = UIView()
  var coinName = UILabel().then {
    $0.text = "-"
    $0.textColor = .black
    $0.font = UIFont.systemFont(ofSize: 12)
    $0.numberOfLines = 2
    $0.textAlignment = .left
  }
  var coinSymbol = UILabel().then {
    $0.text = "-/KRW"
    $0.textColor = .lightGray
    $0.font = UIFont.systemFont(ofSize: 10)
    $0.numberOfLines = 1
    $0.textAlignment = .left
  }
  var price = UILabel().then {
    $0.text = "0"
    $0.textColor = .black
    $0.font = UIFont.systemFont(ofSize: 10)
    $0.adjustsFontSizeToFitWidth = true
    $0.minimumScaleFactor = 0.7
    $0.numberOfLines = 1
    $0.textAlignment = .center
  }
  var volatility = UILabel().then {
    $0.text = "0.0%"
    $0.textColor = .black
    $0.font = UIFont.systemFont(ofSize: 10)
    $0.numberOfLines = 1
    $0.textAlignment = .center
  }
  var tradingVolume = UILabel().then {
    $0.text = "0"
    $0.textColor = .black
    $0.font = UIFont.systemFont(ofSize: 10)
    $0.adjustsFontSizeToFitWidth = true
    $0.minimumScaleFactor = 0.7
    $0.numberOfLines = 1
    $0.textAlignment = .center
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
    self.rootFlexContainer.flex.layout(mode: .adjustHeight)
  }
  
  override func setSelected(_ selected: Bool, animated: Bool) {
    super.setSelected(selected, animated: animated)
    
    // Configure the view for the selected state
  }
  
  func setupViews() {
    self.backgroundColor = .white
    self.isHighlighted = false
    self.addSubview(rootFlexContainer)
    
    self.rootFlexContainer.addSubview(coinName)
    self.rootFlexContainer.addSubview(coinSymbol)
    self.rootFlexContainer.addSubview(price)
    self.rootFlexContainer.addSubview(volatility)
    self.rootFlexContainer.addSubview(tradingVolume)
    
    self.rootFlexContainer.flex.direction(.row).define { flex in
      flex.addItem()
        .direction(.column)
        .justifyContent(.center)
        .alignItems(.center)
        .define { flex in
          flex.addItem(self.coinName).width(80%)
          flex.addItem(self.coinSymbol).width(80%)
        }.width(25%)
      flex.addItem(self.price).width(25%)
      flex.addItem(self.volatility).width(25%)
      flex.addItem(self.tradingVolume).width(25%)
    }
  }
  
  func configure(crypto: CryptoMarket) {
    if crypto.marketEvent.warning {
      self.coinName.text = "[유]\(crypto.koreanName)"
    } else {
      self.coinName.text = crypto.koreanName
    }
    self.coinSymbol.text = crypto.market
    self.price.text = "100"
    self.volatility.text = "0.0%"
    self.tradingVolume.text = "100백만"
    
    setNeedsLayout()
  }
  
}
