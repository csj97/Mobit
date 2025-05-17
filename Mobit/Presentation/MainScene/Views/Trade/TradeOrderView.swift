//
//  TradeOrderView.swift
//  Mobit
//
//  Created by 조성재 on 2/5/25.
//

import UIKit
import ReactorKit
import RxSwift

class TradeOrderView: UIView, ViewRule {
  
  @IBOutlet weak var orderbookTableView: UITableView!
  @IBOutlet weak var segmentedControl: MobitSegmentedControl!
  @IBOutlet weak var segmentedContainerView: UIView!
  
  var disposeBag = DisposeBag()
  var dataSource: UITableViewDiffableDataSource<TableViewSection, OrderUnit>?
  var prevClosingPrice: Double? = nil
  var isFirstInput: Bool = false
  var reactor: CryptoDetailReactor? = nil
  private let cellIndentifier = "OrderBookCell"
  var callback: ((OrderResult) -> ())? = nil
  
  var bidView: TradeBidView? = nil
  var askView: TradeAskView? = nil
  var historyView: TradeHistoryView? = nil
  
  private var askMaxSize: Double? = 0
  private var bidMaxSize: Double? = 0
  
  deinit {
	print("deinit : \(String(describing: type(of: self)))")
  }
  
  static func instanceFromNib(
	reactor: CryptoDetailReactor,
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
	selfView.setUI()
	selfView.setData()
	
	return selfView
  }
  
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
	self.endEditing(true)
  }
  
  func setUI() {
	self.segmentedControl.setSegmentedControl(
	  normalColor: .mobitColors(.lightGrayBG),
	  selectedColor: .white
	)
	
	guard let reactor = self.reactor else { return }
	historyView = TradeHistoryView.instanceFromNib(reactor: reactor) { [weak self] in }
	bidView = TradeBidView.instanceFromNib(
	  reactor: reactor,
	  disposeBag: self.disposeBag
	) { [weak self] bidResult in
	  guard let self = self else { return }
	  switch bidResult {
	  case .updateHistory:
		historyView?.updateHistory()
	  case .alert(let title, let message):
		self.callback?(.alert(title: title, message: message))
	  }
	  
	}
	askView = TradeAskView.instanceFromNib(
	  reactor: reactor,
	  disposeBag: self.disposeBag
	) { [weak self] askResult in
	  guard let self = self else { return }
	  switch askResult {
	  case .updateHistory:
		historyView?.updateHistory()
	  case .alert(let title, let message):
		self.callback?(.alert(title: title, message: message))
	  }
	}
	
	guard let bidView = bidView, let askView = askView, let historyView = historyView else { return }
	
	self.segmentedContainerView.addSubview(bidView)
	self.segmentedContainerView.addSubview(askView)
	self.segmentedContainerView.addSubview(historyView)
	
	bidView.snp.makeConstraints { make in
      make.top.leading.equalToSuperview().offset(10)
	  make.trailing.equalToSuperview().offset(-10)
	  make.bottom.greaterThanOrEqualToSuperview()
	}
	askView.snp.makeConstraints { make in
	  make.top.leading.equalToSuperview().offset(10)
	  make.trailing.equalToSuperview().offset(-10)
	  make.bottom.greaterThanOrEqualToSuperview()
	}
	historyView.snp.makeConstraints { make in
	  make.top.leading.equalToSuperview().offset(10)
	  make.trailing.equalToSuperview().offset(-10)
	  make.bottom.equalToSuperview()
	}
	
	self.segmentedControl.selectedSegmentIndex = 0
	self.tapOnSegmentedControl(self.segmentedControl)
  }
  
  func setData() {
	guard let reactor = self.reactor else { return }
	self.bind(reactor: reactor)
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
  
  @IBAction func tapOnSegmentedControl(_ sender: MobitSegmentedControl) {
    switch sender.selectedSegmentIndex {
    case 0:
      self.bidView?.isHidden = false
      self.askView?.isHidden = true
	  self.historyView?.isHidden = true
	  self.segmentedContainerView.bringSubviewToFront(self.bidView!)
    case 1:
      self.bidView?.isHidden = true
      self.askView?.isHidden = false
	  self.historyView?.isHidden = true
	  self.segmentedContainerView.bringSubviewToFront(self.askView!)
    case 2:
      self.bidView?.isHidden = true
      self.askView?.isHidden = true
	  self.historyView?.isHidden = false
	  self.segmentedContainerView.bringSubviewToFront(self.historyView!)
      
    default:
      break
    }
  }
  
  func setCrypto(crypto: CryptoCellInfo? = nil) {
	
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
  
  /// 현재 물량이 최대 개수 대비 얼마나 되는지 시각화 해주기 위함
  private func updateObBarView() {
	
  }
}

// MARK: Reactor - View
extension TradeOrderView {
  
  func bind(reactor: CryptoDetailReactor) {
	reactor.state.map { $0.obTicker }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.asyncInstance)
	  .subscribe(
		onNext: { [weak self] obTicker in
		  guard let self = self,
				let obTicker = obTicker else { return }
		  let askData = obTicker.orderbookUnits.sorted(
			by: { $0.askPrice > $1.askPrice }
		  ).map { OrderUnit(type: .ask, price: $0.askPrice, size: $0.askSize) }
		  let bidData = obTicker.orderbookUnits.sorted(
			by: { $0.bidPrice > $1.bidPrice }
		  ).map { OrderUnit(type: .bid, price: $0.bidPrice, size: $0.bidSize) }
		  let orderDatas = askData + bidData
		  
		  self.askMaxSize = askData.max(by: { $0.size < $1.size })?.size
		  self.bidMaxSize = bidData.max(by: { $0.size < $1.size })?.size
		  
		  self.applySnapshot(orderDatas: orderDatas)
		}
	  )
	  .disposed(by: self.disposeBag)
  }
}
	
extension TradeOrderView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
	print("clicked")
  }
}
