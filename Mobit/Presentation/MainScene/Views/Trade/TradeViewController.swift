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
import Charts
import GoogleMobileAds
import SwiftUI

struct OrderUnit: Hashable {
  var identifier: String
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
  @IBOutlet weak var bannerContainerView: UIView!
  @IBOutlet weak var miniChartContainerView: UIView!
    
  weak var coordinator: CryptoDetailCoordinator?
  weak var delegate: MainCoordinatorDelegate?
  var reactor: TradeReactor
  var orderView: TradeOrderView? = nil
  var chartView: TradeChartView? = nil
  var informationView: TradeInformationView? = nil
  var prevClosingPrice: Double? = nil
  var disposeBag = DisposeBag()
  /// 가격 변동 -/+/보합에 따른 색상 변경
  var tradeColor: UIColor = .mobitColors(.tradeTextPrimary)
  var arrowImage: UIImage = UIImage()
  var arrowColor: UIColor = .clear
  
  var cryptoData: [CryptoTransactionDataModel] = []
  private var currentInvestData: CryptoTransactionDataModel? = nil
  private var miniChartHostingController: UIHostingController<MiniChartView>? = nil
  private var miniChartCandleEntries: [CandleEntry] = []
  private let tradeBannerSlotID = "trade_bottom"
  
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
  
  // MARK: - Life Cycles
  
  override func viewWillAppear(_ animated: Bool) {
	super.viewWillAppear(animated)
	self.setCrypto()
	self.applyThemeColors()
	self.orderView?.refreshMarketColors()
	self.refreshMiniChartColors()
	self.reactor.action.onNext(.connectSockets)
  }
  
  override func viewDidLoad() {
	super.viewDidLoad()
	setUI()
	setData()
	setChartData()
	loadBannerADView()
	
	self.bind(reactor: self.reactor)
  }
  
  override func viewWillDisappear(_ animated: Bool) {
	super.viewWillDisappear(animated)
	self.delegate?.mainCoordinatorDidRequestShowTabBar()
  }
  /// 앱 상태가 백그라운드에서 Active 상태로 전환 되면 택시 상태를 조회하여 복구
  @objc func viewDidBecomeActive() {
	// print("Mobit Main - viewDidBecomeActive")
	self.hideLoadingIndicator()
  }
  
  /// 앱이 In-Active 상태로 전환
  @objc func viewWillResignActive() {
	// print("Mobit Main - viewWillResignActive")
  }
  
  // MARK: - UI Setting
  
  func setUI() {
	setFavoriteButton()

	applyThemeColors()
	self.miniChartContainerView.layer.borderWidth = 0.5
	
	orderView = TradeOrderView.instanceFromNib(
	  reactor: self.reactor
	) { [weak self] orderResult in
	  guard let self = self else { return }
	  switch orderResult {
	  case .alert(let title, let message):
		self.showDefaultAlert(title: title, message: message)
	  case .successLottie:
		let lottieView = MobitLottieView(
		  lottieName: "check_deep_blue",
		  loopMode: .playOnce,
		  lottieSpeed: 1.7,
		  bgColor: UIColor.mobitColors(.tradeBackground).withAlphaComponent(0.3)
		)
		lottieView.configure()
		
		self.view.addSubview(lottieView)
		
		lottieView.snp.makeConstraints { make in
		  make.edges.equalToSuperview()
		}
		
		DispatchQueue.main.async {
		  lottieView.playLottie {
			UIView.animate(withDuration: 0.4, animations: {
				lottieView.alpha = 0
			}, completion: { _ in
				lottieView.stopLottie()
				lottieView.removeFromSuperview()
			})
		  }
		}
	  case .calcuator(let cryptoInvestData):
		self.showCalculatorView(cryptoInvestData: cryptoInvestData)
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
		MobitAnalyticsUtil.sendScreenEvent(event: .trade_order)
		orderView.isHidden = false
		chartView.isHidden = true
		informationView.isHidden = true
		self.reactor.action.onNext(.setSelectedWholeTab(selectedWholeTab: .trade))
	  case 1:
		MobitAnalyticsUtil.sendScreenEvent(event: .trade_chart)
		orderView.isHidden = true
		chartView.isHidden = false
		informationView.isHidden = true
		self.reactor.action.onNext(.setSelectedWholeTab(selectedWholeTab: .chart))
	  case 2:
		guard self.reactor.hasInformationTabData else {
		  self.showDefaultAlert(
			title: "안내",
			message: "해당 코인에 대한 정보 업데이트가 필요합니다.\n빠른 시일내에 해결하겠습니다."
		  )
		  self.restoreSelectedWholeTab()
		  return
		}

		MobitAnalyticsUtil.sendScreenEvent(event: .trade_info)
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

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
	applyThemeColors()
  }

  private func applyThemeColors() {
	self.view.backgroundColor = .mobitColors(.tradeBackground)
	self.cryptoMarketName.textColor = .mobitColors(.tradeTextPrimary)
	self.segmentedContainerView.backgroundColor = .mobitColors(.tradeBackground)
	self.bannerContainerView.backgroundColor = .mobitColors(.tradeSurface)
	self.setFavoriteButton()
	self.miniChartContainerView.backgroundColor = .clear
	self.miniChartHostingController?.view.backgroundColor = .clear
	self.miniChartContainerView.layer.borderColor = UIColor.mobitColors(.tradeSeparator).resolvedColor(with: traitCollection).cgColor
	if self.arrowColor == .clear {
	  self.tradeColor = .mobitColors(.tradeTextPrimary)
	}
	self.cryptoPrice.textColor = self.tradeColor
	self.cryptoChangedRate.textColor = self.tradeColor
	self.cryptoChangedPrice.textColor = self.tradeColor
	self.cryptoUpDownArrowImageView.tintColor = self.arrowColor
  }

  private func restoreSelectedWholeTab() {
	switch self.reactor.currentState.selectedWholeTab {
	case .trade:
	  self.mobitSegmentedControl.selectedIndex = 0
	  self.orderView?.isHidden = false
	  self.chartView?.isHidden = true
	  self.informationView?.isHidden = true
	case .chart:
	  self.mobitSegmentedControl.selectedIndex = 1
	  self.orderView?.isHidden = true
	  self.chartView?.isHidden = false
	  self.informationView?.isHidden = true
	case .info:
	  self.mobitSegmentedControl.selectedIndex = 2
	  self.orderView?.isHidden = true
	  self.chartView?.isHidden = true
	  self.informationView?.isHidden = false
	}
  }
  
  
  // MARK: - Data Settings
  
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
	
	switch selectCrypto.change {
	case "RISE":
	  self.tradeColor = MarketColorPalette.riseColor
	  self.arrowImage = UIImage(systemName: "arrowtriangle.up.fill")!
	  self.arrowColor = self.tradeColor
	case "FALL":
	  self.tradeColor = MarketColorPalette.fallColor
	  self.arrowImage = UIImage(systemName: "arrowtriangle.down.fill")!
	  self.arrowColor = self.tradeColor
		case "EVEN":
		  self.tradeColor = .mobitColors(.tradeTextPrimary)
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
	
	self.fetchUserCryptoList(
	  marketName: selectCrypto.market,
	  currentPrice: tradePrice
	)
  }
  
  func setFavoriteButton() {
	let emptyStar = UIImage(systemName: "star")
	let fillStar = UIImage(systemName: "star.fill")?.withRenderingMode(.alwaysTemplate)
    let exchange = ExchangeSelectionStore.currentExchange
    let pairID = ExchangeMarketCodeConverter.pairID(
      fromDisplayMarket: self.reactor.selectCrypto.market,
      exchange: exchange
    )
	
    let isFavorite = UserDataManager.isFavorite(pairID: pairID)
	let starImage = isFavorite ? fillStar : emptyStar
	
	self.favoriteButton.tintColor = isFavorite ? .systemYellow : .mobitColors(.tradeTextPrimary)
	self.favoriteButton.setImage(starImage, for: .normal)
  }
  
  /// 백그라운드 포그라운드 노티 설정
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
  
  /// crypto socket 업데이트 될 때, 매수 목록 fetch
  func fetchUserCryptoList(
	marketName: String,
	currentPrice: Double?
  ) {
	guard let currentPrice = currentPrice else { return }
    let targetPairID = ExchangeMarketCodeConverter.pairID(
      fromDisplayMarket: marketName,
      exchange: ExchangeSelectionStore.currentExchange
    )
	guard var investData = self.currentInvestData,
		  investData.staticData.exchangePairID == targetPairID else {
	  self.orderView?.cryptoInvestData = nil
	  self.orderView?.investLiveView.isHidden = true
	  return
	}
	
	let averageBuyPrice = investData.staticData.averageBuyPrice
	let holdingQuantity = investData.staticData.holdingQuantity
	guard averageBuyPrice > 0, holdingQuantity >= 0 else { return }
	
	let profitRate = PortfolioCalculator.profitRate(
	  currentPrice: currentPrice,
	  averageBuyPrice: averageBuyPrice
	)
	let evaluationPrice = PortfolioCalculator.evaluationPrice(
	  currentPrice: currentPrice,
	  holdingQuantity: holdingQuantity
	)
	let evaluationProfitLoss = PortfolioCalculator.evaluationProfitLoss(
	  currentPrice: currentPrice,
	  holdingQuantity: holdingQuantity,
	  averageBuyPrice: averageBuyPrice
	)
	
	investData.dynamicData.profitRate = profitRate
	investData.dynamicData.evaluationPrice = evaluationPrice
	investData.dynamicData.evaluationProfitLoss = evaluationProfitLoss
	self.currentInvestData = investData
	
	guard let orderView = self.orderView else { return }
	if orderView.segmentedControl.selectedIndex == 2 {
	  orderView.investLiveView.isHidden = true
	  return
	}
	
	orderView.investLiveView.isHidden = false
	orderView.setInvestLiveData(data: investData)
  }
  
  /// 하단 배너 광고 불러오기
  func loadBannerADView() {
    self.bannerContainerView.subviews.forEach { $0.removeFromSuperview() }

	// TODO: coupang banner 광고 현재 미동작 (4/10 일단 구글 배너로 배포나감)
	self.showGoogleBanner()
	
//    HybridAdSlotManager.shared.resolveAd(slotID: self.tradeBannerSlotID) { [weak self] result in
//      guard let self = self else { return }
//
//      DispatchQueue.main.async {
//        switch result {
//        case .googleBanner:
//          self.showGoogleBanner()
//        case .coupangWidget(let widget):
//          self.showCoupangWidget(widget: widget)
//        }
//      }
//    }
  }

  private func showGoogleBanner() {
    let bannerView = BannerView(adSize: AdSizeBanner)
    bannerView.adUnitID = MobitConstants.bannerAdType
    bannerView.rootViewController = self
		bannerView.backgroundColor = .mobitColors(.tradeSurface)
    self.bannerContainerView.addSubview(bannerView)

    bannerView.snp.makeConstraints { make in
      make.edges.equalToSuperview()
    }

    bannerView.load(Request())
  }

  private func showCoupangWidget(widget: CoupangWidgetConfig) {
    let widgetView = CoupangWidgetBannerView()
    widgetView.configure(widget: widget)
    self.bannerContainerView.addSubview(widgetView)

    widgetView.snp.makeConstraints { make in
      make.edges.equalToSuperview()
    }
  }
  
  /// price format
  func formatTradePrice(_ tradePrice: Double?, precision: Int = 8) -> String {
	guard let price = tradePrice else {
	  return "N/A"  // 값이 없을 때 반환할 기본 문자열
	}
	return String(format: "%.\(precision)f", price)
  }
  
  
  // MARK: - Charts
  func setChartData() {
	let now = Date()

	let formatter = ISO8601DateFormatter()
	formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

	let toString = formatter.string(from: now)
	
	// 10분봉 144개 > 24시간 미니차트
	self.reactor.action
	  .onNext(.getCandleListMinutes(
		market: self.reactor.selectCrypto.market.marketForCandleRequest,
		unit: 10,
		to: toString,
		count: 144
	  ))
	
//	self.reactor.action
//	  .onNext(.getCandleListDays(
//		market: self.reactor.selectCrypto.market.marketForCandleRequest,
//		to: toString,
//		count: 50,
//		convertingPriceUnit: nil
//	  ))
  }
  
  // MARK: - Button Actions
  @IBAction func tapOnFavoriteButton(_ sender: UIButton) {
    let exchange = ExchangeSelectionStore.currentExchange
    let pairID = ExchangeMarketCodeConverter.pairID(
      fromDisplayMarket: self.reactor.selectCrypto.market,
      exchange: exchange
    )
    let isFavorite = UserDataManager.isFavorite(pairID: pairID)
	
	if !isFavorite {
      UserDataManager.addFavorite(
        displayMarket: self.reactor.selectCrypto.market,
        exchange: exchange
      )
	} else {
      UserDataManager.removeFavorite(
        displayMarket: self.reactor.selectCrypto.market,
        exchange: exchange
      )
	}
	setFavoriteButton()
	applyThemeColors()
  }
  
  @IBAction func tapOnNavigationBack(_ sender: UIButton) {
	self.coordinator?.navigationController.popViewController(animated: true)
    self.reactor.action.onNext(.disconnectSockets(userInitiated: true))
  }
  
  func showDefaultAlert(title: String, message: String) {
	let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
	let okAction = UIAlertAction(title: "확인", style: .default, handler: nil)
	
	alert.addAction(okAction)
	self.present(alert, animated: true, completion: nil)
  }
  
  func showCalculatorView(cryptoInvestData: CryptoTransactionDataModel) {
	let holdingQty = cryptoInvestData.staticData.holdingQuantity.formatSignificantDigits(digits: 2)
	let holdingAvgPrice = cryptoInvestData.staticData.averageBuyPrice.formatSignificantDigits(digits: 4)
	let marketName = cryptoInvestData.staticData.marketName
	
	guard let doubleHoldingQty = Double(holdingQty.replacingOccurrences(of: ",", with: "")),
		  let doubleHoldingAvgPrice = Double(holdingAvgPrice.replacingOccurrences(of: ",", with: "")) else { return }
	
	let calcAveragePriceView = TradeAverageCalcView.instanceFromNib(
	  holdingQuantity: doubleHoldingQty,
	  holdingAverage: doubleHoldingAvgPrice,
	  cryptoSymbol: marketName.marketSymbol
	)
	
	self.presentAverageCalcView(calcAveragePriceView, animated: true)
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
	
		reactor.state.map { $0.candleMinuteResponse }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] minuteCandleList in
		guard let self else { return }
		guard let minuteCandleList = minuteCandleList else { return }
		guard !minuteCandleList.isEmpty else { return }
		
		self.makeMiniChartView(minuteCandleList: minuteCandleList)
	  })
	  .disposed(by: self.disposeBag)

	reactor.state.map { $0.cryptoTransactionDatas }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] cryptos in
		guard let self = self else { return }
        let targetPairID = ExchangeMarketCodeConverter.pairID(
          fromDisplayMarket: reactor.selectCrypto.market,
          exchange: ExchangeSelectionStore.currentExchange
        )
		self.currentInvestData = cryptos.first(where: {
		  $0.staticData.exchangePairID == targetPairID
		})
	  })
	  .disposed(by: self.disposeBag)
	
//	reactor.state.map { $0.candleDayResponse }
//	  .observe(on: MainScheduler.instance)
//	  .subscribe(onNext: { [weak self] dayCandleList in
//		guard let self else { return }
//		guard let dayCandleList = dayCandleList else { return }
//		print("day candle response")
//	  })
//	  .disposed(by: self.disposeBag)
  }
}

// MARK: - WebSocket Pause & Resume
extension TradeViewController: SocketControllable {
  func pauseSocket() {
    self.reactor.action.onNext(.pauseSocket)
  }
  
  func resumeSocket() {
    self.reactor.action.onNext(.resumeSocket)
  }
}

extension TradeViewController {
  /// 우상단 미니 차트뷰 생성
  func makeMiniChartView(minuteCandleList: [MinuteResponseModel]) {
	let candleEntries = self.makeCandleEntries(from: minuteCandleList)
	self.miniChartCandleEntries = candleEntries
	let miniChartView = MiniChartView(candleEntries: candleEntries)
	
	if let existingHosting = self.miniChartHostingController {
	  existingHosting.rootView = miniChartView
	  return
	}
	
	// UIHostingController를 사용하면, SwiftUI가 자신의 사이즈를 스스로 계산하려고 함.
	let hosting = UIHostingController(rootView: miniChartView)
	self.miniChartHostingController = hosting
	self.miniChartContainerView.backgroundColor = .clear
	self.miniChartHostingController?.view.backgroundColor = .clear
	
	self.addChild(hosting)
	hosting.view.translatesAutoresizingMaskIntoConstraints = false
	self.miniChartContainerView.addSubview(hosting.view)
	
	hosting.view.snp.makeConstraints { make in
	  make.top.bottom.equalToSuperview().inset(5)
	  make.horizontalEdges.equalToSuperview()
	}
	hosting.didMove(toParent: self)
  }

  private func refreshMiniChartColors() {
	guard !miniChartCandleEntries.isEmpty else { return }
	miniChartHostingController?.rootView = MiniChartView(candleEntries: miniChartCandleEntries)
  }
  
  /// 캔들을 차트에 보여주기 위한 entry 모델로 변환
  func makeCandleEntries(from response: [MinuteResponseModel]) -> [CandleEntry] {
	response.map { item in
	  CandleEntry(
		date: Date(timeIntervalSince1970: TimeInterval(item.timestamp) / 1000),
		close: item.trade_price
	  )
	}
  }
}
