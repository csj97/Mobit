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

class TradeViewController: MobitBaseViewController {
  
  @IBOutlet weak var cryptoMarketName: UILabel!
  @IBOutlet weak var cryptoPrice: UILabel!
  @IBOutlet weak var cryptoChangedRate: UILabel!
  @IBOutlet weak var cryptoChangedPrice: UILabel!
  @IBOutlet weak var cryptoUpDownArrowImageView: UIImageView!
  @IBOutlet weak var favoriteButton: UIButton!
  @IBOutlet weak var mobitSegmentedControl: MobitNeumorphicSegmentedControl!
  @IBOutlet weak var segmentedContainerView: UIView!
  
  weak var coordinator: CryptoDetailCoordinator?
  weak var delegate: MainCoordinatorDelegate?
  var reactor: TradeReactor
  var orderView: TradeOrderView? = nil
  var chartView: TradeChartView? = nil
  var informationView: TradeInformationView? = nil
  var prevClosingPrice: Double? = nil
  var disposeBag = DisposeBag()
  /// 가격 변동 -/+/보합에 따른 색상 변경
  var tradeColor: UIColor = .black
  var arrowImage: UIImage = UIImage()
  var arrowColor: UIColor = .clear
  
  init(reactor: TradeReactor) {
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
	super.viewWillAppear(animated)
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
  
  override func viewWillDisappear(_ animated: Bool) {
	super.viewWillDisappear(animated)
	self.delegate?.mainCoordinatorDidRequestShowTabBar()
  }
  
  func setUI() {
	setFavoriteButton()
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
	informationView = TradeInformationView.instanceFromNib(
	  reactor: self.reactor
	)
	
	guard let orderView = self.orderView,
		  let chartView = self.chartView,
		  let informationView = self.informationView
	else { return }
	
	self.segmentedContainerView.addSubview(orderView)
	self.segmentedContainerView.addSubview(chartView)
	self.segmentedContainerView.addSubview(informationView)
	
	orderView.snp.makeConstraints { make in
	  make.edges.equalToSuperview()
	}
	chartView.snp.makeConstraints { make in
	  make.edges.equalToSuperview()
	}
	informationView.snp.makeConstraints { make in
	  make.edges.equalToSuperview()
	}
	
	self.mobitSegmentedControl.segments = ["주문", "차트", "정보"]
	self.mobitSegmentedControl.onSegmentChanged = { [weak self] index in
	  guard let self = self else { return }
	  switch index {
	  case 0:
		MobitAnalyticsUtil.sendScreen(event: .trade_order)
		orderView.isHidden = false
		chartView.isHidden = true
		informationView.isHidden = true
		self.reactor.action.onNext(.setSelectedWholeTab(selectedWholeTab: .trade))
	  case 1:
		MobitAnalyticsUtil.sendScreen(event: .trade_chart)
		orderView.isHidden = true
		chartView.isHidden = false
		informationView.isHidden = true
		self.reactor.action.onNext(.setSelectedWholeTab(selectedWholeTab: .chart))
	  case 2:
		MobitAnalyticsUtil.sendScreen(event: .trade_info)
		orderView.isHidden = true
		chartView.isHidden = true
		informationView.isHidden = false
		self.reactor.action.onNext(.setSelectedWholeTab(selectedWholeTab: .info))
		
	  default:
		break
	  }
	}
	
	self.mobitSegmentedControl.selectedIndex = 0
	self.mobitSegmentedControl.onSegmentChanged?(self.mobitSegmentedControl.selectedIndex)
  }
  
  func setData() {
	NotificationCenter.default.addObserver(
		self, selector: #selector(viewDidBecomeActive),
		name: UIApplication.didBecomeActiveNotification,
		object: nil
	)
	NotificationCenter.default.addObserver(
		self, selector: #selector(viewWillResignActive),
		name: UIApplication.willResignActiveNotification,
		object: nil
	)
  }
  
  /// 앱 상태가 백그라운드에서 Active 상태로 전환 되면 택시 상태를 조회하여 복구
  @objc func viewDidBecomeActive() {
	print("Mobit Main - viewDidBecomeActive")
	self.hideLoadingIndicator()
  }
  
  /// 앱이 In-Active 상태로 전환
  @objc func viewWillResignActive() {
	print("Mobit Main - viewWillResignActive")
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
  
  func setFavoriteButton() {
	let emptyStar = UIImage(systemName: "star")
	let fillStar = UIImage(systemName: "star.fill")?.withRenderingMode(.alwaysTemplate)
	
	let isFavorite = UserDataManager.userFavoriteList.contains(
	  where: { $0 == self.reactor.selectCrypto.market }
	)
	let starImage = isFavorite ? fillStar : emptyStar
	
	self.favoriteButton.tintColor = .systemYellow
	self.favoriteButton.setImage(starImage, for: .normal)
  }
  
  @IBAction func tapOnFavoriteButton(_ sender: UIButton) {
	let isFavorite = UserDataManager.userFavoriteList.contains(
	  where: { $0 == self.reactor.selectCrypto.market }
	)
	
	if !isFavorite {
	  UserDataManager.userFavoriteList.append(self.reactor.selectCrypto.market)
	} else {
	  UserDataManager.userFavoriteList.removeAll(
		where: { $0 == self.reactor.selectCrypto.market }
	  )
	}
	setFavoriteButton()
  }
  
  @IBAction func tapOnNavigationBack(_ sender: UIButton) {
	self.coordinator?.navigationController.popViewController(animated: true)
	
	guard let tickerSocketManager = reactor.tickerSocketManager,
		  let orderbookSocketManager = reactor.orderBookSocketManager
	else {
	  reactor.tickerSocketManager = nil
	  reactor.orderBookSocketManager = nil
	  return
	}
	
	tickerSocketManager.disconnect()
	orderbookSocketManager.disconnect()
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
  
  func setSegmentedColor(color: UIColor) {
	
  }
}

// MARK: Reactor - View
extension TradeViewController {
  
  func bind(reactor: TradeReactor) {
	
	reactor.state.map { $0.cryptoCellInfo }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] cellInfo in
		guard let self = self else { return }
		self.setCrypto(crypto: cellInfo)
	  })
	  .disposed(by: self.disposeBag)
	
	reactor.state.map { $0.selectedWholeTab }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe (onNext: { [weak self] tab in
		guard let self = self else { return }
	  })
	  .disposed(by: self.disposeBag)
  }
}

// MARK: - WebSocket Pause & Resume
extension TradeViewController: SocketControllable {
  func pauseSocket() {
	guard let tickerSocketManager = self.reactor.tickerSocketManager,
		  let orderBookSocketManager = self.reactor.orderBookSocketManager
	else { return }
	
	tickerSocketManager.disconnect(manual: false)
	orderBookSocketManager.disconnect(manual: false)
  }
  
  func resumeSocket() {
	guard let tickerSocketManager = self.reactor.tickerSocketManager,
		  let orderBookSocketManager = self.reactor.orderBookSocketManager
	else {
	  self.reactor.action.onNext(.connectTickerSocket)
	  self.reactor.action.onNext(.connectOrderBookSocket)
	  return
	}
	
	tickerSocketManager.reconnectIfNeeded()
	orderBookSocketManager.reconnectIfNeeded()
  }
}
