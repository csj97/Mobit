//
//  Coordinator.swift
//  Mobit
//
//  Created by 조성재 on 7/11/24.
//

import UIKit

protocol BaseCoordinator: AnyObject {
  var childCoordinators: [BaseCoordinator] { get set }
  var navigationController: UINavigationController { get set }
  
  func start()
}
