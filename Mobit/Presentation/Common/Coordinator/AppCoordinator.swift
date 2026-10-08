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
  // 인트로 이후 첫 화면의 실제 표시 완료를 앱 진입 흐름에 전달한다.
  var mainScreenShownCallBack: (() -> Void)?
  
  init(navigationController: UINavigationController) {
    self.navigationController = navigationController
  }
  
  func start() {
    let appTabBarCoordinator = AppTabBarCoordinator(navigationController: self.navigationController)
    appTabBarCoordinator.mainScreenShownCallBack = mainScreenShownCallBack
    self.childCoordinators.append(appTabBarCoordinator)
    appTabBarCoordinator.start()
  }
}
