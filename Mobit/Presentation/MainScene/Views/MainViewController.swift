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

class MainViewController: UIViewController {
  // coordinator <-> viewcontroller 강한 참조 사이클 방지
  weak var coordinator: MainCoordinator?
  var dataSource: UITableViewDiffableDataSource<TableViewSection, CryptoCellInfo>?
  var disposeBag = DisposeBag()
  var reactor: MainReactor
  
  var selectedTab: SelectedTab = .krw
  
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
    $0.titleLabel?.font = UIFont.systemFont(ofSize: 10, weight: .light)
    $0.setTitleColor(.gray, for: .normal)
    $0.tag = 0
  }
  
  // 전일대비
  let previousDayButton: UIButton = UIButton().then {
    $0.setTitle("전일대비↓↑", for: .normal)
    $0.titleLabel?.font = UIFont.systemFont(ofSize: 10, weight: .light)
    $0.setTitleColor(.gray, for: .normal)
    $0.tag = 1
  }
  
  // 거래량
  let tradingVolumeButton: UIButton = UIButton().then {
    $0.setTitle("거래량↓↑", for: .normal)
    $0.titleLabel?.font = UIFont.systemFont(ofSize: 10, weight: .light)
    $0.setTitleColor(.gray, for: .normal)
    $0.tag = 2
  }
  
  let tableView: UITableView = UITableView().then {
    $0.separatorStyle = .singleLine
    $0.separatorInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
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
    
    self.setUpFlexItems()
    
    self.bind(reactor: self.reactor)
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
    self.tableView.register(CoinTableViewCell.self, forCellReuseIdentifier: self.cellIndentifier)
    self.tableView.rowHeight = 50
    
    self.dataSource = UITableViewDiffableDataSource<TableViewSection, CryptoCellInfo>(tableView: self.tableView) { (tableView: UITableView, indexPath: IndexPath, crypto: CryptoCellInfo) -> UITableViewCell? in
      
      guard let cell = self.tableView.dequeueReusableCell(withIdentifier: self.cellIndentifier, for: indexPath) as? CoinTableViewCell else { return UITableViewCell() }
      
      cell.configure(crypto: crypto)
      cell.selectionStyle = .none
      return cell
    }
    
    self.dataSource?.defaultRowAnimation = .fade
    self.tableView.dataSource = self.dataSource
    self.tableView.delegate = self
  }
  
  func applySnapshot(cellInfo: [CryptoCellInfo]?) {
    // tableview에 들어가는 section, item 초기화
    var snapshot = NSDiffableDataSourceSnapshot<TableViewSection, CryptoCellInfo>()
    snapshot.appendSections([.main])
    if let cellInfo = cellInfo, !cellInfo.isEmpty {
      snapshot.appendItems(cellInfo, toSection: .main)
    } else {
      snapshot.appendItems([])
    }
    
    self.dataSource?.apply(snapshot, animatingDifferences: false)
  }
  
  func setTabButton() {
    self.krwButton.addTarget(self, action: #selector(tapOnTabButton(_:)), for: .touchUpInside)
    self.btcButton.addTarget(self, action: #selector(tapOnTabButton(_:)), for: .touchUpInside)
    self.favoriteButton.addTarget(self, action: #selector(tapOnTabButton(_:)), for: .touchUpInside)
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
      self.applySnapshot(cellInfo: reactor.currentState.cryptoCellInfo)
    case 1:
      self.selectedTab = .btc
      self.reactor.action.onNext(.loadCrypto(selectedTab: .btc))
      self.applySnapshot(cellInfo: reactor.currentState.cryptoCellInfo)
    case 2:
      self.selectedTab = .favorite
      self.applySnapshot(cellInfo: [])
    default:
      break
    }
  }
  
  /// UISearchBar 설정
  func setSearchBar() {
    if let searchTextField = self.searchBar.value(forKey: "searchField") as? UISearchTextField {
      searchTextField.do {
        $0.backgroundColor = .clear
        $0.textColor = .black
        $0.attributedPlaceholder = NSAttributedString(string: "코인명/심볼 검색",
                                                      attributes: [NSAttributedString.Key.foregroundColor: UIColor.lightGray])
      }
    }
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
        self.applySnapshot(cellInfo: cellInfos)
      })
      .disposed(by: self.disposeBag)
  }
}

// MARK: TableView Delegate
extension MainViewController: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    print("cell click : \(indexPath.row)")
    self.coordinator?.pushCryptoDetailVC(selectCrypto: reactor.currentState.cryptoCellInfo[indexPath.row].market)
  }
}
