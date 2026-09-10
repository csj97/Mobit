//
//  PNLShareView.swift
//  Mobit
//
//  Created by 조성재 on 8/5/25.
//

import UIKit

struct PNLShareUnit {
  let marketName: String
  let roi: Double
  let pnl: Double
  let quantity: Double
  let entryPrice: Double
  let exitPrice: Double
  let transactionDate: String
  var currency: String = "KRW"
}

enum PNLShareButtonType {
  case save(saveImg: UIImage)
  case share(shareImg: UIImage)
}

class PNLShareView: UIView {
  
  @IBOutlet weak var pnlView: UIView!
    
  @IBOutlet weak var marketName: UILabel!
  @IBOutlet weak var roiLabel: UILabel!
  @IBOutlet weak var entryPriceLabel: UILabel!
  @IBOutlet weak var exitPriceLabel: UILabel!
  @IBOutlet weak var pnlLabel: UILabel!
  @IBOutlet weak var quantityLabel: UILabel!
  @IBOutlet weak var transactionDateLabel: UILabel!
  @IBOutlet weak var buttonStackView: UIStackView!
  
  var callBack: ((PNLShareButtonType) -> ())? = nil
  
  deinit {
	  print("deinit : " + String(describing: type(of: self)))
  }

  static func instanceFromNib(
	pnlShareUnit: PNLShareUnit,
	callBack: @escaping (PNLShareButtonType) -> ()
  ) -> PNLShareView {
	
	let selfView = UINib(
	  nibName: String(describing: self),
	  bundle: nil
	).instantiate(
	  withOwner: self, options: nil
	).first as? PNLShareView
	
	guard let selfView = selfView else {
	  return PNLShareView()
	}
	
	selfView.configure(pnlShareUnit: pnlShareUnit)
	selfView.callBack = callBack
	
	return selfView
  }
  
  func configure(pnlShareUnit: PNLShareUnit) {
    let digits = pnlShareUnit.currency == "KRW" ? 2 : 8
    let unit = pnlShareUnit.currency == "KRW" ? " ₩" : " " + pnlShareUnit.currency
	self.marketName.text = pnlShareUnit.marketName
	self.entryPriceLabel.text = "\(pnlShareUnit.entryPrice.formatSignificantDigits(digits: digits))".addComma()
	self.exitPriceLabel.text = "\(pnlShareUnit.exitPrice.formatSignificantDigits(digits: digits))".addComma()
	self.quantityLabel.text = "\(pnlShareUnit.quantity.formatSignificantDigits(digits: 2))".addComma()
	self.transactionDateLabel.text = pnlShareUnit.transactionDate
	
	var pnlSign = ""
	if pnlShareUnit.pnl > 0 {
	  self.pnlLabel.textColor = MarketColorPalette.riseColor
	  pnlSign = "+"
	} else if pnlShareUnit.pnl < 0 {
	  self.pnlLabel.textColor = MarketColorPalette.fallColor
	  pnlSign = ""
	} else {
	  self.pnlLabel.textColor = .mobitColors(.textPrimary)
	  pnlSign = ""
	}
	self.pnlLabel.text = pnlSign + "\(pnlShareUnit.pnl.formatSignificantDigits(digits: digits))".addComma() + unit
	
	var roiSign = ""
	if pnlShareUnit.roi > 0 {
	  self.roiLabel.textColor = MarketColorPalette.riseColor
	  roiSign = "+"
	} else if pnlShareUnit.pnl < 0 {
	  self.roiLabel.textColor = MarketColorPalette.fallColor
	  roiSign = ""
	} else {
	  self.roiLabel.textColor = .mobitColors(.textPrimary)
	  roiSign = ""
	}
	
	self.roiLabel.text = roiSign + "\(pnlShareUnit.roi.formatSignificantDigits(digits: 2)) %"
  }
  
  @IBAction func tapOnSaveButton(_ sender: UIButton) {
	guard let saveImg = makeShareImage() else { return }
	MobitAnalyticsUtil.sendClickEvent(event: .pnl_click_save)
	self.callBack?(.save(saveImg: saveImg))
  }
  
  @IBAction func tapOnShareButton(_ sender: UIButton) {
	guard let shareImg = makeShareImage() else { return }
	MobitAnalyticsUtil.sendClickEvent(event: .pnl_click_share)
	self.callBack?(.share(shareImg: shareImg))
  }
  
  @IBAction func tapOnCloseButton(_ sender: UIButton) {
	DispatchQueue.main.async {
	  UIView.animate(withDuration: 0.3) {
		self.alpha = 0
	  } completion: { _ in
		self.removeFromSuperview()
	  }
	}
  }
  
  func makeShareImage() -> UIImage? {
	guard let pnlView = self.pnlView else { return nil }

	let screenSize = UIScreen.main.bounds.size
	let captureView = UIView(frame: CGRect(origin: .zero, size: screenSize))
	captureView.backgroundColor = .mobitColors(.backgroundPrimary)

	let pnlImage = pnlView.asImage()
	let pnlImageView = UIImageView(image: pnlImage)
	pnlImageView.contentMode = .scaleAspectFit

	captureView.addSubview(pnlImageView)
	pnlImageView.translatesAutoresizingMaskIntoConstraints = false
	pnlImageView.snp.makeConstraints { make in
	  make.center.equalToSuperview()
	}
	
	captureView.setNeedsLayout()
	captureView.layoutIfNeeded()

	return captureView.asImage()
  }
}
