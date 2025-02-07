//
//  CryptoDetailViewController.swift
//  Mobit
//
//  Created by 조성재 on 8/19/24.
//

import FlexLayout
import RxCocoa
import RxSwift
import ReactorKit
import PinLayout
import Then
import UIKit


class CryptoDetailViewController: UIViewController {
  weak var coordinator: CryptoDetailCoordinator?
  var reactor: CryptoDetailReactor
  var disposeBag = DisposeBag()
  var dataSource: UITableViewDiffableDataSource<TableViewSection, OrderUnit>?
  var prevClosingPrice: Double? = nil
  var isFirstInput: Bool = false
  private let cellIndentifier = "OrderBookCell"
  
  init(reactor: CryptoDetailReactor) {
    self.reactor = reactor
    super.init(nibName: nil, bundle: nil)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  // MARK: UI Component
  let rootContainer: UIView = UIView()
  let naviBar: UIView = UIView()
  let backButton: UIButton = UIButton().then {
    $0.setImage(UIImage(systemName: "arrow.backward"), for: .normal)
    $0.tintColor = UIColor.black
    $0.imageView?.contentMode = .scaleAspectFit
  }
  let titleLabel: UILabel = UILabel().then {
    $0.text = "-"
    $0.textColor = .black
    $0.textAlignment = .center
    $0.font = UIFont.systemFont(ofSize: 15)
  }
  let favoriteButton: UIButton = UIButton().then {
    $0.setImage(UIImage(systemName: "star"), for: .normal)
    $0.tintColor = UIColor.black
    $0.imageView?.contentMode = .scaleAspectFit
  }
  let priceLabel: UILabel = UILabel().then {
    $0.text = "0"
    $0.textColor = .black
    $0.font = UIFont.systemFont(ofSize: 20)
  }
  let changeRateLabel: UILabel = UILabel().then {
    $0.text = "0%"
    $0.textColor = .black
    $0.lineBreakMode = .byWordWrapping
    $0.adjustsFontSizeToFitWidth = true
    $0.font = UIFont.systemFont(ofSize: 11)
  }
  let changePriceImageView: UIImageView = UIImageView().then {
    // 상승, 보합, 하락을 나타내는 삼각형 이미지
    $0.image = UIImage()
    $0.tintColor = .clear
  }
  let changePriceLabel: UILabel = UILabel().then {
    $0.text = "0"
    $0.textColor = .black
    $0.lineBreakMode = .byWordWrapping
    $0.adjustsFontSizeToFitWidth = true
    $0.font = UIFont.systemFont(ofSize: 11)
  }
  let segmentedControl: UISegmentedControl = UISegmentedControl(
    items: ["주문", "차트", "정보"]
  ).then {
    $0.selectedSegmentIndex = 0
    $0.backgroundColor = .clear
    $0.selectedSegmentTintColor = .clear
    $0.setBackgroundImage(UIImage(), for: .normal, barMetrics: .default)
    $0.setDividerImage(
        UIImage(),
        forLeftSegmentState: .normal,
        rightSegmentState: .normal,
        barMetrics: .default
      )
    $0.setTitleTextAttributes(
        [.foregroundColor: UIColor.blue, .font: UIFont.systemFont(ofSize: 15)],
        for: .selected
      )
    $0.setTitleTextAttributes(
        [.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 15)],
        for: .normal
      )
  }
  let orderView: UIView = UIView().then {
    $0.backgroundColor = .yellow
  }
  let orderTableView: UITableView = UITableView().then {
    $0.separatorStyle = .singleLine
    $0.separatorInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
  }
  let tradeView: UIView = UIView().then {
    $0.backgroundColor = .white
  }
  let chartView: UIView = UIView().then {
    $0.backgroundColor = .brown
  }
  let informationView: UIView = UIView().then {
    $0.backgroundColor = .green
  }
  let bidTabButton: UIButton = UIButton().then {
    $0.setTitle("매수", for: .normal)
    $0.setTitleColor(.darkGray, for: .normal)
    $0.setTitleColor(.red, for: .selected)
    $0.titleLabel?.font = UIFont.systemFont(ofSize: 13)
    $0.isSelected = true  // default
    $0.backgroundColor = .white
    $0.tag = 0
  }
  let askTabButton: UIButton = UIButton().then {
    $0.setTitle("매도", for: .normal)
    $0.setTitleColor(.darkGray, for: .normal)
    $0.setTitleColor(.blue, for: .selected)
    $0.titleLabel?.font = UIFont.systemFont(ofSize: 13)
    $0.isSelected = false
    $0.backgroundColor = .mobitColors(.lightGrayBG)
    $0.tag = 1
  }
  let tradeHistoryTabButton: UIButton = UIButton().then {
    $0.setTitle("거래내역", for: .normal)
    $0.setTitleColor(.darkGray, for: .normal)
    $0.titleLabel?.font = UIFont.systemFont(ofSize: 13)
    $0.isSelected = false
    $0.backgroundColor = .mobitColors(.lightGrayBG)
    $0.tag = 2
  }
  let availableOrderLabel: UILabel = UILabel().then {
    $0.text = "주문 가능"
    $0.textColor = .gray
    $0.textAlignment = .left
    $0.font = UIFont.systemFont(ofSize: 12)
  }
  let availableOrderAmount: UILabel = UILabel().then {
    $0.text = "0"
    $0.textColor = .black
    $0.textAlignment = .right
    $0.font = UIFont.systemFont(ofSize: 12, weight: .bold)
    $0.adjustsFontSizeToFitWidth = true
    $0.minimumScaleFactor = 0.5
  }
  let availableOrderCurrency: UILabel = UILabel().then {
    $0.text = "KRW"
    $0.textColor = .black
    $0.textAlignment = .right
    $0.font = UIFont.systemFont(ofSize: 12, weight: .bold)
  }
  let cryptoCountLabel: UILabel = UILabel().then {
    $0.text = "수량"
    $0.textColor = .darkGray
    $0.textAlignment = .left
    $0.font = UIFont.systemFont(ofSize: 12)
  }
  let maxCryptoButton: UIButton = UIButton().then {
    $0.setTitle("최대수량", for: .normal)
    $0.setTitleColor(.black, for: .normal)
    $0.titleLabel?.font = UIFont.systemFont(ofSize: 12)
    $0.backgroundColor = .bgLightGray
  }
  let cryptoCountAmount: UITextField = UITextField().then {
    $0.text = "0"
    $0.textColor = .black
    $0.textAlignment = .right
    
    $0.font = UIFont.systemFont(ofSize: 12)
  }
  let cryptoCountCurrency: UILabel = UILabel().then {
    $0.text = "BTC"
    $0.textColor = .black
    $0.textAlignment = .right
    $0.font = UIFont.systemFont(ofSize: 11)
  }
  let cryptoPriceLabel: UILabel = UILabel().then {
    $0.text = "가격"
    $0.textColor = .black
    $0.textAlignment = .right
    $0.font = UIFont.systemFont(ofSize: 11)
  }
  let cryptoPriceAmount: UITextField = UITextField().then {
    $0.text = "100,000,000" // 첫 진입시 현재가
    $0.textColor = .black
    $0.textAlignment = .right
    $0.font = UIFont.systemFont(ofSize: 11)
  }
  let cryptoPriceCurrency: UILabel = UILabel().then {
    $0.text = "KRW"
    $0.textColor = .black
    $0.textAlignment = .right
    $0.font = UIFont.systemFont(ofSize: 11)
  }
  let cryptoTotalPriceLabel: UILabel = UILabel().then {
    $0.text = "총액"
    $0.textColor = .black
    $0.textAlignment = .right
    $0.font = UIFont.systemFont(ofSize: 11)
  }
  let cryptoTotalPriceAmount: UITextField = UITextField().then {
    $0.text = "0" // 첫 진입시 현재가
    $0.textColor = .black
    $0.textAlignment = .right
    $0.font = UIFont.systemFont(ofSize: 11)
  }
  let cryptoTotalPriceCurrency: UILabel = UILabel().then {
    $0.text = "KRW"
    $0.textColor = .black
    $0.textAlignment = .right
    $0.font = UIFont.systemFont(ofSize: 11)
  }
  let setInitButton: UIButton = UIButton().then {
    $0.setTitle("초기화", for: .normal)
    $0.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
    $0.setTitleColor(.white, for: .normal)
    $0.backgroundColor = .darkGray
  }
  let tradeButton: UIButton = UIButton().then {
    $0.setTitle("매수", for: .normal) // default
    $0.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
    $0.setTitleColor(.white, for: .normal)
    $0.backgroundColor = .red
  }
  
  override func viewWillAppear(_ animated: Bool) {
    self.reactor.action
      .onNext(.connectTickerSocket)
    self.reactor.action
      .onNext(.connectOrderBookSocket)
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    self.view.backgroundColor = .white
    
    self.addViews()
    self.setUpViews()
    self.setTableView()
    self.setButtons()
    self.setSegmentedControl()
    
    self.setUpFlexItems()
    
    self.bind(reactor: self.reactor)
  }
  
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    
    self.rootContainer.pin.all(self.view.pin.safeArea)
    self.rootContainer.flex.layout()
  }
  
  func addViews() {
    self.view.addSubview(self.rootContainer)
    self.rootContainer.addSubview(self.naviBar)
    self.rootContainer.addSubview(self.backButton)
    self.rootContainer.addSubview(self.favoriteButton)
    self.rootContainer.addSubview(self.segmentedControl)
    self.rootContainer.addSubview(self.orderView)
    self.rootContainer.addSubview(self.chartView)
    self.rootContainer.addSubview(self.informationView)
  }
  
  func setUpViews(crypto: CryptoCellInfo? = nil) {
    
    self.prevClosingPrice = crypto?.prevPrice
    let numberFormatter = NumberFormatter()
    numberFormatter.numberStyle = .decimal
    
    let selectCrypto = crypto ?? self.reactor.selectCrypto
    guard let tradePrice = selectCrypto.tradePrice,
          let signedChangeRate = selectCrypto.signedChangeRate,
          let changePrice = selectCrypto.changePrice else { return }
    
    self.titleLabel.text = "\(selectCrypto.cryptoName)(\(selectCrypto.market))"
    if tradePrice < 1 {
      self.priceLabel.text = self.formatTradePrice(tradePrice)
    } else {
      self.priceLabel.text = numberFormatter.string(
        from: NSNumber(value: tradePrice)
      )
    }
    
    self.changeRateLabel.text = String(
      format: "%.2f%%", signedChangeRate * 100
    )
    
    if changePrice < 1 {
      self.changePriceLabel.text = self.formatTradePrice(changePrice)
    } else {
      self.changePriceLabel.text = numberFormatter.string(
        from: NSNumber(value: changePrice)
      )
    }
    
    let currency = crypto?.market.components(separatedBy: "/").first
    self.cryptoCountCurrency.text = currency
    
    switch selectCrypto.change {
    case "RISE":
      self.priceLabel.textColor = .red
      self.changeRateLabel.textColor = .red
      self.changePriceLabel.textColor = .red
      self.changePriceImageView.image = UIImage(systemName: "arrowtriangle.up.fill")
      self.changePriceImageView.tintColor = .red
    case "FALL":
      self.priceLabel.textColor = .blue
      self.changeRateLabel.textColor = .blue
      self.changePriceLabel.textColor = .blue
      self.changePriceImageView.image = UIImage(systemName: "arrowtriangle.down.fill")
      self.changePriceImageView.tintColor = .blue
    case "EVEN":
      self.priceLabel.textColor = .black
      self.changeRateLabel.textColor = .black
      self.changePriceLabel.textColor = .black
      self.changePriceImageView.image = UIImage()
      self.changePriceImageView.tintColor = .clear
    default:
      break
    }
  }
  
  func setTableView() {
    self.orderTableView.register(
      OrderBookCell.self,
      forCellReuseIdentifier: self.cellIndentifier
    )
    self.orderTableView.rowHeight = 50
    
    self.dataSource = UITableViewDiffableDataSource<TableViewSection, OrderUnit>(
      tableView: self.orderTableView
    ) { (
      tableView: UITableView,
      indexPath: IndexPath,
      obUnit: OrderUnit
    ) -> UITableViewCell? in
      
      guard let cell = self.orderTableView.dequeueReusableCell(
        withIdentifier: self.cellIndentifier,
        for: indexPath
      ) as? OrderBookCell else { return UITableViewCell() }
      
      cell.configure(
        changeRate: self.calculateFluctuation(
          obPrice: obUnit.price
        ),
        obType: obUnit.type,
        obPrice: obUnit.price,
        obSize: obUnit.size
      )
      
      cell.selectionStyle = .none
      return cell
    }
    
    self.dataSource?.defaultRowAnimation = .fade
    self.orderTableView.dataSource = self.dataSource
    self.orderTableView.delegate = self
  }
  
  /// TableViewDiffableDataSource Snapshot Update
  func applySnapshot(orderDatas: [OrderUnit]?) {
    // tableview에 들어가는 section, item 초기화
    var snapshot = NSDiffableDataSourceSnapshot<TableViewSection, OrderUnit>()
    snapshot.appendSections([.main])
    if let orderDatas = orderDatas {
      snapshot.appendItems(orderDatas, toSection: .main)
    } else {
      snapshot.appendItems([])
    }
    
    self.dataSource?.apply(snapshot, animatingDifferences: false, completion: {
      if self.isFirstInput == false {
        DispatchQueue.main.async {
          self.isFirstInput = true
          let indexPath = IndexPath(row: 16, section: 0)
          self.orderTableView.scrollToRow(
            at: indexPath,
            at: .middle,
            animated: false
          )
        }
      }
    })
  }
  
  /// flex item 나열
  func setUpFlexItems() {
    rootContainer.flex
      .justifyContent(.start)
      .direction(.column).define { flex in
        // navi bar
        flex.addItem(self.naviBar).height(52)
          .direction(.row).define { flex in
            flex
              .addItem().define({ flex in
                flex
                  .addItem(self.backButton)
                  .height(100%)
                  .aspectRatio(1)
              })
              .height(100%)
              .justifyContent(.center)
            flex
              .addItem(self.titleLabel)
              .grow(1)
              .height(100%)
              .alignItems(.center)
            flex
              .addItem().define({ flex in
                flex
                  .addItem(self.favoriteButton)
                  .height(100%)
                  .aspectRatio(1)
              })
              .height(100%)
              .alignItems(.center)
          }
        
        // 코인 정보
        flex.addItem()
          .direction(.column)
          .define { flex in
            flex.addItem(self.priceLabel)
              .marginLeft(16)
              .marginBottom(10)
            flex.addItem()
              .direction(.row)
              .define { flex in
                flex.addItem(self.changeRateLabel)
                  .grow(1)
                  .marginRight(20)
                flex.addItem()
                  .direction(.row)
                  .alignItems(.center)
                  .define { flex in
                    flex
                      .addItem(self.changePriceImageView)
                      .width(6)
                      .aspectRatio(1)
                      .marginRight(2)
                    flex.addItem(self.changePriceLabel)
                      .width(100%)
                  }
              }.marginLeft(16)
          }
        
        // segmentedControl
        flex.addItem()
          .direction(.column).define { flex in
            flex.addItem(self.segmentedControl)
              .marginTop(10).width(100%).height(50)
            
            flex.addItem(DividerLineView()).height(1)
          }
        
        // 매수, 매도, 거래내역 탭
        // 파생된 view
        flex.addItem()
          .define { flex in
            flex.addItem(self.orderView)
              .position(.absolute)
              .top(0).left(0).right(0).bottom(0)
              .direction(.row)
              .define { flex in
                // order book tableview
                flex.addItem(self.orderTableView)
                  .width(35%)
                // 주문 화면
                flex.addItem(self.tradeView)
                  .width(65%)
                  .direction(.column)
                  .define { flex in
                    flex.addItem().direction(.row)
                      .define { flex in
                        // 매수, 매도, 거래내역 버튼 (basis 균등 비율)
                        flex.addItem(self.bidTabButton).grow(1).basis(0%)
                        flex.addItem(self.askTabButton).grow(1).basis(0%)
                        flex.addItem(self.tradeHistoryTabButton).grow(1).basis(0%)
                      }.height(40)
                    // 주문 컴포넌트 추가
                    flex.addItem().direction(.row)
                      .define { flex in
                        flex.addItem(self.availableOrderLabel)
                        flex.addItem(self.availableOrderAmount)
                          .marginRight(2)
                          .grow(1)
                        flex.addItem(self.availableOrderCurrency)
                      }.marginHorizontal(10).marginTop(10).marginBottom(5)
                    // 수량
                    flex.addItem().direction(.row)
                      .define { flex in
                        flex.addItem().direction(.row)
                          .define { flex in
                            flex.addItem(self.cryptoCountLabel).marginLeft(5)
                            flex.addItem(self.cryptoCountAmount).marginRight(4).grow(1)
                            flex.addItem(self.cryptoCountCurrency).marginRight(10)
                          }
                          .height(40)
                          .marginHorizontal(10).marginBottom(5).grow(1)
                          .cornerRadius(5).border(1, .bgLightGray)
                        flex.addItem(self.maxCryptoButton)
                          .height(40)
                          .width(60)
                          .marginLeft(5)
                          .marginRight(10)
                          .cornerRadius(5)
                      }
                    // 가격
                    flex.addItem().direction(.row)
                      .define { flex in
                        flex.addItem(self.cryptoPriceLabel).marginLeft(5)
                        flex.addItem(self.cryptoPriceAmount).marginRight(4).grow(1)
                        flex.addItem(self.cryptoPriceCurrency).marginRight(10)
                      }
                      .height(40)
                      .marginHorizontal(10).marginBottom(5)
                      .cornerRadius(5).border(1, .bgLightGray)
                    // 총액
                    flex.addItem().direction(.row)
                      .define { flex in
                        flex.addItem(self.cryptoTotalPriceLabel).marginLeft(5)
                        flex.addItem(self.cryptoTotalPriceAmount).marginRight(4).grow(1)
                        flex.addItem(self.cryptoTotalPriceCurrency).marginRight(10)
                      }
                      .height(40)
                      .marginHorizontal(10).marginBottom(10)
                      .cornerRadius(5).border(1, .bgLightGray)
                    
                    flex.addItem().direction(.row).gap(5)
                      .define { flex in
                        flex.addItem(self.setInitButton)
                          .cornerRadius(5)
                          .width(50%)
                        flex.addItem(self.tradeButton)
                          .cornerRadius(5)
                          .width(50%)
                      }
                      .height(40)
                      .marginHorizontal(10)
                  }
              }
            flex.addItem(self.chartView)
              .position(.absolute)
              .top(0).left(0).right(0).bottom(0)
            flex.addItem(self.informationView)
              .position(.absolute)
              .top(0).left(0).right(0).bottom(0)
          }.height(100%)
      }
  }
  
}

// MARK: viewcontroller 기타 설정 메소드
extension CryptoDetailViewController {
  func setButtons() {
    self.backButton.addTarget(
      self, action: #selector(tapOnBackButton(_:)), for: .touchUpInside
    )
    self.bidTabButton.addTarget(
      self, action: #selector(tapOnTradeTabButtons(_:)), for: .touchUpInside
    )
    self.askTabButton.addTarget(
      self, action: #selector(tapOnTradeTabButtons(_:)), for: .touchUpInside
    )
    self.tradeHistoryTabButton.addTarget(
      self, action: #selector(tapOnTradeTabButtons(_:)), for: .touchUpInside
    )
    self.tradeButton.addTarget(
      self, action: #selector(tapOnTradeButton(_:)), for: .touchUpInside
    )
  }
  
  @objc private func tapOnBackButton(_ sender: UIButton) {
    self.coordinator?.navigationController.popViewController(animated: true)
    self.reactor.tickerSocketManager.disconnect()
    self.reactor.orderBookSocketManager.disconnect()
  }
  
  /// 매수, 매도, 거래내역 버튼 터치
  @objc private func tapOnTradeTabButtons(_ sender: UIButton) {
    [bidTabButton, askTabButton, tradeHistoryTabButton]
      .filter { $0.tag != sender.tag }
      .forEach { $0.backgroundColor = .mobitColors(.lightGrayBG) }
    
    self.bidTabButton.isSelected = false
    self.askTabButton.isSelected = false
    self.tradeHistoryTabButton.isSelected = false
    
    sender.isSelected = true
    
    switch sender.tag {
    case 0:
      self.bidTabButton.setTitleColor(.red, for: .selected)
      self.bidTabButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 13)
      self.bidTabButton.backgroundColor = .white
      self.tradeButton.backgroundColor = .red
      self.tradeButton.setTitle("매수", for: .normal)
    case 1:
      self.askTabButton.setTitleColor(.blue, for: .selected)
      self.askTabButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 13)
      self.askTabButton.backgroundColor = .white
      self.tradeButton.backgroundColor = .blue
      self.tradeButton.setTitle("매도", for: .normal)
    case 2:
      self.tradeHistoryTabButton.setTitleColor(.darkGray, for: .selected)
      self.tradeHistoryTabButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 13)
      self.tradeHistoryTabButton.backgroundColor = .white
    default:
      break
    }
  }
  
  @objc private func tapOnTradeButton(_ sender: UIButton) {
    guard let currentPrice = self.reactor.currentState.cryptoInfo?.tradePrice,
          let userBalance = UserDataManager.userInformation?.userAvailableBalance else { return }
    
    let availableAmount = round((userBalance / currentPrice) * 100) / 100
    print("💵 : \(availableAmount)")
  }
  
  func setSegmentedControl() {
    self.segmentedControl
      .addTarget(
        self,
        action: #selector(segmentedValueChanged(_:)),
        for: .valueChanged
      )
    self.segmentedValueChanged(self.segmentedControl)
  }
  
  @objc private func segmentedValueChanged(_ sender: UISegmentedControl) {
    self.orderView.isHidden = sender.selectedSegmentIndex != 0
    self.chartView.isHidden = sender.selectedSegmentIndex != 1
    self.informationView.isHidden = sender.selectedSegmentIndex != 2
  }
  
  /// price format
  func formatTradePrice(_ tradePrice: Double?, precision: Int = 8) -> String {
    guard let price = tradePrice else {
      return "N/A"  // 값이 없을 때 반환할 기본 문자열
    }
    return String(format: "%.\(precision)f", price)
  }
  
  /// 변동성 % 계산
  private func calculateFluctuation(obPrice: Double?) -> Double? {
    guard let obPrice = obPrice,
          let prevClosingPrice = self.prevClosingPrice else {
      return nil
    }
    
    if prevClosingPrice == 0 {
      return 1
    } else {
      let fluctuation = ceil((obPrice / prevClosingPrice) * 100) / 100
      return fluctuation
    }
  }
}

// MARK: Reactor - View
extension CryptoDetailViewController {
  
  func bind(reactor: CryptoDetailReactor) {
    
    reactor.state.map { $0.cryptoInfo }
      .distinctUntilChanged()
      .observe(on: MainScheduler.instance)
      .subscribe(onNext: { cellInfo in
        self.setUpViews(crypto: cellInfo)
      })
      .disposed(by: self.disposeBag)
    
    reactor.state.map { $0.obTicker }
      .distinctUntilChanged()
      .observe(on: MainScheduler.asyncInstance)
      .subscribe(
        onNext: { obTicker in
          guard let obTicker = obTicker else { return }
          let askData = obTicker.orderbookUnits.sorted(
            by: { $0.askPrice > $1.askPrice }
          ).map { OrderUnit(type: .ask, price: $0.askPrice, size: $0.askSize) }
          let bidData = obTicker.orderbookUnits.sorted(
            by: { $0.bidPrice < $1.bidPrice }
          ).map { OrderUnit(type: .bid, price: $0.bidPrice, size: $0.bidSize) }
          let orderDatas = askData + bidData
          self.applySnapshot(orderDatas: orderDatas)
        }
      )
      .disposed(by: self.disposeBag)
  }
}

// MARK: TableView Delegate
extension CryptoDetailViewController: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    print("orderbook cell click : \(indexPath.row)")
  }
}
