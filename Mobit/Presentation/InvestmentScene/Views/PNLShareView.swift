//
//  PNLShareView.swift
//  Mobit
//
//  Created by 조성재 on 8/5/25.
//

import UIKit

struct PNLShareUnit {
  let marketName: String
  let roi: Decimal
  let pnl: Decimal
  let quantity: Decimal
  let entryPrice: Decimal
  let exitPrice: Decimal
  let transactionDate: String
  var currency: String = "KRW"
  var product: TradingProduct = .spot
  var exchange: Exchange? = nil

  var marketDescription: String {
	guard product == .perpetual, let exchange else { return marketName }
	return "\(exchange.rawValue.capitalized) · \(FuturesText.text("futures_product")) · \(currency)\n\(marketName)"
  }
}

extension PNLShareUnit {
  static func spot(_ history: UserPNLHistoryModel) -> PNLShareUnit {
    // 기존 현물 값은 표시 경계에서 십진수로 변환한다.
    var entryPrice = PortfolioCalculator.decimal(history.entryPrice)
    // 원화 원가가 있으면 원본 정밀도로 환산한 종료 가격을 표시한다.
    var exitPrice = PortfolioCalculator.decimal(history.exitPrice)
    // 기존 손익값 또는 원화 정산 원본을 공유한다.
    var pnl = PortfolioCalculator.decimal(history.pnl)
    // 정산 여부에 따라 공유 화면에 표시할 결제 통화다.
    var currency = history.settlementCurrency.rawValue
    if let cost = history.costBasisKRW, let realized = history.realizedProfitLossKRW,
       history.orderQuantity > 0 {
      // 원화 원가와 손익을 해당 체결 수량의 단가로 환산한다.
      let quantity = PortfolioCalculator.decimal(history.orderQuantity)
      entryPrice = cost / quantity
      exitPrice = (cost + realized) / quantity
      pnl = realized
      currency = "KRW"
    }
    // 기존 양수 진입가 조건과 퍼센트 표시 자릿수를 유지한다.
    let roi: Decimal = !entryPrice.isNaN && entryPrice > 0
      ? (exitPrice - entryPrice) / entryPrice * 100 : 0
    return PNLShareUnit(
      marketName: history.marketName,
      roi: roi,
      pnl: pnl,
      quantity: PortfolioCalculator.decimal(history.orderQuantity),
      entryPrice: entryPrice,
      exitPrice: exitPrice,
      transactionDate: history.transactionDate,
      currency: currency,
      exchange: history.exchange
    )
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
	self.entryPriceLabel.text = TradingNumberFormat.string(pnlShareUnit.entryPrice)
	self.exitPriceLabel.text = TradingNumberFormat.string(pnlShareUnit.exitPrice)
	self.quantityLabel.text = TradingNumberFormat.string(pnlShareUnit.quantity)
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
	self.pnlLabel.text = pnlSign + TradingNumberFormat.string(pnlShareUnit.pnl) + unit
	
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
	
	self.roiLabel.text = roiSign + "\(PortfolioCalculator.double(pnlShareUnit.roi).formatSignificantDigits(digits: 2)) %"
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
