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
  
  @IBOutlet weak var cryptoTagCollectionView: SelfSizingCollectionView!
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
  var reactor: TradeReactor? = nil
  var disposeBag = DisposeBag()
  private var cmcInformation: FirebaseCMCResponse? = nil
  
  static func instanceFromNib(
	reactor: TradeReactor
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
	selfView.setUI()
	selfView.setData()
	selfView.configure()
	
	DispatchQueue.main.async {
	  selfView.setNeedsLayout()
	  selfView.layoutIfNeeded()
	}
	
	return selfView
  }
  
  func configure() {
	self.backgroundColor = .mobitColors(.tradeBackground)
	self.cryptoTagCollectionView.backgroundColor = .clear
	self.basicInfoView.backgroundColor = .mobitColors(.tradeSurface)
	self.basicInfoView.layer.borderWidth = 1
	self.priceInfoView.backgroundColor = .mobitColors(.tradeSurface)
	self.priceInfoView.layer.borderWidth = 1
	self.updateResolvedColors()
	self.marketNameLabel.textColor = .mobitColors(.tradeTextPrimary)
	self.symbolLabels.forEach { $0.textColor = .mobitColors(.tradeTextSecondary) }
	[
	  self.totalSupplyLabel,
	  self.marketCapLabel,
	  self.circulatingSupplyLabel,
	  self.updatedAtStringLabel,
	  self.accTradeVolume24HLabel,
	  self.accTradePrice24HLabel,
	  self.prevClosingPriceLabel,
	  self.highest52WeekPriceLabel,
	  self.lowest52WeekPriceLabel
	].forEach { $0?.textColor = .mobitColors(.tradeTextPrimary) }
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
	configure()
	updateResolvedColors()
  }

  private func updateResolvedColors() {
	let borderColor = UIColor.mobitColors(.tradeSeparator).resolvedColor(with: traitCollection).cgColor
	self.backgroundColor = .mobitColors(.tradeBackground)
	self.basicInfoView.backgroundColor = .mobitColors(.tradeSurface)
	self.priceInfoView.backgroundColor = .mobitColors(.tradeSurface)
	self.basicInfoView.layer.borderColor = borderColor
	self.priceInfoView.layer.borderColor = borderColor
  }
  
  func setUI() {
	guard let cmcInformation = self.reactor?.cmcInformation else { return }
	
	self.cmcInformation = cmcInformation
	let iconURL = URL(string: cmcInformation.iconURL)!
	self.cryptoImageView.load(from: iconURL)
	self.marketNameLabel.text = cmcInformation.name
	self.symbolLabels.forEach { $0.text = cmcInformation.symbol }
	self.totalSupplyLabel.text = cmcInformation.totalSupply.formatSignificantDigits()
	self.marketCapLabel.text = cmcInformation.marketCap.formatSignificantDigits() + " 원"
	self.updatedAtStringLabel.text = cmcInformation.updatedAtString
	self.circulatingSupplyLabel.text = cmcInformation.circulatingSupply.formatSignificantDigits()
	
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
	self.cryptoTagCollectionView.register(
	  UINib(nibName: "TradeInfoCollectionViewCell", bundle: nil),
	  forCellWithReuseIdentifier: "TradeInfoCollectionViewCell"
	)

	self.cryptoTagCollectionView.delegate = self
	self.cryptoTagCollectionView.dataSource = self
	
	guard let reactor = self.reactor else { return }
	self.bind(reactor: reactor)
  }
}

// MARK: Reactor - View
extension TradeInformationView {
  
  func bind(reactor: TradeReactor) {
  }
}


extension TradeInformationView: UICollectionViewDelegate, UICollectionViewDataSource {
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
	return self.cmcInformation?.tags?.count ?? 0
  }
  
  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
	guard let cell = collectionView.dequeueReusableCell(
	  withReuseIdentifier: "TradeInfoCollectionViewCell",
	  for: indexPath
	) as? TradeInfoCollectionViewCell else {
	  return UICollectionViewCell()
	}
	
	guard let tags = self.cmcInformation?.tags else {
	  return UICollectionViewCell()
	}
	
	let tag = tags[indexPath.row]
	cell.configure(tag: tag)
	cell.layoutIfNeeded()
	
	return cell
  }
}
