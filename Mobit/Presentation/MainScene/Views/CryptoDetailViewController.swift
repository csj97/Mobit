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
    $0.font = UIFont.systemFont(ofSize: 11)
  }
  
  
  override func viewDidLoad() {
    super.viewDidLoad()
    self.view.backgroundColor = .white
    
    self.addViews()
    self.setUpViews()
    self.setButtons()
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
    self.rootContainer.addSubview(self.titleLabel)
    self.rootContainer.addSubview(self.favoriteButton)
    self.rootContainer.addSubview(self.priceLabel)
    self.rootContainer.addSubview(self.changeRateLabel)
    self.rootContainer.addSubview(self.changePriceImageView)
    self.rootContainer.addSubview(self.changePriceLabel)
  }
  
  func setUpViews(crypto: CryptoCellInfo? = nil) {
    
    let numberFormatter = NumberFormatter()
    numberFormatter.numberStyle = .decimal
    
    let selectCrypto = crypto ?? self.reactor.selectCrypto
    guard let tradePrice = selectCrypto.tradePrice,
          let signedChangeRate = selectCrypto.signedChangeRate,
          let changePrice = selectCrypto.changePrice else { return }
    
    self.titleLabel.text = "\(selectCrypto.cryptoName)(\(selectCrypto.market))"
    if selectCrypto.tradePrice ?? 0 < 1 {
      self.priceLabel.text = self.formatTradePrice(tradePrice)
    } else {
      self.priceLabel.text = numberFormatter
        .string(from: NSNumber(value: selectCrypto.tradePrice ?? 0))
    }
    
    self.changeRateLabel.text = String(
      format: "%.2f%%",
      signedChangeRate * 100
    )
    
    if changePrice < 1 {
      self.changePriceLabel.text = self
        .formatTradePrice(changePrice)
    } else {
      self.changePriceLabel.text = numberFormatter
        .string(from: NSNumber(value: changePrice))
    }
    
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
    
    self.reactor.action
      .onNext(.connectTickerSocket(cryptoCellInfo: selectCrypto))
  }
  
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
                  }.marginLeft(20)
              }
              .marginLeft(16)
          }
          .width(100%)
      }
  }
  
}

extension CryptoDetailViewController {
  func setButtons() {
    self.backButton
      .addTarget(
        self,
        action: #selector(tapOnBackButton(_:)),
        for: .touchUpInside
      )
  }
  
  @objc private func tapOnBackButton(_ sender: UIButton) {
    self.coordinator?.navigationController.popViewController(animated: true)
  }
  
  func formatTradePrice(_ tradePrice: Double?, precision: Int = 8) -> String {
    guard let price = tradePrice else {
      return "N/A"  // 값이 없을 때 반환할 기본 문자열
    }
    return String(format: "%.\(precision)f", price)
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
  }
}
