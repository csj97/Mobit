import UIKit

final class FuturesCoordinator: NSObject, BaseCoordinator, UINavigationControllerDelegate, MainCoordinatorDelegate {
  var childCoordinators: [BaseCoordinator] = []
  var navigationController = UINavigationController()
  let investmentNavigationController = UINavigationController()
  weak var delegate: MainCoordinatorDelegate?
  let reactor: FuturesAccountReactor
  private let marketReactor: MainReactor

  override convenience init() {
	let exchange = ExchangeSelectionStore.currentExchange
    self.init(
      reactor: FuturesAccountReactor(account: TradingAccountID(exchange: exchange, product: .perpetual, currency: .krw)),
      marketReactor: MainReactor(
        mainUseCase: MainUseCase(mainRepository: MainRepository(exchangeProvider: ExchangeAdapterRegistry.default))
      )
    )
  }

  init(reactor: FuturesAccountReactor, marketReactor: MainReactor) {
    self.reactor = reactor
    self.marketReactor = marketReactor
	super.init()
  }

  func start() {
	for (navigation, section) in [(navigationController, FuturesAccountViewController.Section.market)] {
	  navigation.delegate = self
	  navigation.isNavigationBarHidden = true
	  let controller = FuturesAccountViewController(reactor: reactor, marketReactor: marketReactor, section: section)
	  controller.coordinator = self
	  navigation.viewControllers = [controller]
	}
	investmentNavigationController.delegate = self
	investmentNavigationController.isNavigationBarHidden = true
	let investment = FuturesInvestmentViewController(reactor: reactor, marketReactor: marketReactor)
	investment.coordinator = self
	investmentNavigationController.viewControllers = [investment]
    // 저장된 포지션을 누르기 전에 같은 상세 진입에 필요한 종목 조회를 시작한다.
    marketReactor.action.onNext(.loadCryptoList)
  }

  func openPNL() {
	let controller = PNLViewController()
	controller.futuresReactor = reactor
	controller.delegate = self
	investmentNavigationController.pushViewController(controller, animated: true)
	delegate?.mainCoordinatorDidRequestHideTabBar()
  }

  func disconnectSocket() { marketReactor.action.onNext(.disconnectSocket) }
  func switchExchange(_ exchange: Exchange) { delegate?.mainCoordinatorDidRequestExchangeSwitch(to: exchange) }

  func open(coin: CryptoCellInfo, from navigation: UINavigationController?) {
    openTrade(market: coin.market, from: navigation)
  }

  func open(position: FuturesPosition, from navigation: UINavigationController?) {
    guard position.order.account == reactor.account else { return }
    openTrade(market: FuturesText.symbol(position.order.instrument), from: navigation)
  }

  // 목록 조회 상태를 검증한 뒤 마켓·투자내역 모두 같은 TradeVC 경로로 이동한다.
  private func openTrade(market: String, from navigation: UINavigationController?) {
    guard let navigation, navigation.transitionCoordinator == nil,
      navigation.topViewController?.presentedViewController == nil,
      !(navigation.topViewController is TradeViewController)
    else { return }
    guard reactor.account.exchange == ExchangeSelectionStore.currentExchange, market.hasSuffix("/KRW") else {
      showEntryAlert("futures_trade_unavailable", from: navigation)
      return
    }
    // 화면에 남아 있는 목록 대신 같은 계좌의 최신 조회 상태로 진입 가능 여부를 판단한다.
    let state = marketReactor.currentState
    if state.isLoading {
      showEntryAlert("futures_trade_loading", from: navigation)
      return
    }
    if state.errorMessage != nil {
      showEntryAlert("futures_trade_load_failed", from: navigation, retry: true)
      return
    }
    guard let coin = state.totalCryptoList.first(where: { $0.market == market }), !coin.isUpcomingListing else {
      showEntryAlert("futures_trade_unavailable", from: navigation, retry: true)
      return
    }
	let symbol = coin.market.components(separatedBy: "/").first ?? ""
	let information = AppDataManager.shared.cachedKRWCMCList.first { $0.symbol == symbol }
	let detail = CryptoDetailCoordinator(
	  selectCrypto: coin,
	  cmcInformation: information,
	  navigationController: navigation
	)
	detail.futuresReactor = reactor
	detail.delegate = self
	childCoordinators.append(detail)
	detail.start()
	delegate?.mainCoordinatorDidRequestHideTabBar()
  }

  private func showEntryAlert(_ key: String, from navigation: UINavigationController, retry: Bool = false) {
    guard let presenter = navigation.topViewController, presenter.presentedViewController == nil else { return }
    // 준비되지 않은 상세 화면 대신 표시하는 안내이며 뒤의 내비게이션 상태는 유지한다.
    let alert = UIAlertController(title: FuturesText.text("common_notice"), message: FuturesText.text(key), preferredStyle: .alert)
    if retry {
      alert.addAction(
        UIAlertAction(title: FuturesText.text("futures_trade_retry"), style: .default) { [weak self] _ in
          self?.marketReactor.action.onNext(.loadCryptoList)
        }
      )
      alert.addAction(UIAlertAction(title: FuturesText.text("common_cancel"), style: .cancel))
    } else {
      alert.addAction(UIAlertAction(title: FuturesText.text("common_confirm"), style: .default))
    }
    presenter.present(alert, animated: true)
  }

  func navigationController(
	_ navigationController: UINavigationController,
	didShow viewController: UIViewController,
	animated: Bool
  ) {
	if viewController is FuturesAccountViewController || viewController is FuturesInvestmentViewController {
	  delegate?.mainCoordinatorDidRequestShowTabBar()
	  childCoordinators.removeAll()
	}
  }
  func mainCoordinatorDidRequestShowTabBar() { delegate?.mainCoordinatorDidRequestShowTabBar() }
}
