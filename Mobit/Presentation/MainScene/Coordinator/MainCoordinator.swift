//
//  MainCoordinator.swift
//  Mobit
//
//  Created by 조성재 on 7/16/24.
//

import UIKit

protocol MainCoordinatorDelegate: AnyObject {
  func mainCoordinatorDidRequestHideTabBar()
  func mainCoordinatorDidRequestShowTabBar()
}

/// optional로 사용할 수 있게 처리
extension MainCoordinatorDelegate {
  func mainCoordinatorDidRequestHideTabBar() { }
  func mainCoordinatorDidRequestShowTabBar() { }
}

class MainCoordinator: NSObject, BaseCoordinator, UINavigationControllerDelegate {
  var childCoordinators = [BaseCoordinator]()
  var navigationController: UINavigationController
  var dataManager: AppDataManager
  weak var delegate: MainCoordinatorDelegate?
  
  init(
	navigationController: UINavigationController,
	dataManager: AppDataManager
  ) {
	self.navigationController = navigationController
	self.navigationController.isNavigationBarHidden = true
	self.dataManager = dataManager
  }
  
  func start() {
	self.navigationController.delegate = self
	let reactor = MainReactor(mainUseCase: MainUseCase(mainRepository: MainRepository()))
	let mainVC = MainViewController(reactor: reactor)
	mainVC.coordinator = self
	self.navigationController.viewControllers = [mainVC]
  }
  
  func pushCryptoDetailVC(
	selectCrypto: CryptoCellInfo,
	cmcSymbol: String,
	completion: ((String?) -> Void)?
  ) {
	guard selectCrypto.market.contains("/") else {
	  let message = "해당 코인에 대한 정보 업데이트가 필요합니다.\n빠른 시일내에 해결하겠습니다."
	  completion?(message)
	  return
	}

	let cmcList = selectCrypto.market.contains("KRW")
	? self.dataManager.cachedKRWCMCList
	: self.dataManager.cachedBTCCMCList

	let cmcInformation = cmcList.first(where: { $0.symbol == cmcSymbol })
	
    let cryptoDetailCoordinator = CryptoDetailCoordinator(
	  selectCrypto: selectCrypto,
	  cmcInformation: cmcInformation,
	  navigationController: self.navigationController
	)
    self.childCoordinators.append(cryptoDetailCoordinator)
	cryptoDetailCoordinator.delegate = self
    cryptoDetailCoordinator.start()
	
	self.delegate?.mainCoordinatorDidRequestHideTabBar()
	
	completion?(nil)
  }
  
  func pushNoticeAppUpdateVC() {
	let noticeAppUpdateCoordinator = NoticeAppUpdateCoordinator(
	  navigationController: self.navigationController
	)
	self.childCoordinators.append(noticeAppUpdateCoordinator)
	noticeAppUpdateCoordinator.delegate = self
	noticeAppUpdateCoordinator.start()
	
	self.delegate?.mainCoordinatorDidRequestHideTabBar()
  }
  
  /// BTC 코인 목록 탭 노출
  func showBTCCoinList() {
    
  }
  
  /// 관심 코인 목록 탭 노출
  func showFavoriteCoinList() {
    
  }
  
  func navigationController(
    _ navigationController: UINavigationController,
    didShow viewController: UIViewController,
    animated: Bool
  ) {
    // 뒤로가기 이 후, mainVC로 돌아왔다면, 다시 socket 연결
    if let mainVC = viewController as? MainViewController {
      let hasLoadedData = !mainVC.reactor.currentState.totalCryptoList.isEmpty
      if hasLoadedData {
        mainVC.reactor.action.onNext(.resumeSocket)
      } else {
        mainVC.reactor.action.onNext(.loadCryptoList)
      }
    }
  }
}

extension MainCoordinator: MainCoordinatorDelegate {
  func mainCoordinatorDidRequestShowTabBar() {
	self.delegate?.mainCoordinatorDidRequestShowTabBar()
  }
}
