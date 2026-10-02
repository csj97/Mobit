import UIKit

final class FuturesCoordinator: NSObject, BaseCoordinator, UINavigationControllerDelegate, MainCoordinatorDelegate {
  var childCoordinators: [BaseCoordinator] = []
  var navigationController = UINavigationController()
  let investmentNavigationController = UINavigationController()
  weak var delegate: MainCoordinatorDelegate?
  let reactor: FuturesAccountReactor
  private let marketReactor: MainReactor

  override init() {
    let exchange = ExchangeSelectionStore.currentExchange
    reactor = FuturesAccountReactor(account: TradingAccountID(exchange: exchange, product: .perpetual, currency: .krw))
    marketReactor = MainReactor(mainUseCase: MainUseCase(mainRepository: MainRepository(exchangeProvider: ExchangeAdapterRegistry.default)))
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
  }

  func openPNL() {
    let controller = PNLViewController()
    controller.futuresReactor = reactor
    investmentNavigationController.pushViewController(controller, animated: true)
    delegate?.mainCoordinatorDidRequestHideTabBar()
  }

  func disconnectSocket() { marketReactor.action.onNext(.disconnectSocket) }
  func switchExchange(_ exchange: Exchange) { delegate?.mainCoordinatorDidRequestExchangeSwitch(to: exchange) }

  func open(coin: CryptoCellInfo, from navigation: UINavigationController?) {
    guard coin.market.hasSuffix("/KRW"), let navigation else { return }
    let symbol = coin.market.components(separatedBy: "/").first ?? ""
    let information = AppDataManager.shared.cachedKRWCMCList.first { $0.symbol == symbol }
    let detail = CryptoDetailCoordinator(selectCrypto: coin, cmcInformation: information, navigationController: navigation)
    detail.futuresReactor = reactor
    detail.delegate = self
    childCoordinators.append(detail)
    detail.start()
    delegate?.mainCoordinatorDidRequestHideTabBar()
  }

  func open(position: FuturesPosition, from navigation: UINavigationController?) {
    if let coin = marketReactor.currentState.totalCryptoList.first(where: { $0.market == FuturesText.symbol(position.order.instrument) }) {
      open(coin: coin, from: navigation)
    } else if let navigation {
      let order = FuturesOrderViewController(reactor: reactor, instrument: position.order.instrument)
      order.title = FuturesText.symbol(position.order.instrument)
      navigation.setNavigationBarHidden(false, animated: false)
      navigation.pushViewController(order, animated: true)
      delegate?.mainCoordinatorDidRequestHideTabBar()
    }
  }

  func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
    if viewController is FuturesAccountViewController || viewController is FuturesInvestmentViewController {
      delegate?.mainCoordinatorDidRequestShowTabBar()
      childCoordinators.removeAll()
    }
  }
  func mainCoordinatorDidRequestShowTabBar() { delegate?.mainCoordinatorDidRequestShowTabBar() }
}
