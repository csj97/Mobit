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
  
  init(selectCrypto: CryptoCellInfo, navigationController: UINavigationController) {
    self.selectCrypto = selectCrypto
    self.navigationController = navigationController
    self.navigationController.isNavigationBarHidden = true
  }
  
  func start() {
    let reactor = CryptoDetailReactor(selectCrypto: self.selectCrypto, cryptoDetailUseCase: CryptoDetailUseCase(cryptoDetailRepository: CryptoDetailRepository()))
    let cryptoDetailVC = CryptoDetailViewController(reactor: reactor)
    cryptoDetailVC.coordinator = self
    self.navigationController.pushViewController(cryptoDetailVC, animated: true)
  }
  
}
