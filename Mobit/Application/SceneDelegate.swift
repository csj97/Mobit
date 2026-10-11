//
//  SceneDelegate.swift
//  Mobit
//
//  Created by 조성재 on 7/10/24.
//

import UIKit
import RxSwift

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

  var window: UIWindow?
  var appCoordinator: AppCoordinator?
  private let disposeBag = DisposeBag()
  // 인트로가 아니라 메인 화면이 실제 표시됐는지 확인한다.
  private var mainScreenShown = false
  // 청산 정산과 별개로 화면 준비·활성 상태에 맞춰 안내를 표시한다.
  private lazy var liquidationNotices = FuturesLiquidationNoticePresenter(
	window: window,
	canShow: { [weak self] account in
	  self?.mainScreenShown == true && self?.window?.windowScene?.activationState == .foregroundActive
		&& TradingRules.canShowLiquidationNotice(
		  for: account,
		  selectedExchange: ExchangeSelectionStore.currentExchange,
		  selectedProduct: ExchangeSelectionStore.currentProduct
		)
	}
  )

  func scene(
	_ scene: UIScene,
	willConnectTo session: UISceneSession,
	options connectionOptions: UIScene.ConnectionOptions
  ) {
	guard let windowScene = (scene as? UIWindowScene) else { return }
	let navigationController = UINavigationController()

	self.window = CustomWindow(frame: UIScreen.main.bounds)
	self.window?.windowScene = windowScene
	self.window?.overrideUserInterfaceStyle = UserDataManager.appTheme.userInterfaceStyle

	let mobitLaunchScreen = MobitLaunchScreen()
	self.window?.rootViewController = mobitLaunchScreen
	self.window?.makeKeyAndVisible()
	FuturesHistoryCheckService.shared.liquidationEvents
	  .subscribe(onNext: { [weak self] positions in self?.liquidationNotices.receive(positions) })
	  .disposed(by: disposeBag)

	AppDataManager.shared.refreshCMCData()

	FuturesHistoryCheckService.shared.prepareLaunch().subscribe(
	  onNext: { [weak self] _ in
		guard let self else { return }
		self.window?.rootViewController = navigationController

		self.appCoordinator = AppCoordinator(navigationController: navigationController)
		self.appCoordinator?.mainScreenShownCallBack = { [weak self] in
		  self?.mainScreenShown = true
		  self?.liquidationNotices.showPendingNotices()
		}
		self.appCoordinator?.tradingSelectionChangedCallBack = { [weak self] in
		  self?.liquidationNotices.showPendingNotices()
		}
		self.appCoordinator?.start()
	  }
	).disposed(by: disposeBag)
  }

  func sceneDidDisconnect(_ scene: UIScene) {
	liquidationNotices.suspend()
	// Called as the scene is being released by the system.
	// This occurs shortly after the scene enters the background, or when its session is discarded.
	// Release any resources associated with this scene that can be re-created the next time the scene connects.
	// The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
	liquidationNotices.showPendingNotices()
	RewardedAdManager.shared.retryPendingRewards()
	if TradingRules.Futures.HistoryCheck.shouldRefresh(
	  on: .appForeground,
	  selectedProduct: ExchangeSelectionStore.currentProduct
	) { FuturesHistoryCheckService.shared.refresh() }
	// Called when the scene has moved from an inactive state to an active state.
	// Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
  }

  func sceneWillResignActive(_ scene: UIScene) {
	liquidationNotices.suspend()
	FuturesHistoryCheckService.shared.suspend()
	// Called when the scene will move from an active state to an inactive state.
	// This may occur due to temporary interruptions (ex. an incoming phone call).
  }

  func sceneWillEnterForeground(_ scene: UIScene) {
	// Called as the scene transitions from the background to the foreground.
	// Use this method to undo the changes made on entering the background.
  }

  func sceneDidEnterBackground(_ scene: UIScene) {
	// Called as the scene transitions from the foreground to the background.
	// Use this method to save data, release shared resources, and store enough scene-specific state information
	// to restore the scene back to its current state.
  }

}

// 청산 저장은 서비스에서 완료하고, 이 객체는 안내의 표시 순서와 수명만 관리한다.
final class FuturesLiquidationNoticePresenter: NSObject {
  // 안내를 올릴 Scene의 창이며 창의 수명을 연장하지 않는다.
  private weak var window: UIWindow?
  // 메인 화면·Scene 활성 상태와 현재 선택한 거래 계좌를 함께 확인한다.
  private let canShow: (TradingAccountID) -> Bool
  // 표시 중인 안내도 닫힐 때까지 보관해 비활성화 중 유실을 막는다.
  private var pendingNotices: [[FuturesPosition]] = []
  // 다른 거래소 안내를 건너뛰어 표시한 항목만 닫을 때 제거한다.
  private var displayedNoticeIndex: Int?
  // 창에서 제거되면 해제되는 현재 안내다.
  private weak var banner: UILabel?
  // 수동 닫기와 비활성화 시 취소할 자동 닫기 작업이다.
  private var dismissWorkItem: DispatchWorkItem?

  init(window: UIWindow?, canShow: @escaping (TradingAccountID) -> Bool) {
	self.window = window
	self.canShow = canShow
	super.init()
  }

  func receive(_ positions: [FuturesPosition]) {
	guard !positions.isEmpty else { return }
	// 한 검증에서 여러 거래소가 청산돼도 안내는 계좌별로 분리한다.
	var notices: [[FuturesPosition]] = []
	for position in positions {
	  if let index = notices.firstIndex(where: { $0.first?.order.account == position.order.account }) {
		notices[index].append(position)
	  } else { notices.append([position]) }
	}
	pendingNotices.append(contentsOf: notices)
	showPendingNotices()
  }

  func showPendingNotices() {
	if let index = displayedNoticeIndex, let account = pendingNotices[index].first?.order.account,
	   !canShow(account) { suspend() }
	guard let window, banner == nil,
	  let index = pendingNotices.firstIndex(where: { notice in
		guard let account = notice.first?.order.account else { return false }
		return canShow(account)
	  }) else { return }
	// 현재 화면에 해당하는 계좌의 안내만 표시한다.
	let positions = pendingNotices[index]
	// 사용자에게 아직 전달되지 않은 첫 번째 청산 안내다.
	let notice = UILabel()
	notice.numberOfLines = 0
	notice.font = .preferredFont(forTextStyle: .subheadline)
	notice.adjustsFontForContentSizeCategory = true
	notice.textAlignment = .center
	notice.textColor = .mobitColors(.textPrimary)
	notice.backgroundColor = .mobitColors(.surfacePrimary)
	notice.layer.cornerRadius = 12
	notice.clipsToBounds = true
	notice.text = positions.map { position in
	  String(
		format: FuturesText.text("futures_liquidation_notice"),
		FuturesText.text(position.order.account.exchange == .upbit ? "futures_upbit" : "futures_bithumb"),
		FuturesText.symbol(position.order.instrument),
		FuturesText.text(position.order.side == .long ? "futures_long" : "futures_short"),
		position.order.leverage
	  )
	}.joined(separator: "\n")
	notice.isUserInteractionEnabled = true
	notice.accessibilityIdentifier = "futuresLiquidationNotice"
	notice.accessibilityCustomActions = [
	  UIAccessibilityCustomAction(
		name: FuturesText.text("futures_dismiss_notice"),
		target: self,
		selector: #selector(dismissForAccessibility)
	  )
	]
	notice.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissNotice)))
	// 위로 올리는 동작만 안내 닫기로 인식한다.
	let swipe = UISwipeGestureRecognizer(target: self, action: #selector(dismissNotice))
	swipe.direction = .up
	notice.addGestureRecognizer(swipe)
	window.addSubview(notice)
	notice.translatesAutoresizingMaskIntoConstraints = false
	NSLayoutConstraint.activate([
	  notice.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 8),
	  notice.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 16),
	  notice.trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -16),
	  notice.heightAnchor.constraint(greaterThanOrEqualToConstant: 64)
	])
	banner = notice
	displayedNoticeIndex = index
	UIAccessibility.post(notification: .announcement, argument: notice.text)
	// 대기 시간이 아닌 실제 화면에 표시한 시점부터 3초를 센다.
	let dismiss = DispatchWorkItem { [weak self, weak notice] in
	  guard let self, let notice, self.banner === notice else { return }
	  self.dismissNotice()
	}
	dismissWorkItem = dismiss
	DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: dismiss)
  }

  @objc func dismissNotice() {
	guard let banner, banner.isUserInteractionEnabled, let index = displayedNoticeIndex else { return }
	dismissWorkItem?.cancel()
	dismissWorkItem = nil
	banner.isUserInteractionEnabled = false
	// Auto Layout으로 확정한 높이만큼 이동해 화면 위로 완전히 사라지게 한다.
	window?.layoutIfNeeded()
	UIView.animate(
	  withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.25,
	  delay: 0,
	  options: [.beginFromCurrentState, .curveEaseIn],
	  animations: {
		banner.transform = CGAffineTransform(translationX: 0, y: -banner.frame.maxY)
		banner.alpha = 0
	  },
	  completion: { [weak self] _ in
		guard let self, self.banner === banner else { return }
		banner.removeFromSuperview()
		self.banner = nil
		self.displayedNoticeIndex = nil
		self.pendingNotices.remove(at: index)
		self.showPendingNotices()
	  }
	)
  }

  @objc private func dismissForAccessibility() -> Bool {
	dismissNotice()
	return true
  }

  func suspend() {
	dismissWorkItem?.cancel()
	dismissWorkItem = nil
	// 닫기 애니메이션이 끝나더라도 보관 중인 안내를 삭제하지 않도록 연결을 먼저 끊는다.
	let notice = banner
	banner = nil
	displayedNoticeIndex = nil
	notice?.layer.removeAllAnimations()
	notice?.removeFromSuperview()
  }
}
