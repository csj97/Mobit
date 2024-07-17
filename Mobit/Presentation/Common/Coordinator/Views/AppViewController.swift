//
//  AppViewController.swift
//  Mobit
//
//  Created by 조성재 on 7/17/24.
//

import FlexLayout
import RxCocoa
import RxSwift
import PinLayout
import Then
import UIKit

// 껍데기 앱 viewcontroller
class AppViewController: UIViewController {
  // coordinator <-> viewcontroller 강한 참조 사이클 방지
  weak var coordinator: AppTabBarCoordinator?
  
  override func viewDidLoad() {
    super.viewDidLoad()
    self.view.backgroundColor = .white
    
  }
}
