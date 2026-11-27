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
  // 탭 구성 이후 거래소·상품 변경을 Scene의 청산 안내에 전달한다.
  var tradingSelectionChangedCallBack: (() -> Void)?
  
  init(navigationController: UINavigationController) {
    self.navigationController = navigationController
  }
  
  // 인트로에서 준비한 목록을 같은 Scene의 첫 탭 구성에 전달한다.
  lazy var appTabBarCoordinator = AppTabBarCoordinator(navigationController: navigationController)

  func start() {
    appTabBarCoordinator.mainScreenShownCallBack = mainScreenShownCallBack
    appTabBarCoordinator.tradingSelectionChangedCallBack = tradingSelectionChangedCallBack
    self.childCoordinators.append(appTabBarCoordinator)
    appTabBarCoordinator.start()
  }

  func showPushDestination(_ destination: PushNotificationDestination, exchange: Exchange?) {
    childCoordinators.compactMap { $0 as? AppTabBarCoordinator }.first?.showPushDestination(destination, exchange: exchange)
  }
}
