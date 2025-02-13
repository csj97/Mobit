//
//  TradeHistoryView.swift
//  Mobit
//
//  Created by 조성재 on 2/9/25.
//

import UIKit
import RxSwift

class TradeHistoryView: UIView, ViewRule {
  
  @IBOutlet weak var historyTableView: UITableView!
  @IBOutlet weak var noHistoryView: UIView!
  
  var disposeBag = DisposeBag()
  var reactor: CryptoDetailReactor? = nil
  var tempTradeHistory: [TradeHistoryInformation?] = [
	TradeHistoryInformation(
	  tradeDate: "02.11 20:43",
	  marketName: "XRP/KRW",
	  tradeCryptoPrice: 3715,
	  tradeAmount: 11.70717423,
	  tradeTotalPrice: 39980
	),
	TradeHistoryInformation(
	  tradeDate: "02.11 20:43",
	  marketName: "XRP/KRW",
	  tradeCryptoPrice: 3715,
	  tradeAmount: 11.70717423,
	  tradeTotalPrice: 39980
	),
	TradeHistoryInformation(
	  tradeDate: "02.11 20:43",
	  marketName: "XRP/KRW",
	  tradeCryptoPrice: 3715,
	  tradeAmount: 11.70717423,
	  tradeTotalPrice: 39980
	)
  ]
  
  deinit {
	print("deinit : \(String(describing: type(of: self)))")
  }
  
  static func instanceFromNib(
	reactor: CryptoDetailReactor,
	result: @escaping () -> ()
  ) -> TradeHistoryView {
	
	let selfView = UINib(
	  nibName: String(describing: self),
	  bundle: nil
	).instantiate(
	  withOwner: self, options: nil
	).first as? TradeHistoryView
	
	guard let selfView = selfView else {
	  return TradeHistoryView()
	}
	
	selfView.reactor = reactor
	selfView.setUI()
	selfView.setData()
	
	return selfView
  }
  
  func setUI() {
    self.noHistoryView.isHidden = true
  }
  
  func setData() {
    self.historyTableView.delegate = self
	self.historyTableView.dataSource = self
	self.historyTableView.register(
	  UINib(nibName: "TradeHistoryTableViewCell", bundle: nil),
	  forCellReuseIdentifier: "TradeHistoryTableViewCell"
	)
	self.historyTableView.rowHeight = UITableView.automaticDimension
  }
  
  // TODO: UserDefault에 Key 값을 "MobitTrade(MarketName)"으로 설정하고
  // 내부에 [TradeHistoryInformation]을 저장
  // 꺼내쓸 땐, MarketName으로 Key를 조회하고 없으면 noHistoryView 노출
}

// MARK: - UITableView Delegate, DataSource
extension TradeHistoryView: UITableViewDelegate, UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
	return self.tempTradeHistory.count
  }
  
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
	guard let cell = tableView.dequeueReusableCell(
		withIdentifier: "TradeHistoryTableViewCell",
		for: indexPath
	) as? TradeHistoryTableViewCell,
		  let tradeInfo = tempTradeHistory[indexPath.row] else {
		return UITableViewCell()
	}
	
	cell.configure(tradeInfo: tradeInfo)
	
	return cell
  }
  
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    
  }
}
