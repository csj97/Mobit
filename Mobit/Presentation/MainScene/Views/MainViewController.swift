//
//  MainViewController.swift
//  Mobit
//
//  Created by 조성재 on 7/16/24.
//

import FlexLayout
import RxCocoa
import RxSwift
import PinLayout
import Then
import UIKit

class MainViewController: UIViewController {
  // coordinator <-> viewcontroller 강한 참조 사이클 방지
  var coordinator: MainCoordinator?
  let rootContainer: UIView = UIView()
  
  let label = UILabel().then {
    $0.textColor = .black
    $0.text = "mainviewcontroller Hello"
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    print("mainviewcontroller")
    self.view.backgroundColor = .white
    self.addViews()
    self.setUpFlexItems()
  }
  
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    
    rootContainer.pin.all(self.view.pin.safeArea)
    rootContainer.flex.layout()
  }
  
  func addViews() {
    self.view.addSubview(self.rootContainer)
  }
  
  func setUpFlexItems() {
    rootContainer.flex.define { flex in
      flex.addItem(self.label).alignItems(.center)
    }
  }
}
