//
//  NewsCoordinator.swift
//  Mobit
//
//  Created by 조성재 on 11/27/25.
//

import UIKit

class NewsCoordinator: BaseCoordinator {
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
		let newsVC = NewsViewController()
		newsVC.coordinator = self
		self.navigationController.viewControllers = [newsVC]
  }
}

extension NewsCoordinator: MainCoordinatorDelegate {
  func mainCoordinatorDidRequestShowTabBar() {
	self.delegate?.mainCoordinatorDidRequestShowTabBar()
  }
}
