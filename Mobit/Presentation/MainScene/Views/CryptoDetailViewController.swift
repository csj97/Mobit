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
  let text: UILabel = UILabel().then {
    $0.text = ""
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    self.view.backgroundColor = .white
    
    self.addViews()
    self.setUpFlexItems()
    
    self.text.text = self.reactor.selectCrypto
  }
  
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    
    self.rootContainer.pin.all(self.view.pin.safeArea)
    self.rootContainer.flex.layout()
  }
  
  func addViews() {
    self.view.addSubview(self.rootContainer)
    self.rootContainer.addSubview(self.text)
  }
  
  func setUpFlexItems() {
    rootContainer.flex
      .justifyContent(.start)
      .direction(.column).define { flex in
        flex.addItem(self.text).width(100%).height(30%)
      }
  }
  
}
