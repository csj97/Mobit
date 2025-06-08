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
  
  init(navigationController: UINavigationController) {
    self.navigationController = navigationController
  }
  
  func start() {
    let tabBarController = UITabBarController()
    
    setTabBarAppearance(tabBarController: tabBarController)
    
    // 메인화면
    let mainNavigation = UINavigationController()
    let mainCoordinator = MainCoordinator(navigationController: mainNavigation)
    self.childCoordinators.append(mainCoordinator)
    mainCoordinator.start()
    
    let mainTabBarItem = UITabBarItem(
      title: "거래소",
      image: UIImage(named: "bitcoin_convert"),
      selectedImage: UIImage(named: "bitcoin_convert")
    )
    mainNavigation.tabBarItem = mainTabBarItem
    
    // 투자내역 화면
    let investNavigation = UINavigationController()
    let investmentCoordinator = InvestmentCoordinator(navigationController: investNavigation)
    self.childCoordinators.append(investmentCoordinator)
    investmentCoordinator.start()
    
    let investTabBarItem = UITabBarItem(
      title: "투자내역",
      image: UIImage(named: "wallet"),
      selectedImage: UIImage(named: "wallet")
    )
    investNavigation.tabBarItem = investTabBarItem
    
    // 더보기 화면
    let moreNavigation = UINavigationController()
    let moreCoordinator = MoreCoordinator(navigationController: moreNavigation)
    self.childCoordinators.append(moreCoordinator)
    moreCoordinator.start()
    
    let moreTabBarItem = UITabBarItem(
      title: "더보기",
	  image: UIImage(named: "more_square"),
      selectedImage: UIImage(named: "more_square")
    )
    moreNavigation.tabBarItem = moreTabBarItem
    
    // TabBar viewcontroller 설정
    tabBarController.viewControllers = [
      mainCoordinator.navigationController,
      investmentCoordinator.navigationController,
      moreCoordinator.navigationController
    ]
    
    self.navigationController.viewControllers = [tabBarController]
    self.navigationController.isNavigationBarHidden = true
  }
  
  func setTabBarAppearance(tabBarController: UITabBarController) {
    let appearance = UITabBarAppearance()
    appearance.configureWithOpaqueBackground()
    appearance.backgroundColor = .white
    
    tabBarController.tabBar.standardAppearance = appearance
    tabBarController.tabBar.scrollEdgeAppearance = tabBarController.tabBar.standardAppearance
    tabBarController.tabBar.barTintColor = .white
    tabBarController.tabBar.isTranslucent = false
  }
}
