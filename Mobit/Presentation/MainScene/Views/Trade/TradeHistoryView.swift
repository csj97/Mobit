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
  var reactor: TradeReactor? = nil
  var transaction: [TransactionInfo]? = nil
  var callBack: (() -> ())? = nil
  
  deinit {
	print("deinit : \(String(describing: type(of: self)))")
  }
  
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
	self.endEditing(true)
  }
  
  static func instanceFromNib(
	reactor: TradeReactor,
	callBack: @escaping () -> ()
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
	selfView.callBack = callBack
	selfView.setUI()
	selfView.setData()
	
	return selfView
  }
  
  func setUI() {
    self.noHistoryView.isHidden = true
	self.historyTableView.separatorStyle = .none
  }
  
  func setData() {
    self.historyTableView.delegate = self
	self.historyTableView.dataSource = self
	self.historyTableView.register(
	  UINib(nibName: "TradeHistoryTableViewCell", bundle: nil),
	  forCellReuseIdentifier: "TradeHistoryTableViewCell"
	)
	self.historyTableView.rowHeight = UITableView.automaticDimension
	// 최초 로드는 window에 붙은 뒤로 미룬다 (didMoveToWindow). off-window reloadData 경고 방지
  }

  override func didMoveToWindow() {
	super.didMoveToWindow()
	guard window != nil else { return }
	self.updateHistory()
  }
  
  func updateHistory() {
	guard let transaction = UserDataManager.userTransactionList?.filter({
			$0.marketName == self.reactor?.selectCrypto.market
		  }) else { return }
	
	if transaction.count == 0 {
	  noHistoryView.isHidden = false
	  historyTableView.isHidden = true
	} else {
	  self.noHistoryView.isHidden = true
	  self.historyTableView.isHidden = false
	}
	
	self.transaction = transaction
	self.historyTableView.reloadData()
  }
}

// MARK: - UITableView Delegate, DataSource
extension TradeHistoryView: UITableViewDelegate, UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
	return self.transaction?.count ?? 0
  }
  
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
	guard let cell = tableView.dequeueReusableCell(
		withIdentifier: "TradeHistoryTableViewCell",
		for: indexPath
	) as? TradeHistoryTableViewCell,
		  let marketName = self.reactor?.selectCrypto.market,
		  let transactionInfo = self.transaction?.reversed()[indexPath.row] else {
		return UITableViewCell()
	}
	
	cell.selectionStyle = .none
	cell.configure(
	  marketName: marketName,
	  transactionInfo: transactionInfo
	)
	
	return cell
  }
  
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    
  }
}
