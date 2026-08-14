//
//  MainCryptoTableViewCell.swift
//  Mobit
//
//  Created by 조성재 on 7/3/25.
//

import UIKit
import SkeletonView

class MainCryptoTableViewCell: UITableViewCell {
  
  @IBOutlet weak var priceBox: UIView!
  @IBOutlet weak var cryptoName: UILabel!					// 코인명
  @IBOutlet weak var cryptoSymbol: UILabel!				// 심볼
  @IBOutlet weak var cryptoPrice: UILabel!					// 현재가
  @IBOutlet weak var cryptoChangeRate: UILabel!			// 전일대비
  @IBOutlet weak var cryptoAccTradePrice: UILabel!		// 거래대금
  
  override func awakeFromNib() {
	super.awakeFromNib()
	self.backgroundColor = .mobitColors(.backgroundPrimary)
	self.contentView.backgroundColor = .mobitColors(.backgroundPrimary)
	self.cryptoName.textColor = .mobitColors(.textPrimary)
	self.cryptoSymbol.textColor = .mobitColors(.textTertiary)
	self.cryptoAccTradePrice.textColor = .mobitColors(.textPrimary)
	// 현재가·전일대비는 regular라 다소 연해 보여 medium으로 강조
	self.cryptoPrice.font = .systemFont(ofSize: 13, weight: .medium)
	self.cryptoChangeRate.font = .systemFont(ofSize: 13, weight: .medium)
	// 셀 배경 틴트가 보이도록 내부 스택뷰의 흰 배경을 비움
	self.priceBox.superview?.backgroundColor = .clear
	self.cryptoName.superview?.backgroundColor = .clear
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
	  attributedString.addAttribute(
		.foregroundColor,
		value: UIColor.mobitColors(.textPrimary),
		range: NSRange(location: 0, length: attributedString.length)
	  )
	  // [유]에만 경고 색상 적용
	  attributedString.addAttribute(.foregroundColor,
									value: UIColor.red,
									range: NSRange(location: 0, length: 3))
	  
	  self.cryptoName.attributedText = attributedString
	} else {
	  self.cryptoName.attributedText = nil
	  self.cryptoName.textColor = .mobitColors(.textPrimary)
	  self.cryptoName.text = crypto.cryptoName
	}
	self.cryptoSymbol.text = crypto.market
	self.cryptoSymbol.textColor = .mobitColors(.textTertiary)
	self.cryptoAccTradePrice.textColor = .mobitColors(.textPrimary)
	
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
	  self.cryptoPrice.textColor = MarketColorPalette.fallColor
	  self.cryptoChangeRate.textColor = MarketColorPalette.fallColor
	} else if signedChangeRate == 0 {
	  self.cryptoPrice.textColor = .mobitColors(.textPrimary)
	  self.cryptoChangeRate.textColor = .mobitColors(.textPrimary)
	} else {
	  self.cryptoPrice.textColor = MarketColorPalette.riseColor
	  self.cryptoChangeRate.textColor = MarketColorPalette.riseColor
	}

	// 상승/하락/보합 색을 아주 연하게 셀 배경 틴트로 표시 (더보기에서 on/off)
	if UserDataManager.marketCellTintEnabled == false {
	  self.contentView.backgroundColor = .clear
	} else if signedChangeRate > 0 {
	  self.contentView.backgroundColor = MarketColorPalette.riseColor.withAlphaComponent(0.08)
	} else if signedChangeRate < 0 {
	  self.contentView.backgroundColor = MarketColorPalette.fallColor.withAlphaComponent(0.08)
	} else {
	  self.contentView.backgroundColor = UIColor.mobitColors(.surfacePrimary)
	}

	if isScrolling == false {
	  switch change {
	  case "RISE":
		DispatchQueue.main.async {
		  UIView.animate(withDuration: 0.15) {
			self.priceBox.layer.borderColor = MarketColorPalette.riseColor.cgColor
		  } completion: { _ in
			self.priceBox.layer.borderColor = UIColor.clear.cgColor
		  }
		}
		
	  case "FALL":
		DispatchQueue.main.async {
		  UIView.animate(withDuration: 0.15) {
			self.priceBox.layer.borderColor = MarketColorPalette.fallColor.cgColor
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
  
  func setupSkeletonView() {
	// 셀의 모든 서브뷰를 skeletonable로 설정
	self.isSkeletonable = true
	self.contentView.isSkeletonable = true
	
	// 스켈레톤을 적용할 특정 뷰들 설정
	self.cryptoName.isSkeletonable = true
	self.cryptoSymbol.isSkeletonable = true
	self.cryptoPrice.isSkeletonable = true
	self.cryptoChangeRate.isSkeletonable = true
	self.cryptoAccTradePrice.isSkeletonable = true
	self.isSkeletonable = true
	self.contentView.isSkeletonable = true
	
	// 스켈레톤 스타일
	cryptoName.skeletonCornerRadius = 4
	cryptoSymbol.skeletonCornerRadius = 4
	cryptoPrice.skeletonCornerRadius = 4
	cryptoChangeRate.skeletonCornerRadius = 4
	cryptoAccTradePrice.skeletonCornerRadius = 4
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
	var formatVolume: String = ""
	let numberFormatter = NumberFormatter()
	numberFormatter.numberStyle = .decimal
	
	if cryptoSymbolType == CryptoSymbolType.krw.rawValue {
	  numberFormatter.maximumFractionDigits = 0
	  formatVolume = numberFormatter.string(from: NSNumber(value: tradeVolume / 1_000_000)) ?? "0"
	  currency = "백만"
	} else {
	  numberFormatter.maximumFractionDigits = 6
	  formatVolume = numberFormatter.string(from: NSNumber(value: tradeVolume)) ?? "0"
	  currency = ""
	}
	
//	guard let formatVolume = numberFormatter.string(
//	  from: NSNumber(value: tradeVolume / 1_000_000)
//	) else { return "-" }
	
	
	return formatVolume + currency
  }
  
  enum CryptoSymbolType: String {
	case krw = "KRW"
	case btc = "BTC"
  }
}
