import UIKit
import SnapKit
import RxSwift
import RxCocoa

final class FuturesAccountViewController: MobitBaseViewController, UITableViewDataSource, UITableViewDelegate, SocketControllable {
  enum Section: Int { case market, positions, history, pnl }
  private let reactor: FuturesAccountReactor
  private let marketReactor: MainReactor
  private let bag = DisposeBag()
  private var coins: [CryptoCellInfo] = []
  private var displayedIDs: [String] = []
  private var historyFailed = false
  private var favoritesOnly = false
  private var records: [FuturesTransactionRecord] = []
  private var section: Section
  private let table = UITableView(frame: .zero, style: .insetGrouped)
  private let search = UISearchBar()
  private let marketTools = UIStackView()
  private let tabs = UISegmentedControl(items: [FuturesText.text("futures_krw"), FuturesText.text("futures_positions"),
    FuturesText.text("futures_history"), "PNL"])
  weak var coordinator: FuturesCoordinator?

  init(reactor: FuturesAccountReactor, marketReactor: MainReactor, section: Section) {
    self.reactor = reactor
    self.marketReactor = marketReactor
    self.section = section
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .mobitColors(.backgroundPrimary)
    let title = FuturesText.label(style: .headline)
    title.text = "MOBIT · \(FuturesText.text("futures_paper"))"
    let exchange = FuturesText.button(reactor.account.exchange == .upbit ? "futures_upbit" : "futures_bithumb") { [weak self] in self?.chooseExchange() }
    let header = UIStackView(arrangedSubviews: [title, exchange])
    header.alignment = .center
    header.spacing = 8
    exchange.setContentHuggingPriority(.required, for: .horizontal)
    let sort = UIButton(type: .system)
    sort.setImage(UIImage(systemName: "arrow.up.arrow.down"), for: .normal)
    sort.accessibilityLabel = FuturesText.text("futures_sort")
    sort.showsMenuAsPrimaryAction = true
    sort.menu = UIMenu(children: [
      ("futures_sort_price", CryptoSortType.currentPriceDescending),
      ("futures_sort_change", .previousDayDescending),
      ("futures_sort_volume", .tradeVolumeDescending)
    ].map { key, type in
      UIAction(title: FuturesText.text(key)) { [weak self] _ in self?.marketReactor.action.onNext(.setSortType(sortBy: type)) }
    })
    sort.snp.makeConstraints { $0.width.height.greaterThanOrEqualTo(44) }
    marketTools.addArrangedSubview(search)
    marketTools.addArrangedSubview(sort)
    marketTools.alignment = .center
    search.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let stack = UIStackView(arrangedSubviews: [header, marketTools, tabs, table])
    stack.axis = .vertical
    stack.spacing = 8
    view.addSubview(stack)
    stack.snp.makeConstraints {
      $0.top.equalTo(view.safeAreaLayoutGuide).offset(8)
      $0.leading.trailing.equalToSuperview().inset(12)
      $0.bottom.equalTo(view.safeAreaLayoutGuide)
    }
    search.showsBookmarkButton = true
    search.setImage(UIImage(systemName: "star"), for: .bookmark, state: .normal)
    search.rx.bookmarkButtonClicked.subscribe(onNext: { [weak self] in
      guard let self else { return }
      favoritesOnly.toggle()
      search.setImage(UIImage(systemName: favoritesOnly ? "star.fill" : "star"), for: .bookmark, state: .normal)
      render()
    }).disposed(by: bag)
    search.placeholder = FuturesText.text("futures_search")
    search.searchBarStyle = .minimal
    tabs.selectedSegmentIndex = section.rawValue
    tabs.accessibilityLabel = FuturesText.text("futures_account_sections")
    table.dataSource = self
    table.delegate = self
    table.rowHeight = UITableView.automaticDimension
    table.selfSizingInvalidation = .enabledIncludingConstraints
    table.estimatedRowHeight = 100
    table.keyboardDismissMode = .onDrag
    table.backgroundColor = .clear
    table.contentInset.bottom = 80
    table.verticalScrollIndicatorInsets.bottom = 80
    table.refreshControl = UIRefreshControl()
    table.refreshControl?.rx.controlEvent(.valueChanged).subscribe(onNext: { [weak self] in
      self?.reactor.action.onNext(.reload)
      self?.marketReactor.action.onNext(.loadCryptoList)
    }).disposed(by: bag)
    tabs.rx.selectedSegmentIndex.changed.subscribe(onNext: { [weak self] index in
      guard let self, let section = Section(rawValue: index) else { return }
      self.section = section
      marketTools.isHidden = section != .market
      render()
    }).disposed(by: bag)
    search.rx.text.orEmpty.distinctUntilChanged().subscribe(onNext: { [weak self] _ in self?.render() }).disposed(by: bag)
    reactor.state.observe(on: MainScheduler.instance).subscribe(onNext: { [weak self] _ in self?.render() }).disposed(by: bag)
    marketReactor.state.map(\.totalCryptoList).throttle(.milliseconds(250), latest: true, scheduler: MainScheduler.instance)
      .subscribe(onNext: { [weak self] _ in self?.render() }).disposed(by: bag)
    marketTools.isHidden = section != .market
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(true, animated: animated)
    reactor.action.onNext(.reload)
    resumeSocket()
  }
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    pauseSocket()
  }
  func resumeSocket() {
    marketReactor.action.onNext(marketReactor.currentState.totalCryptoList.isEmpty ? .loadCryptoList : .resumeSocket)
  }
  func pauseSocket() { marketReactor.action.onNext(.pauseSocket) }

  private func render() {
    guard isViewLoaded else { return }
    let query = search.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    coins = marketReactor.currentState.totalCryptoList.filter {
      $0.market.hasSuffix("/KRW") && (query.isEmpty || $0.market.localizedCaseInsensitiveContains(query) || $0.cryptoName.localizedCaseInsensitiveContains(query))
    }
    if favoritesOnly {
      let favorites = Set(UserDataManager.userFavoritePairs.filter { $0.exchange == reactor.account.exchange }.map(\.pairID))
      coins = coins.filter { favorites.contains($0.exchangePairID) }
    }
    do {
      records = try reactor.currentState.snapshot?.transactionHistory(for: reactor.account).reversed() ?? []
      historyFailed = false
    } catch { historyFailed = true }

    if section == .pnl { records = records.filter { $0.realizedPnL != nil } }
    table.refreshControl?.endRefreshing()
    let itemIDs: [String]
    switch section {
    case .market: itemIDs = coins.map(\.market)
    case .positions: itemIDs = reactor.positions.map { $0.id.uuidString }
    case .history, .pnl: itemIDs = records.map(\.id)
    }
    let ids = ["account", "status", "reward"] + (itemIDs.isEmpty ? ["empty"] : itemIDs)
    if displayedIDs == ids {
      for indexPath in table.indexPathsForVisibleRows ?? [] {
        guard let cell = table.cellForRow(at: indexPath) else { continue }
        configure(cell, at: indexPath)
      }
    } else {
      displayedIDs = ids
      table.reloadData()
    }
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    let count: Int
    switch self.section {
    case .market: count = coins.count
    case .positions: count = reactor.positions.count
    case .history, .pnl: count = records.count
    }
    return 3 + max(1, count)
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell: UITableViewCell
    if indexPath.row == 0 {
      cell = tableView.dequeueReusableCell(withIdentifier: "summary") as? FuturesSummaryCell ?? FuturesSummaryCell(style: .default, reuseIdentifier: "summary")
    } else {
      cell = tableView.dequeueReusableCell(withIdentifier: "futures") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "futures")
    }
    configure(cell, at: indexPath)
    return cell
  }

  private func configure(_ cell: UITableViewCell, at indexPath: IndexPath) {
    if let summary = cell as? FuturesSummaryCell {
      summary.configure(reactor)
      return
    }
    var content = UIListContentConfiguration.subtitleCell()
    content.textProperties.font = .preferredFont(forTextStyle: .body)
    content.textProperties.numberOfLines = 0
    content.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
    content.secondaryTextProperties.numberOfLines = 0
    cell.accessoryType = .none
    cell.selectionStyle = .none
    if indexPath.row == 1 {
      content.text = FuturesText.status(reactor)
      content.textProperties.font = .preferredFont(forTextStyle: .footnote)
      content.secondaryText = nil
      cell.accessoryType = .none
    } else if indexPath.row == 2 {
      content.text = FuturesText.text("futures_charge")
      content.secondaryText = "+10,000,000 KRW"
      cell.accessoryType = .disclosureIndicator
    } else {
      let row = indexPath.row - 3
      switch section {
      case .market:
        if coins.indices.contains(row) {
          let coin = coins[row]
          content.text = "\(coin.cryptoName) · \(coin.market)"
          let price = coin.tradePrice.flatMap { $0.isFinite && $0 > 0 ? Decimal($0) : nil }
          let change = coin.signedChangeRate.flatMap { $0.isFinite ? Decimal($0 * 100) : nil }
          content.secondaryText = "\(FuturesText.number(price, digits: 4)) KRW · \(FuturesText.number(change, digits: 2))%"
          cell.accessoryType = .disclosureIndicator
        } else {
          content.text = FuturesText.text(marketReactor.currentState.isLoading ? "futures_loading" : "futures_empty_market")
        }
      case .positions:
        if reactor.positions.indices.contains(row), let snapshot = reactor.currentState.snapshot {
          do { content.text = try FuturesText.position(reactor.positions[row], snapshot: snapshot, quotes: reactor.currentState.quotes) }
          catch { content.text = FuturesText.text("futures_storage_error") }
          content.secondaryText = FuturesText.text("futures_manage")
          cell.accessoryType = .disclosureIndicator
        } else { content.text = FuturesText.text("futures_no_position") }
      case .history, .pnl:
        if historyFailed {
          content.text = FuturesText.text("futures_storage_error")
        } else if records.indices.contains(row) {
          let record = records[row]
          content.text = "\(FuturesText.symbol(record.instrument)) · \(FuturesText.side(record.side)) \(record.leverage)× · \(FuturesText.text("futures_" + record.kind.rawValue))"
          var lines = [FuturesText.date(Date(timeIntervalSince1970: Double(record.intervalStart) / 1000)),
            "\(FuturesText.text("futures_quantity")) \(FuturesText.number(record.quantity, digits: 8)) · \(FuturesText.text("futures_price")) \(FuturesText.number(record.price, digits: 4)) KRW"]
          if let end = record.intervalEndExclusive {
            lines[0] = "\(FuturesText.text("futures_occurrence")) \(lines[0]) ~ \(FuturesText.date(Date(timeIntervalSince1970: Double(end) / 1000)))"
            lines.append("\(FuturesText.text("futures_settled")) \(FuturesText.date(record.recordedAt))")
          }
          if let pnl = record.realizedPnL { lines.append("\(FuturesText.text("futures_realized")) \(FuturesText.number(pnl)) KRW") }
          content.secondaryText = lines.joined(separator: "\n")
        } else { content.text = FuturesText.text("futures_no_history") }
      }
    }
    cell.contentConfiguration = content
  }

  func tableView(
	_ tableView: UITableView,
	heightForRowAt indexPath: IndexPath
  ) -> CGFloat {
    indexPath.row == 1 && FuturesText.status(reactor).isEmpty ? 0 : UITableView.automaticDimension
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    switch indexPath.row {
    case 1: reactor.action.onNext(.reload)
    case 2:
      guard !reactor.currentState.submitting else { return }
      show(alertType: .canCancel, title: FuturesText.text("futures_charge"), content: FuturesText.text("futures_reward_note")) { [weak self] confirmed in
        guard let self, confirmed else { return }
        RewardedAdManager.shared.showAd(from: self, account: reactor.account)
      }
    case 3...:
      let row = indexPath.row - 3
      if section == .market, coins.indices.contains(row), !coins[row].isUpcomingListing {
        coordinator?.open(coin: coins[row], from: navigationController)
      } else if section == .positions, reactor.positions.indices.contains(row) {
        coordinator?.open(position: reactor.positions[row], from: navigationController)
      }
    default: break
    }
  }

  private func chooseExchange() {
    let sheet = UIAlertController(title: FuturesText.text("futures_exchange"), message: nil, preferredStyle: .actionSheet)
    for exchange in [Exchange.upbit, .bithumb] {
      sheet.addAction(UIAlertAction(title: FuturesText.text(exchange == .upbit ? "futures_upbit" : "futures_bithumb"), style: .default) { [weak self] _ in
        self?.coordinator?.switchExchange(exchange)
      })
    }
    sheet.addAction(UIAlertAction(title: FuturesText.text("futures_cancel"), style: .cancel))
    sheet.popoverPresentationController?.sourceView = view
    sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.safeAreaInsets.top, width: 1, height: 1)
    present(sheet, animated: true)
  }
}

private final class FuturesSummaryCell: UITableViewCell {
  private let title = FuturesText.label(style: .headline)
  private let note = FuturesText.label(style: .caption1)
  private let values = (0..<4).map { _ in FuturesText.label(style: .headline) }
  private let rows = [UIStackView(), UIStackView()]

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    let keys = ["futures_total", "futures_available", "futures_pnl", "futures_realized"]
    for index in keys.indices {
      let caption = FuturesText.label(style: .caption1)
      caption.text = FuturesText.text(keys[index])
      caption.textColor = .secondaryLabel
      let column = UIStackView(arrangedSubviews: [caption, values[index]])
      column.axis = .vertical
      column.spacing = 4
      rows[index / 2].addArrangedSubview(column)
    }
    rows.forEach { $0.distribution = .fillEqually; $0.spacing = 12 }
    let stack = UIStackView(arrangedSubviews: [title] + rows + [note])
    stack.axis = .vertical
    stack.spacing = 12
    contentView.addSubview(stack)
    stack.snp.makeConstraints { $0.edges.equalTo(contentView.layoutMarginsGuide) }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ reactor: FuturesAccountReactor) {
    rows.forEach { $0.axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal }
    title.text = "\(FuturesText.text(reactor.account.exchange == .upbit ? "futures_upbit" : "futures_bithumb")) · \(FuturesText.text("futures_product")) KRW"
    let cash = reactor.currentState.snapshot?.accounts.first { $0.id == reactor.account }?.availableBalance
    values.forEach { $0.text = "—" }
    values[1].text = FuturesText.number(cash)
    note.text = nil
    guard let snapshot = reactor.currentState.snapshot else { return }
    do {
      let realized = try snapshot.transactionHistory(for: reactor.account).compactMap(\.realizedPnL).reduce(Decimal(0), FuturesDecimal.add)
      values[3].text = FuturesText.number(realized)
      let valuation = try snapshot.valuation(
		for: reactor.account,
		quotes: reactor.currentState.quotes,
		now: Date(),
		allowStaleQuotes: true
	  )
      values[0].text = FuturesText.number(valuation.totalEquity)
      values[2].text = FuturesText.number(valuation.unrealizedPnL)
      values[3].text = FuturesText.number(valuation.realizedPnL)
      note.text = cash == 0 && reactor.positions.isEmpty ? FuturesText.text("futures_zero_balance") : nil
    } catch { note.text = nil }
  }
}
