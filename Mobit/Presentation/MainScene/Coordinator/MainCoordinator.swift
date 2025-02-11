//
//  MainCoordinator.swift
//  Mobit
//
//  Created by 조성재 on 7/16/24.
//

import UIKit

class MainCoordinator: NSObject, BaseCoordinator, UINavigationControllerDelegate {
  var childCoordinators = [BaseCoordinator]()
  var navigationController: UINavigationController
  
  init(navigationController: UINavigationController) {
    self.navigationController = navigationController
    self.navigationController.isNavigationBarHidden = true
  }
  
  func start() {
    self.navigationController.delegate = self
    let reactor = MainReactor(mainUseCase: MainUseCase(mainRepository: MainRepository()))
    let mainVC = MainViewController(reactor: reactor)
    mainVC.coordinator = self
    self.navigationController.viewControllers = [mainVC]
  }
  
  
  func pushCryptoDetailVC(selectCrypto: CryptoCellInfo) {
    let cryptoDetailCoordinator = CryptoDetailCoordinator(
	  selectCrypto: selectCrypto,
	  navigationController: self.navigationController
	)
    self.childCoordinators.append(cryptoDetailCoordinator)
    cryptoDetailCoordinator.start()
  }
  
  /// BTC 코인 목록 탭 노출
  func showBTCCoinList() {
    
  }
  
  /// 관심 코인 목록 탭 노출
  func showFavoriteCoinList() {
    
  }
  
  func navigationController(
    _ navigationController: UINavigationController,
    didShow viewController: UIViewController,
    animated: Bool
  ) {
    // 뒤로가기 이 후, mainVC로 돌아왔다면, 다시 socket 연결
    if let mainVC = viewController as? MainViewController {
      mainVC.reactor.action.onNext(.loadCrypto(selectedTab: .krw))
    }
  }
}
