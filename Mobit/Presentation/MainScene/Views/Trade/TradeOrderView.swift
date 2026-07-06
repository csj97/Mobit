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
    
  var disposeBag = DisposeBag()
  var dataSource: UITableViewDiffableDataSource<TableViewSection, OrderUnit>?
  var prevClosingPrice: Double? = nil
  var isFirstInput: Bool = false
  var reactor: TradeReactor? = nil
  var callback: ((OrderResult) -> ())? = nil
  var cryptoInvestData: CryptoTransactionDataModel? = nil
  var bidView: TradeBidView? = nil
  var askView: TradeAskView? = nil
  var historyView: TradeHistoryView? = nil
  
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
	callback: @escaping (OrderResult) -> ()
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
	selfView.callback = callback
	selfView.setData()
	selfView.setUI()
	
	return selfView
  }
  
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
	self.endEditing(true)
  }
  
  func setUI() {
	
	guard let reactor = self.reactor else { return }
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
		MobitAnalyticsUtil.sendClickEvent(event: .trade_order_buy_fail)
		self.callback?(.alert(title: title, message: message))
	  case .successLottie:
		MobitAnalyticsUtil.sendClickEvent(event: .trade_order_buy_complete)
		self.callback?(.successLottie)
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
		MobitAnalyticsUtil.sendClickEvent(event: .trade_order_sell_fail)
		self.callback?(.alert(title: title, message: message))
	  case .successLottie:
		MobitAnalyticsUtil.sendClickEvent(event: .trade_order_sell_complete)
		self.callback?(.successLottie)
	  default:
		break
	  }
	}
	
	guard let bidView = bidView, let askView = askView, let historyView = historyView else { return }
	
	self.segmentedContainerStackView.addArrangedSubview(bidView)
	self.segmentedContainerStackView.addArrangedSubview(askView)
	self.segmentedContainerStackView.addArrangedSubview(historyView)
	
	bidView.isHidden = true
	askView.isHidden = true
	historyView.isHidden = true
	
	self.segmentedControl.segments = ["매수", "매도", "거래내역"]
	self.segmentedControl.onSegmentChanged = { index in
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
	  
	  self.layoutIfNeeded()
	  self.segmentedContainerStackView.layoutIfNeeded()
	}
	self.orderbookTableView.backgroundColor = .clear
	self.segmentedControl.selectedIndex = 0
	self.segmentedControl.onSegmentChanged?(0)
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
	) { (
	  tableView: UITableView,
	  indexPath: IndexPath,
	  obUnit: OrderUnit
	) -> UITableViewCell? in
	  
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
	
	self.cryptoAveragePrice.text = "\(data.staticData.averageBuyPrice.formatSignificantDigits(digits: 4))"
	self.cryptoHoldingQuantity.text = "\(data.staticData.holdingQuantity.formatSignificantDigits(digits: 2))"
	self.cryptoEvalPrice.text = "\(data.dynamicData.evaluationPrice.formatSignificantDigits())" + " KRW"
	self.cryptoEvalLoss.text = "\(data.dynamicData.evaluationProfitLoss.formatSignificantDigits(digits: 0))" + " KRW"
	self.cryptoProfitRate.text = "\(data.dynamicData.profitRate.formatSignificantDigits(digits: 2))" + " %"
	
	// 상승/하락 색상 테마(MarketColorPalette) 반영
	let textColor = MarketColorPalette.color(forSignedValue: data.dynamicData.evaluationProfitLoss)
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
	self.callback?(.calcuator(cryptoInvestData: cryptoInvestData))
  }
  
}

// MARK: Reactor - View
extension TradeOrderView {
  
  func bind(reactor: TradeReactor) {
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
		guard let self else { return }
		
		// 거래 내역에선 업데이트 안하기 때문
		if self.segmentedControl.selectedIndex == 2 {
		  self.investLiveView.isHidden = true
		} else {
		  guard let cryptoInvestData = cryptos.first(where: {
			$0.staticData.marketName ==  reactor.selectCrypto.market
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
