//
//  MainTabBarCoordinator.swift
//  Mobit
//
//  Created by 조성재 on 7/16/24.
//

import UIKit

class AppTabBarCoordinator: BaseCoordinator {
  var childCoordinators = [BaseCoordinator]()
  var navigationController: UINavigationController
  private let mobitTabBarController = MobitTabBarViewController()
  
  init(navigationController: UINavigationController) {
    self.navigationController = navigationController
  }
  
  func start() {
	// 메인화면
	let mainNavigation = UINavigationController()
	let mainCoordinator = MainCoordinator(
	  navigationController: mainNavigation,
	  dataManager: AppDataManager.shared
	)
	mainCoordinator.delegate = self
	self.childCoordinators.append(mainCoordinator)
	mainCoordinator.start()
	
	// 투자내역 화면
	let investNavigation = UINavigationController()
	let investmentCoordinator = InvestmentCoordinator(
	  navigationController: investNavigation,
	  dataManager: AppDataManager.shared
	)
	investmentCoordinator.delegate = self
	self.childCoordinators.append(investmentCoordinator)
	investmentCoordinator.start()
	
	let newsNavigation = UINavigationController()
	let newsCoordinator = NewsCoordinator(
	  navigationController: newsNavigation,
	  dataManager: AppDataManager.shared
	)
	newsCoordinator.delegate = self
	self.childCoordinators.append(newsCoordinator)
	newsCoordinator.start()
	
	// 더보기 화면
	let moreNavigation = UINavigationController()
	let moreCoordinator = MoreCoordinator(navigationController: moreNavigation)
	moreCoordinator.delegate = self
	self.childCoordinators.append(moreCoordinator)
	moreCoordinator.start()
	
	// TabBar viewcontroller 설정
	self.mobitTabBarController.setViewControllers([
	  mainCoordinator.navigationController,
	  investmentCoordinator.navigationController,
	  newsCoordinator.navigationController,
	  moreCoordinator.navigationController
	])
	
	self.navigationController.viewControllers = [mobitTabBarController]
	self.navigationController.isNavigationBarHidden = true
  }
}

extension AppTabBarCoordinator: MainCoordinatorDelegate {
  func mainCoordinatorDidRequestHideTabBar() {
	self.mobitTabBarController.mobitTabBar.isHidden = true
  }
  
  func mainCoordinatorDidRequestShowTabBar() {
	self.mobitTabBarController.mobitTabBar.isHidden = false
  }
}
