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
  func mainCoordinatorDidRequestExchangeSwitch(to exchange: Exchange)
}

/// optional로 사용할 수 있게 처리
extension MainCoordinatorDelegate {
  func mainCoordinatorDidRequestHideTabBar() { }
  func mainCoordinatorDidRequestShowTabBar() { }
  func mainCoordinatorDidRequestExchangeSwitch(to exchange: Exchange) { }
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
    let exchangeProvider = ExchangeAdapterRegistry.default
    let reactor = MainReactor(
      mainUseCase: MainUseCase(
        mainRepository: MainRepository(exchangeProvider: exchangeProvider)
      )
    )
	let mainVC = MainViewController(reactor: reactor)
	mainVC.coordinator = self
	self.navigationController.viewControllers = [mainVC]
  }
  
  func pushCryptoTradeVC(
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
  
  /// 공포·탐욕 지수 설명 바텀 시트
  func presentFearGreedInfoVC(fearGreedIndex: FearGreedIndex?) {
    let infoVC = FearGreedInfoViewController(fearGreedIndex: fearGreedIndex)
    infoVC.modalPresentationStyle = .pageSheet
    if let sheet = infoVC.sheetPresentationController {
      sheet.detents = [.medium(), .large()]
      sheet.prefersGrabberVisible = true
    }
    self.navigationController.present(infoVC, animated: true)
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

  func switchExchange(to exchange: Exchange) {
	self.delegate?.mainCoordinatorDidRequestExchangeSwitch(to: exchange)
  }
  
  /// 다른 탭(투자내역 등)에서 상세로 진입할 때, 메인 소켓을 메인 경로와 동일하게 제어한다.
  func disconnectSocket() {
    guard let mainVC = self.navigationController.viewControllers.first as? MainViewController else { return }
    mainVC.reactor.action.onNext(.disconnectSocket)
  }

  func resumeSocket() {
    guard let mainVC = self.navigationController.viewControllers.first as? MainViewController else { return }
    mainVC.reactor.action.onNext(.resumeSocket)
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
