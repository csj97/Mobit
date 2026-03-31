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
import Network

enum TableViewSection: CaseIterable {
  case main
  case invest
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

class MainViewController: MobitBaseViewController {
  
  weak var coordinator: MainCoordinator?
  var dataSource: UITableViewDiffableDataSource<TableViewSection, CryptoCellInfo>?
  var disposeBag = DisposeBag()
  var reactor: MainReactor
  var isSocketUpdating = false
  var prevSortedButton: UIButton?
  let defaultTitles = ["현재가 ↑↓", "전일대비 ↑↓", "거래대금 ↑↓"]
  
  var selectedTab: SelectedTab = .krw {
	didSet { self.reactor.action.onNext(.setSelectedTab(tab: selectedTab)) }
  }
  
  private let cellIndentifier = "MainCryptoTableViewCell"
  
  init(reactor: MainReactor) {
	self.reactor = reactor
	super.init(nibName: nil, bundle: nil)
  }
  
  required init?(coder: NSCoder) {
	fatalError("init(coder:) has not been implemented")
  }
  
  // MARK: - UI Components
  let rootContainer: UIView = UIView()
  
  let searchBar = UISearchBar().then {
	$0.backgroundColor = .white
	$0.backgroundImage = UIImage()
	$0.translatesAutoresizingMaskIntoConstraints = true
  }
  
  let holdButton: UIButton = UIButton().then {
	$0.setTitle("보유코인", for: .normal)
	$0.titleLabel?.font = UIFont(name: "SUIT-SemiBold", size: 15)
	$0.setTitleColor(.black, for: .normal)
	$0.setTitleColor(.blue, for: .selected)
	$0.tag = 0
  }
  
  let krwButton: UIButton = UIButton().then {
	$0.setTitle("원화마켓", for: .normal)
	$0.titleLabel?.font = UIFont(name: "SUIT-SemiBold", size: 15)
	$0.setTitleColor(.black, for: .normal)
	$0.setTitleColor(.blue, for: .selected)
	$0.isSelected = true
	$0.tag = 1
  }
  
  let btcButton: UIButton = UIButton().then {
	$0.setTitle("BTC마켓", for: .normal)
	$0.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
	$0.setTitleColor(.black, for: .normal)
	$0.setTitleColor(.blue, for: .selected)
	$0.tag = 2
  }
  
  // 관심 버튼
  let favoriteButton: UIButton = UIButton().then {
	$0.setTitle("즐겨찾기", for: .normal)
	$0.titleLabel?.font = UIFont(name: "SUIT-SemiBold", size: 15)
	$0.setTitleColor(.black, for: .normal)
	$0.setTitleColor(.blue, for: .selected)
	$0.tag = 3
  }
  
  // 현재가 기준 정렬 버튼
  let currentPriceButton: UIButton = UIButton().then {
	$0.setTitle("현재가↓↑", for: .normal)
	$0.titleLabel?.font = UIFont(name: "SUIT-SemiBold", size: 12)
	$0.setTitleColor(.gray, for: .normal)
	$0.setTitleColor(.blue, for: .selected)
	$0.tag = 0
  }
  
  // 전일대비
  let previousDayButton: UIButton = UIButton().then {
	$0.setTitle("전일대비↓↑", for: .normal)
	$0.titleLabel?.font = UIFont(name: "SUIT-SemiBold", size: 12)
	$0.setTitleColor(.gray, for: .normal)
	$0.setTitleColor(.blue, for: .selected)
	$0.tag = 1
  }
  
  // 거래대금
  let tradingVolumeButton: UIButton = UIButton().then {
	$0.setTitle("거래대금↓↑", for: .normal)
	$0.titleLabel?.font = UIFont(name: "SUIT-SemiBold", size: 12)
	$0.setTitleColor(.gray, for: .normal)
	$0.setTitleColor(.blue, for: .selected)
	$0.tag = 2
  }
  
  let tableView: UITableView = UITableView().then {
	$0.separatorStyle = .singleLine
	$0.separatorInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
  }
  
  let noFavoriteView: UIView = UIView().then {
	$0.backgroundColor = .white
	$0.isHidden = true
  }
  
  let noFavoriteLabel: UILabel = UILabel().then {
	$0.text = "즐겨찾기 설정된 코인이 없습니다."
	$0.font = UIFont(name: "SUIT-Medium", size: 14)
	$0.textAlignment = .center
	$0.textColor = .black
  }
  
  var networkLostView: NetworkLostView? = nil
  var lottieLoadingView: MobitLottieView? = nil
  
  
  // MARK: - Life Cycle
  
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
	
	// 필요할 때 주석 해제 후, 배포
	// self.reactor.action.onNext(.checkNewVersion)
	
	guard self.selectedTab == .favorite else { return }
	self.updateFavoriteUI()
  }
  
  override func viewDidLoad() {
	super.viewDidLoad()
	self.view.backgroundColor = .white
	
	self.checkNetworkStatus()
	
	// DiffableDataSource 사용을 위해 Hashable하게 데이터 모델이 수정됨에 따라 데이터 안정화를 위한 덮어쓰기 (구버전 사용자 에러 방지)
	let list = UserDataManager.userCryptoList
	UserDataManager.userCryptoList = list
	
	self.addViews()
	self.setSearchBar()
	self.setTableView()
	self.setTabButton()
	self.setButtonGesture()
	self.setUpFlexItems()
	
	self.showLoadingIndicator()
	
	self.bind(reactor: self.reactor)
  }
  
  override func viewDidLayoutSubviews() {
	super.viewDidLayoutSubviews()
	
	rootContainer.pin.all(self.view.pin.safeArea)
	rootContainer.flex.layout()
  }
  
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
	self.view.endEditing(true)
  }
  
  // MARK: - Setup
  func addViews() {
	self.view.addSubview(self.rootContainer)
	self.rootContainer.addSubview(self.searchBar)
	self.rootContainer.addSubview(self.krwButton)
	self.rootContainer.addSubview(self.favoriteButton)
	self.rootContainer.addSubview(self.currentPriceButton)
	self.rootContainer.addSubview(self.previousDayButton)
	self.rootContainer.addSubview(self.tradingVolumeButton)
	self.rootContainer.addSubview(self.tableView)
  }
  
  func setTableView() {
	let nib = UINib(nibName: "MainCryptoTableViewCell", bundle: nil)
	self.tableView.register(nib, forCellReuseIdentifier: self.cellIndentifier)
	self.tableView.keyboardDismissMode = .onDrag
	self.tableView.backgroundColor = .white
	self.tableView.backgroundView = nil
	self.tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 70, right: 0)
	
	self.dataSource = UITableViewDiffableDataSource<TableViewSection, CryptoCellInfo>(
	  tableView: self.tableView
	) { [weak self] (tableView, indexPath, crypto) -> UITableViewCell? in
	  guard let self = self,
			let cell = tableView.dequeueReusableCell(
			  withIdentifier: self.cellIndentifier,
			  for: indexPath
			) as? MainCryptoTableViewCell else {
		return UITableViewCell()
	  }
	  
	  self.hideLoadingIndicator()
	  
	  cell.configure(crypto: crypto, isScrolling: self.isSocketUpdating)
	  cell.selectionStyle = .none
	  return cell
	}
	
	self.dataSource?.defaultRowAnimation = .fade
	self.tableView.dataSource = self.dataSource
	self.tableView.delegate = self
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
  }
  
  @objc private func tapOnSortButton(_ sender: UIButton) {
	
	MobitAnalyticsUtil.sendClickEvent(event: .exchange_sort)
	
	self.resumeSocket()
	
	guard self.reactor.socketManager?.isConnected == true else {
	  self.show(
		alertType: .onlyConfirm,
		title: "오류",
		content: "네트워크 연결이 소실되었습니다.\n앱을 종료 후 다시 실행 해주세요.",
		callBack: nil
	  )
	  return
	}
	
	// 직전 선택 버튼 해제
	if let prevSortedButton = self.prevSortedButton,
	   prevSortedButton !== sender {
	  let title = defaultTitles[prevSortedButton.tag]
	  prevSortedButton.setTitle(title, for: .normal)
	  prevSortedButton.isSelected = false
	}
	
	// 새 정렬 타입 결정
	let newSortType: CryptoSortType? = {
	  switch sender.tag {
	  case 0:
		return self.reactor.currentState.sortBy == .currentPriceAscending
		? .currentPriceDescending : .currentPriceAscending
	  case 1:
		return self.reactor.currentState.sortBy == .previousDayAscending
		? .previousDayDescending : .previousDayAscending
	  case 2:
		return self.reactor.currentState.sortBy == .tradeVolumeAscending
		? .tradeVolumeDescending : .tradeVolumeAscending
	  default:
		return nil
	  }
	}()
	
	guard let newSortType = newSortType else { return }
	
	self.reactor.action.onNext(.setSortType(sortBy: newSortType))
	
	let sortedTitle = self.reactor.currentState.sortBy.rawValue
	sender.setTitle(sortedTitle, for: .normal)
	sender.isSelected = true
	self.prevSortedButton = sender
  }
  
  func setTabButton() {
	self.holdButton.addTarget(
	  self, action: #selector(tapOnTabButton(_:)), for: .touchUpInside
	)
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
	self.holdButton.isSelected = false
	self.krwButton.isSelected = false
	self.btcButton.isSelected = false
	self.favoriteButton.isSelected = false
	
	sender.isSelected = true
	
	guard sender.tag != self.selectedTab.rawValue else { return }
	
	switch sender.tag {
	case 0:
	  self.reactor.action.onNext(.loadUserCryptos)
	  self.selectedTab = .hold
	  self.tableView.isHidden = false
	  self.noFavoriteView.isHidden = true
	  
	case 1:
	  self.selectedTab = .krw
	  self.tableView.isHidden = false
	  self.noFavoriteView.isHidden = true
	  
	case 2:
	  self.selectedTab = .btc
	  self.tableView.isHidden = false
	  self.noFavoriteView.isHidden = true
	  
	case 3:
	  self.selectedTab = .favorite
	  self.updateFavoriteUI()
	  
	default:
	  break
	}
  }
  
  /// UISearchBar 설정
  func setSearchBar() {
	if let searchTextField = self.searchBar.value(
	  forKey: "searchField"
	) as? UISearchTextField {
	  searchTextField.do {
		$0.backgroundColor = .clear
		$0.textColor = .black
		$0.font = UIFont(name: "SUIT-SemiBold", size: 13)
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
		  flex.addItem(self.holdButton).width(25%)
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
		
		flex.addItem().direction(.column).define { flex in
		  flex.addItem(self.tableView).grow(1)
		  
		  flex.addItem(self.noFavoriteView)
			.position(.absolute)
			.top(0).bottom(80).left(0).right(0)
			.justifyContent(.center)
			.alignItems(.center)
			.backgroundColor(.white)
			.define { flex in
			  flex.addItem(self.noFavoriteLabel)
			}
		}.grow(1)
	  }
  }
}

// MARK: - Reactor Binding
extension MainViewController: View {
  
  func bind(reactor: MainReactor) {
	
	// totalCryptoList 변경 감지 → 현재 탭에 맞게 필터링하여 스냅샷 적용
	reactor.state
	  .map { $0.totalCryptoList }
	  .throttle(.milliseconds(100), scheduler: MainScheduler.instance)
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] totalList in
		guard let self = self else { return }
		guard !self.isSocketUpdating else { return }
		
		// 현재 탭 + 검색어에 맞게 필터링
		let filteredList = self.filterListForCurrentTab(totalList: totalList)
		
		// 테이블뷰 업데이트
		self.applySnapshot(cellInfos: filteredList)
		
		// 사용자 매수 목록 업데이트
		self.updateUserCryptoList(from: filteredList)
	  })
	  .disposed(by: self.disposeBag)
	
	// 버전 체크
	reactor.state
	  .map { $0.isVersionDifferent }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] isDiffer in
		if isDiffer {
		  self?.coordinator?.pushNoticeAppUpdateVC()
		}
	  })
	  .disposed(by: self.disposeBag)
  }
  
  /// 현재 탭 + 검색어에 따라 리스트 필터링
  private func filterListForCurrentTab(totalList: [CryptoCellInfo]) -> [CryptoCellInfo] {
	let searchText = self.searchBar.text?.lowercased() ?? ""
	let favoriteMarkets = Set(UserDataManager.userFavoriteList)
	
	var filteredList = totalList
	
	// 1️⃣ 탭별 필터링
	switch self.selectedTab {
	case .hold:
	  let userCryptos = self.reactor.currentState.userCryptos
	  let holdingMarkets = userCryptos.map { $0.staticData.marketName }
	  filteredList = filteredList.filter { holdingMarkets.contains($0.market) }
	  
	case .krw:
	  filteredList = filteredList.filter { $0.market.contains("/KRW") }
	  
	case .btc:
	  filteredList = filteredList.filter { $0.market.contains("/BTC") }
	  
	case .favorite:
	  filteredList = filteredList.filter { favoriteMarkets.contains($0.market) }
	}
	
	// 2️⃣ 검색어 필터링
	if !searchText.isEmpty {
	  filteredList = filteredList.filter {
		$0.market.lowercased().contains(searchText) ||
		$0.cryptoName.lowercased().contains(searchText)
	  }
	}
	
	return filteredList
  }
  
  /// 스냅샷 적용
  private func applySnapshot(cellInfos: [CryptoCellInfo]) {
	DispatchQueue.main.async { [weak self] in
	  guard let self = self else { return }
	  
	  var snapshot = NSDiffableDataSourceSnapshot<TableViewSection, CryptoCellInfo>()
	  snapshot.appendSections([.main])
	  snapshot.appendItems(cellInfos, toSection: .main)
	  
	  self.dataSource?.apply(snapshot, animatingDifferences: false)
	}
  }
  
  /// 사용자 매수 목록 업데이트
  private func updateUserCryptoList(from cellInfos: [CryptoCellInfo]) {
	guard let userCryptoList = UserDataManager.userCryptoList else { return }
	
	let userMarketNames = Set(userCryptoList.map { $0.staticData.marketName })
	
	cellInfos
	  .filter { userMarketNames.contains($0.market) }
	  .forEach { cellInfo in
		self.fetchUserCryptoList(
		  marketName: cellInfo.market,
		  currentPrice: cellInfo.tradePrice
		)
	  }
  }
  
  /// 매수 목록 fetch
  private func fetchUserCryptoList(marketName: String, currentPrice: Double?) {
	guard let updateCryptoIndex = UserDataManager.userCryptoList?
	  .firstIndex(where: { $0.staticData.marketName == marketName }),
		  let currentPrice = currentPrice,
		  let averageBuyPrice = UserDataManager.userCryptoList?[updateCryptoIndex].staticData.averageBuyPrice,
		  let holdingQuantity = UserDataManager.userCryptoList?[updateCryptoIndex].staticData.holdingQuantity
	else { return }
	
	UserDataManager.userCryptoList?[updateCryptoIndex].dynamicData.profitRate =
	MarketDataServiceUtil.shared.fetchProfitRate(
	  for: marketName,
	  currentPrice: currentPrice,
	  averageBuyPrice: averageBuyPrice
	)
	
	UserDataManager.userCryptoList?[updateCryptoIndex].dynamicData.evaluationPrice =
	MarketDataServiceUtil.shared.fetchEvalPrice(
	  for: marketName,
	  currentPrice: currentPrice,
	  holdingQuantity: holdingQuantity
	)
	
	UserDataManager.userCryptoList?[updateCryptoIndex].dynamicData.evaluationProfitLoss =
	MarketDataServiceUtil.shared.fetchEvalProfitLoss(
	  for: marketName,
	  currentPrice: currentPrice,
	  holdingQuantity: holdingQuantity,
	  averageBuyPrice: averageBuyPrice
	)
  }
  
  /// 즐겨찾기 UI 업데이트
  private func updateFavoriteUI() {
	let favoriteMarketNames = UserDataManager.userFavoriteList
	let favoriteCellInfos = self.reactor.currentState.totalCryptoList.filter {
	  favoriteMarketNames.contains($0.market)
	}
	
	if favoriteCellInfos.isEmpty {
	  self.tableView.isHidden = true
	  self.noFavoriteView.isHidden = false
	} else {
	  self.tableView.isHidden = false
	  self.noFavoriteView.isHidden = true
	  self.applySnapshot(cellInfos: favoriteCellInfos)
	}
  }
}

// MARK: - TableView Delegate
extension MainViewController: UITableViewDelegate {
  
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
	
	// ⭐️ 현재 화면에 표시 중인 리스트 가져오기
	let displayedList = self.filterListForCurrentTab(
	  totalList: reactor.currentState.totalCryptoList
	)
	
	guard indexPath.row < displayedList.count else { return }
	
	let selectedCrypto = displayedList[indexPath.row]
	let symbol = selectedCrypto.market.replacingOccurrences(
	  of: "/(KRW|BTC)",
	  with: "",
	  options: .regularExpression
	)
	
	self.coordinator?.pushCryptoDetailVC(
	  selectCrypto: selectedCrypto,
	  cmcSymbol: symbol,
	  completion: { [weak self] errorMsg in
		guard let self = self else { return }
		
		if let errorMsg = errorMsg {
		  self.show(
			alertType: .onlyConfirm,
			title: "안내",
			content: errorMsg,
			callBack: nil
		  )
		} else {
		  if let searchText = self.searchBar.text, !searchText.isEmpty {
			self.searchBar.text = ""
			self.searchBar.resignFirstResponder()
		  }
		  self.reactor.action.onNext(.disconnectSocket)
		}
	  }
	)
  }
  
  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
	isSocketUpdating = true
  }
  
  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
	isSocketUpdating = false
  }
}


// MARK: - UISearchBarDelegate

extension MainViewController: UISearchBarDelegate {
  
  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
	// ⭐️ 검색어가 변경되면 자동으로 필터링됨 (bind에서 처리)
	let filteredList = self.filterListForCurrentTab(
	  totalList: reactor.currentState.totalCryptoList
	)
	self.applySnapshot(cellInfos: filteredList)
  }
  
  func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
	searchBar.text = nil
	searchBar.resignFirstResponder()
	
	let filteredList = self.filterListForCurrentTab(
	  totalList: reactor.currentState.totalCryptoList
	)
	self.applySnapshot(cellInfos: filteredList)
  }
}

// MARK: - WebSocket Pause & Resume
extension MainViewController: SocketControllable {
  
  func pauseSocket() {
	self.reactor.socketManager?.disconnect()
  }
  
  func resumeSocket() {
	guard self.reactor.socketManager?.isConnected == false else { return }
	self.reactor.socketManager?.reconnectIfNeeded()
	self.reactor.action.onNext(.loadCryptoList)
	self.reactor.action.onNext(.loadUserCryptos)
  }
}

// MARK: - Network Monitoring
extension MainViewController {
  
  func checkNetworkStatus() {
	NotificationCenter.default.addObserver(
	  self,
	  selector: #selector(networkStatusChanged(_:)),
	  name: .networkStatusChanged,
	  object: nil
	)
  }
  
  /// 네트워크 상태 점검
  @objc private func networkStatusChanged(_ notification: Notification) {
	guard let userInfo = notification.userInfo,
		  let isConnected = userInfo["isConnected"] as? Bool else { return }
	
	if !isConnected {
	  // 🚨 네트워크 완전 유실 상태
	  showNetworkLostView()
	} else {
	  // ✅ 네트워크 복구됨
	  hideNetworkLostView()
	}
  }
  
  /// 네트워크 유실 화면 노출
  private func showNetworkLostView() {
	
	// 중복 생성 방지
	if self.networkLostView != nil { return }
	
	self.networkLostView = NetworkLostView()
	guard let networkLostView = self.networkLostView else { return }
	
	networkLostView.configure()
	view.addSubview(networkLostView)
	
	networkLostView.snp.makeConstraints { make in
	  make.edges.equalToSuperview()
	}
  }
  
  /// 네트워크 유실 화면 제거
  private func hideNetworkLostView() {
	guard let networkLostView = self.networkLostView else { return }
	networkLostView.removeFromSuperview()
	self.networkLostView = nil
  }
}
