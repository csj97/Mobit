//
//  InvestmentCoordinator.swift
//  Mobit
//
//  Created by 조성재 on 7/17/24.
//

import UIKit

class InvestmentCoordinator: NSObject, BaseCoordinator, UINavigationControllerDelegate {
  var childCoordinators = [BaseCoordinator]()
  var navigationController: UINavigationController
  var dataManager: AppDataManager
  weak var delegate: MainCoordinatorDelegate?

  // 상세(Trade) 진입/복귀 시 메인 소켓을 제어하기 위한 훅. 부모(AppTabBarCoordinator)가 주입한다.
  var onEnterCryptoDetail: (() -> Void)?
  var onExitCryptoDetail: (() -> Void)?

  init(
	navigationController: UINavigationController,
	dataManager: AppDataManager
  ) {
    self.navigationController = navigationController
	self.dataManager = dataManager
	super.init()
  }

  func start() {
	self.navigationController.delegate = self
	let reactor = InvestReactor(mainUseCase: MainUseCase(mainRepository: MainRepository()))
	let investmentVC = InvestmentViewController(reactor: reactor)
    investmentVC.coordinator = self
    self.navigationController.viewControllers = [investmentVC]
  }

  func navigationController(
	_ navigationController: UINavigationController,
	didShow viewController: UIViewController,
	animated: Bool
  ) {
	// 상세(Trade)에서 투자내역으로 복귀한 시점. 메인 경로의 didShow와 동일하게 메인 소켓을 재연결한다.
	if viewController is InvestmentViewController {
	  self.onExitCryptoDetail?()
	}
  }
  
  // CryptoTradeViewController 이동
  func pushCryptoTradeVC(
	selectCrypto: CryptoCellInfo,
	cmcSymbol: String,
	completion: ((String?) -> Void)? = nil
  ) {
	guard selectCrypto.market.contains("/") else {
	  let message = "해당 코인에 대한 정보 업데이트가 필요합니다.\n빠른 시일내에 해결하겠습니다."
	  completion?(message)
	  return
	}

	let cmcList = selectCrypto.market.contains("KRW")
	? self.dataManager.cachedKRWCMCList
	: self.dataManager.cachedBTCCMCList

	// CMC 정보가 없어도(nil) 이동은 진행한다. 정보 탭만 비활성 처리됨 (Main과 동일)
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
	// 메인 경로와 동일하게, 상세 진입 시 메인 소켓을 끊는다 (중복 소켓 방지)
	self.onEnterCryptoDetail?()

	completion?(nil)
  }
  
  func pushPnlVC() {
	let pnlCoordinator = PNLCoordinator(
	  navigationController: self.navigationController
	)
	self.childCoordinators.append(pnlCoordinator)
	pnlCoordinator.delegate = self
	pnlCoordinator.start()
	
	self.delegate?.mainCoordinatorDidRequestHideTabBar()
  }
}

extension InvestmentCoordinator: MainCoordinatorDelegate {
  func mainCoordinatorDidRequestShowTabBar() {
	self.delegate?.mainCoordinatorDidRequestShowTabBar()
  }
}
