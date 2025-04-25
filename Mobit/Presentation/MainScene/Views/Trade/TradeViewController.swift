//
//  TradeViewController.swift
//  Mobit
//
//  Created by 조성재 on 2/4/25.
//

import UIKit
import SnapKit
import ReactorKit
import RxSwift

struct OrderUnit: Hashable {
  var identifier: UUID = UUID()
  var type: OrderType
  var price: Double
  var size: Double
}

/// 매수, 매도 타입
enum OrderType: Codable, Equatable {
  case ask
  case bid
}

class TradeViewController: UIViewController, ViewRule {
  
  @IBOutlet weak var cryptoMarketName: UILabel!
  @IBOutlet weak var cryptoPrice: UILabel!
  @IBOutlet weak var cryptoChangedRate: UILabel!
  @IBOutlet weak var cryptoChangedPrice: UILabel!
  @IBOutlet weak var cryptoUpDownArrowImageView: UIImageView!
  @IBOutlet weak var segmentedControl: MobitSegmentedControl!
  @IBOutlet weak var segmentedContainerView: UIView!
  @IBOutlet weak var informationView: UIView!
  
  weak var coordinator: CryptoDetailCoordinator?
  var reactor: CryptoDetailReactor
  var orderView: TradeOrderView? = nil
  var chartView: TradeChartView? = nil
  var prevClosingPrice: Double? = nil
  var disposeBag = DisposeBag()
  /// 가격 변동 -/+/보합에 따른 색상 변경
  var tradeColor: UIColor = .black
  var arrowImage: UIImage = UIImage()
  var arrowColor: UIColor = .clear
  
  init(reactor: CryptoDetailReactor) {
	self.reactor = reactor
	super.init(nibName: nil, bundle: nil)
  }
  
  required init?(coder: NSCoder) {
	fatalError("init(coder:) has not been implemented")
  }
  
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
	self.view.endEditing(true)
  }
  
  override func viewWillAppear(_ animated: Bool) {
	self.reactor.action
	  .onNext(.connectTickerSocket)
	self.reactor.action
	  .onNext(.connectOrderBookSocket)
  }
  
  override func viewDidLoad() {
	super.viewDidLoad()
	setUI()
	setData()
	
	self.bind(reactor: self.reactor)
  }
  
  func setUI() {
	orderView = TradeOrderView.instanceFromNib(
	  reactor: self.reactor
	) { [weak self] orderResult in
	  guard let self = self else { return }
	  switch orderResult {
	  case .alert(let title, let message):
		self.showDefaultAlert(title: title, message: message)
	  default:
		break
	  }
	}
	chartView = TradeChartView.instanceFromNib(symbol: self.reactor.selectCrypto.market)
	
	guard let orderView = self.orderView,
		  let chartView = self.chartView
	else { return }
	
	self.segmentedContainerView.addSubview(orderView)
	self.segmentedContainerView.addSubview(chartView)
	self.segmentedContainerView.addSubview(self.informationView)
	
	self.segmentedControl.setSegmentedControl(
	  normalColor: .mobitColors(.lightGrayBG),
	  selectedColor: .white
	)
	
	orderView.snp.makeConstraints { make in
	  make.edges.equalToSuperview()
	}
	chartView.snp.makeConstraints { make in
	  make.edges.equalToSuperview()
	}
	self.informationView.snp.makeConstraints { make in
	  make.edges.equalToSuperview()
	}
	
	self.segmentedControl.selectedSegmentIndex = 0
	self.tapOnSegmentedControl(self.segmentedControl)
  }
  
  func setCrypto(crypto: CryptoCellInfo? = nil) {
	self.prevClosingPrice = crypto?.prevPrice
	let numberFormatter = NumberFormatter()
	numberFormatter.numberStyle = .decimal
	
	let selectCrypto = crypto ?? self.reactor.selectCrypto
	guard let tradePrice = selectCrypto.tradePrice,
		  let signedChangeRate = selectCrypto.signedChangeRate,
		  let changePrice = selectCrypto.changePrice else { return }
	
	self.cryptoMarketName.text = "\(selectCrypto.cryptoName)(\(selectCrypto.market))"
	if tradePrice < 1 {
	  self.cryptoPrice.text = self.formatTradePrice(tradePrice)
	} else {
	  self.cryptoPrice.text = numberFormatter.string(
		from: NSNumber(value: tradePrice)
	  )
	}
	
	self.cryptoChangedRate.text = String(
	  format: "%.2f%%", signedChangeRate * 100
	)
	
	if changePrice < 1 {
	  self.cryptoChangedPrice.text = self.formatTradePrice(changePrice)
	} else {
	  self.cryptoChangedPrice.text = numberFormatter.string(
		from: NSNumber(value: changePrice)
	  )
	}
	
	let currency = crypto?.market.components(separatedBy: "/").first
//	self.cryptoCountCurrency.text = currency
	
	switch selectCrypto.change {
	case "RISE":
	  self.tradeColor = .red
	  self.arrowImage = UIImage(systemName: "arrowtriangle.up.fill")!
	  self.arrowColor = self.tradeColor
	case "FALL":
	  self.tradeColor = .blue
	  self.arrowImage = UIImage(systemName: "arrowtriangle.down.fill")!
	  self.arrowColor = self.tradeColor
	case "EVEN":
	  self.tradeColor = .black
	  self.arrowImage = UIImage()
	  self.arrowColor = .clear
	default:
	  break
	}
	
	self.cryptoPrice.textColor = tradeColor
	self.cryptoChangedRate.textColor = tradeColor
	self.cryptoChangedPrice.textColor = tradeColor
	self.cryptoUpDownArrowImageView.image = arrowImage
	self.cryptoUpDownArrowImageView.tintColor = arrowColor
  }
  
  func setData() {
  }
  
  @IBAction func tapOnSegmentedControl(_ sender: UISegmentedControl) {
	switch sender.selectedSegmentIndex {
	case 0:
	  orderView?.isHidden = false
	  chartView?.isHidden = true
	  self.informationView.isHidden = true
	case 1:
	  orderView?.isHidden = true
	  chartView?.isHidden = false
	  self.informationView.isHidden = true
	case 2:
	  orderView?.isHidden = true
	  chartView?.isHidden = true
	  self.informationView.isHidden = false
	  
	default:
	  break
	}
  }
  
  @IBAction func tapOnNavigationBack(_ sender: UIButton) {
	self.coordinator?.navigationController.popViewController(animated: true)
	self.reactor.tickerSocketManager.disconnect()
	self.reactor.orderBookSocketManager.disconnect()
  }
  
  /// price format
  func formatTradePrice(_ tradePrice: Double?, precision: Int = 8) -> String {
	guard let price = tradePrice else {
	  return "N/A"  // 값이 없을 때 반환할 기본 문자열
	}
	return String(format: "%.\(precision)f", price)
  }
  
  func showDefaultAlert(title: String, message: String) {
	let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
	let okAction = UIAlertAction(title: "확인", style: .default, handler: nil)
	
	alert.addAction(okAction)
	self.present(alert, animated: true, completion: nil)
  }
}

// MARK: Reactor - View
extension TradeViewController {
  
  func bind(reactor: CryptoDetailReactor) {
	
	reactor.state.map { $0.cryptoInfo }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] cellInfo in
		guard let self = self else { return }
		self.setCrypto(crypto: cellInfo)
	  })
	  .disposed(by: self.disposeBag)
  }
}
