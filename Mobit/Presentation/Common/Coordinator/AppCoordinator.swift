//
//  AppCoordinator.swift
//  Mobit
//
//  Created by 조성재 on 7/11/24.
//

import UIKit

class AppCoordinator: BaseCoordinator {
  var childCoordinators = [BaseCoordinator]()
  var navigationController: UINavigationController
  
  init(navigationController: UINavigationController) {
    self.navigationController = navigationController
  }
  
  func start() {
    let appTabBarCoordinator = AppTabBarCoordinator(navigationController: self.navigationController)
    self.childCoordinators.append(appTabBarCoordinator)
    appTabBarCoordinator.start()
  }
}
