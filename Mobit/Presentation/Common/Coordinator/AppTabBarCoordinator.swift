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
    
    // 메인화면
    let mainNavigation = UINavigationController()
    let mainCoordinator = MainCoordinator(navigationController: mainNavigation)
    self.childCoordinators.append(mainCoordinator)
    mainCoordinator.start()
    
    let mainTabBarItem = UITabBarItem(
      title: "홈",
      image: UIImage(systemName: "folder.circle"),
      selectedImage: UIImage(systemName: "folder.circle.fill")
    )
    mainNavigation.tabBarItem = mainTabBarItem
    
    // 투자내역 화면
    let investNavigation = UINavigationController()
    let investmentCoordinator = InvestmentCoordinator(navigationController: investNavigation)
    self.childCoordinators.append(investmentCoordinator)
    investmentCoordinator.start()
    
    let investTabBarItem = UITabBarItem(
      title: "투자내역",
      image: UIImage(systemName: "doc.circle"),
      selectedImage: UIImage(systemName: "doc.circle.fill")
    )
    investNavigation.tabBarItem = investTabBarItem
    
    // 더보기 화면
    let moreNavigation = UINavigationController()
    let moreCoordinator = MoreCoordinator(navigationController: moreNavigation)
    self.childCoordinators.append(moreCoordinator)
    moreCoordinator.start()
    
    let moreTabBarItem = UITabBarItem(
      title: "더보기",
      image: UIImage(systemName: "ellipsis.circle"),
      selectedImage: UIImage(systemName: "ellipsis.circle.fill")
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
}
