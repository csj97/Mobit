//
//  CryptoDetailCoordinator.swift
//  Mobit
//
//  Created by 조성재 on 8/19/24.
//

import UIKit

class CryptoDetailCoordinator: BaseCoordinator {
  var childCoordinators = [BaseCoordinator]()
  var navigationController: UINavigationController
  var selectCrypto: CryptoCellInfo
  weak var delegate: MainCoordinatorDelegate?
  
  init(selectCrypto: CryptoCellInfo, navigationController: UINavigationController) {
    self.selectCrypto = selectCrypto
    self.navigationController = navigationController
    self.navigationController.isNavigationBarHidden = true
  }
  
  func start() {
    let reactor = CryptoDetailReactor(
      selectCrypto: self.selectCrypto,
      cryptoDetailUseCase: CryptoDetailUseCase(
        cryptoDetailRepository: CryptoDetailRepository()
      )
    )
    let tradeVC =  TradeViewController(reactor: reactor)
    tradeVC.coordinator = self
	tradeVC.hidesBottomBarWhenPushed = true
	tradeVC.delegate = self
    self.navigationController.pushViewController(tradeVC, animated: true)
  }
}

extension CryptoDetailCoordinator: MainCoordinatorDelegate {
  func mainCoordinatorDidRequestShowTabBar() {
	self.delegate?.mainCoordinatorDidRequestShowTabBar()
  }
}
