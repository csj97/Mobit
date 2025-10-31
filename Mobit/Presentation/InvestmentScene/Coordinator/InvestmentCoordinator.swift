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
  var dataManager: AppDataManager
  weak var delegate: MainCoordinatorDelegate?
  
  init(
	navigationController: UINavigationController,
	dataManager: AppDataManager
  ) {
    self.navigationController = navigationController
	self.dataManager = dataManager
  }
  
  func start() {
	let reactor = InvestReactor()
	let investmentVC = InvestmentViewController(reactor: reactor)
    investmentVC.coordinator = self
    self.navigationController.viewControllers = [investmentVC]
  }
  
  func pushCryptoDetailVC(
	selectCrypto: CryptoCellInfo,
	cmcSymbol: String
  ) {
	let cmcList = selectCrypto.market.contains("KRW")
	? self.dataManager.cachedKRWCMCList
	: self.dataManager.cachedBTCCMCList
	
	guard let cmcInformation = cmcList.first(
	  where: { $0.symbol == cmcSymbol }
	) else { return }
	
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
  
  func pushPnlVC() {
	let pnlCoordinator = PNLCoordinator(
	  navigationController: self.navigationController
	)
	self.childCoordinators.append(pnlCoordinator)
	pnlCoordinator.delegate = self
	pnlCoordinator.start()
	
	self.delegate?.mainCoordinatorDidRequestHideTabBar()
  }
}

extension InvestmentCoordinator: MainCoordinatorDelegate {
  func mainCoordinatorDidRequestShowTabBar() {
	self.delegate?.mainCoordinatorDidRequestShowTabBar()
  }
}
