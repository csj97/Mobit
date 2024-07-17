//
//  MainCoordinator.swift
//  Mobit
//
//  Created by 조성재 on 7/16/24.
//

import UIKit

class MainCoordinator: BaseCoordinator {
  var childCoordinators = [BaseCoordinator]()
  var navigationController: UINavigationController
  
  init(navigationController: UINavigationController) {
    self.navigationController = navigationController
  }
  
  func start() {
    let mainVC = MainViewController()
    mainVC.coordinator = self
    self.navigationController.viewControllers = [mainVC]
  }
  
  /// KRW 코인 목록 탭 노출
  func showKRWCoinList() {
    
  }
  
  /// BTC 코인 목록 탭 노출
  func showBTCCoinList() {
    
  }
  
  /// 관심 코인 목록 탭 노출
  func showFavoriteCoinList() {
    
  }
}
