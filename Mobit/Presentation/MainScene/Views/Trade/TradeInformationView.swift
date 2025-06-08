//
//  TradeInformationView.swift
//  Mobit
//
//  Created by 조성재 on 5/25/25.
//

import Foundation
import UIKit
import RxSwift

class TradeInformationView: UIView, ViewRule {
  
  @IBOutlet weak var cryptoImageView: UIImageView!
  @IBOutlet weak var marketNameLabel: UILabel!
  @IBOutlet weak var basicInfoView: UIView!
  @IBOutlet weak var priceInfoView: UIView!
  @IBOutlet var symbolLabels: [UILabel]!
  @IBOutlet weak var totalSupplyLabel: UILabel!
  @IBOutlet weak var marketCapLabel: UILabel!
  @IBOutlet weak var circulatingSupplyLabel: UILabel!
  @IBOutlet weak var updatedAtStringLabel: UILabel!
  @IBOutlet weak var accTradeVolume24HLabel: UILabel!
  @IBOutlet weak var accTradePrice24HLabel: UILabel!
  @IBOutlet weak var prevClosingPriceLabel: UILabel!
  @IBOutlet weak var highest52WeekPriceLabel: UILabel!
  @IBOutlet weak var lowest52WeekPriceLabel: UILabel!
  
  var symbol: String? = nil
  var reactor: CryptoDetailReactor? = nil
  var disposeBag = DisposeBag()
  private var cryptoQuotesInfo: CryptoQuoteResponse? = nil
  
  static func instanceFromNib(
	reactor: CryptoDetailReactor
  ) -> TradeInformationView {
	
	let selfView = UINib(
	  nibName: String(describing: self),
	  bundle: nil
	).instantiate(
	  withOwner: self, options: nil
	).first as? TradeInformationView
	
	guard let selfView = selfView else {
	  return TradeInformationView()
	}
	
	selfView.reactor = reactor
	selfView.setData()
	selfView.configure()
	
	return selfView
  }
  
  func configure() {
	self.basicInfoView.layer.borderColor = UIColor.lightGray.withAlphaComponent(0.5).cgColor
	self.basicInfoView.layer.borderWidth = 1
	self.priceInfoView.layer.borderColor = UIColor.lightGray.withAlphaComponent(0.5).cgColor
	self.priceInfoView.layer.borderWidth = 1
  }
  
  func setUI() {
	guard let cryptoQuotesInfo = cryptoQuotesInfo else { return }
	
	if let iconURL = cryptoQuotesInfo.iconURL {
	  self.cryptoImageView.load(from: iconURL)
	} else {
	  self.cryptoImageView.image = UIImage(named: "")
	}
	
	self.marketNameLabel.text = cryptoQuotesInfo.name
	self.symbolLabels.forEach { $0.text = cryptoQuotesInfo.symbol }
	self.totalSupplyLabel.text = cryptoQuotesInfo.totalSupply.formatSignificantDigits()
	self.marketCapLabel.text = cryptoQuotesInfo.marketCap.formatSignificantDigits() + " 원"
	self.updatedAtStringLabel.text = cryptoQuotesInfo.updatedAtString
	self.circulatingSupplyLabel.text = cryptoQuotesInfo.circulatingSupply.formatSignificantDigits()
	
	guard let selectedCrypto = self.reactor?.selectCrypto,
		  let accTradePrice24h = selectedCrypto.accTradePrice24h,
		  let accTradeVolume24h = selectedCrypto.accTradeVolume24h,
		  let prevPrice = selectedCrypto.prevPrice,
		  let highest52WeekPrice = selectedCrypto.highest52WeekPrice,
		  let lowest52WeekPrice = selectedCrypto.lowest52WeekPrice
	else { return }
	
	self.accTradeVolume24HLabel.text = accTradeVolume24h.formatSignificantDigits()
	self.accTradePrice24HLabel.text = "\(accTradePrice24h.formatSignificantDigits()) 원"
	self.prevClosingPriceLabel.text = "\(prevPrice.formatSignificantDigits()) 원"
	self.highest52WeekPriceLabel.text = "\(highest52WeekPrice.formatSignificantDigits()) 원"
	self.lowest52WeekPriceLabel.text = "\(lowest52WeekPrice.formatSignificantDigits()) 원"
  }
  
  func setData() {
	guard let reactor = self.reactor else { return }
	self.bind(reactor: reactor)
	self.reactor?.action.onNext(.getCryptoInformation)
  }
}

// MARK: Reactor - View
extension TradeInformationView {
  
  func bind(reactor: CryptoDetailReactor) {
	reactor.state.map { $0.cryptoQuotesInfo }
	  .distinctUntilChanged()
	  .subscribe(onNext: { cryptoQuotesInfo in
		guard let cryptoQuotesInfo = cryptoQuotesInfo else { return }
		self.cryptoQuotesInfo = cryptoQuotesInfo
		self.setUI()
		print("🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁")
		print(cryptoQuotesInfo)
	  })
	  .disposed(by: disposeBag)
	
  }
}
