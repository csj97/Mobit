//
//  MainViewController.swift
//  Mobit
//
//  Created by 조성재 on 7/16/24.
//

import FlexLayout
import RxCocoa
import RxSwift
import ReactorKit
import PinLayout
import Then
import UIKit

enum TableViewSection: CaseIterable {
  case main
}

enum CryptoSortType: String {
  case normal
  case currentPriceAscending = "현재가↑"  // 오름차순 1,2,3,4
  case currentPriceDescending = "현재가↓" // 내림차순 4,3,2,1
  case previousDayAscending = "전일대비↑"
  case previousDayDescending = "전일대비↓"
  case tradeVolumeAscending = "거래대금↑"
  case tradeVolumeDescending = "거래대금↓"
}

class MainViewController: UIViewController {
  // coordinator <-> viewcontroller 강한 참조 사이클 방지
  weak var coordinator: MainCoordinator?
  var dataSource: UITableViewDiffableDataSource<TableViewSection, CryptoCellInfo>?
  var disposeBag = DisposeBag()
  var reactor: MainReactor
  var isSocketUpdating = false
  var selectedTab: SelectedTab = .krw
  var prevSortedButton: UIButton?
  let defaultTitles = ["현재가 ↑↓", "전일대비 ↑↓", "거래대금 ↑↓"]
  
  private let cellIndentifier = "CryptoCell"
  
  init(reactor: MainReactor) {
    self.reactor = reactor
    super.init(nibName: nil, bundle: nil)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  // MARK: UI Component
  let rootContainer: UIView = UIView()
  let searchBar = UISearchBar().then {
    $0.backgroundColor = .white
    $0.backgroundImage = UIImage()
    $0.translatesAutoresizingMaskIntoConstraints = true
  }
  // 원화 버튼
  let krwButton: UIButton = UIButton().then {
    $0.setTitle("KRW", for: .normal)
    $0.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
    $0.setTitleColor(.black, for: .normal)
    $0.setTitleColor(.blue, for: .selected)
    $0.isSelected = true  // default
    $0.tag = 0
  }
  // BTC 버튼
  let btcButton: UIButton = UIButton().then {
    $0.setTitle("BTC", for: .normal)
    $0.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
    $0.setTitleColor(.black, for: .normal)
    $0.setTitleColor(.blue, for: .selected)
    $0.tag = 1
  }
  // 관심 버튼
  let favoriteButton: UIButton = UIButton().then {
    $0.setTitle("관심", for: .normal)
    $0.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
    $0.setTitleColor(.black, for: .normal)
    $0.setTitleColor(.blue, for: .selected)
    $0.tag = 2
  }
  
  // 현재가 기준 정렬 버튼
  let currentPriceButton: UIButton = UIButton().then {
    $0.setTitle("현재가↓↑", for: .normal)
    $0.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
    $0.setTitleColor(.gray, for: .normal)
    $0.setTitleColor(.blue, for: .selected)
    $0.tag = 0
  }
  
  // 전일대비
  let previousDayButton: UIButton = UIButton().then {
    $0.setTitle("전일대비↓↑", for: .normal)
    $0.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
    $0.setTitleColor(.gray, for: .normal)
    $0.setTitleColor(.blue, for: .selected)
    $0.tag = 1
  }
  
  // 거래대금
  let tradingVolumeButton: UIButton = UIButton().then {
    $0.setTitle("거래대금↓↑", for: .normal)
    $0.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
    $0.setTitleColor(.gray, for: .normal)
    $0.setTitleColor(.blue, for: .selected)
    $0.tag = 2
  }
  
  let tableView: UITableView = UITableView().then {
    $0.separatorStyle = .singleLine
    $0.separatorInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
  }
  
  let keyboardDismissButton: UIButton = UIButton().then {
	$0.setTitle("키보드 내리기", for: .normal)
	$0.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
	$0.backgroundColor = .mobitColors(.lightGrayBG)
  }
  
  // MARK: Life Cycle
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    self.view.backgroundColor = .white
    
    self.addViews()
    
    self.setSearchBar()
    self.setTableView()
    self.setTabButton()
	self.setButtonGesture()
    
    self.setUpFlexItems()
    
    self.bind(reactor: self.reactor)
	
//	let userCryptoList = UserDataManager.userCryptoList ?? []
//	
//	userCryptoList.forEach { item in
//	  let itemTransaction = item.staticData.transactionHistoryList
//	  itemTransaction.forEach { transaction in
//		let tempTransaction: TransactionInfo = TransactionInfo(
//		  marketName: item.staticData.marketName,
//		  executedDate: transaction.executedDate,
//		  executedPrice: transaction.executedPrice,
//		  executedQuantity: transaction.executedQuantity,
//		  executedAmount: transaction.executedAmount
//		)
//		UserDataManager.userTransactionList?.append(tempTransaction)
//	  }
//	}
	
	guard let transactionHistory = UserDataManager.userTransactionList else { return }
	print(transactionHistory)
  }
  
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    
    rootContainer.pin.all(self.view.pin.safeArea)
    rootContainer.flex.layout()
  }
  
  // MARK: Sub Methods
  func addViews() {
    self.view.addSubview(self.rootContainer)
    self.rootContainer.addSubview(self.searchBar)
    self.rootContainer.addSubview(self.krwButton)
    self.rootContainer.addSubview(self.btcButton)
    self.rootContainer.addSubview(self.favoriteButton)
    self.rootContainer.addSubview(self.currentPriceButton)
    self.rootContainer.addSubview(self.previousDayButton)
    self.rootContainer.addSubview(self.tradingVolumeButton)
    self.rootContainer.addSubview(self.tableView)
  }
  
  func setTableView() {
    self.tableView.register(
      CoinTableViewCell.self,
      forCellReuseIdentifier: self.cellIndentifier
    )
    self.tableView.rowHeight = 50
	self.tableView.keyboardDismissMode = .onDrag
    
    self.dataSource = UITableViewDiffableDataSource<TableViewSection, CryptoCellInfo>(
      tableView: self.tableView
    ) { (
      tableView: UITableView,
      indexPath: IndexPath,
      crypto: CryptoCellInfo
    ) -> UITableViewCell? in
      
      guard let cell = self.tableView.dequeueReusableCell(
        withIdentifier: self.cellIndentifier,
        for: indexPath
      ) as? CoinTableViewCell else { return UITableViewCell() }
      
      cell.configure(crypto: crypto, isScrolling: self.isSocketUpdating)
      cell.selectionStyle = .none
      return cell
    }
    
    self.dataSource?.defaultRowAnimation = .fade
    self.tableView.dataSource = self.dataSource
    self.tableView.delegate = self
  }
  
  func applySnapshot(cellInfos: [CryptoCellInfo]?) {
    // tableview에 들어가는 section, item 초기화
    var snapshot = NSDiffableDataSourceSnapshot<TableViewSection, CryptoCellInfo>()
    snapshot.appendSections([.main])
    if let cellInfos = cellInfos, !cellInfos.isEmpty {
      snapshot.appendItems(cellInfos, toSection: .main)
    } else {
      snapshot.appendItems([])
    }
	
	guard let userCryptoList = UserDataManager.userCryptoList else { return }
	let userMarketNames = userCryptoList.map { $0.staticData.marketName }
	let filteredCellInfos = cellInfos?.filter {
	  userMarketNames.contains($0.market)
	}
	
	filteredCellInfos?.forEach({ cellInfo in
	  fetchBidCryptoList(
		marketName: cellInfo.market,
		currentPrice: cellInfo.tradePrice
	  )
	})
	
    self.dataSource?.apply(snapshot, animatingDifferences: false)
  }
  
  /// crypto socket 업데이트 될 떄, 매수 목록 fetch
  func fetchBidCryptoList(
	marketName: String,
	currentPrice: Double?
  ) {
	guard let updateCryptoIndex = UserDataManager.userCryptoList?
	  .firstIndex(where: { $0.staticData.marketName == marketName }),
		  let currentPrice = currentPrice,
		  let averageBuyPrice = UserDataManager.userCryptoList?[updateCryptoIndex].staticData.averageBuyPrice,
		  let cumulHoldingQunatity = UserDataManager.userCryptoList?[updateCryptoIndex].staticData.holdingQuantity
	else { return }
	
	UserDataManager.userCryptoList?[updateCryptoIndex].dynamicData.profitRate = MarketDataServiceUtil.shared.fetchProfitRate(
	  for: marketName,
	  currentPrice: currentPrice,
	  averageBuyPrice: averageBuyPrice
	)
	UserDataManager.userCryptoList?[updateCryptoIndex].dynamicData.evaluationPrice = MarketDataServiceUtil.shared.fetchEvalPrice(
	  for: marketName,
	  currentPrice: currentPrice,
	  cumulHoldingQuantity: cumulHoldingQunatity
	)
	UserDataManager.userCryptoList?[updateCryptoIndex].dynamicData.evaluationProfitLoss = MarketDataServiceUtil.shared.fetchEvalProfitLoss(
	  for: marketName,
	  currentPrice: currentPrice,
	  cumulHoldingQuantity: cumulHoldingQunatity,
	  averageBuyPrice: averageBuyPrice
	)
  }
  
  func setButtonGesture() {
    self.currentPriceButton.addTarget(
      self, action: #selector(tapOnSortButton(_:)), for: .touchUpInside
    )
    self.previousDayButton.addTarget(
      self, action: #selector(tapOnSortButton(_:)), for: .touchUpInside
    )
    self.tradingVolumeButton.addTarget(
      self, action: #selector(tapOnSortButton(_:)), for: .touchUpInside
    )
	self.keyboardDismissButton.addTarget(
	  self, action: #selector(tapOnSortButton(_:)), for: .touchUpInside
	)
  }
  
  @objc private func tapOnSortButton(_ sender: UIButton) {
    // 직전 선택 버튼 해제
    if let prevSortedButton = self.prevSortedButton,
       prevSortedButton !== sender {
      let title = defaultTitles[prevSortedButton.tag]
      prevSortedButton.setTitle(title, for: .normal)
      prevSortedButton.isSelected = false
    }
    
	var newSortType: CryptoSortType? = nil
	switch sender.tag {
	case 0:
	  newSortType = self.reactor.currentState.sortBy == .currentPriceAscending
	  ? .currentPriceDescending : .currentPriceAscending
	case 1:
	  newSortType = self.reactor.currentState.sortBy == .previousDayAscending
	  ? .previousDayDescending : .previousDayAscending
	case 2:
	  newSortType = self.reactor.currentState.sortBy == .tradeVolumeAscending
	  ? .tradeVolumeDescending : .tradeVolumeAscending
	default:
	  break
	}
    
    guard let newSortType = newSortType else { return }
    self.reactor.action.onNext(.setSortType(sortBy: newSortType))
    
    let sortedTitle = self.reactor.currentState.sortBy.rawValue
    sender.setTitle(sortedTitle , for: .normal)
    sender.isSelected = true
    self.prevSortedButton = sender
  }
  
  @objc private func tapOnKeyboardDismissButton(_ sender: UIButton) {
  }
  
  func setTabButton() {
    self.krwButton.addTarget(
      self, action: #selector(tapOnTabButton(_:)), for: .touchUpInside
    )
    self.btcButton.addTarget(
      self, action: #selector(tapOnTabButton(_:)), for: .touchUpInside
    )
    self.favoriteButton.addTarget(
      self, action: #selector(tapOnTabButton(_:)), for: .touchUpInside
    )
  }
  
  @objc private func tapOnTabButton(_ sender: UIButton) {
    // 모든 버튼의 선택 상태를 해제
    self.krwButton.isSelected = false
    self.btcButton.isSelected = false
    self.favoriteButton.isSelected = false
    
    sender.isSelected = true
    
    switch sender.tag {
    case 0:
      self.selectedTab = .krw
      self.reactor.action.onNext(.loadCrypto(selectedTab: .krw))
      self.applySnapshot(cellInfos: reactor.currentState.cryptoCellInfo)
    case 1:
      self.selectedTab = .btc
      self.reactor.action.onNext(.loadCrypto(selectedTab: .btc))
      self.applySnapshot(cellInfos: reactor.currentState.cryptoCellInfo)
    case 2:
      self.selectedTab = .favorite
      self.applySnapshot(cellInfos: [])
    default:
      break
    }
  }
  
  /// 특정 텍스트만 색상 변경
  func setUniqueTextColor(
	preTitle: String,
	title: String,
	targetText: String
  ) -> NSAttributedString {
    let attributedTitle = NSMutableAttributedString(string: title)
    
    // 맨 앞 title
    let preRange = (title as NSString).range(of: preTitle)
    attributedTitle.addAttribute(
      .foregroundColor,
      value: UIColor.blue,
      range: preRange
    )
    
    // 끝 글자인 "↓↑" 부분에 대한 색상 변경
    let range = (title as NSString).range(of: targetText)
    attributedTitle.addAttribute(
      .foregroundColor,
      value: UIColor.blue,
      range: range
    )
    
    return attributedTitle
  }
  
  /// UISearchBar 설정
  func setSearchBar() {
    if let searchTextField = self.searchBar.value(
      forKey: "searchField"
    ) as? UISearchTextField {
      searchTextField.do {
        $0.backgroundColor = .clear
        $0.textColor = .black
        $0.attributedPlaceholder = NSAttributedString(
          string: "코인명/심볼 검색",
          attributes: [NSAttributedString.Key.foregroundColor: UIColor.lightGray]
        )
      }
    }
	self.searchBar.delegate = self
  }
  
  /// FlexItem 설정
  func setUpFlexItems() {
    rootContainer.flex
      .justifyContent(.start)
      .direction(.column).define { flex in
        flex.addItem(self.searchBar).height(45).width(100%)
        // KRW, BTC, 관심
        flex.addItem().direction(.row).define { flex in
          flex.addItem(self.krwButton).width(25%)
          flex.addItem(self.btcButton).width(25%)
          flex.addItem(self.favoriteButton).width(25%)
        }.height(40)
        flex.addItem(DividerLineView()).height(1)
        flex.addItem().direction(.row).justifyContent(.end).define { flex in
          flex.addItem(self.currentPriceButton).width(25%)
          flex.addItem(self.previousDayButton).width(25%)
          flex.addItem(self.tradingVolumeButton).width(25%)
        }
        flex.addItem(DividerLineView()).height(1)
        flex.addItem(self.tableView).grow(1)
    }
  }
}

// MARK: Reactor - View
extension MainViewController: View {
  func bind(reactor: MainReactor) {
    
    reactor.state.map { $0.cryptoCellInfo }
      .distinctUntilChanged()
      .observe(on: MainScheduler.instance)
      .subscribe(onNext: { cellInfos in
        if self.isSocketUpdating == false {
		  if let searchText = self.searchBar.text?.lowercased(), !searchText.isEmpty {
			let filteredArray = cellInfos.filter {
			  $0.market.lowercased().contains(searchText) ||
			  $0.cryptoName.lowercased().contains(searchText.lowercased())
			}
			self.applySnapshot(cellInfos: filteredArray)
		  } else {
			self.applySnapshot(cellInfos: cellInfos)
		  }
        }
      })
      .disposed(by: self.disposeBag)
  }
}

// MARK: TableView Delegate
extension MainViewController: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
	self.reactor.action.onNext(.disconnectSocket)
	
	var cryptoCellInfo = reactor.currentState.cryptoCellInfo
	
	if let searchText = self.searchBar.text, !searchText.isEmpty {
	  cryptoCellInfo = cryptoCellInfo.filter { $0.cryptoName.contains(searchText) }
	}
    self.coordinator?.pushCryptoDetailVC(
      selectCrypto: cryptoCellInfo[indexPath.row]
    )
	
	if let searchText = self.searchBar.text, !searchText.isEmpty {
	  self.searchBar.text = ""
	  self.searchBar.resignFirstResponder()
	}
  }
  
  /// 스크롤 시작되면 소켓 업데이트 일시정지
  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    isSocketUpdating = true
  }
  
  /// 스크롤 끝나면 소켓 업데이트 재개
  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    isSocketUpdating = false
  }
}

extension MainViewController: UISearchBarDelegate {
  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
	let cellInfos = self.reactor.currentState.cryptoCellInfo
	if searchText.isEmpty {
	  self.applySnapshot(cellInfos: cellInfos)
	} else {
	  let filteredArray = cellInfos.filter { $0.cryptoName.contains(searchText) }
	  self.applySnapshot(cellInfos: filteredArray)
	}
  }
  
  func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
	let cellInfos = self.reactor.currentState.cryptoCellInfo
	searchBar.text = nil
	searchBar.resignFirstResponder() // 키보드 내림
	self.applySnapshot(cellInfos: cellInfos)
  }
}

// MARK: - WebSocket Pause & Resume
extension MainViewController: SocketControllable {
  func pauseSocket() {
	self.reactor.socketManager.disconnect(manual: false)
  }
  
  func resumeSocket() {
	self.reactor.socketManager.reconnectIfNeeded()
  }
}
