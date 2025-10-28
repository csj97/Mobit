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

enum InvestSortType: String {
  case name = "이름순"		// 이름순
  case pnlHighToLow = "수익률 높은순"	// 수익률 높은순
  case pnlLowToHigh = "수익률 낮은순"	// 수익률 낮은순
  case evalProfitLossHighToLow = "평가손익 높은순"	// 평가손익 높은순
  case evalProfitLossLowToHigh = "평가손익 낮은순"	// 평가손익 낮은순
  case evalPriceHighToLow = "평가금액 높은순"	// 평가금액 높은순
  case evalPriceLowToHigh = "평가금액 낮은순"	// 평가금액 낮은순
}

class InvestmentViewController: MobitBaseViewController {
  @IBOutlet weak var transactionTableview: UITableView!
  @IBOutlet weak var totalUserBalance: UILabel!
  @IBOutlet weak var totalEvalProfitLoss: UILabel!
  @IBOutlet weak var totalProfitRate: UILabel!
  @IBOutlet weak var totalBuyPrice: UILabel!
  @IBOutlet weak var availableUserBalance: UILabel!
  @IBOutlet weak var noResultView: UIView!
  @IBOutlet weak var sortLabel: UILabel!
    @IBOutlet weak var dimView: UIView!
    
  weak var coordinator: InvestmentCoordinator?
  var dataSource: UITableViewDiffableDataSource<TableViewSection, CryptoTransactionDataModel>?
  var disposeBag = DisposeBag()
  var reactor: InvestReactor
  var cryptos: [CryptoTransactionDataModel] = []
  var userAvailableBalance: Double = 0
  var pendingUpdate: [CryptoTransactionDataModel]?
  private var selectedSortType: InvestSortType = .name {
	didSet {
	  self.cryptos = self.sortCryptos(sortType: self.selectedSortType, cryptos: cryptos)
	  self.transactionTableview.reloadData()
	  self.sortLabel.text = self.selectedSortType.rawValue
	}
  }
  private var sortedInvestCryptos: [CryptoTransactionDataModel] = []
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
	setTableView()
  }
  
  override func viewDidLayoutSubviews() {
	super.viewDidLayoutSubviews()
  }
  
  func setUI() {
//	self.transactionTableview.delegate = self
//	self.transactionTableview.dataSource = self
	self.transactionTableview.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 70, right: 0)
  }
  
  func setData() {
	self.bind(reactor: self.reactor)
	self.reactor.action.onNext(.loadTransactions)
  }
  
  func setTableView() {
	let nib = UINib(nibName: "InvestmentTableViewCell", bundle: nil)
	self.transactionTableview.register(nib, forCellReuseIdentifier: "InvestmentTableViewCell")
	self.transactionTableview.register(
	  UINib(nibName: "InvestmentTableViewCell", bundle: nil),
	  forCellReuseIdentifier: "InvestmentTableViewCell"
	)
	
	self.transactionTableview.bounces = false
	
	self.dataSource = UITableViewDiffableDataSource<TableViewSection, CryptoTransactionDataModel>(
	  tableView: self.transactionTableview,
	  cellProvider: { tableView, indexPath, cryptoTransacDataModel in
		
		guard let cell = self.transactionTableview.dequeueReusableCell(
		  withIdentifier: "InvestmentTableViewCell",
		  for: indexPath
		) as? InvestmentTableViewCell else { return UITableViewCell() }
		
		let isLast = (indexPath.row == self.cryptos.count - 1)
		let crypto = self.cryptos[indexPath.row]
		cell.configure(crypto: crypto, isLast: isLast)
		cell.selectionStyle = .none
		
		return cell
	})
	
	self.dataSource?.defaultRowAnimation = .fade
	self.transactionTableview.dataSource = self.dataSource
	self.transactionTableview.delegate = self
  }
  
  func applySnapshot(cryptoTransacDataModel: [CryptoTransactionDataModel]?) {
	DispatchQueue.main.async {
	  // tableview에 들어가는 section, item 초기화
	  var snapshot = NSDiffableDataSourceSnapshot<TableViewSection, CryptoTransactionDataModel>()
	  snapshot.appendSections([.invest])
	  if let cryptoTransacDataModel = cryptoTransacDataModel, !cryptoTransacDataModel.isEmpty {
		snapshot.appendItems(cryptoTransacDataModel, toSection: .invest)
	  } else {
		snapshot.appendItems([])
	  }
	  
	  self.dataSource?.apply(snapshot, animatingDifferences: false)
	}
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
	  self.totalProfitRate.textColor = .systemBlue
	} else if totalProfitRate == 0 {
	  self.totalProfitRate.textColor = .black
	} else {
	  self.totalProfitRate.textColor = .systemRed
	}
	self.totalEvalProfitLoss.text = totalEvalProfitLossString + " 원"
	self.totalBuyPrice.text = totalBuyPriceString + " 원"
  }
  
  func sortCryptos(sortType: InvestSortType, cryptos: [CryptoTransactionDataModel]) -> [CryptoTransactionDataModel] {
	var sortedCryptos: [CryptoTransactionDataModel] = []
	
	switch sortType {
	case .name:
	  sortedCryptos = cryptos
		.sorted { $0.staticData.marketName.lowercased() < $1.staticData.marketName.lowercased() }
	case .pnlHighToLow:
	  sortedCryptos = cryptos
		.sorted { $0.dynamicData.profitRate > $1.dynamicData.profitRate }
	case .pnlLowToHigh:
	  sortedCryptos = cryptos
		.sorted { $0.dynamicData.profitRate < $1.dynamicData.profitRate }
	case .evalProfitLossHighToLow:
	  sortedCryptos = cryptos
		.sorted { $0.dynamicData.evaluationProfitLoss > $1.dynamicData.evaluationProfitLoss }
	case .evalProfitLossLowToHigh:
	  sortedCryptos = cryptos
		.sorted { $0.dynamicData.evaluationProfitLoss < $1.dynamicData.evaluationProfitLoss }
	case .evalPriceHighToLow:
	  sortedCryptos = cryptos
		.sorted { $0.dynamicData.evaluationPrice > $1.dynamicData.evaluationPrice }
	case .evalPriceLowToHigh:
	  sortedCryptos = cryptos
		.sorted { $0.dynamicData.evaluationPrice < $1.dynamicData.evaluationPrice }
	}
	
	return sortedCryptos
  }
  
  // MARK: - Button Actions
    
  /// 충전하기 버튼 클릭
  @IBAction func tapOnChargeButton(_ sender: NeumorphicButton) {
	MobitAnalyticsUtil.sendClickEvent(event: .investment_charge)
	
	self.show(
	  alertType: .canCancel,
	  title: "안내",
	  content: "본 광고를 시청하시면 모의투자 금액\n10,000,000원이 보유 금액으로 추가됩니다."
	) { isOk in
	  if isOk {
		MobitAnalyticsUtil.sendClickEvent(event: .ad_click_confirm)
		RewardedAdManager.shared.showAd(from: self) {
		  self.show(alertType: .onlyConfirm, content: "충전이 완료 되었습니다.", callBack: nil)
		  UserDataManager.userInformation?.userAvailableBalance += 10_000_000
		}
	  } else {
		MobitAnalyticsUtil.sendClickEvent(event: .ad_click_cancel)
	  }
	}
  }
  
  /// P&L 버튼 클릭
  @IBAction func tapOnPnlButton(_ sender: UIButton) {
	MobitAnalyticsUtil.sendClickEvent(event: .investment_pnl)
	self.coordinator?.pushPnlVC()
  }
    
  /// 정렬 버튼
  @IBAction func tapOnSortButton(_ sender: UIButton) {
	let sortTypes: [InvestSortType] = [
	  .name, .pnlHighToLow, .pnlLowToHigh, .evalProfitLossHighToLow, .evalProfitLossLowToHigh, .evalPriceHighToLow, .evalPriceLowToHigh
	]
	let sortTitles: [String] = sortTypes.map { $0.rawValue }
	
	self.showBottomSheet(
	  title: "정렬 방법",
	  contentList: sortTitles,
	  sortType: self.selectedSortType
	) { index in
	  self.selectedSortType = sortTypes[index]
	}
  }
}

// MARK: Reactor - View
extension InvestmentViewController: View {
  func bind(reactor: InvestReactor) {
	reactor.state.map { $0.cryptos }
	  .compactMap { $0 }
	  .throttle(.milliseconds(100), scheduler: MainScheduler.instance)
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] cryptos in
		guard let self else { return }
		guard !self.isScrolling else { return }
		
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
		  // self.cryptos = cryptos.reversed()
		  self.cryptos = self.sortCryptos(sortType: self.selectedSortType, cryptos: cryptos)
		  self.updateTotalDatas(cryptos: cryptos)
		  self.applySnapshot(cryptoTransacDataModel: cryptos.reversed())
		}
	  })
	  .disposed(by: self.disposeBag)
	
	reactor.state.map { $0.userAvailableBalance }
	  .throttle(.milliseconds(100), scheduler: MainScheduler.instance)
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] userAvailableBalance in
		guard let self else { return }
		guard !self.isScrolling else { return }
		self.userAvailableBalance = userAvailableBalance
		self.updateTotalDatas(cryptos: self.cryptos)
	  })
	  .disposed(by: self.disposeBag)
  }
}

extension InvestmentViewController: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
	let userValidTransactionList = UserDataManager.userValidTransactionList
	let selectedCryptoMarketName = self.cryptos[indexPath.row].staticData.marketName
	
	guard let selectedCryptoName = self.cryptos[indexPath.row].staticData.cryptoName else { return }
	
	// 터치하면 디테일 화면으로 이동
	let symbol = selectedCryptoMarketName.replacingOccurrences(of: "/KRW", with: "")
	let selectedCrypto = CryptoCellInfo(
	  cryptoName: selectedCryptoName,
	  market: selectedCryptoMarketName
	)

	self.coordinator?.pushCryptoDetailVC(
	  selectCrypto: selectedCrypto,
	  cmcSymbol: symbol
	)
  }
}

extension InvestmentViewController {
  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
	  isScrolling = true
  }

  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
	if let update = pendingUpdate {
	  self.cryptos = update
	  pendingUpdate = nil
	}
	isScrolling = false
  }
}
