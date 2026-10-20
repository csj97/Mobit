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
  var product: TradingProduct = .spot
  var exchange: Exchange? = nil

  var marketDescription: String {
	guard product == .perpetual, let exchange else { return marketName }
	return "\(exchange.rawValue.capitalized) · \(FuturesText.text("futures_product")) · \(currency)\n\(marketName)"
  }
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
  @IBOutlet weak var entryTitle: UILabel!
  @IBOutlet weak var exitTitle: UILabel!
  
  // 미리보기를 연 원본 계좌를 보존해 저장·공유 클릭을 다른 선택 계좌에 붙이지 않는다.
  private var analyticsAccount: TradingAccountID?

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
    analyticsAccount = pnlShareUnit.exchange.map {
      TradingAccountID(exchange: $0, product: pnlShareUnit.product, currency: .krw)
    }
    if pnlShareUnit.product == .perpetual {
      entryTitle.text = FuturesText.text("futures_entry")
      exitTitle.text = FuturesText.text("futures_exit_price")
      marketName.numberOfLines = 0
    }
    let unit = pnlShareUnit.currency == "KRW" ? " ₩" : " " + pnlShareUnit.currency
	self.marketName.text = pnlShareUnit.marketDescription
	self.entryPriceLabel.text = "\(pnlShareUnit.entryPrice.formatTradingValue())".addComma()
	self.exitPriceLabel.text = "\(pnlShareUnit.exitPrice.formatTradingValue())".addComma()
	self.quantityLabel.text = "\(pnlShareUnit.quantity.formatTradingValue())".addComma()
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
	self.pnlLabel.text = pnlSign + "\(pnlShareUnit.pnl.formatTradingValue())".addComma() + unit
	
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
	MobitAnalyticsUtil.sendClickEvent(event: .pnl_click_save, account: analyticsAccount)
	self.callBack?(.save(saveImg: saveImg))
  }
  
  @IBAction func tapOnShareButton(_ sender: UIButton) {
	guard let shareImg = makeShareImage() else { return }
	MobitAnalyticsUtil.sendClickEvent(event: .pnl_click_share, account: analyticsAccount)
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

	layoutIfNeeded()
	// 기본 공유 이미지 크기는 유지하고 긴 카드에는 바깥 여백까지 포함한다.
	let screenSize = UIScreen.main.bounds.size
	// 미리보기와 같은 최소 바깥 여백을 이미지에도 남긴다.
	let imageInset: CGFloat = 16
	// 스크롤 영역보다 긴 카드도 원본 크기로 저장할 수 있는 캔버스다.
	let captureSize = CGSize(
	  width: max(screenSize.width, pnlView.bounds.width + imageInset * 2),
	  height: max(screenSize.height, pnlView.bounds.height + imageInset * 2)
	)
	// 완성된 카드 전체를 가운데 배치하는 공유 이미지 배경이다.
	let captureView = UIView(frame: CGRect(origin: .zero, size: captureSize))
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
