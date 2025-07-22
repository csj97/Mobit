//
//  MobitCommunityCoordinator.swift
//  Mobit
//
//  Created by 조성재 on 7/17/25.
//

import UIKit

class MobitCommunityCoordinator: BaseCoordinator {
  var childCoordinators = [BaseCoordinator]()
  var navigationController: UINavigationController
  weak var delegate: MainCoordinatorDelegate?
  
  init(
	navigationController: UINavigationController
  ) {
	self.navigationController = navigationController
	self.navigationController.isNavigationBarHidden = true
  }
  
  func start() {
	let mobitCommunityVC = MobitCommunityViewController()
	mobitCommunityVC.coordinator = self
	mobitCommunityVC.delegate = self
	mobitCommunityVC.hidesBottomBarWhenPushed = true
	self.navigationController.pushViewController(mobitCommunityVC, animated: true)
  }
}

extension MobitCommunityCoordinator: MainCoordinatorDelegate {
  func mainCoordinatorDidRequestShowTabBar() {
	self.delegate?.mainCoordinatorDidRequestShowTabBar()
  }
}
