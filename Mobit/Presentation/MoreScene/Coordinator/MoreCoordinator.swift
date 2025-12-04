//
//  MoreCoordinator.swift
//  Mobit
//
//  Created by 조성재 on 7/17/24.
//

import UIKit

class MoreCoordinator: BaseCoordinator {
  var childCoordinators = [BaseCoordinator]()
  var navigationController: UINavigationController
  weak var delegate: MainCoordinatorDelegate?
  
  init(navigationController: UINavigationController) {
    self.navigationController = navigationController
  }
  
  func start() {
    let moreVC = MoreViewController()
    moreVC.coordinator = self
    self.navigationController.viewControllers = [moreVC]
  }
  
  func pushMobitCommunityViewController() {
	let mobitCommunityCoordinator = MobitCommunityCoordinator(
	  navigationController: self.navigationController
	)
	self.childCoordinators.append(mobitCommunityCoordinator)
	mobitCommunityCoordinator.delegate = self
	mobitCommunityCoordinator.start()
	
	// 하단 탭바 숨기기
	self.delegate?.mainCoordinatorDidRequestHideTabBar()
  }
  
  func pushBinanceLeaderBoardViewController() {
	let leaderboardCoordinator = LeaderBoardCoordinator(
	  navigationController: self.navigationController
	)
	self.childCoordinators.append(leaderboardCoordinator)
	leaderboardCoordinator.delegate = self
	leaderboardCoordinator.start()
	
	// 하단 탭바 숨기기
	self.delegate?.mainCoordinatorDidRequestHideTabBar()
  }
}

extension MoreCoordinator: MainCoordinatorDelegate {
  /// 하단 탭바 노출
  func mainCoordinatorDidRequestShowTabBar() {
	self.delegate?.mainCoordinatorDidRequestShowTabBar()
  }
}
