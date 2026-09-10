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
  @IBOutlet weak var chargeButton: NeumorphicButton!
    
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
	  self.applySnapshot(cryptoTransacDataModel: self.cryptos)
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
	applyThemeColors()
	updateTotalDatas(cryptos: cryptos)
	transactionTableview.reloadData()
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

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
	applyThemeColors()
	transactionTableview.reloadData()
  }
  
  func setUI() {
//	self.transactionTableview.delegate = self
//	self.transactionTableview.dataSource = self
	applyThemeColors()
	self.transactionTableview.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 70, right: 0)
  }

  private func applyThemeColors() {
	self.view.backgroundColor = .mobitColors(.investmentBackground)
	self.transactionTableview.backgroundColor = .mobitColors(.investmentBackground)
	self.noResultView.backgroundColor = .mobitColors(.investmentBackground)
	self.transactionTableview.superview?.backgroundColor = .mobitColors(.investmentBackground)
	self.dimView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
	self.sortLabel.textColor = .mobitColors(.investmentTextPrimary)
	[
	  self.totalUserBalance,
	  self.totalBuyPrice,
	  self.availableUserBalance
	].forEach { $0?.textColor = .mobitColors(.investmentTextPrimary) }
	self.applyInvestmentPanelTheme()
	self.applyChargeButtonStyle()
  }

  private func applyChargeButtonStyle() {
	self.chargeButton.configuration = nil
	self.chargeButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
	self.chargeButton.titleLabel?.backgroundColor = .clear
	self.chargeButton.titleLabel?.isOpaque = false
  }

  private func applyInvestmentPanelTheme() {
	self.transactionTableview.backgroundColor = .mobitColors(.investmentBackground)
	self.transactionTableview.superview?.backgroundColor = .mobitColors(.investmentBackground)
	self.noResultView.backgroundColor = .mobitColors(.investmentBackground)
	self.dimView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
	self.sortLabel.textColor = .mobitColors(.investmentTextSecondary)
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
		let crypto = cryptoTransacDataModel
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
	  
      let previous = self.dataSource?.snapshot()
      snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { previous?.indexOfItem($0) != nil })
	  self.dataSource?.apply(snapshot, animatingDifferences: false)
	}
  }
  
  func updateTotalDatas(cryptos: [CryptoTransactionDataModel]) {
	guard let availableUserBalance = UserDataManager.userInformation?.userAvailableBalance else { return }

	// BTC 마켓 보유분은 BTC 단위로 기록되므로 합산 전에 원화로 환산한다.
	let btcKRWPrice = AppDataManager.shared.btcKRWPrice()
	// 총 보유자산
	let totalUserBalance = PortfolioCalculator.totalAssetValue(
	  availableBalance: availableUserBalance,
	  cryptos: cryptos,
	  btcKRWPrice: btcKRWPrice
	)
	// 평가손익
	let totalProfitLoss = PortfolioCalculator.totalEvaluationProfitLoss(
	  cryptos: cryptos,
	  btcKRWPrice: btcKRWPrice
	)
	// 수익률
	let totalProfitRate: Double
	if let totalProfitLoss, let totalUserBalance {
	  totalProfitRate = PortfolioCalculator.totalProfitRate(
		totalProfitLoss: totalProfitLoss,
		totalAssetValue: totalUserBalance
	  )
	} else {
	  totalProfitRate = 0
	}

	// 총 매수
	let totalBuyPrice = PortfolioCalculator.totalBuyAmount(
	  cryptos: cryptos,
	  btcKRWPrice: btcKRWPrice
	)

	let availableUserBalanceString: String = availableUserBalance == 0 ? "0" : availableUserBalance.formatSignificantDigits()
	let totalProfitRateString: String = totalProfitRate == 0 ? "0" : totalProfitRate.formatSignificantDigits(digits: 4)

	self.availableUserBalance.text = availableUserBalanceString + " 원"
	self.totalUserBalance.text = Self.krwText(totalUserBalance)
	self.totalProfitRate.text = (totalUserBalance == nil || totalProfitLoss == nil) ? Self.unavailableText : totalProfitRateString + " %"
	self.totalProfitRate.textColor = MarketColorPalette.color(forSignedValue: totalProfitRate)
	self.totalEvalProfitLoss.text = Self.krwText(totalProfitLoss)
	self.totalEvalProfitLoss.textColor = MarketColorPalette.color(forSignedValue: totalProfitLoss ?? 0)
	self.totalBuyPrice.text = Self.krwText(totalBuyPrice)
  }

  /// BTC/KRW 시세를 아직 받지 못한 상태를 0원으로 보여주면 자산이 사라진 것처럼 읽힌다.
  static let unavailableText = "-"

  private static func krwText(_ value: Double?) -> String {
	guard let value else { return unavailableText }
	return (value == 0 ? "0" : value.formatSignificantDigits(digits: 0)) + " 원"
  }

  func applyCryptos(_ cryptos: [CryptoTransactionDataModel]) {
	guard cryptos.count != 0 else {
	  self.noResultView.isHidden = false
      self.cryptos = []
      self.applySnapshot(cryptoTransacDataModel: [])
	  self.updateTotalDatas(cryptos: [])

	  return
	}

	self.noResultView.isHidden = true
	self.cryptos = self.sortCryptos(sortType: self.selectedSortType, cryptos: cryptos)
	self.updateTotalDatas(cryptos: cryptos)
	self.applySnapshot(cryptoTransacDataModel: self.cryptos)
  }

  func sortCryptos(sortType: InvestSortType, cryptos: [CryptoTransactionDataModel]) -> [CryptoTransactionDataModel] {
    if sortType == .name {
      return cryptos.sorted { $0.staticData.marketName.lowercased() < $1.staticData.marketName.lowercased() }
    }
    let ascending = [.pnlLowToHigh, .evalProfitLossLowToHigh, .evalPriceLowToHigh].contains(sortType)
    let valued = cryptos.enumerated().map { index, crypto in
      (index, crypto, PortfolioCalculator.valuation(
        of: crypto, btcKRWPrice: AppDataManager.shared.btcKRWPrice(for: crypto.staticData.exchange)
      ))
    }
    func value(_ valuation: PortfolioCalculator.Valuation) -> Double? {
      switch sortType {
      case .pnlHighToLow, .pnlLowToHigh: return valuation.profitRate
      case .evalProfitLossHighToLow, .evalProfitLossLowToHigh: return valuation.profitLossKRW
      default: return valuation.evaluationKRW
      }
    }
    return valued.sorted {
      let left = value($0.2), right = value($1.2)
      if left == right { return $0.0 < $1.0 }
      return PortfolioCalculator.orderedBefore(left, right, ascending: ascending)
    }.map { $0.1 }
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
	  MobitAnalyticsUtil.sendClickEvent(
		location: "투자내역_화면",
		stepDepth01: "투자내역_탭",
		stepDepth02: "정렬_변경",
		stepDepth03: sortTypes[index].rawValue,
		extraParameters: ["selected_sort": sortTypes[index].rawValue]
	  )
	}
  }
}

// MARK: Reactor - View
extension InvestmentViewController: View {
  func bind(reactor: InvestReactor) {
    AppDataManager.shared.btcKRWPriceUpdates
      .observe(on: MainScheduler.instance)
      .filter { $0 == ExchangeSelectionStore.currentExchange }
      .subscribe(onNext: { [weak self] _ in
        guard let self else { return }
        if self.isScrolling { self.pendingUpdate = self.pendingUpdate ?? self.cryptos }
        else { self.applyCryptos(self.cryptos) }
      })
      .disposed(by: self.disposeBag)

	reactor.state.map { $0.cryptos }
	  .compactMap { $0 }
	  .throttle(.milliseconds(100), scheduler: MainScheduler.instance)
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] cryptos in
		guard let self else { return }

		// 스크롤 중에는 갱신을 미뤄 두고, 잠금 해제 시 마지막 값만 반영한다.
		guard !self.isScrolling else {
		  self.pendingUpdate = cryptos
		  return
		}

		self.pendingUpdate = nil
		self.applyCryptos(cryptos)
	  })
	  .disposed(by: self.disposeBag)
	
	reactor.state.map { $0.userAvailableBalance }
	  .throttle(.milliseconds(100), scheduler: MainScheduler.instance)
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] userAvailableBalance in
		guard let self else { return }
		self.userAvailableBalance = userAvailableBalance
		// 값은 항상 보관하고, 스크롤 중에는 합계 표시 갱신만 미룬다.
		guard !self.isScrolling else { return }
		self.updateTotalDatas(cryptos: self.cryptos)
	  })
	  .disposed(by: self.disposeBag)

	// 보유코인 선택 → 티커 조회 완료 후 상세 화면으로 이동
	reactor.state.map { $0.detailCrypto }
	  .distinctUntilChanged()
	  .compactMap { $0 }
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] info in
		guard let self else { return }
		let symbol = info.market.replacingOccurrences(
		  of: "/(KRW|BTC)",
		  with: "",
		  options: .regularExpression
		)
		self.coordinator?.pushCryptoTradeVC(
		  selectCrypto: info,
		  cmcSymbol: symbol,
		  completion: { [weak self] errorMsg in
			guard let self = self, let errorMsg = errorMsg else { return }
			self.show(alertType: .onlyConfirm, title: "안내", content: errorMsg, callBack: nil)
		  }
		)
	  })
	  .disposed(by: self.disposeBag)
  }
}

extension InvestmentViewController: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
	let selectedCryptoMarketName = self.cryptos[indexPath.row].staticData.marketName

	guard let selectedCryptoName = self.cryptos[indexPath.row].staticData.cryptoName else { return }

	// 티커 조회 후 상세로 이동 (정보 탭 데이터까지 채우기 위함). 이동은 bind의 detailCrypto 구독에서 처리
	self.reactor.action.onNext(
	  .prepareDetailCrypto(marketName: selectedCryptoMarketName, cryptoName: selectedCryptoName)
	)
  }
}

extension InvestmentViewController {
  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
	  isScrolling = true
  }

  // 감속 없이 드래그가 끝나면 didEndDecelerating이 호출되지 않아 잠금이 남는다.
  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
	guard !decelerate else { return }
	releaseScrollLock()
  }

  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
	releaseScrollLock()
  }

  private func releaseScrollLock() {
	isScrolling = false

	guard let update = pendingUpdate else {
	  // 스크롤 중 잔고만 바뀐 경우에도 합계 표시를 맞춘다.
	  updateTotalDatas(cryptos: cryptos)
	  return
	}
	pendingUpdate = nil
	applyCryptos(update)
  }
}
