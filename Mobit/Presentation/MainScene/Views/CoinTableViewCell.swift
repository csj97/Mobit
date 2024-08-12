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
  
  let priceBox = UIView().then {
    $0.layer.borderWidth = 0.3
    $0.layer.borderColor = UIColor.clear.cgColor
    $0.layer.masksToBounds = true
  }
  
  var coinName = UILabel().then {
    $0.text = "-"
    $0.textColor = .black
    $0.font = UIFont.systemFont(ofSize: 12)
    $0.numberOfLines = 1
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
  var changeRate = UILabel().then {
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
    self.rootFlexContainer.flex.layout()
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
    self.rootFlexContainer.addSubview(priceBox)
    self.rootFlexContainer.addSubview(price)
    self.rootFlexContainer.addSubview(changeRate)
    self.rootFlexContainer.addSubview(tradingVolume)
    
    self.rootFlexContainer.flex.direction(.row).define { flex in
      flex.addItem()
        .direction(.column)
        .justifyContent(.center)
        .define { flex in
          flex.addItem(self.coinName).width(80%)
          flex.addItem(self.coinSymbol).width(80%)
        }.width(25%).paddingLeft(10)
      flex.addItem().width(25%)
        .alignItems(.center)
        .justifyContent(.center)
        .define { flex in
          flex.addItem(self.priceBox).width(80%).height(80%)
            .justifyContent(.center)
            .define { flex in
              flex.addItem(self.price)
            }
        }
      
      flex.addItem(self.changeRate).width(25%)
      flex.addItem(self.tradingVolume).width(25%)
    }
  }
  
  func configure(crypto: CryptoCellInfo) {
    
    guard let marketEvent = crypto.marketEvent,
          let tradePrice = crypto.tradePrice,
          let signedChangeRate = crypto.signedChangeRate,
          let accTradeVolume = crypto.accTradeVolume,
          let change = crypto.change  else { return }
    
    if marketEvent.warning == true {
      self.coinName.text = "[유]\(crypto.cryptoName)"
    } else {
      self.coinName.text = crypto.cryptoName
    }
    self.coinSymbol.text = crypto.market
    
    let numberFormatter = NumberFormatter()
    numberFormatter.numberStyle = .decimal
    self.price.text = numberFormatter.string(from: NSNumber(value: tradePrice))
    
    self.changeRate.text = String(format: "%.3f%%", signedChangeRate)
    self.tradingVolume.text = String(format: "%.f", accTradeVolume)
    
    switch change {
    case "RISE":
      self.price.textColor = .red
      self.changeRate.textColor = .red
      DispatchQueue.main.async {
        UIView.animate(withDuration: 0.3) {
          self.priceBox.layer.borderColor = UIColor.red.cgColor
        } completion: { _ in
          self.priceBox.layer.borderColor = UIColor.clear.cgColor
        }
      }
      
    case "FALL":
      self.price.textColor = .blue
      self.changeRate.textColor = .blue
      DispatchQueue.main.async {
        UIView.animate(withDuration: 0.15) {
          self.priceBox.layer.borderColor = UIColor.blue.cgColor
        } completion: { _ in
          self.priceBox.layer.borderColor = UIColor.clear.cgColor
        }
      }
      
    case "EVEN":
      self.price.textColor = .black
      self.changeRate.textColor = .black
      DispatchQueue.main.async {
        self.priceBox.layer.borderColor = UIColor.clear.cgColor
      }
      
    default:
      break
    }
    
    setNeedsLayout()
  }
  
}
