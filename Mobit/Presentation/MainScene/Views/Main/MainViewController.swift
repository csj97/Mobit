//
//  MainViewController.swift
//  Mobit
//
//  Created by 조성재 on 7/16/24.
//

import FlexLayout
import GoogleMobileAds
import RxCocoa
import RxSwift
import ReactorKit
import PinLayout
import Then
import UIKit
import Network
import SnapKit

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
  // 보유 탭 전용 (표시 시점 정렬)
  case evaluationPriceAscending = "평가금액↑"
  case evaluationPriceDescending = "평가금액↓"
  case averageBuyPriceAscending = "평균매수가↑"
  case averageBuyPriceDescending = "평균매수가↓"
  case profitRateAscending = "수익률↑"
  case profitRateDescending = "수익률↓"
}

/// FlexLayout이 leaf로 측정할 때 내부 Auto Layout 콘텐츠 높이를 돌려주는 컨테이너.
/// (기본 UIView.sizeThatFits는 Auto Layout 크기를 반영하지 않아 고정 높이가 필요해진다)
final class SelfSizingContentView: UIView {
  override func sizeThatFits(_ size: CGSize) -> CGSize {
	let targetWidth = size.width.isFinite && size.width > 0
	  ? size.width : UIView.layoutFittingCompressedSize.width
	let fitting = systemLayoutSizeFitting(
	  CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height),
	  withHorizontalFittingPriority: .required,
	  verticalFittingPriority: .fittingSizeLevel
	)
	return CGSize(width: size.width, height: fitting.height)
  }
}

class MainViewController: MobitBaseViewController {
  
  weak var coordinator: MainCoordinator?
  var dataSource: UITableViewDiffableDataSource<TableViewSection, CryptoCellInfo>?
  var disposeBag = DisposeBag()
  var reactor: MainReactor
  var isSocketUpdating = false
  var prevSortedButton: UIButton?
  let defaultTitles = ["현재가 ↑↓", "전일대비 ↑↓", "거래대금 ↑↓"]
  // 보유 탭 전용 헤더/정렬 상태 (마켓 정렬과 독립적으로 관리)
  let holdDefaultTitles = ["평가금액 ↑↓", "평균매수가 ↑↓", "수익률 ↑↓"]
  private var holdSortBy: CryptoSortType = .normal
  private let mainNativeAdLastShownDateKey = "main_native_ad_popup_last_shown_date"
  private var hasRequestedMainNativeAd = false
  private var isLoadingMainNativeAd = false
  private var mainNativeAd: NativeAd?
  private var mainAdLoader: AdLoader?
  
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

  // FlexLayout이 내부 Auto Layout 콘텐츠 높이를 스스로 측정하도록 SelfSizingContentView 사용
  private let portfolioSummaryView = SelfSizingContentView().then {
	$0.backgroundColor = UIColor.mobitColors(.white_FBFBFB)
  }

  private let totalBalanceTitleLabel: UILabel = UILabel().then {
	$0.text = "총매수"
	$0.font = UIFont(name: "SUIT-Medium", size: 12)
	$0.textColor = .darkGray
  }

  private let totalBalanceLabel: UILabel = UILabel().then {
	$0.text = "0"
	$0.font = UIFont(name: "SUIT-SemiBold", size: 12)
	$0.textColor = .black
	$0.textAlignment = .right
	$0.adjustsFontSizeToFitWidth = true
	$0.minimumScaleFactor = 0.3
  }

  private let summaryVerticalDividerView: UIView = UIView().then {
	$0.backgroundColor = UIColor.mobitColors(.lineLightGray)
  }

  private let profitLossTitleLabel: UILabel = UILabel().then {
	$0.text = "평가손익"
	$0.font = UIFont(name: "SUIT-Medium", size: 12)
	$0.textColor = .darkGray
  }

  private let profitLossValueLabel: UILabel = UILabel().then {
	$0.text = "0"
	$0.font = UIFont(name: "SUIT-SemiBold", size: 12)
	$0.textColor = .black
	$0.textAlignment = .right
	$0.adjustsFontSizeToFitWidth = true
	$0.minimumScaleFactor = 0.4
  }

  private let evaluationPriceTitleLabel: UILabel = UILabel().then {
	$0.text = "총평가"
	$0.font = UIFont(name: "SUIT-Medium", size: 12)
	$0.textColor = .darkGray
  }

  private let evaluationPriceValueLabel: UILabel = UILabel().then {
	$0.text = "0"
	$0.font = UIFont(name: "SUIT-SemiBold", size: 12)
	$0.textColor = .black
	$0.textAlignment = .right
	$0.adjustsFontSizeToFitWidth = true
	$0.minimumScaleFactor = 0.3
  }

  private let profitRateTitleLabel: UILabel = UILabel().then {
	$0.text = "수익률"
	$0.font = UIFont(name: "SUIT-Medium", size: 12)
	$0.textColor = .darkGray
  }

  private let profitRateValueLabel: UILabel = UILabel().then {
	$0.text = "0 %"
	$0.font = UIFont(name: "SUIT-SemiBold", size: 12)
	$0.textColor = .black
	$0.textAlignment = .right
	$0.adjustsFontSizeToFitWidth = true
	$0.minimumScaleFactor = 0.4
  }
  
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
  
  // 우측 하단 플로팅 버튼: 탭하면 공포·탐욕 지수 바텀시트를 띄운다
  private let fearGreedFloatingButton: UIButton = UIButton().then {
	$0.backgroundColor = .white
	$0.layer.cornerRadius = 28
	// 떠 있는 듯한 입체 음영
	$0.layer.applyShadow(color: .black, alpha: 0.25, x: 0, y: 4, blur: 12)

	let font = UIFont(name: "SUIT-Bold", size: 12) ?? .systemFont(ofSize: 12, weight: .bold)
	let paragraph = NSMutableParagraphStyle()
	paragraph.alignment = .center
	// 공포=파랑 / 탐욕=빨강 (앱 관례, 게이지와 동일)
	let title = NSMutableAttributedString(
	  string: "공포\n",
	  attributes: [.foregroundColor: UIColor(hex: "#4C6EF5"), .font: font, .paragraphStyle: paragraph]
	)
	title.append(NSAttributedString(
	  string: "탐욕",
	  attributes: [.foregroundColor: UIColor(hex: "#FA5252"), .font: font, .paragraphStyle: paragraph]
	))
	$0.titleLabel?.numberOfLines = 2
	$0.titleLabel?.textAlignment = .center
	$0.setAttributedTitle(title, for: .normal)
	$0.accessibilityLabel = "공포·탐욕 지수"
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
	self.updatePortfolioSummary()
	
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
	self.setPortfolioSummaryView()
	self.setSearchBar()
	self.setTableView()
	self.setTabButton()
	self.setButtonGesture()
	self.setUpFlexItems()
	self.setFearGreedFloatingButton()

	self.showLoadingIndicator()
	
	self.bind(reactor: self.reactor)

	// 공포·탐욕 지수는 하루 단위 갱신이므로 진입 시 1회만 조회
	self.reactor.action.onNext(.loadFearGreedIndex)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    self.requestMainNativeAdIfNeeded()
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
	self.rootContainer.addSubview(self.portfolioSummaryView)
	self.rootContainer.addSubview(self.krwButton)
	self.rootContainer.addSubview(self.favoriteButton)
	self.rootContainer.addSubview(self.currentPriceButton)
	self.rootContainer.addSubview(self.previousDayButton)
	self.rootContainer.addSubview(self.tradingVolumeButton)
	self.rootContainer.addSubview(self.tableView)
  }

  func setPortfolioSummaryView() {
	let totalBalanceRow = makeSummaryRow(
	  titleLabel: totalBalanceTitleLabel,
	  valueLabel: totalBalanceLabel
	)
	let evaluationPriceRow = makeSummaryRow(
	  titleLabel: evaluationPriceTitleLabel,
	  valueLabel: evaluationPriceValueLabel
	)
	let profitLossRow = makeSummaryRow(
	  titleLabel: profitLossTitleLabel,
	  valueLabel: profitLossValueLabel
	)
	let profitRateRow = makeSummaryRow(
	  titleLabel: profitRateTitleLabel,
	  valueLabel: profitRateValueLabel
	)

	let leftColumnStack = UIStackView(arrangedSubviews: [
	  totalBalanceRow,
	  evaluationPriceRow
	])
	leftColumnStack.axis = .vertical
	leftColumnStack.spacing = 5

	let rightColumnStack = UIStackView(arrangedSubviews: [
	  profitLossRow,
	  profitRateRow
	])
	rightColumnStack.axis = .vertical
	rightColumnStack.spacing = 5

	let contentStack = UIStackView(arrangedSubviews: [
	  leftColumnStack,
	  summaryVerticalDividerView,
	  rightColumnStack
	])
	contentStack.axis = .horizontal
	contentStack.alignment = .fill
	contentStack.distribution = .fill
	contentStack.spacing = 14

	self.portfolioSummaryView.addSubview(contentStack)

	contentStack.snp.makeConstraints { make in
	  make.top.equalToSuperview().offset(10)
	  make.leading.equalToSuperview().inset(14)
	  // FlexLayout이 폭을 정하기 전(초기 width 0) 순간 충돌 로그를 피하려 trailing만 양보 가능하게 둔다.
	  make.trailing.equalToSuperview().inset(14).priority(999)
	  make.bottom.equalToSuperview().offset(-10)
	}

	leftColumnStack.snp.makeConstraints { make in
	  make.width.equalTo(rightColumnStack)
	}

	summaryVerticalDividerView.snp.makeConstraints { make in
	  make.width.equalTo(1)
	}

	self.updatePortfolioSummary()
  }

  private func makeSummaryRow(
	titleLabel: UILabel,
	valueLabel: UILabel
  ) -> UIStackView {
	let stackView = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
	stackView.axis = .horizontal
	stackView.alignment = .center
	stackView.distribution = .fill
	stackView.spacing = 8
	return stackView
  }

  private func updatePortfolioSummary(
	cryptos: [CryptoTransactionDataModel]? = UserDataManager.userCryptoList
  ) {
	let cryptos = cryptos ?? []
	let availableBalance = UserDataManager.userInformation?.userAvailableBalance ?? 0
	let totalBalance = PortfolioCalculator.totalAssetValue(
	  availableBalance: availableBalance,
	  cryptos: cryptos
	)
	let totalBuyAmount = PortfolioCalculator.totalBuyAmount(cryptos: cryptos)
	let totalProfitLoss = PortfolioCalculator.totalEvaluationProfitLoss(cryptos: cryptos)
	let totalEvaluationPrice = PortfolioCalculator.totalEvaluationPrice(cryptos: cryptos)
	let totalProfitRate = PortfolioCalculator.totalProfitRate(
	  totalProfitLoss: totalProfitLoss,
	  totalAssetValue: totalBalance
	)

	self.totalBalanceLabel.attributedText = self.attributedKRWAmount(self.formattedKRW(totalBuyAmount))
	self.profitLossValueLabel.attributedText = self.attributedKRWAmount(self.formattedSignedKRW(totalProfitLoss, includeUnit: false))
	self.evaluationPriceValueLabel.attributedText = self.attributedKRWAmount(self.formattedKRW(totalEvaluationPrice))
	self.profitRateValueLabel.text = self.formattedSignedPercent(totalProfitRate)
	self.profitLossValueLabel.textColor = self.portfolioValueColor(totalProfitLoss)
	self.profitRateValueLabel.textColor = self.portfolioValueColor(totalProfitRate)
  }

  private func formattedKRW(_ value: Double) -> String {
	value == 0 ? "0" : abs(value).formatSignificantDigits(digits: 0)
  }

  // 금액 뒤에 작은 '원' 단위를 붙인다. 숫자는 라벨 기본 색/폰트 유지, '원'만 작게 회색 처리
  private func attributedKRWAmount(_ amountText: String) -> NSAttributedString {
	let numberFont = UIFont(name: "SUIT-SemiBold", size: 12) ?? .systemFont(ofSize: 12, weight: .semibold)
	let unitFont = UIFont(name: "SUIT-Medium", size: 9) ?? .systemFont(ofSize: 9)
	let result = NSMutableAttributedString(string: amountText, attributes: [.font: numberFont])
	result.append(NSAttributedString(
	  string: " 원",
	  attributes: [.font: unitFont, .foregroundColor: UIColor.darkGray]
	))
	return result
  }

  private func formattedSignedKRW(_ value: Double, includeUnit: Bool = true) -> String {
	guard value != 0 else { return includeUnit ? "0 KRW" : "0" }
	let prefix = value > 0 ? "+" : "-"
	let formattedValue = "\(prefix)\(self.formattedKRW(value))"
	return includeUnit ? "\(formattedValue) KRW" : formattedValue
  }

  private func formattedSignedPercent(_ value: Double) -> String {
	guard value != 0 else { return "0 %" }
	let prefix = value > 0 ? "+" : "-"
	let formattedValue = abs(value).formatSignificantDigits(digits: 2)
	return "\(prefix)\(formattedValue) %"
  }

  private func portfolioValueColor(_ value: Double) -> UIColor {
	MarketColorPalette.color(forSignedValue: value)
  }
  
  func setTableView() {
	let nib = UINib(nibName: "MainCryptoTableViewCell", bundle: nil)
	self.tableView.register(nib, forCellReuseIdentifier: self.cellIndentifier)
	self.tableView.register(
	  MainHoldingTableViewCell.self,
	  forCellReuseIdentifier: MainHoldingTableViewCell.reuseIdentifier
	)
	self.tableView.keyboardDismissMode = .onDrag
	self.tableView.backgroundColor = .white
	self.tableView.backgroundView = nil
	// 하단 탭바에 마지막 행이 가리지 않도록 여백 확보
	self.tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 70, right: 0)
	
	self.dataSource = UITableViewDiffableDataSource<TableViewSection, CryptoCellInfo>(
	  tableView: self.tableView
	) { [weak self] (tableView, indexPath, crypto) -> UITableViewCell? in
	  guard let self = self else { return UITableViewCell() }

	  // 보유 탭은 전용 셀(평가금액·보유량/평균매수가/수익률·평가손익)
	  if self.selectedTab == .hold {
		guard let cell = tableView.dequeueReusableCell(
		  withIdentifier: MainHoldingTableViewCell.reuseIdentifier,
		  for: indexPath
		) as? MainHoldingTableViewCell else { return UITableViewCell() }
		cell.configure(crypto: crypto)
		return cell
	  }

	  guard let cell = tableView.dequeueReusableCell(
		withIdentifier: self.cellIndentifier,
		for: indexPath
	  ) as? MainCryptoTableViewCell else { return UITableViewCell() }

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
	self.resumeSocket()

	let isHold = (self.selectedTab == .hold)
	let titles = isHold ? holdDefaultTitles : defaultTitles

	// 직전 선택 버튼 해제
	if let prevSortedButton = self.prevSortedButton,
	   prevSortedButton !== sender {
	  prevSortedButton.setTitle(titles[prevSortedButton.tag], for: .normal)
	  prevSortedButton.isSelected = false
	}

	// 오름↑ → 내림↓ → 초기(.normal) 3단계 순환
	let (ascending, descending) = self.sortTypes(forButtonTag: sender.tag, isHold: isHold)
	let current = isHold ? self.holdSortBy : self.reactor.currentState.sortBy
	let newSortType: CryptoSortType
	if current == ascending {
	  newSortType = descending
	} else if current == descending {
	  newSortType = .normal
	} else {
	  newSortType = ascending
	}

	// 적용: 보유는 표시 시점 정렬(리액터 미변경), 마켓은 기존 리액터 정렬
	if isHold {
	  self.holdSortBy = newSortType
	  self.refreshDisplayedList()
	} else {
	  self.reactor.action.onNext(.setSortType(sortBy: newSortType))
	}

	MobitAnalyticsUtil.sendClickEvent(event: .exchange_sort)
	MobitAnalyticsUtil.sendClickEvent(
	  location: "거래소_화면",
	  stepDepth01: "\(self.analyticsTabName(self.selectedTab))_탭",
	  stepDepth02: "정렬_변경",
	  stepDepth03: "\(self.analyticsSortCriterion(forButtonTag: sender.tag, isHold: isHold))_\(self.analyticsSortDirection(for: newSortType))",
	  extraParameters: [
		"selected_tab": self.analyticsTabName(self.selectedTab),
		"sort_criterion": self.analyticsSortCriterion(forButtonTag: sender.tag, isHold: isHold),
		"sort_direction": self.analyticsSortDirection(for: newSortType),
		"sort_label": newSortType == .normal ? "기본순서" : newSortType.rawValue
	  ]
	)

	// 버튼 비주얼 (초기 순서면 기본 상태로 리셋)
	if newSortType == .normal {
	  sender.setTitle(titles[sender.tag], for: .normal)
	  sender.isSelected = false
	  self.prevSortedButton = nil
	} else {
	  sender.setTitle(newSortType.rawValue, for: .normal)
	  sender.isSelected = true
	  self.prevSortedButton = sender
	}
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
	  self.refreshDisplayedList()
	  
	case 1:
	  self.selectedTab = .krw
	  self.refreshDisplayedList()
	  
	case 2:
	  self.selectedTab = .btc
	  self.refreshDisplayedList()
	  
	case 3:
	  self.selectedTab = .favorite
	  self.refreshDisplayedList()

	default:
	  break
	}

	MobitAnalyticsUtil.sendClickEvent(
	  location: "거래소_화면",
	  stepDepth01: "메인_탭",
	  stepDepth02: "탭_선택",
	  stepDepth03: self.analyticsTabName(self.selectedTab),
	  extraParameters: ["selected_tab": self.analyticsTabName(self.selectedTab)]
	)

	// 탭별 정렬 상태에 맞춰 헤더(정렬 버튼) 복원
	self.updateSortHeaderUI()
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

		flex.addItem(self.portfolioSummaryView)
		  .marginTop(4)
		  .marginBottom(6)

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
		  flex.backgroundColor(.whiteFBFBFB)
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

  private func setFearGreedFloatingButton() {
	self.view.addSubview(self.fearGreedFloatingButton)
	self.fearGreedFloatingButton.snp.makeConstraints { make in
	  make.trailing.equalTo(self.view.safeAreaLayoutGuide).offset(-16)
	  // 하단 탭바(65pt) 위에 띄운다
	  make.bottom.equalTo(self.view.safeAreaLayoutGuide).offset(-(65 + 16))
	  make.width.height.equalTo(56)
	}
	self.fearGreedFloatingButton.addTarget(
	  self, action: #selector(didTapFearGreedButton), for: .touchUpInside
	)
  }

  @objc private func didTapFearGreedButton() {
	let levelTitle = self.analyticsFearGreedLevelTitle()
	MobitAnalyticsUtil.sendClickEvent(
	  location: "거래소_화면",
	  stepDepth01: "메인_플로팅버튼",
	  stepDepth02: "공포탐욕_설명_열기",
	  stepDepth03: levelTitle,
	  extraParameters: [
		"fear_greed_level": levelTitle,
		"fear_greed_value": self.reactor.currentState.fearGreedIndex?.value ?? -1
	  ]
	)
	self.coordinator?.presentFearGreedInfoVC(
	  fearGreedIndex: self.reactor.currentState.fearGreedIndex
	)
  }
}

private extension MainViewController {
  func analyticsTabName(_ tab: SelectedTab) -> String {
	switch tab {
	case .hold: return "보유코인"
	case .krw: return "원화마켓"
	case .btc: return "BTC마켓"
	case .favorite: return "즐겨찾기"
	}
  }

  func analyticsSortCriterion(forButtonTag tag: Int, isHold: Bool) -> String {
	if isHold {
	  switch tag {
	  case 0: return "평가금액"
	  case 1: return "평균매수가"
	  case 2: return "수익률"
	  default: return "알수없음"
	  }
	}

	switch tag {
	case 0: return "현재가"
	case 1: return "전일대비"
	case 2: return "거래대금"
	default: return "알수없음"
	}
  }

  func analyticsSortDirection(for sortType: CryptoSortType) -> String {
	switch sortType {
	case .normal:
	  return "기본순서"
	case .currentPriceAscending,
		.previousDayAscending,
		.tradeVolumeAscending,
		.evaluationPriceAscending,
		.averageBuyPriceAscending,
		.profitRateAscending:
	  return "오름차순"
	case .currentPriceDescending,
		.previousDayDescending,
		.tradeVolumeDescending,
		.evaluationPriceDescending,
		.averageBuyPriceDescending,
		.profitRateDescending:
	  return "내림차순"
	}
  }

  func analyticsFearGreedLevelTitle() -> String {
	guard let value = self.reactor.currentState.fearGreedIndex?.value else {
	  return "데이터없음"
	}
	return FearGreedLevel(value: value).title
  }
}

// MARK: - Main Native Ad
extension MainViewController {
  private func requestMainNativeAdIfNeeded() {
    guard self.hasRequestedMainNativeAd == false else { return }
    self.hasRequestedMainNativeAd = true

    let defaults = UserDefaults.standard
    let todayKey = self.mainNativeAdTodayKey()
    let lastShownDate = defaults.string(forKey: self.mainNativeAdLastShownDateKey)

    if lastShownDate == todayKey {
      return
    }

    self.loadMainNativeAd()
  }

  private func mainNativeAdTodayKey() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
  }

  private func loadMainNativeAd() {
    guard self.isLoadingMainNativeAd == false else { return }
    self.isLoadingMainNativeAd = true
    self.mainNativeAd = nil
    self.mainAdLoader?.delegate = nil
    self.mainAdLoader = nil

    let options = NativeAdViewAdOptions()
    let multipleOptions = MultipleAdsAdLoaderOptions()
    multipleOptions.numberOfAds = 1

    let adLoader = AdLoader(
      adUnitID: MobitConstants.nativeAdType,
      rootViewController: self,
      adTypes: [.native],
      options: [options, multipleOptions]
    )
    self.mainAdLoader = adLoader
    adLoader.delegate = self
    adLoader.load(Request())
  }

  private func presentMainNativeAdIfNeeded() {
    guard let ad = self.mainNativeAd else { return }
    guard self.presentedViewController == nil else { return }
    guard self.view.window != nil else { return }

    let popup = MainNativeAdPopupViewController(ad: ad) { [weak self] in
      self?.mainNativeAd = nil
    }
    popup.modalPresentationStyle = .overFullScreen
    popup.modalTransitionStyle = .crossDissolve
    self.present(popup, animated: true)
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
		
		self.updateUserCryptoList(from: totalList)
		
		// 현재 탭 + 검색어에 맞게 필터링
		let filteredList = self.filterListForCurrentTab(totalList: totalList)
		
		// 테이블뷰 업데이트
		self.applySnapshot(cellInfos: filteredList)
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
	
	reactor.state
	  .map { $0.isLoading }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] isLoading in
		guard let self = self else { return }
		isLoading ? self.showLoadingIndicator() : self.hideLoadingIndicator()
	  })
	  .disposed(by: self.disposeBag)
	
	reactor.state
	  .map { $0.errorMessage }
	  .distinctUntilChanged { $0 == $1 }
	  .compactMap { $0 }
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] message in
		guard let self = self else { return }
		self.show(
		  alertType: .onlyConfirm,
		  title: "안내",
		  content: message,
		  callBack: nil
		)
		self.reactor.action.onNext(.clearErrorMessage)
	  })
	  .disposed(by: self.disposeBag)

	reactor.state
	  .map { $0.userCryptos }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] _ in
		guard let self = self else { return }
		self.updatePortfolioSummary()
		guard self.selectedTab == .hold else { return }
		self.refreshDisplayedList()
	  })
	  .disposed(by: self.disposeBag)

	UserDataManager.userAvailableBalanceObservable
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] _ in
		self?.updatePortfolioSummary()
	  })
	  .disposed(by: self.disposeBag)
  }
  
  /// 현재 탭 + 검색어에 따라 리스트 필터링
  private func filterListForCurrentTab(totalList: [CryptoCellInfo]) -> [CryptoCellInfo] {
	let searchText = self.searchBar.text?.lowercased() ?? ""
	let favoriteMarkets = Set(UserDataManager.userFavoriteList)
	
	var filteredList = totalList
	
	// 1. 탭별 필터링
	switch self.selectedTab {
	case .hold:
	  // 보유 코인만 남기고, 보유데이터(보유량/평단/평가금액/수익률)를 표시 시세 기준으로 채운다.
	  let holdingByMarket = Dictionary(
		self.reactor.currentState.userCryptos.map { ($0.staticData.marketName, $0) },
		uniquingKeysWith: { first, _ in first }
	  )
	  filteredList = filteredList.compactMap { cell in
		guard let holding = holdingByMarket[cell.market] else { return nil }
		var enriched = cell
		let qty = holding.staticData.holdingQuantity
		let avg = holding.staticData.averageBuyPrice
		enriched.holdingQuantity = qty
		enriched.averageBuyPrice = avg
		if let price = cell.tradePrice {
		  enriched.evaluationPrice = price * qty
		  enriched.evaluationProfitLoss = (price - avg) * qty
		  enriched.profitRate = avg > 0 ? ((price - avg) / avg) * 100 : 0
		} else {
		  enriched.evaluationPrice = holding.dynamicData.evaluationPrice
		  enriched.evaluationProfitLoss = holding.dynamicData.evaluationProfitLoss
		  enriched.profitRate = holding.dynamicData.profitRate
		}
		return enriched
	  }

	case .krw:
	  filteredList = filteredList.filter { $0.market.contains("/KRW") }
	  
	case .btc:
	  filteredList = filteredList.filter { $0.market.contains("/BTC") }
	  
	case .favorite:
	  filteredList = filteredList.filter { favoriteMarkets.contains($0.market) }
	}
	
	// 2. 검색어 필터링
	if !searchText.isEmpty {
	  filteredList = filteredList.filter {
		$0.market.lowercased().contains(searchText) ||
		$0.cryptoName.lowercased().contains(searchText)
	  }
	}

	// 3. 보유 탭은 마켓 정렬과 독립적으로 표시 시점에 정렬
	if self.selectedTab == .hold {
	  filteredList = self.sortHoldList(filteredList, by: self.holdSortBy)
	}

	return filteredList
  }

  /// 보유 탭 표시 시점 정렬 (마켓 정렬과 분리)
  private func sortHoldList(_ list: [CryptoCellInfo], by sortType: CryptoSortType) -> [CryptoCellInfo] {
	switch sortType {
	case .evaluationPriceAscending:  return list.sorted { ($0.evaluationPrice ?? 0) < ($1.evaluationPrice ?? 0) }
	case .evaluationPriceDescending: return list.sorted { ($0.evaluationPrice ?? 0) > ($1.evaluationPrice ?? 0) }
	case .averageBuyPriceAscending:  return list.sorted { ($0.averageBuyPrice ?? 0) < ($1.averageBuyPrice ?? 0) }
	case .averageBuyPriceDescending: return list.sorted { ($0.averageBuyPrice ?? 0) > ($1.averageBuyPrice ?? 0) }
	case .profitRateAscending:       return list.sorted { ($0.profitRate ?? 0) < ($1.profitRate ?? 0) }
	case .profitRateDescending:      return list.sorted { ($0.profitRate ?? 0) > ($1.profitRate ?? 0) }
	default:
	  // 초기 순서: 보유 목록 순서 기준 (마켓 정렬 영향 없음)
	  let order = Dictionary(
		self.reactor.currentState.userCryptos.enumerated().map { ($1.staticData.marketName, $0) },
		uniquingKeysWith: { first, _ in first }
	  )
	  return list.sorted { (order[$0.market] ?? Int.max) < (order[$1.market] ?? Int.max) }
	}
  }

  /// 버튼 태그 → (오름, 내림) 정렬 타입 (탭에 따라 마켓/보유 컬럼)
  private func sortTypes(forButtonTag tag: Int, isHold: Bool) -> (CryptoSortType, CryptoSortType) {
	if isHold {
	  switch tag {
	  case 0: return (.evaluationPriceAscending, .evaluationPriceDescending)
	  case 1: return (.averageBuyPriceAscending, .averageBuyPriceDescending)
	  case 2: return (.profitRateAscending, .profitRateDescending)
	  default: return (.normal, .normal)
	  }
	} else {
	  switch tag {
	  case 0: return (.currentPriceAscending, .currentPriceDescending)
	  case 1: return (.previousDayAscending, .previousDayDescending)
	  case 2: return (.tradeVolumeAscending, .tradeVolumeDescending)
	  default: return (.normal, .normal)
	  }
	}
  }

  /// 현재 탭의 정렬 상태에 맞춰 헤더(정렬 버튼) 타이틀·선택 상태를 복원한다.
  private func updateSortHeaderUI() {
	let isHold = (self.selectedTab == .hold)
	let titles = isHold ? holdDefaultTitles : defaultTitles
	let currentSort = isHold ? self.holdSortBy : self.reactor.currentState.sortBy
	let buttons = [self.currentPriceButton, self.previousDayButton, self.tradingVolumeButton]

	self.prevSortedButton = nil
	for button in buttons {
	  let (asc, desc) = self.sortTypes(forButtonTag: button.tag, isHold: isHold)
	  if currentSort == asc || currentSort == desc {
		button.setTitle(currentSort.rawValue, for: .normal)
		button.isSelected = true
		self.prevSortedButton = button
	  } else {
		button.setTitle(titles[button.tag], for: .normal)
		button.isSelected = false
	  }
	}
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

  private func refreshDisplayedList() {
	let filteredList = self.filterListForCurrentTab(
	  totalList: reactor.currentState.totalCryptoList
	)

	if self.selectedTab == .favorite, filteredList.isEmpty {
	  self.tableView.isHidden = true
	  self.noFavoriteView.isHidden = false
	} else {
	  self.tableView.isHidden = false
	  self.noFavoriteView.isHidden = true
	  self.applySnapshot(cellInfos: filteredList)
	}
  }
  
  /// 사용자 매수 목록 업데이트
  private func updateUserCryptoList(from cellInfos: [CryptoCellInfo]) {
	guard var userCryptoList = UserDataManager.userCryptoList, !userCryptoList.isEmpty else { return }

	// market -> index 맵 (탐색 O(1))
	let indexByMarket = Dictionary(
	  uniqueKeysWithValues: userCryptoList.enumerated().map { ($1.staticData.marketName, $0) }
	)

	for cell in cellInfos {
	  guard let currentPrice = cell.tradePrice,
			let idx = indexByMarket[cell.market] else { continue }

	  let avg = userCryptoList[idx].staticData.averageBuyPrice
	  let qty = userCryptoList[idx].staticData.holdingQuantity

	  userCryptoList[idx].dynamicData.profitRate = MarketDataServiceUtil.shared.calculateProfitRate(
		  currentPrice: currentPrice,
		  averageBuyPrice: avg
		)

	  userCryptoList[idx].dynamicData.evaluationPrice = MarketDataServiceUtil.shared.calculateEvalPrice(
		currentPrice: currentPrice,
		holdingQuantity: qty
	  )

	  userCryptoList[idx].dynamicData.evaluationProfitLoss = MarketDataServiceUtil.shared.calculateEvalProfitLoss(
		currentPrice: currentPrice,
		holdingQuantity: qty,
		averageBuyPrice: avg
	  )
	}

	// 최종적으로 1회 저장 (반복문 안에서 저장 연산 X)
	UserDataManager.userCryptoList = userCryptoList
	self.updatePortfolioSummary(cryptos: userCryptoList)
  }
  
  /// 즐겨찾기 UI 업데이트
  private func updateFavoriteUI() {
	self.refreshDisplayedList()
  }
}

// MARK: - TableView Delegate
extension MainViewController: UITableViewDelegate {
  
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
	
	// 현재 화면에 표시 중인 리스트 가져오기
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
	
	self.coordinator?.pushCryptoTradeVC(
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
	// 검색어가 변경되면 자동으로 필터링됨 (bind에서 처리)
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
    self.reactor.action.onNext(.pauseSocket)
  }
  
  func resumeSocket() {
    self.reactor.action.onNext(.resumeSocket)
  }
}

extension MainViewController: AdLoaderDelegate, NativeAdLoaderDelegate, NativeAdDelegate {
  func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
    self.isLoadingMainNativeAd = false
    nativeAd.delegate = self
    self.mainNativeAd = nativeAd
    Log.info("메인 네이티브 광고 로드 완료")
    self.presentMainNativeAdIfNeeded()
  }

  func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
    self.isLoadingMainNativeAd = false
    self.mainNativeAd = nil
    Log.info("메인 네이티브 광고 로드 실패: \(error.localizedDescription)")
  }

  func nativeAdDidRecordClick(_ nativeAd: NativeAd) {
    Log.info("메인 네이티브 광고 클릭")
  }

  func nativeAdDidRecordImpression(_ nativeAd: NativeAd) {
	UserDefaults.standard.set(self.mainNativeAdTodayKey(), forKey: self.mainNativeAdLastShownDateKey)
    Log.info("메인 네이티브 광고 노출")
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
	  // 네트워크 완전 유실 상태
	  showNetworkLostView()
	} else {
	  // 네트워크 복구됨
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

final class MainNativeAdPopupViewController: UIViewController {
  private let ad: NativeAd
  private let onDismiss: (() -> Void)?

  init(ad: NativeAd, onDismiss: (() -> Void)? = nil) {
    self.ad = ad
    self.onDismiss = onDismiss
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    self.setupUI()
  }

  private func setupUI() {
    self.view.backgroundColor = .clear

    let dimView = UIView()
    dimView.translatesAutoresizingMaskIntoConstraints = false
    dimView.backgroundColor = UIColor.black.withAlphaComponent(0.45)
    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.dismissPopup))
    dimView.addGestureRecognizer(tapGesture)

	let closeBackgroundView = UIView()
	closeBackgroundView.backgroundColor = .darkGray
	closeBackgroundView.clipsToBounds = true

	let closeButton = UIButton(type: .system)
	closeButton.tintColor = .white
	let symbolConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
	closeButton.setPreferredSymbolConfiguration(symbolConfig, forImageIn: .normal)
	closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
	closeButton.addTarget(self, action: #selector(self.dismissPopup), for: .touchUpInside)

    let cardView = self.makeAdCardView(ad: self.ad)
    cardView.translatesAutoresizingMaskIntoConstraints = false

    self.view.addSubview(dimView)
    self.view.addSubview(closeBackgroundView)
    self.view.addSubview(cardView)
	closeBackgroundView.addSubview(closeButton)
	
	dimView.snp.makeConstraints { make in
	  make.edges.equalToSuperview()
	}
	
	closeBackgroundView.snp.makeConstraints { make in
	  make.trailing.equalTo(cardView.snp.trailing)
	  make.top.equalTo(cardView.snp.bottom)
	  make.width.height.equalTo(40)
	}

	closeButton.snp.makeConstraints { make in
	  make.center.equalToSuperview()
	  make.edges.equalToSuperview()
	}
	
	cardView.snp.makeConstraints { make in
	  make.center.equalToSuperview()
	  make.leading.greaterThanOrEqualTo(self.view.safeAreaLayoutGuide.snp.leading).offset(16)
	  make.trailing.lessThanOrEqualTo(self.view.safeAreaLayoutGuide.snp.trailing).offset(-16)
	  make.top.greaterThanOrEqualTo(self.view.safeAreaLayoutGuide.snp.top).offset(16)
	  make.bottom.lessThanOrEqualTo(self.view.safeAreaLayoutGuide.snp.bottom).offset(-16)
	  make.width.equalTo(self.view.safeAreaLayoutGuide.snp.width).multipliedBy(0.88).priority(999)
	}
  }

  private func makeAdCardView(ad: NativeAd) -> NativeAdView {
    let adView = NativeAdView()
    adView.backgroundColor = .white
    adView.layer.cornerRadius = 4
    adView.layer.masksToBounds = true

    let container = UIView()
    adView.addSubview(container)
	container.snp.makeConstraints { make in
	  make.edges.equalToSuperview().inset(16)
	}

    let badgeLabel = UILabel()
    badgeLabel.text = "광고"
    badgeLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
    badgeLabel.textColor = .white
    badgeLabel.backgroundColor = UIColor.mobitPrimary
    badgeLabel.layer.cornerRadius = 4
    badgeLabel.layer.masksToBounds = true
    badgeLabel.textAlignment = .center

    let adChoicesView = AdChoicesView()

    let mediaView = MediaView()
    mediaView.layer.cornerRadius = 12
    mediaView.clipsToBounds = true

    let headlineLabel = UILabel()
    headlineLabel.font = UIFont.boldSystemFont(ofSize: 16)
    headlineLabel.numberOfLines = 0
	headlineLabel.textColor = .black

    let bodyLabel = UILabel()
    bodyLabel.font = UIFont.systemFont(ofSize: 12)
    bodyLabel.numberOfLines = 0
	bodyLabel.textColor = .black

    let ctaButton = UIButton(type: .system)
	
	var config = UIButton.Configuration.filled()
	config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
	config.baseBackgroundColor = .mobitPrimary
	config.baseForegroundColor = .white
	config.cornerStyle = .fixed
	config.background.cornerRadius = 4
	ctaButton.configuration = config

    ctaButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
	ctaButton.configuration = config
    ctaButton.isUserInteractionEnabled = false

    let iconView = UIImageView()
    iconView.layer.cornerRadius = 8
    iconView.clipsToBounds = true
    iconView.contentMode = .scaleAspectFit

    let advertiserLabel = UILabel()
    advertiserLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
    advertiserLabel.textColor = .secondaryLabel
    advertiserLabel.numberOfLines = 1

    container.addSubview(badgeLabel)
    container.addSubview(adChoicesView)
    container.addSubview(mediaView)
    container.addSubview(iconView)
    container.addSubview(headlineLabel)
    container.addSubview(bodyLabel)
    container.addSubview(ctaButton)
    container.addSubview(advertiserLabel)

    let mediaAspectRatio = ad.mediaContent.aspectRatio > 0 ? ad.mediaContent.aspectRatio : 1.91

    badgeLabel.snp.makeConstraints { make in
      make.top.leading.equalToSuperview()
      make.width.greaterThanOrEqualTo(36)
      make.height.equalTo(22)
    }

    adChoicesView.snp.makeConstraints { make in
      make.centerY.equalTo(badgeLabel.snp.centerY)
      make.trailing.equalToSuperview()
      make.width.lessThanOrEqualTo(40)
      make.height.lessThanOrEqualTo(20)
      make.leading.greaterThanOrEqualTo(badgeLabel.snp.trailing).offset(8)
    }

    mediaView.snp.makeConstraints { make in
      make.top.equalTo(badgeLabel.snp.bottom).offset(12)
      make.leading.trailing.equalToSuperview()
      make.height.equalTo(mediaView.snp.width).dividedBy(mediaAspectRatio).priority(999)
      make.height.greaterThanOrEqualTo(120)
      make.height.lessThanOrEqualTo(container.snp.width).multipliedBy(1.25)
    }

    iconView.snp.makeConstraints { make in
      make.top.equalTo(mediaView.snp.bottom).offset(12)
      make.leading.equalToSuperview()
      make.width.equalTo(container.snp.width).multipliedBy(0.18).priority(999)
      make.width.greaterThanOrEqualTo(44)
      make.width.lessThanOrEqualTo(64)
      make.height.equalTo(iconView.snp.width)
    }

    headlineLabel.snp.makeConstraints { make in
      make.top.equalTo(iconView.snp.top)
      make.leading.equalTo(iconView.snp.trailing).offset(12)
      make.trailing.equalToSuperview()
    }

    bodyLabel.snp.makeConstraints { make in
      make.top.equalTo(headlineLabel.snp.bottom).offset(8)
      make.leading.trailing.equalTo(headlineLabel)
    }

    ctaButton.snp.makeConstraints { make in
      make.top.equalTo(iconView.snp.bottom)
      make.leading.equalTo(iconView.snp.leading)
      make.trailing.lessThanOrEqualToSuperview()
    }

    advertiserLabel.snp.makeConstraints { make in
      make.top.equalTo(ctaButton.snp.bottom).offset(10)
      make.top.greaterThanOrEqualTo(iconView.snp.bottom).offset(10)
      make.leading.trailing.equalToSuperview()
      make.bottom.equalToSuperview()
    }

    headlineLabel.text = ad.headline
    bodyLabel.text = ad.body
    ctaButton.setTitle(ad.callToAction, for: .normal)

    if let icon = ad.icon?.image {
      iconView.image = icon
      iconView.isHidden = false
    } else {
      iconView.isHidden = true
    }

    if let advertiser = ad.advertiser {
      advertiserLabel.text = "제공: \(advertiser)"
      advertiserLabel.isHidden = false
    } else {
      advertiserLabel.isHidden = true
    }

    adView.mediaView = mediaView
    adView.headlineView = headlineLabel
    adView.bodyView = bodyLabel
    adView.callToActionView = ctaButton
    adView.iconView = iconView
    adView.adChoicesView = adChoicesView
    adView.advertiserView = advertiserLabel
    adView.nativeAd = ad

    return adView
  }

  @objc private func dismissPopup() {
    self.dismiss(animated: true) { [weak self] in
      self?.onDismiss?()
    }
  }
}
