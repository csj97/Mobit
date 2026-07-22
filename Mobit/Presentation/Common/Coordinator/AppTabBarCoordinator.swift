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
  private var mainCoordinator: MainCoordinator?
  private var investmentCoordinator: InvestmentCoordinator?
  private var newsCoordinator: NewsCoordinator?
  private var moreCoordinator: MoreCoordinator?
  
  init(navigationController: UINavigationController) {
    self.navigationController = navigationController
  }
  
  func start() {
	self.configureTabs(selectedIndex: 0)
	self.navigationController.viewControllers = [mobitTabBarController]
	self.navigationController.isNavigationBarHidden = true
  }

  func switchExchange(to exchange: Exchange) {
	guard ExchangeSelectionStore.currentExchange != exchange else { return }
	// 새 거래소 탭을 구성하기 전에 이전 거래소 소켓 연결을 먼저 종료한다.
	self.mainCoordinator?.disconnectSocket()
	ExchangeSelectionStore.currentExchange = exchange
	// 전환된 거래소의 보유 현금을 구독자에게 즉시 반영한다.
	UserDataManager.publishCurrentExchangeBalance()
	// 정보탭 CMC 캐시를 새 거래소 기준으로 갱신한다.
	AppDataManager.shared.refreshCMCData(for: exchange)
	self.configureTabs(selectedIndex: 0)
  }

  private func configureTabs(selectedIndex: Int) {
	let mainNavigation = UINavigationController()
	let mainCoordinator = MainCoordinator(
	  navigationController: mainNavigation,
	  dataManager: AppDataManager.shared
	)
	mainCoordinator.delegate = self
	mainCoordinator.start()

	let investNavigation = UINavigationController()
	let investmentCoordinator = InvestmentCoordinator(
	  navigationController: investNavigation,
	  dataManager: AppDataManager.shared
	)
	investmentCoordinator.delegate = self
	investmentCoordinator.onEnterCryptoDetail = { [weak mainCoordinator] in
	  mainCoordinator?.disconnectSocket()
	}
	investmentCoordinator.onExitCryptoDetail = { [weak mainCoordinator] in
	  mainCoordinator?.resumeSocket()
	}
	investmentCoordinator.start()

	let newsNavigation = UINavigationController()
	let newsCoordinator = NewsCoordinator(
	  navigationController: newsNavigation,
	  dataManager: AppDataManager.shared
	)
	newsCoordinator.delegate = self
	newsCoordinator.start()

	let moreNavigation = UINavigationController()
	let moreCoordinator = MoreCoordinator(navigationController: moreNavigation)
	moreCoordinator.delegate = self
	moreCoordinator.start()

	self.mainCoordinator = mainCoordinator
	self.investmentCoordinator = investmentCoordinator
	self.newsCoordinator = newsCoordinator
	self.moreCoordinator = moreCoordinator
	self.childCoordinators = [
	  mainCoordinator,
	  investmentCoordinator,
	  newsCoordinator,
	  moreCoordinator
	]

	self.mobitTabBarController.setViewControllers([
	  mainCoordinator.navigationController,
	  investmentCoordinator.navigationController,
	  newsCoordinator.navigationController,
	  moreCoordinator.navigationController
	], selectedIndex: selectedIndex)
  }
}

extension AppTabBarCoordinator: MainCoordinatorDelegate {
  func mainCoordinatorDidRequestHideTabBar() {
	self.mobitTabBarController.mobitTabBar.isHidden = true
  }
  
  func mainCoordinatorDidRequestShowTabBar() {
	self.mobitTabBarController.mobitTabBar.isHidden = false
  }

  func mainCoordinatorDidRequestExchangeSwitch(to exchange: Exchange) {
	self.switchExchange(to: exchange)
  }
}
