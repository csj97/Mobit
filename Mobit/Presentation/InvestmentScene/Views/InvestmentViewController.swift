//
//  InvestmentViewController.swift
//  Mobit
//
//  Created by 조성재 on 4/8/25.
//

import FlexLayout
import RxCocoa
import RxSwift
import PinLayout
import ReactorKit
import UIKit

class InvestmentViewController: UIViewController, ViewRule {
  @IBOutlet weak var transactionTableview: UITableView!
    
  weak var coordinator: InvestmentCoordinator?
  var disposeBag = DisposeBag()
  var reactor: InvestReactor
  var cryptos: [CryptoTransactionDataModel] = []
  var pendingUpdate: [CryptoTransactionDataModel]?
  private var isScrolling = false
  
  init(reactor: InvestReactor) {
	self.reactor = reactor
	super.init(nibName: nil, bundle: nil)
  }
  
  required init?(coder: NSCoder) {
	fatalError("init(coder:) has not been implemented")
  }
  
  override func viewDidLoad() {
	super.viewDidLoad()
	setUI()
	setData()
  }
  
  override func viewDidLayoutSubviews() {
	super.viewDidLayoutSubviews()
  }
  
  func setUI() {
	self.transactionTableview.delegate = self
	self.transactionTableview.dataSource = self
	
	self.transactionTableview.register(
	  UINib(nibName: "InvestmentTableViewCell", bundle: nil),
	  forCellReuseIdentifier: "InvestmentTableViewCell"
	)
  }
  
  func setData() {
	self.bind(reactor: self.reactor)
	self.reactor.action.onNext(.loadTransactions)
  }
}

// MARK: Reactor - View
extension InvestmentViewController: View {
  func bind(reactor: InvestReactor) {
	reactor.state.map { $0.crypto }
	  .compactMap { $0 }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] cryptos in
		guard let self else { return }

		if self.isScrolling {
			self.pendingUpdate = cryptos
		} else {
			self.cryptos = cryptos
			self.transactionTableview.reloadData()
		}
	  })
	  .disposed(by: self.disposeBag)
  }
}

extension InvestmentViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
	return self.cryptos.count
  }
  
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
	guard let cell = tableView.dequeueReusableCell(
	  withIdentifier: "InvestmentTableViewCell",
		for: indexPath
	) as? InvestmentTableViewCell else {
		return UITableViewCell()
	}
	
	let crypto = self.cryptos[indexPath.row]
	cell.configure(crypto: crypto)
	cell.selectionStyle = .none
	
	return cell
  }
  
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
	let userValidTransactionList = UserDataManager.userValidTransactionList
	let selectedCrypto = self.cryptos[indexPath.row].staticData.marketName
	let selectedValidTransaction = userValidTransactionList?.first { $0.marketName == selectedCrypto }
	print("===========================")
	print(selectedValidTransaction?.transaction)
	print("===========================")
  }
}

extension InvestmentViewController {
  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
	  isScrolling = true
  }

  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
	  isScrolling = false
	  if let update = pendingUpdate {
		  self.cryptos = update
		  self.transactionTableview.reloadData()
		  pendingUpdate = nil
	  }
  }
}
