//
//  MainCryptoTableViewCell.swift
//  Mobit
//
//  Created by 조성재 on 7/3/25.
//

import UIKit

class MainCryptoTableViewCell: UITableViewCell {
  
  @IBOutlet weak var priceBox: UIView!
  @IBOutlet weak var cryptoName: UILabel!					// 코인명
  @IBOutlet weak var cryptoSymbol: UILabel!				// 심볼
  @IBOutlet weak var cryptoPrice: UILabel!					// 현재가
  @IBOutlet weak var cryptoChangeRate: UILabel!			// 전일대비
  @IBOutlet weak var cryptoAccTradePrice: UILabel!		// 거래대금
  
  override func awakeFromNib() {
	super.awakeFromNib()
	// Initialization code
  }
  
  override func setSelected(_ selected: Bool, animated: Bool) {
	super.setSelected(selected, animated: animated)
	
	// Configure the view for the selected state
  }
  
  func configure(
	crypto: CryptoCellInfo,
	isScrolling: Bool
  ) {
	
	self.priceBox.layer.borderWidth = 0.3
	self.priceBox.layer.borderColor = UIColor.clear.cgColor
	self.priceBox.layer.masksToBounds = true
	
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
	  
	  self.cryptoName.attributedText = attributedString
	} else {
	  self.cryptoName.text = crypto.cryptoName
	}
	self.cryptoSymbol.text = crypto.market
	
	let numberFormatter = NumberFormatter()
	numberFormatter.numberStyle = .decimal
	if tradePrice < 1 {
	  self.cryptoPrice.text = formatDecimalPoint(tradePrice)
	} else {
	  self.cryptoPrice.text = numberFormatter.string(from: NSNumber(value: tradePrice))
	}
	
	self.cryptoChangeRate.text = String(format: "%.2f%%", signedChangeRate * 100)
	
	let cryptoSymbolType = crypto.market.split(separator: "/").last!
	
	self.cryptoAccTradePrice.text = formatTradeVolume(
	  for: accTradeVolume,
	  cryptoSymbolType: String(cryptoSymbolType)
	)
	
	if signedChangeRate < 0 {
	  self.cryptoPrice.textColor = .blue
	  self.cryptoChangeRate.textColor = .blue
	} else if signedChangeRate == 0 {
	  self.cryptoPrice.textColor = .black
	  self.cryptoChangeRate.textColor = .black
	} else {
	  self.cryptoPrice.textColor = .red
	  self.cryptoChangeRate.textColor = .red
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
	layoutIfNeeded()
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
  
  enum CryptoSymbolType: String {
	case krw = "KRW"
	case btc = "BTC"
  }
}
