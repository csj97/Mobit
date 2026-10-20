//
//  TradeOrderView.swift
//  Mobit
//
//  Created by 조성재 on 2/5/25.
//

import UIKit
import ReactorKit
import RxSwift
import SkeletonView
import GoogleMobileAds

class TradeOrderView: UIView, ViewRule {
  
  @IBOutlet weak var orderbookTableView: UITableView!
  @IBOutlet weak var segmentedControl: NeumorphicSegmentedControl!
  @IBOutlet weak var segmentedContainerView: UIView!
  @IBOutlet weak var segmentedContainerStackView: UIStackView!
  @IBOutlet weak var cryptoAveragePrice: UILabel!
  @IBOutlet weak var cryptoHoldingQuantity: UILabel!
  @IBOutlet weak var cryptoEvalPrice: UILabel!
  @IBOutlet weak var cryptoEvalLoss: UILabel!
  @IBOutlet weak var cryptoProfitRate: UILabel!
  @IBOutlet weak var investLiveView: UIView!
  @IBOutlet weak var averagePriceCalculatorButton: UIButton!
    
  var disposeBag = DisposeBag()
  var dataSource: UITableViewDiffableDataSource<TableViewSection, OrderUnit>?
  var prevClosingPrice: Double? = nil
  var isFirstInput: Bool = false
  var reactor: TradeReactor? = nil
  // 주문 결과나 계산기 요청을 상위 화면에 전달한다.
  var callBack: ((OrderResult) -> ())? = nil
  var cryptoInvestData: CryptoTransactionDataModel? = nil
  var bidView: TradeBidView? = nil
  var askView: TradeAskView? = nil
  var historyView: TradeHistoryView? = nil
  private weak var futuresOrderController: FuturesOrderViewController?
  // XIB에서 현물 주문 폼과 보유자산을 함께 감싸는 스크롤 영역이다.
  @IBOutlet private weak var spotOrderScrollView: UIScrollView!
  // 자체 스크롤을 가진 선물 주문 화면을 현물 스크롤과 분리해 배치한다.
  @IBOutlet private weak var futuresOrderContainerView: UIView!
  
  private let cellIndentifier = "OrderBookCell"
  private var askMaxSize: Double? = 0
  private var bidMaxSize: Double? = 0
  private var isOrderbookScrolling = false
  private var pendingOrderBook: Orderbook?
  
  deinit {
	print("deinit : \(String(describing: type(of: self)))")
  }
  
  static func instanceFromNib(
	reactor: TradeReactor,
    futuresOrderController: FuturesOrderViewController? = nil,
	// 주문 결과나 계산기 요청을 상위 화면에 전달한다.
	callBack: @escaping (OrderResult) -> ()
  ) -> TradeOrderView {
	
	let selfView = UINib(
	  nibName: String(describing: self),
	  bundle: nil
	).instantiate(
	  withOwner: self, options: nil
	).first as? TradeOrderView
	
	guard let selfView = selfView else {
	  return TradeOrderView()
	}
	
	selfView.reactor = reactor
    selfView.futuresOrderController = futuresOrderController
    futuresOrderController?.captureOrderPrice = { [weak reactor] in
      reactor?.captureFuturesOrderPrice()
    }
    futuresOrderController?.orderPriceUpdates = reactor.state.map { [weak reactor] _ in
      reactor?.captureFuturesOrderPrice()?.quote
    }.distinctUntilChanged().map { _ in () }
	selfView.callBack = callBack
	selfView.setData()
	selfView.setUI()
	
	return selfView
  }
  
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
	self.endEditing(true)
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
	applyThemeColors()
	orderbookTableView.reloadData()
  }
  
  func setUI() {
	guard let reactor = self.reactor else { return }
	self.applyThemeColors()
    if let controller = futuresOrderController {
      spotOrderScrollView.isHidden = true
      futuresOrderContainerView.isHidden = false
      futuresOrderContainerView.addSubview(controller.view)
      controller.view.snp.makeConstraints { $0.edges.equalToSuperview() }
      investLiveView.isHidden = true
      segmentedControl.segments = ["futures_long", "futures_short", "futures_history"].map(FuturesText.text)
      segmentedControl.onSegmentChanged = { [weak controller] index in controller?.selectTab(index) }
      segmentedControl.selectedIndex = 0
      controller.selectTab(0)
    } else {
      buildOrderSubViews(reactor: reactor)
    }
  }

  private func applyThemeColors() {
	self.backgroundColor = .mobitColors(.tradeBackground)
	self.segmentedContainerView.backgroundColor = .clear
	self.segmentedContainerStackView.backgroundColor = .clear
	self.investLiveView.backgroundColor = .clear
	self.applyCalculatorButtonColor()
	[
	  self.cryptoAveragePrice,
	  self.cryptoHoldingQuantity,
	  self.cryptoEvalPrice
	].forEach { $0?.textColor = .mobitColors(.tradeTextPrimary) }
	self.orderbookTableView.backgroundColor = .clear
	if let cryptoInvestData {
	  setInvestLiveData(data: cryptoInvestData)
	}
  }

  // 계산기 아이콘 색상
  private func applyCalculatorButtonColor() {
	let image = UIImage(named: "calculator")?.withRenderingMode(.alwaysTemplate)
	self.averagePriceCalculatorButton.setImage(image, for: .normal)
	self.averagePriceCalculatorButton.tintColor = .mobitColors(.tradeTextSecondary)
  }

  func refreshMarketColors() {
	applyThemeColors()
	segmentedControl.refreshMarketColors()
	bidView?.refreshMarketColors()
	askView?.refreshMarketColors()
	orderbookTableView.reloadData()
	historyView?.updateHistory()
  }

  private func buildOrderSubViews(reactor: TradeReactor) {
    // 계측 때문에 하위 주문 콜백이 Reactor를 추가로 붙잡지 않도록 값만 캡처한다.
    let analyticsAccount = TradingAccountID.spot(for: reactor.exchange)
    // 현물 KRW·BTC 마켓의 원래 종목을 결과 이벤트까지 유지한다.
    let analyticsInstrument = reactor.analyticsInstrument()
	historyView = TradeHistoryView.instanceFromNib(reactor: reactor) { }
	bidView = TradeBidView.instanceFromNib(
	  reactor: reactor,
	  disposeBag: self.disposeBag
	) { [weak self] bidResult in
	  guard let self = self else { return }
	  switch bidResult {
	  case .updateHistory:
		askView?.updateCryptoData()
		historyView?.updateHistory()
	  case .alert(let title, let message):
		MobitAnalyticsUtil.sendClickEvent(
          event: .trade_order_buy_fail,
          account: analyticsAccount,
          instrument: analyticsInstrument
        )
		self.callBack?(.alert(title: title, message: message))
	  case .settlementRateUnavailable:
        MobitAnalyticsUtil.sendClickEvent(
          event: .trade_order_buy_fail,
          account: analyticsAccount,
          instrument: analyticsInstrument,
          extraParameters: ["failure_reason": "BTC_환산시세_미확보"]
        )
		// BTC 환산 시세 실패도 상위 화면의 확인·재조회 알럿으로 전달한다.
		self.callBack?(.settlementRateUnavailable)
	  case .tradeCompleted:
		MobitAnalyticsUtil.sendClickEvent(
          event: .trade_order_buy_complete,
          account: analyticsAccount,
          instrument: analyticsInstrument
        )
		self.callBack?(.tradeCompleted)
	  default:
		break
	  }
	}
	askView = TradeAskView.instanceFromNib(
	  reactor: reactor,
	  disposeBag: self.disposeBag
	) { [weak self] askResult in
	  guard let self = self else { return }
	  switch askResult {
	  case .updateHistory:
		bidView?.updateCryptoData()
		historyView?.updateHistory()
	  case .alert(let title, let message):
		MobitAnalyticsUtil.sendClickEvent(
          event: .trade_order_sell_fail,
          account: analyticsAccount,
          instrument: analyticsInstrument
        )
		self.callBack?(.alert(title: title, message: message))
	  case .settlementRateUnavailable:
        MobitAnalyticsUtil.sendClickEvent(
          event: .trade_order_sell_fail,
          account: analyticsAccount,
          instrument: analyticsInstrument,
          extraParameters: ["failure_reason": "BTC_환산시세_미확보"]
        )
		// BTC 환산 시세 실패도 상위 화면의 확인·재조회 알럿으로 전달한다.
		self.callBack?(.settlementRateUnavailable)
	  case .tradeCompleted:
		MobitAnalyticsUtil.sendClickEvent(
          event: .trade_order_sell_complete,
          account: analyticsAccount,
          instrument: analyticsInstrument
        )
		self.callBack?(.tradeCompleted)
	  default:
		break
	  }
	}
	
	guard let bidView = bidView, let askView = askView, let historyView = historyView else { return }
	
	self.segmentedContainerStackView.addArrangedSubview(bidView)
	self.segmentedContainerStackView.addArrangedSubview(askView)
	self.segmentedContainerStackView.addArrangedSubview(historyView)
	// 스크롤 하단의 750보다 낮춰 작은 표시 영역에서도 내역의 최소 높이를 우선한다.
	let historyHeightPriority = UILayoutPriority.defaultHigh.rawValue - 1
	historyView.snp.makeConstraints {
	  $0.height.equalTo(spotOrderScrollView.frameLayoutGuide.snp.height).priority(historyHeightPriority)
	}
	configureSpotOrderScrollView()
	
	bidView.isHidden = true
	askView.isHidden = true
	historyView.isHidden = true
	
	self.segmentedControl.segments = ["매수", "매도", "거래내역"]
	self.segmentedControl.onSegmentChanged = { [weak self] index in
      guard let self else { return }
      self.endEditing(true)
      self.spotOrderScrollView?.setContentOffset(.zero, animated: false)
	  switch index {
	  case 0:
		bidView.isHidden = false
		askView.isHidden = true
		historyView.isHidden = true
		self.investLiveView.isHidden = self.cryptoInvestData == nil
		
	  case 1:
		bidView.isHidden = true
		askView.isHidden = false
		historyView.isHidden = true
		self.investLiveView.isHidden = self.cryptoInvestData == nil
		
	  case 2:
		bidView.isHidden = true
		askView.isHidden = true
		historyView.isHidden = false
		self.investLiveView.isHidden = true
		historyView.updateHistory()
		
	  default:
		break
	  }
	  
      // 초기 선택과 사용자의 매수·매도·내역 전환을 현재 현물 마켓으로 구분한다.
      let events: [MobitAnalyticsScreenEventType] = [.trade_order_buy, .trade_order_sell, .trade_order_history]
      if events.indices.contains(index) {
        MobitAnalyticsUtil.sendScreenEvent(
          event: events[index],
          account: analyticsAccount,
          instrument: analyticsInstrument
        )
      }
	  self.layoutIfNeeded()
	  self.segmentedContainerStackView.layoutIfNeeded()
	}
	self.orderbookTableView.backgroundColor = .clear
	self.segmentedControl.selectedIndex = 0
	self.segmentedControl.onSegmentChanged?(0)
  }

  private func configureSpotOrderScrollView() {
    // 기본 레이아웃은 XIB에 두고 시스템 키보드 경계만 코드에서 연결한다.
    spotOrderScrollView.snp.makeConstraints {
      $0.bottom.lessThanOrEqualTo(keyboardLayoutGuide.snp.top)
    }
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(revealSpotOrderInput),
      name: UITextField.textDidBeginEditingNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(revealSpotOrderInput),
      name: UIResponder.keyboardDidChangeFrameNotification,
      object: nil
    )
  }

  @objc private func revealSpotOrderInput() {
    // 다른 화면의 입력 이벤트는 무시하고 현재 편집하는 입력란만 보이게 이동한다.
    guard let scroll = spotOrderScrollView,
          let field = [bidView?.inputTradeAmount, bidView?.totalPriceTextField,
                       askView?.inputTradeAmount, askView?.totalPriceTextField]
            .compactMap({ $0 }).first(where: { $0.isFirstResponder }),
          field.isDescendant(of: scroll) else { return }
    layoutIfNeeded()
    scroll.scrollRectToVisible(field.convert(field.bounds, to: scroll).insetBy(dx: 0, dy: -8), animated: false)
  }

  
  func setData() {
    guard let reactor = self.reactor else { return }
    self.bind(reactor: reactor)
    reactor.action.onNext(.loadTransactions)
    self.prevClosingPrice = self.reactor?.selectCrypto.prevPrice
    
	self.orderbookTableView.register(
	  OrderBookCell.self,
	  forCellReuseIdentifier: "OrderBookCell"
	)
	self.dataSource = UITableViewDiffableDataSource<TableViewSection, OrderUnit>(
	  tableView: orderbookTableView
	) { [weak self] (
	  tableView: UITableView,
	  indexPath: IndexPath,
	  obUnit: OrderUnit
	) -> UITableViewCell? in
	  guard let self else { return nil }
	  
	  guard let cell = self.orderbookTableView.dequeueReusableCell(
		withIdentifier: self.cellIndentifier,
		for: indexPath
	  ) as? OrderBookCell,
			let askMaxSize = self.askMaxSize,
			let bidMaxSize = self.bidMaxSize
	  else { return UITableViewCell() }
	  
	  cell.configure(
		changeRate: self.calculateFluctuation(
		  obPrice: obUnit.price
		),
		obType: obUnit.type,
		obPrice: obUnit.price,
		obSize: obUnit.size,
		askMaxSize: askMaxSize,
		bidMaxSize: bidMaxSize
	  )
	  
	  cell.selectionStyle = .none
	  return cell
	}
	
	self.dataSource?.defaultRowAnimation = .fade
	orderbookTableView.dataSource = self.dataSource
	orderbookTableView.delegate = self
  }
  
  func setInvestLiveData(data: CryptoTransactionDataModel) {
	self.cryptoInvestData = data
	
    let valuation = PortfolioCalculator.valuation(
      of: data, btcKRWPrice: AppDataManager.shared.lastBTCKRWPrice(for: data.staticData.exchange)
    )
    if data.settlementCurrency == .btc {
      self.cryptoAveragePrice.text = data.staticData.averageBuyPrice.formatTradingValue()
    } else {
      self.cryptoAveragePrice.text = valuation.averagePriceKRW.map {
        $0.formatTradingValue() + " \(FuturesText.text("currency_krw_unit"))"
      } ?? "-"
    }
    self.cryptoHoldingQuantity.text = data.staticData.holdingQuantity.formatTradingValue()
    self.cryptoEvalPrice.text = valuation.evaluationKRW.map { $0.formatTradingValue() + " \(FuturesText.text("currency_krw_unit"))" } ?? "-"
    self.cryptoEvalLoss.text = valuation.profitLossKRW.map { $0.formatTradingValue() + " \(FuturesText.text("currency_krw_unit"))" } ?? "-"
    self.cryptoProfitRate.text = valuation.profitRate.map { $0.formatSignificantDigits(digits: 2) + " %" } ?? "-"
    let textColor = MarketColorPalette.color(forSignedValue: valuation.profitLossKRW ?? 0)
    self.cryptoEvalLoss.textColor = textColor
    self.cryptoProfitRate.textColor = textColor
  }
  
  /// TableViewDiffableDataSource Snapshot Update
  func applySnapshot(orderDatas: [OrderUnit]?) {
	
	// tableview에 들어가는 section, item 초기화
	var snapshot = NSDiffableDataSourceSnapshot<TableViewSection, OrderUnit>()
	snapshot.appendSections([.main])
	snapshot.appendItems(orderDatas ?? [], toSection: .main)
	
	dataSource?.apply(snapshot, animatingDifferences: false, completion: { [weak self] in
	  guard let self = self else { return }
	  guard !self.isFirstInput, let orderDatas, !orderDatas.isEmpty else { return }
	  
	  self.isFirstInput = true
	  let targetIndexPath = IndexPath(row: orderDatas.count / 2, section: 0)
	  
	  DispatchQueue.main.async {
		
		self.orderbookTableView.scrollToRow(
		  at: targetIndexPath,
		  at: .middle,
		  animated: false
		)
	  }
	})
  }
  
  /// 변동성 % 계산
  private func calculateFluctuation(obPrice: Double?) -> Double? {
	guard let obPrice = obPrice,
		  let prevClosingPrice = self.prevClosingPrice else {
	  return nil
	}
	
	if prevClosingPrice == 0 {
	  return 1
	} else {
	  let fluctuation = ((obPrice - prevClosingPrice) / prevClosingPrice) * 100
	  return fluctuation.formatDigits(digits: 2)
	}
  }
  
  @IBAction func tapOnAveragePriceCalcButton(_ sender: UIButton) {
	
	guard let cryptoInvestData = self.cryptoInvestData else { return }
	self.callBack?(.calcuator(cryptoInvestData: cryptoInvestData))
  }
  
}

// MARK: Reactor - View
extension TradeOrderView {
  
  func bind(reactor: TradeReactor) {
    AppDataManager.shared.btcKRWPriceUpdates
      .observe(on: MainScheduler.instance)
      .subscribe(onNext: { [weak self] exchange in
        guard let self, let holding = self.cryptoInvestData,
              holding.staticData.exchange == exchange else { return }
        self.setInvestLiveData(data: holding)
      })
      .disposed(by: self.disposeBag)

	reactor.state.map { $0.obTicker }
	  .throttle(.milliseconds(150), scheduler: MainScheduler.instance)
	  .observe(on: MainScheduler.asyncInstance)
	  .subscribe(
		onNext: { [weak self] obTicker in
		  guard let self = self,
				let obTicker = obTicker else { return }
		  
		  if self.isOrderbookScrolling {
			self.pendingOrderBook = obTicker
			return
		  }
		  
		  self.renderOrderBook(obTicker)
		}
	  )
	  .disposed(by: self.disposeBag)
	
	reactor.state.map { $0.cryptoTransactionDatas }
	  .compactMap { $0 }
	  .distinctUntilChanged()
	  .throttle(.milliseconds(350), scheduler: MainScheduler.instance)
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] cryptos in
		guard let self, self.futuresOrderController == nil else { return }
        let targetPairID = ExchangeMarketCodeConverter.pairID(
          fromDisplayMarket: reactor.selectCrypto.market,
          exchange: reactor.exchange
        )
		
		// 거래 내역에선 업데이트 안하기 때문
		if self.segmentedControl.selectedIndex == 2 {
		  self.investLiveView.isHidden = true
		} else {
		  guard let cryptoInvestData = cryptos.first(where: {
			$0.staticData.exchangePairID == targetPairID
		  }) else {
			self.cryptoInvestData = nil
			self.investLiveView.isHidden = true
			return
		  }
		  
		  self.investLiveView.isHidden = false
		  self.setInvestLiveData(data: cryptoInvestData)
		}
	  })
	  .disposed(by: self.disposeBag)
  }

  /// orderbook data 렌더링 (
  private func renderOrderBook(_ obTicker: Orderbook) {
    let askData = obTicker.orderbookUnits
      .sorted(by: { $0.askPrice > $1.askPrice })
      .enumerated()
      .map { (index, unit) in
        OrderUnit(
          identifier: "ask-\(index)",
          type: .ask,
          price: unit.askPrice,
          size: unit.askSize
        )
      }

    let bidData = obTicker.orderbookUnits
      .sorted(by: { $0.bidPrice > $1.bidPrice })
      .enumerated()
      .map { (index, unit) in
        OrderUnit(
          identifier: "bid-\(index)",
          type: .bid,
          price: unit.bidPrice,
          size: unit.bidSize
        )
      }

    let orderDatas = askData + bidData
    self.askMaxSize = askData.max(by: { $0.size < $1.size })?.size
    self.bidMaxSize = bidData.max(by: { $0.size < $1.size })?.size
    self.applySnapshot(orderDatas: orderDatas)
  }

  /// pending orderbook data 처리
  private func flushPendingOrderBookIfNeeded() {
	guard !self.isOrderbookScrolling,
		  let pendingOrderBook = self.pendingOrderBook else { return }

	self.pendingOrderBook = nil
	self.renderOrderBook(pendingOrderBook)
  }
}
		
extension TradeOrderView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
	// print("clicked")
  }
  
  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
	self.isOrderbookScrolling = true
  }
  
  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
	guard !decelerate else { return }
	self.isOrderbookScrolling = false
	self.flushPendingOrderBookIfNeeded()
  }
  
  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
	self.isOrderbookScrolling = false
	self.flushPendingOrderBookIfNeeded()
  }
}
