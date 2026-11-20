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

  // 정렬 계산과 별개로 화면에 표시할 현지화 키를 제공한다.
  var localizationKey: String {
	switch self {
	case .name: return "sort_name"
	case .pnlHighToLow: return "sort_return_high"
	case .pnlLowToHigh: return "sort_return_low"
	case .evalProfitLossHighToLow: return "sort_profit_high"
	case .evalProfitLossLowToHigh: return "sort_profit_low"
	case .evalPriceHighToLow: return "sort_value_high"
	case .evalPriceLowToHigh: return "sort_value_low"
	}
  }
}

class InvestmentViewController: MobitBaseViewController {
  @IBOutlet weak var transactionTableview: UITableView!
  // 자산 요약과 빈 목록 안내를 목록과 함께 스크롤한다.
  @IBOutlet var summaryHeaderView: InvestmentSummaryView!
  // 현재 계좌의 거래소를 선택한다.
  @IBOutlet private weak var exchangeButton: UIButton!
  // 화면 제목을 앱의 포인트 색상으로 표시한다.
  @IBOutlet private weak var screenTitleLabel: UILabel!
  // 기존 투자손익 내역 화면으로 이동한다.
  @IBOutlet private weak var historyButton: UIButton!
  @IBOutlet weak var totalUserBalance: UILabel!
  // 선물과 공유하는 XIB 제목이며 현물에서는 기존 문구를 유지한다.
  @IBOutlet weak var totalEvaluationTitle: UILabel!
  @IBOutlet weak var totalEvalProfitLoss: UILabel!
  @IBOutlet weak var totalProfitRate: UILabel!
  @IBOutlet weak var totalBuyPrice: UILabel!
  // 주문가능 잔고를 제외한 보유 코인의 평가금액이다.
  @IBOutlet weak var totalEvaluationAmount: UILabel!
  @IBOutlet weak var totalBuyTitle: UILabel!
  @IBOutlet weak var emptyLabel: UILabel!
  @IBOutlet weak var availableUserBalance: UILabel!
  @IBOutlet weak var noResultView: UIView!
  @IBOutlet weak var sortLabel: UILabel!
  @IBOutlet weak var dimView: UIView!
  @IBOutlet weak var chargeButton: InvestmentChargeButton!
    
  weak var coordinator: InvestmentCoordinator?
  var dataSource: UITableViewDiffableDataSource<TableViewSection, CryptoTransactionDataModel>?
  var disposeBag = DisposeBag()
  var reactor: InvestReactor
  // 테이블에 마지막으로 표시한 보유 암호화폐 목록이다.
  private var displayedUserHeldCryptos: [CryptoTransactionDataModel] = []
  var userAvailableBalance: Double = 0
  // 스크롤이 끝나면 표시할 보유 암호화폐 목록이며, 빈 배열은 보유 종목이 없음을 뜻한다.
  private(set) var pendingUserHeldCryptos: [CryptoTransactionDataModel]?
  private var supportedMarketPairIDs: Set<ExchangePairID>?
  // 정산 확인 후 진행 중인 거래소 목록 조회를 화면 수명에 맞춰 취소한다.
  private let settlementVerification = SerialDisposable()
  // 정산 전 목록 조회가 끝나기 전의 중복 요청을 막는다.
  private var isVerifyingSettlement = false
  private var selectedSortType: InvestSortType = .name {
	didSet {
	  self.displayedUserHeldCryptos = self.sortCryptos(sortType: self.selectedSortType, cryptos: displayedUserHeldCryptos)
	  self.applySnapshot(cryptoTransacDataModel: self.displayedUserHeldCryptos)
	  self.sortLabel.text = FuturesText.text(self.selectedSortType.localizationKey)
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
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    showSupportedMarketsRetryIfNeeded()
    MobitAnalyticsUtil.sendScreenEvent(
      location: "투자내역_화면",
      stepDepth01: "투자내역_탭",
      stepDepth02: "보유자산_조회",
      account: .spot(for: ExchangeSelectionStore.currentExchange)
    )
  }

  override func viewWillAppear(_ animated: Bool) {
	super.viewWillAppear(animated)
	
	self.navigationController?.navigationBar.isHidden = true
	applyThemeColors()
	updateTotalDatas(cryptos: displayedUserHeldCryptos)
	self.reactor.action.onNext(.loadTransactions)
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    settlementVerification.disposable = Disposables.create()
    isVerifyingSettlement = false
    reactor.action.onNext(.invalidateSupportedMarkets)
  }
  
  override func viewDidLoad() {
	super.viewDidLoad()
	setUI()
	setData()
	setTableView()
  }

  override func viewDidLayoutSubviews() {
	super.viewDidLayoutSubviews()
	summaryHeaderView.updateLayout(in: transactionTableview)
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
	applyThemeColors()
	transactionTableview.reloadData()
  }
  
  func setUI() {
	summaryHeaderView.configure(product: .spot)
	summaryHeaderView.updateCount(displayedUserHeldCryptos.count)
	sortLabel.text = FuturesText.text(selectedSortType.localizationKey)
	InvestmentSummaryView.configureNavigation(
	  titleLabel: screenTitleLabel,
	  historyButton: historyButton,
	  exchangeButton: exchangeButton,
	  account: .spot(for: ExchangeSelectionStore.currentExchange)
	)
	exchangeButton.addTarget(self, action: #selector(presentExchangeSheet), for: .touchUpInside)
	transactionTableview.tableHeaderView = summaryHeaderView
	applyThemeColors()
	self.transactionTableview.contentInset.bottom = 16
  }

  @objc private func presentExchangeSheet() {
	guard presentedViewController == nil else { return }
	// 확인 전에는 현재 거래소와 시세 구독을 변경하지 않는다.
	let controller = ExchangeSelectionSheetViewController(
	  selectedExchange: ExchangeSelectionStore.currentExchange
	) { [weak self] exchange in self?.coordinator?.switchExchange(to: exchange) }
	controller.prepareSheet(for: view.bounds.width)
	present(controller, animated: true)
  }

  private func applyThemeColors() {
	self.view.backgroundColor = .mobitColors(.investmentBackground)
	self.transactionTableview.backgroundColor = .mobitColors(.investmentBackground)
	self.noResultView.backgroundColor = .mobitColors(.investmentBackground)
	self.dimView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
	self.sortLabel.textColor = .mobitColors(.investmentTextPrimary)
	summaryHeaderView.applyThemeColors()
	[
	  self.totalUserBalance,
	  self.totalBuyPrice,
	  self.totalEvaluationAmount,
	  self.availableUserBalance
	].forEach { $0?.textColor = .mobitColors(.investmentTextPrimary) }
	self.applyInvestmentPanelTheme()
  }

  private func applyInvestmentPanelTheme() {
	self.transactionTableview.backgroundColor = .mobitColors(.investmentBackground)
	self.noResultView.backgroundColor = .mobitColors(.investmentBackground)
	self.dimView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
	self.sortLabel.textColor = .mobitColors(.investmentTextSecondary)
  }

  func setData() {
	self.bind(reactor: self.reactor)
  }

  func setTableView() {
	self.transactionTableview.register(
	  UINib(nibName: "InvestmentTableViewCell", bundle: nil),
	  forCellReuseIdentifier: "InvestmentTableViewCell"
	)
	
	self.transactionTableview.bounces = false
	self.transactionTableview.rowHeight = UITableView.automaticDimension
	self.transactionTableview.estimatedRowHeight = 160
	
	self.dataSource = UITableViewDiffableDataSource<TableViewSection, CryptoTransactionDataModel>(
	  tableView: self.transactionTableview,
	  cellProvider: { [weak self] tableView, indexPath, cryptoTransacDataModel in
		guard let self else { return nil }
		
		guard let cell = self.transactionTableview.dequeueReusableCell(
		  withIdentifier: "InvestmentTableViewCell",
		  for: indexPath
		) as? InvestmentTableViewCell else { return UITableViewCell() }
		
		let isLast = (indexPath.row == self.displayedUserHeldCryptos.count - 1)
		let crypto = cryptoTransacDataModel
		cell.configure(
		  crypto: crypto,
		  isLast: isLast,
		  isTradingUnsupported: self.isTradingUnsupported(crypto)
		)
		cell.unsupportedSettlementCallBack = { [weak self] in
		  // 갱신된 보유 목록에서 버튼에 해당하는 종목을 다시 확인한다.
		  guard let self, let currentCrypto = self.displayedUserHeldCryptos.first(where: {
			$0.staticData.exchangePairID == crypto.staticData.exchangePairID
		  }),
			self.isTradingUnsupported(currentCrypto) else { return }
		  self.showDelistingSettlementAlert(for: currentCrypto)
		}
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
	let btcKRWPrice = AppDataManager.shared.lastBTCKRWPrice()
	// 총 보유자산
	let totalUserBalance = PortfolioCalculator.totalAssetValueDecimal(
	  availableBalance: availableUserBalance,
	  cryptos: cryptos,
	  btcKRWPrice: btcKRWPrice
	)
	// 평가손익
	let totalProfitLoss = PortfolioCalculator.totalEvaluationProfitLossDecimal(
	  cryptos: cryptos,
	  btcKRWPrice: btcKRWPrice
	)
	// 수익률
	let totalProfitRate: Double
	if let totalProfitLoss, let totalUserBalance {
	  // 수익률 표시 정책은 유지하되 합계의 나눗셈까지 십진수로 계산한다.
	  let rate = totalUserBalance == 0 ? Decimal(0) : totalProfitLoss / totalUserBalance * 100
	  totalProfitRate = PortfolioCalculator.double(rate)
	} else {
	  totalProfitRate = 0
	}

	// 총 매수
	let totalBuyPrice = PortfolioCalculator.totalBuyAmountDecimal(
	  cryptos: cryptos,
	  btcKRWPrice: btcKRWPrice
	)

	// 요약의 단위는 별도 제목에서 한 번만 표시한다.
	let availableUserBalanceString: String = availableUserBalance == 0 ? "0" : availableUserBalance.formatTradingValue()
	// 기존 수익률 자릿수는 유지하고 이익의 양수 부호만 보강한다.
	let totalProfitRateString: String = (totalProfitRate > 0 ? "+" : "")
	  + (totalProfitRate == 0 ? "0" : totalProfitRate.formatSignificantDigits(digits: 4))

	self.availableUserBalance.text = availableUserBalanceString
	self.totalUserBalance.text = Self.krwText(totalUserBalance)
	self.totalEvaluationAmount.text = Self.krwText(PortfolioCalculator.totalEvaluationPriceDecimal(cryptos: cryptos, btcKRWPrice: btcKRWPrice))
	self.totalProfitRate.text = (totalUserBalance == nil || totalProfitLoss == nil) ? Self.unavailableText : totalProfitRateString + "%"
	self.totalProfitRate.textColor = MarketColorPalette.color(forSignedValue: totalProfitRate)
	self.totalEvalProfitLoss.text = totalProfitLoss.map { ($0 > 0 ? "+" : "") + Self.krwText($0) } ?? Self.unavailableText
	self.totalEvalProfitLoss.textColor = MarketColorPalette.color(forSignedValue: totalProfitLoss.map { $0 > 0 ? 1 : ($0 < 0 ? -1 : 0) } ?? 0)
	self.totalBuyPrice.text = Self.krwText(totalBuyPrice)
	summaryHeaderView.updateLayout(in: transactionTableview)
  }

  /// BTC/KRW 시세를 아직 받지 못한 상태를 0원으로 보여주면 자산이 사라진 것처럼 읽힌다.
  static let unavailableText = "-"

  private static func krwText(_ value: Decimal?) -> String {
	guard let value, !value.isNaN else { return unavailableText }
	return TradingNumberFormat.string(value)
  }

  private func isTradingUnsupported(_ crypto: CryptoTransactionDataModel) -> Bool {
	guard crypto.staticData.exchange == reactor.exchange,
          reactor.exchange == ExchangeSelectionStore.currentExchange,
          let supportedMarketPairIDs, !supportedMarketPairIDs.isEmpty else { return false }
	return !supportedMarketPairIDs.contains(crypto.staticData.exchangePairID)
  }

  private func showDelistingSettlementAlert(for crypto: CryptoTransactionDataModel) {
    guard !isVerifyingSettlement, presentedViewController == nil, !isBeingDismissed else { return }
    // 미리보기에는 화면에 남아 있을 수 있는 이전 시세 대신 저장된 정산 기준을 사용한다.
    guard let holding = UserDataManager.userCryptoList?.first(where: {
      $0.staticData.exchangePairID == crypto.staticData.exchangePairID
    }) else {
      showDelistingSettlementError(TradeOrderValidator.ValidationError.insufficientHolding)
      return
    }
    // 사용자가 확인한 정산 기준을 실제 정산 시 다시 비교한다.
    let quote: TradeOrderService.DelistingSettlementQuote
    switch TradeOrderService.delistingSettlementQuote(for: holding) {
    case .success(let value):
      quote = value
    case .failure(let error):
      showDelistingSettlementError(error)
      return
    }
    // 마켓의 기초자산 심볼은 보유 수량의 단위를 표시한다.
    let symbol = quote.marketName.split(separator: "/").first.map(String.init) ?? quote.marketName
    // 종목명이 없는 경우에도 사용자가 정산 대상을 알아볼 수 있다.
    let marketName = holding.staticData.cryptoName.flatMap { $0.isEmpty ? nil : $0 } ?? symbol
    // 반환 금액은 결제 통화로 표시해 BTC 마켓을 원화와 구분한다.
    let currency = quote.currency == .krw ? FuturesText.text("currency_krw_unit") : quote.currency.rawValue
    // 실제 정산에 앞서 저장된 금액과 대상 자산을 확인한다.
    let alert = MobitAlertViewController(
      alertType: .canCancel,
      title: FuturesText.text("spot_delisting_title"),
      content: FuturesText.text("spot_delisting_message")
    ) { [weak self] isConfirmed in
      guard let self, isConfirmed else { return }
      guard self.viewIfLoaded?.window != nil,
            holding.staticData.exchange == ExchangeSelectionStore.currentExchange else { return }
      guard let current = self.displayedUserHeldCryptos.first(where: {
        $0.staticData.exchangePairID == holding.staticData.exchangePairID
      }) else {
        self.showDelistingSettlementError(.settlementChanged)
        return
      }
      guard let supportedMarketPairIDs = self.supportedMarketPairIDs,
            !supportedMarketPairIDs.isEmpty else {
        self.showSupportedMarketsError(message: FuturesText.text("spot_delisting_market_unavailable"))
        return
      }
      guard !supportedMarketPairIDs.contains(current.staticData.exchangePairID) else {
        self.showSupportedMarketsError(message: FuturesText.text("spot_delisting_support_changed"))
        return
      }
      self.verifyAndSettleDelistedHolding(holding, expectedQuote: quote)
    }
    alert.setDelistingSettlementDetails(
      market: "\(marketName) (\(symbol))",
      quantity: TradingNumberFormat.string(quote.quantity),
      quantityUnit: symbol,
      amount: "\(TradingNumberFormat.string(quote.executedAmount)) \(currency)"
    )
    present(alert, animated: true)
  }

  private func verifyAndSettleDelistedHolding(
    _ crypto: CryptoTransactionDataModel,
    expectedQuote: TradeOrderService.DelistingSettlementQuote
  ) {
    guard !isVerifyingSettlement, crypto.staticData.exchange == ExchangeSelectionStore.currentExchange else { return }
    isVerifyingSettlement = true
    // 이전 목록과 진행 중이던 목록 요청은 정산의 근거로 다시 사용하지 않는다.
    reactor.action.onNext(.invalidateSupportedMarkets)
    settlementVerification.disposable = reactor.verifiedDelistingSettlementRate(
      for: crypto.staticData.exchangePairID,
      currency: expectedQuote.currency
    )
      .subscribe(onNext: { [weak self] rate in
        guard let self else { return }
        self.isVerifyingSettlement = false
        guard self.viewIfLoaded?.window != nil,
              crypto.staticData.exchange == ExchangeSelectionStore.currentExchange else { return }
        self.settleDelistedHolding(crypto, expectedQuote: expectedQuote, btcKRWPrice: rate)
      }, onError: { [weak self] error in
        guard let self else { return }
        self.isVerifyingSettlement = false
        guard self.viewIfLoaded?.window != nil,
              crypto.staticData.exchange == ExchangeSelectionStore.currentExchange else { return }
        // 목록 조회 자체의 통신 오류도 목록 재확인 안내로 연결한다.
        let reason = error as? InvestReactor.DelistingVerificationError ?? .unavailable
        self.showSupportedMarketsError(message: reason.message)
      })
  }

  private func showSupportedMarketsError(message: String) {
    show(
      alertType: .onlyConfirm,
      title: FuturesText.text("spot_delisting_error_title"),
      content: message
    ) { [weak self] _ in
      self?.reactor.action.onNext(.loadTransactions)
    }
  }

  private func showSupportedMarketsRetryIfNeeded() {
    guard reactor.currentState.supportedMarketsFailed,
          reactor.exchange == ExchangeSelectionStore.currentExchange,
          reactor.currentState.cryptos.contains(where: { $0.staticData.exchange == reactor.exchange }),
          viewIfLoaded?.window != nil, presentedViewController == nil else { return }
    show(
      alertType: .canCancel,
      title: FuturesText.text("spot_delisting_market_check_title"),
      content: FuturesText.text("spot_delisting_market_check_message"),
      confirmTitle: FuturesText.text("spot_delisting_market_check_retry"),
      cancelTitle: FuturesText.text("settings_close")
    ) { [weak self] retry in
      guard retry else { return }
      self?.reactor.action.onNext(.loadTransactions)
    }
  }

  private func settleDelistedHolding(
    _ crypto: CryptoTransactionDataModel,
    expectedQuote: TradeOrderService.DelistingSettlementQuote,
    btcKRWPrice: Double?
  ) {
	let result = TradeOrderService.executeDelistingSettlement(
	  marketName: crypto.staticData.marketName,
	  exchange: crypto.staticData.exchange,
	  btcKRWPrice: btcKRWPrice,
      expectedQuote: expectedQuote
	)
    reactor.action.onNext(.loadTransactions)

	switch result {
	case .success:
	  self.show(
		alertType: .onlyConfirm,
		title: "정산 완료",
		content: "전량 매도가 완료되었으며 실현손익과 보유자산에 반영되었습니다.",
		callBack: nil
	  )
	case .failure(let error):
      showDelistingSettlementError(error)
	}
  }

  private func showDelistingSettlementError(_ error: TradeOrderValidator.ValidationError) {
    show(
      alertType: .onlyConfirm,
      title: FuturesText.text("spot_delisting_error_title"),
      content: error.message,
      callBack: nil
    )
  }

  private func refreshDisplayedHoldings() {
    if isScrolling {
      // 상태만 바뀐 경우에는 먼저 도착한 최신 보유 목록을 보존한다.
      pendingUserHeldCryptos = pendingUserHeldCryptos ?? displayedUserHeldCryptos
    } else {
      applyHoldings(displayedUserHeldCryptos)
    }
  }

  private func applyHoldings(_ holdings: [CryptoTransactionDataModel]) {
	summaryHeaderView.updateCount(holdings.count)
	guard holdings.count != 0 else {
	  self.noResultView.isHidden = false
      self.displayedUserHeldCryptos = []
      self.applySnapshot(cryptoTransacDataModel: [])
	  self.updateTotalDatas(cryptos: [])

	  return
	}

	self.noResultView.isHidden = true
	self.displayedUserHeldCryptos = self.sortCryptos(sortType: self.selectedSortType, cryptos: holdings)
	self.updateTotalDatas(cryptos: holdings)
	self.applySnapshot(cryptoTransacDataModel: self.displayedUserHeldCryptos)
  }

  func sortCryptos(sortType: InvestSortType, cryptos: [CryptoTransactionDataModel]) -> [CryptoTransactionDataModel] {
    if sortType == .name {
      return cryptos.sorted { $0.staticData.marketName.lowercased() < $1.staticData.marketName.lowercased() }
    }
    let ascending = [.pnlLowToHigh, .evalProfitLossLowToHigh, .evalPriceLowToHigh].contains(sortType)
    let valued = cryptos.enumerated().map { index, crypto in
      (index, crypto, PortfolioCalculator.valuation(
        of: crypto, btcKRWPrice: AppDataManager.shared.lastBTCKRWPrice(for: crypto.staticData.exchange)
      ))
    }
    return valued.sorted {
      if sortType == .pnlHighToLow || sortType == .pnlLowToHigh {
        // 수익률은 기존 표시·정렬 정책에 따라 Double로 비교한다.
        let left = $0.2.profitRate, right = $1.2.profitRate
        if left == right { return $0.0 < $1.0 }
        return PortfolioCalculator.orderedBefore(left, right, ascending: ascending)
      }
      // 평가금액과 손익은 저장된 원가의 마지막 1원까지 비교한다.
      let left = sortType == .evalProfitLossHighToLow || sortType == .evalProfitLossLowToHigh
        ? $0.2.profitLossKRW : $0.2.evaluationKRW
      let right = sortType == .evalProfitLossHighToLow || sortType == .evalProfitLossLowToHigh
        ? $1.2.profitLossKRW : $1.2.evaluationKRW
      if left == right { return $0.0 < $1.0 }
      switch (left, right) {
      case let (left?, right?): return ascending ? left < right : left > right
      case (_?, nil): return true
      default: return false
      }
    }.map { $0.1 }
  }
  
  // MARK: - Button Actions

  @IBAction private func tapOnAssetInfoButton(_ sender: UIButton) {
	show(
	  alertType: .onlyConfirm,
	  title: FuturesText.text("investment_assets_info"),
	  content: FuturesText.text("investment_spot_assets_description"),
	  callBack: nil
	)
  }
    
  /// 충전하기 버튼 클릭
  @IBAction func tapOnChargeButton(_ sender: InvestmentChargeButton) {
    // 광고 안내 중 모드가 바뀌어도 버튼을 누른 현물 계좌를 유지한다.
    let account = TradingAccountID.spot(for: ExchangeSelectionStore.currentExchange)
    MobitAnalyticsUtil.sendClickEvent(event: .investment_charge, account: account)
	self.show(
	  alertType: .canCancel,
	  title: "안내",
	  content: "본 광고를 시청하시면 모의투자 금액\n10,000,000원이 보유 금액으로 추가됩니다."
	) { isOk in
	  if isOk {
		MobitAnalyticsUtil.sendClickEvent(event: .ad_click_confirm, account: account, extraParameters: ["entry_point": "투자내역_충전"])
        RewardedAdManager.shared.showAd(from: self, account: account)
	  } else {
		MobitAnalyticsUtil.sendClickEvent(event: .ad_click_cancel, account: account, extraParameters: ["entry_point": "투자내역_충전"])
	  }
	}
  }
  
  /// P&L 버튼 클릭
  @IBAction func tapOnPnlButton(_ sender: UIButton) {
	MobitAnalyticsUtil.sendClickEvent(event: .investment_pnl, account: .spot(for: ExchangeSelectionStore.currentExchange))
	self.coordinator?.pushPnlVC()
  }
    
  /// 정렬 버튼
  @IBAction func tapOnSortButton(_ sender: UIButton) {
	let sortTypes: [InvestSortType] = [
	  .name, .pnlHighToLow, .pnlLowToHigh, .evalProfitLossHighToLow, .evalProfitLossLowToHigh, .evalPriceHighToLow, .evalPriceLowToHigh
	]
	let sortTitles: [String] = sortTypes.map { FuturesText.text($0.localizationKey) }
	
	self.showBottomSheet(
	  title: FuturesText.text("sort_method"),
	  contentList: sortTitles,
	  sortType: self.selectedSortType
	) { index in
	  self.selectedSortType = sortTypes[index]
	  MobitAnalyticsUtil.sendClickEvent(
		location: "투자내역_화면",
		stepDepth01: "투자내역_탭",
		stepDepth02: "정렬_변경",
		stepDepth03: sortTypes[index].rawValue,
        account: .spot(for: ExchangeSelectionStore.currentExchange),
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
        self?.refreshDisplayedHoldings()
      })
      .disposed(by: self.disposeBag)

	reactor.state.map { $0.cryptos }
	  .throttle(.milliseconds(100), scheduler: MainScheduler.instance)
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  // Reactor가 새로 전달한 보유 암호화폐 목록을 받는다.
	  .subscribe(onNext: { [weak self] updatedUserHeldCryptos in
		guard let self else { return }

		// 스크롤 중에는 갱신을 미뤄 두고, 잠금 해제 시 마지막 값만 반영한다.
		guard !self.isScrolling else {
		  self.pendingUserHeldCryptos = updatedUserHeldCryptos
		  return
		}

		self.pendingUserHeldCryptos = nil
		self.applyHoldings(updatedUserHeldCryptos)
	  })
	  .disposed(by: self.disposeBag)

	reactor.state.map { $0.supportedMarketPairIDs }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] supportedMarketPairIDs in
		guard let self else { return }
		self.supportedMarketPairIDs = supportedMarketPairIDs
		self.refreshDisplayedHoldings()
	  })
	  .disposed(by: self.disposeBag)

    reactor.state.map { [exchange = reactor.exchange] state in
      state.supportedMarketsFailed && state.cryptos.contains { $0.staticData.exchange == exchange }
    }
      .distinctUntilChanged()
      .filter { $0 }
      .observe(on: MainScheduler.instance)
      .subscribe(onNext: { [weak self] _ in self?.showSupportedMarketsRetryIfNeeded() })
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
		self.updateTotalDatas(cryptos: self.displayedUserHeldCryptos)
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
	guard indexPath.row < self.displayedUserHeldCryptos.count else { return }
	let selectedCrypto = self.displayedUserHeldCryptos[indexPath.row]
	guard !self.isTradingUnsupported(selectedCrypto) else { return }
	let selectedCryptoMarketName = selectedCrypto.staticData.marketName

	guard let selectedCryptoName = selectedCrypto.staticData.cryptoName else { return }

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

	guard let pendingUserHeldCryptos else {
	  // 스크롤 중 잔고만 바뀐 경우에도 합계 표시를 맞춘다.
	  updateTotalDatas(cryptos: displayedUserHeldCryptos)
	  return
	}
	self.pendingUserHeldCryptos = nil
	applyHoldings(pendingUserHeldCryptos)
  }
}
