//
//  File.swift
//  Mobit
//
//  Created by 조성재 on 7/29/25.
//

import UIKit

class PNLCoordinator: BaseCoordinator {
  var childCoordinators = [BaseCoordinator]()
  var navigationController: UINavigationController
  weak var delegate: MainCoordinatorDelegate?
  
  init(navigationController: UINavigationController) {
	self.navigationController = navigationController
  }
  
  func start() {
	let pnlVC = PNLViewController()
	pnlVC.coordinator = self
	pnlVC.hidesBottomBarWhenPushed = true
	pnlVC.delegate = self
	self.navigationController.pushViewController(pnlVC, animated: true)
  }
}

extension PNLCoordinator: MainCoordinatorDelegate {
  func mainCoordinatorDidRequestShowTabBar() {
	self.delegate?.mainCoordinatorDidRequestShowTabBar()
  }
}
