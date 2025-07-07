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
  @IBOutlet weak var totalUserBalance: UILabel!
  @IBOutlet weak var totalEvalProfitLoss: UILabel!
  @IBOutlet weak var totalProfitRate: UILabel!
  @IBOutlet weak var totalBuyPrice: UILabel!
  @IBOutlet weak var availableUserBalance: UILabel!
  @IBOutlet weak var noResultView: UIView!
    
  weak var coordinator: InvestmentCoordinator?
  var disposeBag = DisposeBag()
  var reactor: InvestReactor
  var cryptos: [CryptoTransactionDataModel] = []
  var userAvailableBalance: Double = 0
  var pendingUpdate: [CryptoTransactionDataModel]?
  private var isScrolling = false
  
  init(reactor: InvestReactor) {
	self.reactor = reactor
	super.init(nibName: nil, bundle: nil)
  }
  
  required init?(coder: NSCoder) {
	fatalError("init(coder:) has not been implemented")
  }
  
  override func viewWillAppear(_ animated: Bool) {
	super.viewWillAppear(animated)
	
	self.navigationController?.navigationBar.isHidden = true
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
  
  func updateTotalDatas(cryptos: [CryptoTransactionDataModel]) {
	guard let availableUserBalance = UserDataManager.userInformation?.userAvailableBalance else { return }
	// 총 보유자산
	let totalUserBalance = availableUserBalance + cryptos.reduce(0) {
	  $0 + $1.self.dynamicData.evaluationPrice
	}
	// 평가손익
	let totalProfitLoss = cryptos.reduce(0) {
	  $0 + $1.dynamicData.evaluationProfitLoss
	}
	// 수익률
	var totalProfitRate: Double

	if totalUserBalance != 0 {
		totalProfitRate = (totalProfitLoss / totalUserBalance) * 100
	} else {
		totalProfitRate = 0 // 혹은 nil 처리 또는 다른 기본값
	}
	
	// 총 매수
	let totalBuyPrice = cryptos.reduce(0) {
	  $0 + $1.self.staticData.buyAmount
	}
	
	let availableUserBalanceString: String = availableUserBalance == 0 ? "0" : availableUserBalance.formatSignificantDigits()
	let totalUserBalanceString: String = totalUserBalance == 0 ? "0" : totalUserBalance.formatSignificantDigits(digits: 0)
	let totalProfitRateString: String = totalProfitRate == 0 ? "0" : totalProfitRate.formatSignificantDigits(digits: 4)
	let totalEvalProfitLossString: String = totalProfitRate == 0 ? "0" : totalProfitLoss.formatSignificantDigits(digits: 0)
	let totalBuyPriceString: String = totalBuyPrice == 0 ? "0" : totalBuyPrice.formatSignificantDigits(digits: 0)
	
	self.availableUserBalance.text = availableUserBalanceString + " 원"
	self.totalUserBalance.text = totalUserBalanceString + " 원"
	self.totalProfitRate.text = totalProfitRateString + " %"
	if totalProfitRate < 0 {
	  self.totalProfitRate.textColor = .blue
	} else if totalProfitRate == 0 {
	  self.totalProfitRate.textColor = .black
	} else {
	  self.totalProfitRate.textColor = .red
	}
	self.totalEvalProfitLoss.text = totalEvalProfitLossString + " 원"
	self.totalBuyPrice.text = totalBuyPriceString + " 원"
  }
}

// MARK: Reactor - View
extension InvestmentViewController: View {
  func bind(reactor: InvestReactor) {
	reactor.state.map { $0.cryptos }
	  .compactMap { $0 }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] cryptos in
		guard let self else { return }
		
		guard cryptos.count != 0 else {
		  self.noResultView.isHidden = false
		  self.updateTotalDatas(cryptos: [])
		  
		  return
		}
		
		self.noResultView.isHidden = true
		
		if self.isScrolling {
		  self.pendingUpdate = cryptos
		} else {
		  self.pendingUpdate = nil
		  self.cryptos = cryptos
		  self.updateTotalDatas(cryptos: cryptos)
		  self.transactionTableview.reloadData()
		}
	  })
	  .disposed(by: self.disposeBag)
	
	reactor.state.map { $0.userAvailableBalance }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] userAvailableBalance in
		guard let self else { return }
		self.userAvailableBalance = userAvailableBalance
		self.updateTotalDatas(cryptos: self.cryptos)
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
	let selectedCryptoMarketName = self.cryptos[indexPath.row].staticData.marketName
	let selectedValidTransaction = userValidTransactionList?.filter { $0.marketName == selectedCryptoMarketName }
	print("===========================")
	print(selectedValidTransaction)
	print("===========================")
	
	// 터치하면 디테일 화면으로 이동
//	let selectedCrypto = CryptoCellInfo(
//	  cryptoName: "",
//	  market: selectedCryptoMarketName
//	)
//	
//	self.coordinator?.pushCryptoDetailVC(selectCrypto: selectedCrypto)
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
