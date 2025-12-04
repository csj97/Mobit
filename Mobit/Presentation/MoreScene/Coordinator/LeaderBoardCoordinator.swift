//
//  LeaderBoardCoordinator.swift
//  Mobit
//
//  Created by 조성재 on 12/3/25.
//

import UIKit

class LeaderBoardCoordinator: BaseCoordinator {
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
	let leaderboardVC = LeaderBoardViewController()
	leaderboardVC.coordinator = self
	leaderboardVC.delegate = self
	leaderboardVC.hidesBottomBarWhenPushed = true
	self.navigationController.pushViewController(leaderboardVC, animated: true)
  }
}

extension LeaderBoardCoordinator: MainCoordinatorDelegate {
  func mainCoordinatorDidRequestShowTabBar() {
	self.delegate?.mainCoordinatorDidRequestShowTabBar()
  }
}
