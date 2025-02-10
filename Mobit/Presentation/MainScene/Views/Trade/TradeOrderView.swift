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
  
  var bidView: TradeBidView? = nil
  var askView: TradeAskView? = nil
  
  deinit {
	print("deinit : \(String(describing: type(of: self)))")
  }
  
  static func instanceFromNib(
	reactor: CryptoDetailReactor,
	result: @escaping () -> ()
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
	selfView.setUI()
	selfView.setData()
	
	return selfView
  }
  
  func setUI() {
	self.segmentedControl.setSegmentedControl(
	  normalColor: .mobitColors(.lightGrayBG),
	  selectedColor: .white
	)
	
	guard let reactor = self.reactor else { return }
	bidView = TradeBidView.instanceFromNib(reactor: reactor, disposeBag: self.disposeBag) { [weak self] in }
	askView = TradeAskView.instanceFromNib(reactor: reactor,  disposeBag: self.disposeBag) { [weak self] in }
	
	guard let bidView = bidView, let askView = askView else { return }
	
	self.segmentedContainerView.addSubview(bidView)
	self.segmentedContainerView.addSubview(askView)
	
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
	
	self.segmentedControl.selectedSegmentIndex = 0
	self.tapOnSegmentedControl(self.segmentedControl)
  }
  
  func setData() {
	guard let reactor = self.reactor else { return }
	self.bind(reactor: reactor)
	
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
	  ) as? OrderBookCell else { return UITableViewCell() }
	  
	  cell.configure(
		changeRate: self.calculateFluctuation(
		  obPrice: obUnit.price
		),
		obType: obUnit.type,
		obPrice: obUnit.price,
		obSize: obUnit.size
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
    case 1:
      self.bidView?.isHidden = true
      self.askView?.isHidden = false
    case 2:
      self.bidView?.isHidden = true
      self.askView?.isHidden = true
      
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
	if let orderDatas = orderDatas {
	  snapshot.appendItems(orderDatas, toSection: .main)
	} else {
	  snapshot.appendItems([])
	}
	
	self.dataSource?.apply(snapshot, animatingDifferences: false, completion: {
	  if self.isFirstInput == false {
		DispatchQueue.main.async {
		  self.isFirstInput = true
		  let indexPath = IndexPath(row: 16, section: 0)
		  self.orderbookTableView.scrollToRow(
			at: indexPath,
			at: .middle,
			animated: false
		  )
		}
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
	  let fluctuation = ceil((obPrice / prevClosingPrice) * 100) / 100
	  return fluctuation
	}
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
			by: { $0.bidPrice < $1.bidPrice }
		  ).map { OrderUnit(type: .bid, price: $0.bidPrice, size: $0.bidSize) }
		  let orderDatas = askData + bidData
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
