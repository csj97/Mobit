//
//  InvestmentCoordinator.swift
//  Mobit
//
//  Created by 조성재 on 7/17/24.
//

import UIKit

class InvestmentCoordinator: BaseCoordinator {
  var childCoordinators = [BaseCoordinator]()
  var navigationController: UINavigationController
  weak var delegate: MainCoordinatorDelegate?
  
  init(navigationController: UINavigationController) {
    self.navigationController = navigationController
  }
  
  func start() {
	let reactor = InvestReactor()
	let investmentVC = InvestmentViewController(reactor: reactor)
    investmentVC.coordinator = self
    self.navigationController.viewControllers = [investmentVC]
  }
  
  func pushCryptoDetailVC(
	selectCrypto: CryptoCellInfo,
	cmcInformation: FirebaseCMCResponse
  ) {
	let cryptoDetailCoordinator = CryptoDetailCoordinator(
	  selectCrypto: selectCrypto,
	  cmcInformation: cmcInformation,
	  navigationController: self.navigationController
	)
	self.childCoordinators.append(cryptoDetailCoordinator)
	cryptoDetailCoordinator.delegate = self
	cryptoDetailCoordinator.start()
	
	self.delegate?.mainCoordinatorDidRequestHideTabBar()
  }
}

extension InvestmentCoordinator: MainCoordinatorDelegate {
  func mainCoordinatorDidRequestShowTabBar() {
	self.delegate?.mainCoordinatorDidRequestShowTabBar()
  }
}
