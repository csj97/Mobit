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
  
  init(navigationController: UINavigationController) {
    self.navigationController = navigationController
  }
  
  func start() {
    let moreVC = MoreViewController()
    moreVC.coordinator = self
    self.navigationController.viewControllers = [moreVC]
  }
}
