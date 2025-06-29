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
  var changeRate = UILabel().then {
    $0.text = "0.0%"
    $0.textColor = .black
    $0.font = UIFont.systemFont(ofSize: 10)
    $0.numberOfLines = 1
    $0.textAlignment = .center
  }
  var accTradePrice = UILabel().then {
    $0.text = "0"
    $0.textColor = .black
    $0.font = UIFont.systemFont(ofSize: 12)
    $0.adjustsFontSizeToFitWidth = true
    $0.minimumScaleFactor = 0.7
    $0.numberOfLines = 1
    $0.textAlignment = .right
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
    self.rootFlexContainer.addSubview(accTradePrice)
    
    self.rootFlexContainer.flex.direction(.row).define { flex in
      flex.addItem()
        .direction(.column)
        .justifyContent(.center)
        .define { flex in
          flex.addItem(self.coinName).width(100%)
          flex.addItem(self.coinSymbol).width(100%)
        }.width(25%)
      flex.addItem()
        .alignItems(.center)
        .justifyContent(.center)
        .define { flex in
          flex.addItem(self.priceBox).width(80%).height(80%)
            .justifyContent(.center)
            .define { flex in
              flex.addItem(self.price)
            }
        }.width(25%)
      
      flex.addItem(self.changeRate).width(25%)
      flex.addItem(self.accTradePrice).width(25%)
    }
    .padding(0, 10)
  }
  
  func configure(
    crypto: CryptoCellInfo,
    isScrolling: Bool
  ) {
    
    guard let marketEvent = crypto.marketEvent,
          let tradePrice = crypto.tradePrice,
          let signedChangeRate = crypto.signedChangeRate,
          let accTradeVolume = crypto.accTradePrice24h,
          let change = crypto.change  else { return }
    
    if marketEvent.warning == true {
	  let fullText = "[유]\(crypto.cryptoName)"
	  let attributedString = NSMutableAttributedString(string: fullText)

	  // [유]에만 색상 적용
	  attributedString.addAttribute(.foregroundColor,
									 value: UIColor.red,
									 range: NSRange(location: 0, length: 3))

	  self.coinName.attributedText = attributedString
    } else {
      self.coinName.text = crypto.cryptoName
    }
    self.coinSymbol.text = crypto.market
    
    let numberFormatter = NumberFormatter()
    numberFormatter.numberStyle = .decimal
    if tradePrice < 1 {
      self.price.text = formatDecimalPoint(tradePrice)
    } else {
      self.price.text = numberFormatter.string(from: NSNumber(value: tradePrice))
    }
    
    self.changeRate.text = String(format: "%.2f%%", signedChangeRate * 100)
    
    let cryptoSymbolType = crypto.market.split(separator: "/").last!
    
    self.accTradePrice.text = formatTradeVolume(
      for: accTradeVolume,
      cryptoSymbolType: String(cryptoSymbolType)
    )
    
    if signedChangeRate < 0 {
      self.price.textColor = .blue
      self.changeRate.textColor = .blue
    } else if signedChangeRate == 0 {
      self.price.textColor = .black
      self.changeRate.textColor = .black
    } else {
      self.price.textColor = .red
      self.changeRate.textColor = .red
    }
    
    if isScrolling == false {
      switch change {
      case "RISE":
        DispatchQueue.main.async {
          UIView.animate(withDuration: 0.15) {
            self.priceBox.layer.borderColor = UIColor.red.cgColor
          } completion: { _ in
            self.priceBox.layer.borderColor = UIColor.clear.cgColor
          }
        }
        
      case "FALL":
        DispatchQueue.main.async {
          UIView.animate(withDuration: 0.15) {
            self.priceBox.layer.borderColor = UIColor.blue.cgColor
          } completion: { _ in
            self.priceBox.layer.borderColor = UIColor.clear.cgColor
          }
        }
        
      case "EVEN":
        DispatchQueue.main.async {
          self.priceBox.layer.borderColor = UIColor.clear.cgColor
        }
        
      default:
        break
      }
    }
    
    setNeedsLayout()
  }
  
  /// 1보다 작은 금액 Format 설정
  /// - Parameters:
  ///   - tradePrice: 변환할 거래 가격
  ///   - precision: 소수점 자리 수
  func formatDecimalPoint(
    _ tradePrice: Double?,
    _ precision: Int = 8
  ) -> String {
    guard let price = tradePrice else {
      return "N/A"  // 값이 없을 때 반환할 기본 문자열
    }
    
    return String(format: "%.\(precision)f", price)
  }
  
  /// 거래대금 Format
  func formatTradeVolume(
    for tradeVolume: Double,
    cryptoSymbolType: String
  ) -> String {
    var currency: String = ""
    let numberFormatter = NumberFormatter()
    numberFormatter.numberStyle = .decimal
    
    if cryptoSymbolType == CryptoSymbolType.krw.rawValue {
      numberFormatter.maximumFractionDigits = 0
      currency = "백만"
    } else {
      numberFormatter.maximumFractionDigits = 3
      currency = ""
    }
    
    guard let formatVolume = numberFormatter.string(
      from: NSNumber(value: tradeVolume / 1_000_000)
    ) else { return "-"}
    
    
    return formatVolume + currency
  }
  
}

enum CryptoSymbolType: String {
  case krw = "KRW"
  case btc = "BTC"
}

