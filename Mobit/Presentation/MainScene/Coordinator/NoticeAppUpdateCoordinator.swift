//
//  NoticeAppUpdateCoordinator.swift
//  Mobit
//
//  Created by 조성재 on 7/6/25.
//

import UIKit

class NoticeAppUpdateCoordinator: BaseCoordinator {
  var childCoordinators = [BaseCoordinator]()
  var navigationController: UINavigationController
  weak var delegate: MainCoordinatorDelegate?
  
  init(navigationController: UINavigationController) {
	self.navigationController = navigationController
	self.navigationController.isNavigationBarHidden = true
  }
  
  func start() {
	let noticeVC = NoticeForceUpdateViewController()
	noticeVC.hidesBottomBarWhenPushed = true
	noticeVC.delegate = self
	
	self.navigationController.pushViewController(noticeVC, animated: true)
  }
}

extension NoticeAppUpdateCoordinator: MainCoordinatorDelegate {
  func mainCoordinatorDidRequestShowTabBar() {
	self.delegate?.mainCoordinatorDidRequestShowTabBar()
  }
  
  func mainCoordinatorDidRequestHideTabBar() {
	self.delegate?.mainCoordinatorDidRequestHideTabBar()
  }
}
