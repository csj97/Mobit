import UIKit
import RxSwift
import RxCocoa

final class FuturesInvestmentViewController: MobitBaseViewController, UITableViewDelegate, SocketControllable {
  @IBOutlet weak var transactionTableview: UITableView!
  @IBOutlet weak var totalUserBalance: UILabel!
  // 현물과 공유하는 요약 제목을 선물의 보유 포지션 범위에 맞춰 표시한다.
  @IBOutlet weak var totalEvaluationTitle: UILabel!
  @IBOutlet weak var totalEvalProfitLoss: UILabel!
  @IBOutlet weak var totalProfitRate: UILabel!
  @IBOutlet weak var totalBuyPrice: UILabel!
  @IBOutlet weak var totalBuyTitle: UILabel!
  @IBOutlet weak var availableUserBalance: UILabel!
  @IBOutlet weak var noResultView: UIView!
  @IBOutlet weak var emptyLabel: UILabel!
  @IBOutlet weak var sortLabel: UILabel!
  @IBOutlet weak var dimView: UIView!
  @IBOutlet weak var chargeButton: MobitChargeButton!

  weak var coordinator: FuturesCoordinator?
  private let reactor: FuturesAccountReactor
  private let marketReactor: MainReactor
  // 화면이 해제될 때 Rx 구독을 함께 정리한다.
  private let disposeBag = DisposeBag()
  // 실제 실패에만 기존 목록 하단에서 오류·재시도를 제공한다.
  private lazy var dataErrorView = FuturesDataStatusView { [weak self] in self?.reactor.action.onNext(.reload) }
  private var dataSource: UITableViewDiffableDataSource<TableViewSection, UUID>?
  private var items: [(position: FuturesPosition, value: FuturesValuation?)] = []
  private var selectedSortType: InvestSortType = .name

  init(reactor: FuturesAccountReactor, marketReactor: MainReactor) {
    self.reactor = reactor
    self.marketReactor = marketReactor
    super.init(nibName: "InvestmentViewController", bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    applyThemeColors()
    totalBuyTitle.text = FuturesText.text("futures_total_margin")
    totalEvaluationTitle.text = FuturesText.text("futures_total_evaluation")
    chargeButton.accessibilityLabel = FuturesText.text("futures_charge")
    transactionTableview.contentInset.bottom = 70
    transactionTableview.bounces = false
    transactionTableview.rowHeight = UITableView.automaticDimension
    transactionTableview.estimatedRowHeight = 160
    transactionTableview.sectionFooterHeight = UITableView.automaticDimension
    transactionTableview.estimatedSectionFooterHeight = 44
    transactionTableview.register(UINib(nibName: "InvestmentTableViewCell", bundle: nil), forCellReuseIdentifier: "InvestmentTableViewCell")
    dataSource = UITableViewDiffableDataSource<TableViewSection, UUID>(tableView: transactionTableview) { [weak self] table, path, id in
      guard let self, let item = items.first(where: { $0.position.id == id }),
            let cell = table.dequeueReusableCell(withIdentifier: "InvestmentTableViewCell", for: path) as? InvestmentTableViewCell else {
        return UITableViewCell()
      }
      cell.configure(position: item.position, valuation: item.value, isLast: path.row == items.count - 1)
      cell.selectionStyle = .none
      return cell
    }
    transactionTableview.delegate = self
    reactor.state.observe(on: MainScheduler.instance)
      .subscribe(onNext: { [weak self] _ in self?.render() }).disposed(by: disposeBag)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(true, animated: animated)
    reactor.action.onNext(.reload)
    resumeSocket()
    render()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    pauseSocket()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard isViewLoaded, previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
    applyThemeColors()
  }

  func resumeSocket() {
    marketReactor.action.onNext(marketReactor.currentState.totalCryptoList.isEmpty ? .loadCryptoList : .resumeSocket)
  }
  func pauseSocket() { marketReactor.action.onNext(.pauseSocket) }

  private func applyThemeColors() {
    view.backgroundColor = .mobitColors(.investmentBackground)
    transactionTableview.backgroundColor = .mobitColors(.investmentBackground)
    noResultView.backgroundColor = .mobitColors(.investmentBackground)
    dimView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
    sortLabel.textColor = .mobitColors(.investmentTextSecondary)
    [totalUserBalance, totalBuyPrice, availableUserBalance].forEach {
      $0?.textColor = .mobitColors(.investmentTextPrimary)
    }
  }

  private func render() {
    guard isViewLoaded, !transactionTableview.isDragging, !transactionTableview.isDecelerating else { return }
    // 오류 유무가 바뀔 때만 section을 갱신해 footer 생성·제거를 반영한다.
    let previouslyHadError = !dataErrorView.isHidden
    dataErrorView.render(
      message: reactor.needsDataRetry ? FuturesText.status(reactor) : "",
      retry: reactor.needsDataRetry && reactor.currentState.networkAvailable != false && !reactor.currentState.submitting
    )
    let state = reactor.currentState
    let positions = reactor.positions
    let now = Date()
    // 검증 전에는 메인 화면과 같은 마지막 검증 가격으로 평가한다.
    let quotes = reactor.valuationQuotes
    items = positions.map { ($0, try? FuturesText.valuation($0, quotes: quotes)) }
    items.sort { left, right in
      if selectedSortType == .name {
        return FuturesText.symbol(left.position.order.instrument) < FuturesText.symbol(right.position.order.instrument)
      }
      func value(_ item: (position: FuturesPosition, value: FuturesValuation?)) -> Decimal? {
        switch selectedSortType {
        case .pnlHighToLow, .pnlLowToHigh: return item.value?.displayedROEPercent
        case .evalProfitLossHighToLow, .evalProfitLossLowToHigh: return try? item.value?.displayedPnL
        default: return item.value?.displayedEquity
        }
      }
      let lhs = value(left), rhs = value(right)
      if lhs == rhs { return left.position.id.uuidString < right.position.id.uuidString }
      guard let lhs else { return false }
      guard let rhs else { return true }
      return [.pnlLowToHigh, .evalProfitLossLowToHigh, .evalPriceLowToHigh].contains(selectedSortType) ? lhs < rhs : lhs > rhs
    }
    let cash = state.snapshot?.accounts.first { $0.id == reactor.account }?.availableBalance
    availableUserBalance.text = Self.krw(cash)
    let margin = state.snapshot.flatMap { _ in try? positions.map { try $0.margin }.reduce(Decimal(0), FuturesDecimal.add) }
    totalBuyPrice.text = Self.krw(margin)
    let valuation = try? state.snapshot?.valuation(
	  for: reactor.account,
	  quotes: quotes,
	  now: now,
	  forDisplay: true
	)
    totalUserBalance.text = Self.krw(valuation.flatMap { try? $0.positionsEquity })
    totalEvalProfitLoss.text = Self.krw(valuation?.unrealizedPnL)
    // 선물 수익률은 보유 현금을 제외하고 포지션에 사용한 증거금을 기준으로 계산한다.
    let rate = valuation.flatMap { $0.reservedMargin > 0 ? try? FuturesDecimal.multiply(FuturesDecimal.divide($0.unrealizedPnL, $0.reservedMargin), 100) : Decimal(0) }
    totalProfitRate.text = rate.map { FuturesText.number($0, digits: 2) + " %" } ?? "—"
    let color = valuation.map { MarketColorPalette.color(forSignedValue: NSDecimalNumber(decimal: $0.unrealizedPnL).doubleValue) }
      ?? UIColor.mobitColors(.investmentTextSecondary)
    totalEvalProfitLoss.textColor = color
    totalProfitRate.textColor = color
    chargeButton.isEnabled = !state.submitting
    noResultView.isHidden = !items.isEmpty || reactor.needsDataRetry
    emptyLabel.text = state.loadFailed ? FuturesText.text("futures_storage_error")
      : state.snapshot == nil ? FuturesText.text("futures_loading") : FuturesText.text("futures_no_position")
    emptyLabel.numberOfLines = 0
    emptyLabel.isHidden = false
    sortLabel.text = FuturesText.text(Self.sortKey(selectedSortType))
    var snapshot = NSDiffableDataSourceSnapshot<TableViewSection, UUID>()
    snapshot.appendSections([.invest])
    snapshot.appendItems(items.map { $0.position.id })
    let previous = dataSource?.snapshot()
    if previous?.sectionIdentifiers.contains(.invest) == true && previouslyHadError != reactor.needsDataRetry {
      snapshot.reloadSections([.invest])
    } else {
      snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { previous?.indexOfItem($0) != nil })
    }
    dataSource?.apply(snapshot, animatingDifferences: false)
  }

  private static func krw(_ value: Decimal?) -> String {
    value.map { FuturesText.number($0) + " \(FuturesText.text("currency_krw_unit"))" } ?? "—"
  }

  private static func sortKey(_ type: InvestSortType) -> String {
    switch type {
    case .name: return "futures_sort_name"
    case .pnlHighToLow: return "futures_sort_roe_high"
    case .pnlLowToHigh: return "futures_sort_roe_low"
    case .evalProfitLossHighToLow: return "futures_sort_pnl_high"
    case .evalProfitLossLowToHigh: return "futures_sort_pnl_low"
    case .evalPriceHighToLow: return "futures_sort_equity_high"
    case .evalPriceLowToHigh: return "futures_sort_equity_low"
    }
  }

  @IBAction func tapOnChargeButton(_ sender: MobitChargeButton) {
    guard !reactor.currentState.submitting else { return }
    MobitAnalyticsUtil.sendClickEvent(event: .investment_charge)
    show(alertType: .canCancel, title: FuturesText.text("futures_charge"), content: FuturesText.text("futures_reward_note")) { [weak self] confirmed in
      MobitAnalyticsUtil.sendClickEvent(event: confirmed ? .ad_click_confirm : .ad_click_cancel)
      guard let self, confirmed else { return }
      RewardedAdManager.shared.showAd(from: self, account: reactor.account)
    }
  }

  @IBAction func tapOnPnlButton(_ sender: UIButton) {
    MobitAnalyticsUtil.sendClickEvent(event: .investment_pnl)
    coordinator?.openPNL()
  }

  @IBAction func tapOnSortButton(_ sender: UIButton) {
    let types: [InvestSortType] = [.name, .pnlHighToLow, .pnlLowToHigh, .evalProfitLossHighToLow,
      .evalProfitLossLowToHigh, .evalPriceHighToLow, .evalPriceLowToHigh]
    showBottomSheet(title: FuturesText.text("futures_sort_method"), contentList: types.map { FuturesText.text(Self.sortKey($0)) }, sortType: selectedSortType) { [weak self] index in
      guard let self, types.indices.contains(index) else { return }
      selectedSortType = types[index]
      render()
    }
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    guard let id = dataSource?.itemIdentifier(for: indexPath), let position = reactor.positions.first(where: { $0.id == id }) else { return }
    coordinator?.open(position: position, from: navigationController)
  }

  func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
    reactor.needsDataRetry ? UITableView.automaticDimension : .leastNormalMagnitude
  }

  func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
    guard reactor.needsDataRetry else { return nil }
    // 정상 갱신에서는 footer를 만들지 않아 기존 목록 배치를 유지한다.
    let footer = UIView()
    footer.addSubview(dataErrorView)
    dataErrorView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      dataErrorView.topAnchor.constraint(equalTo: footer.topAnchor, constant: 12),
      dataErrorView.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -12),
      dataErrorView.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 20),
      dataErrorView.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -20)
    ])
    return footer
  }

  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    if !decelerate { render() }
  }
  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { render() }
}
