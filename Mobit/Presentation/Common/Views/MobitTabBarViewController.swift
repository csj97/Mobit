//
//  MobitTabBarViewController.swift
//  Mobit
//
//  Created by 조성재 on 6/15/25.
//

import UIKit
import RxSwift
import SnapKit

enum TradingControlsLayout {
  // 공포·탐욕 버튼과 스위치의 최대 너비가 같은 배치 기준을 사용한다.
  static let accessorySize: CGFloat = 56
  // 하단 컨트롤과 화면 안전영역 사이의 최소 좌우 여백이다.
  static let horizontalInset: CGFloat = 16
  // 스위치가 길어져도 공포·탐욕 버튼과 확보할 최소 간격이다.
  static let accessorySpacing: CGFloat = 24
}

class MobitTabBarViewController: MobitBaseViewController {
  private enum ForegroundIndicatorState {
    case idle, background, checking
  }
  // 계좌별 복귀 표시 기회를 모든 탭과 거래 상세·종료 화면에서 공유한다.
  private var foregroundIndicatorState = ForegroundIndicatorState.idle
  // 계좌·상품 변경 시 이전 검증 구독을 함께 종료한다.
  private var foregroundDisposeBag = DisposeBag()
  // 자동 재시도와 화면 이벤트가 대기 상한을 다시 시작하지 못하게 한다.
  private var foregroundIndicatorTimeout: Disposable?

  deinit { foregroundIndicatorTimeout?.dispose() }

  func bindForegroundVerification(
    _ reactor: FuturesAccountReactor?,
    scheduler: SchedulerType = MainScheduler.instance
  ) {
    finishForegroundIndicator()
    foregroundDisposeBag = DisposeBag()
    guard let reactor else { return }
    NotificationCenter.default.rx.notification(UIApplication.willResignActiveNotification)
      .observe(on: MainScheduler.instance)
      .subscribe(onNext: { [weak self] _ in self?.finishForegroundIndicator() })
      .disposed(by: foregroundDisposeBag)
    NotificationCenter.default.rx.notification(UIApplication.didEnterBackgroundNotification)
      .observe(on: MainScheduler.instance)
      .subscribe(onNext: { [weak self] _ in
        guard let self else { return }
        self.foregroundIndicatorState = self.viewIfLoaded?.window != nil ? .background : .idle
      }).disposed(by: foregroundDisposeBag)
    NotificationCenter.default.rx.notification(UIApplication.didBecomeActiveNotification)
      .observe(on: MainScheduler.asyncInstance)
      .subscribe(onNext: { [weak self, weak reactor] _ in
        guard let self, let reactor, self.foregroundIndicatorState == .background else { return }
        self.foregroundIndicatorState = .checking
        self.updateForegroundIndicator(reactor, scheduler: scheduler)
      }).disposed(by: foregroundDisposeBag)
    reactor.state.observe(on: MainScheduler.asyncInstance)
      .subscribe(onNext: { [weak self, weak reactor] _ in
        guard let reactor else { return }
        self?.updateForegroundIndicator(reactor, scheduler: scheduler)
      }).disposed(by: foregroundDisposeBag)
  }

  private func updateForegroundIndicator(_ reactor: FuturesAccountReactor, scheduler: SchedulerType) {
    guard foregroundIndicatorState == .checking else { return }
    guard viewIfLoaded?.window != nil, UIApplication.shared.applicationState == .active,
      reactor.currentState.networkAvailable != false, !reactor.hasVerificationFailure, !reactor.canSubmit else {
      finishForegroundIndicator()
      return
    }
    showLoadingIndicator()
    guard foregroundIndicatorTimeout == nil else { return }
    foregroundIndicatorTimeout = Observable<Int>.timer(MainReactor.marketRequestTimeout, scheduler: scheduler)
      .observe(on: MainScheduler.instance)
      .subscribe(onNext: { [weak self] _ in self?.finishForegroundIndicator() })
  }

  // 하위 화면의 실제 오류 안내도 공통 복귀 잠금보다 우선한다.
  func finishForegroundIndicator() {
    foregroundIndicatorState = .idle
    foregroundIndicatorTimeout?.dispose()
    foregroundIndicatorTimeout = nil
    hideLoadingIndicator()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    finishForegroundIndicator()
  }

  // 탭바 표시 스타일. 이 값만 바꾸면 하단 밀착/플로팅 사이를 전환한다.
  // (뷰 로드 전에 설정해야 반영된다. 기본값 변경 또는 AppTabBarCoordinator에서 지정)
  enum Style {
	case standard  // 화면 하단에 밀착된 일반 탭바
	case floating  // 하단에서 띄운 카드형 탭바
  }
  var style: Style = .standard

  let mobitTabBar = MobitTabBar(tabItems: [.exchange, .wallet, .news, .more])
  private var currentViewController: UIViewController?
  private var viewControllers: [UIViewController] = []
  private(set) var selectedIndex: Int = 0

  private let productControl = TradingProductControl()
  // 공포·탐욕 버튼이 있는 거래소 탭에서만 오른쪽 공간을 추가로 확보한다.
  private var productTrailingConstraint: Constraint?
  var onProductSelected: ((TradingProduct) -> Void)?
  private var tradingChromeHidden = false

  func setProduct(_ product: TradingProduct) {
    loadViewIfNeeded()
    productControl.selectedSegmentIndex = product == .spot ? 0 : 1
  }

  func setTradingChromeHidden(_ hidden: Bool) {
    tradingChromeHidden = hidden
    mobitTabBar.isHidden = hidden
    updateProductVisibility()
  }

  private func updateProductVisibility() {
    let visible = !tradingChromeHidden && selectedIndex < 2
    productControl.isHidden = !visible
    // 거래소에만 있는 부속 버튼을 제외한 범위까지 스위치를 확장할 수 있다.
    let trailingInset = TradingControlsLayout.horizontalInset
      + (selectedIndex == 0 ? TradingControlsLayout.accessorySize + TradingControlsLayout.accessorySpacing : 0)
    productTrailingConstraint?.update(offset: -trailingInset)
    updateContentSafeArea()
  }

  private func updateContentSafeArea() {
    guard let currentViewController else { return }
    guard productControl.isHidden || productControl.bounds.height > 0 else { return }
    // 거래소의 기존 여백은 유지하고 투자내역에만 스위치 실측 높이를 반영한다.
    let bottomInset: CGFloat
    if productControl.isHidden {
      bottomInset = 0
    } else if selectedIndex == 0 {
      bottomInset = 76
    } else {
      bottomInset = max(0, view.safeAreaLayoutGuide.layoutFrame.maxY - productControl.frame.minY)
    }
    guard currentViewController.additionalSafeAreaInsets.bottom != bottomInset else { return }
    currentViewController.additionalSafeAreaInsets.bottom = bottomInset
  }

  @objc private func selectProduct() {
    onProductSelected?(productControl.selectedSegmentIndex == 0 ? .spot : .perpetual)
  }

  func alignTradingAccessory(_ accessory: UIView) {
    guard let container = accessory.superview, container.isDescendant(of: view),
      productControl.bounds.height > 0 else { return }
    let controlFrame = productControl.convert(productControl.bounds, to: container)
    let bottomOffset = controlFrame.midY + accessory.bounds.height / 2 - container.safeAreaLayoutGuide.layoutFrame.maxY
    // 화면이 내비게이션 계층에서 분리돼도 버튼의 위치 제약은 소유 화면 안에 남긴다.
    accessory.snp.updateConstraints {
      $0.bottom.equalTo(container.safeAreaLayoutGuide).offset(bottomOffset)
    }
  }

  func getTradingContentBottomInset(in contentView: UIView) -> CGFloat {
    // 실제로 겹치는 하단 컨트롤만 제외해 목록의 빈 안내 영역을 계산한다.
    let coveredTop = [productControl, mobitTabBar].compactMap { control -> CGFloat? in
      guard !control.isHidden, control.bounds.height > 0 else { return nil }
      // 자식 화면의 Safe Area가 이미 제외한 영역을 중복 차감하지 않는다.
      let frame = control.convert(control.bounds, to: contentView)
      return frame.intersects(contentView.bounds) ? frame.minY : nil
    }.min()
    guard let coveredTop else { return 0 }
    return min(contentView.bounds.height, max(0, contentView.bounds.maxY - coveredTop))
  }

  var onTabSelected: ((Int) -> Void)?
  // 첫 화면 표시 완료 후 대기 중인 앱 안내를 노출한다.
  var didAppearCallBack: (() -> Void)?

  override func viewDidAppear(_ animated: Bool) {
	super.viewDidAppear(animated)
	didAppearCallBack?()
	didAppearCallBack = nil
  }

  override func viewDidLoad() {
	super.viewDidLoad()
	setupUI()

	mobitTabBar.didSelectItem = { [weak self] index in
	  self?.switchToTab(index: index)
	  self?.onTabSelected?(index)
	}
  }

  override func viewDidLayoutSubviews() {
	super.viewDidLayoutSubviews()
	// 플로팅 스타일에서만 카드형 둥근 모서리 적용
	mobitTabBar.layer.cornerRadius = style == .floating ? 30 : 0
    updateContentSafeArea()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
	applyTabBarShadow()
  }

  private func setupUI() {
	view.backgroundColor = .clear
	view.addSubview(mobitTabBar)
	UITabBar.clearShadow()
    view.addSubview(productControl)
    productControl.accessibilityLabel = FuturesText.text("futures_product_selector")
    productControl.accessibilityIdentifier = "tradingProductSelector"
    productControl.addTarget(self, action: #selector(selectProduct), for: .valueChanged)
    productControl.snp.makeConstraints {
      // 중앙 정렬과 옆 버튼 간격을 함께 지킬 수 있는 범위에서만 너비를 늘린다.
      $0.centerX.equalToSuperview()
      $0.bottom.equalTo(mobitTabBar.snp.top).offset(-12)
      $0.leading.greaterThanOrEqualTo(view.safeAreaLayoutGuide).offset(TradingControlsLayout.horizontalInset)
      productTrailingConstraint = $0.trailing.lessThanOrEqualTo(view.safeAreaLayoutGuide)
        .offset(-(TradingControlsLayout.horizontalInset + TradingControlsLayout.accessorySize + TradingControlsLayout.accessorySpacing)).constraint
      $0.height.greaterThanOrEqualTo(52)
    }

	mobitTabBar.translatesAutoresizingMaskIntoConstraints = false

	switch style {
	case .standard:
	  applyTabBarShadow()
	  mobitTabBar.snp.makeConstraints { make in
		make.leading.trailing.bottom.equalToSuperview()
		// 탭 콘텐츠 65pt + 하단 safe area(홈 인디케이터)는 배경으로 채움
		make.top.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(-65)
	  }
	case .floating:
	  applyTabBarShadow()
	  mobitTabBar.snp.makeConstraints { make in
		make.leading.equalToSuperview().offset(10)
		make.trailing.equalToSuperview().offset(-10)
		make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-10)
		make.height.equalTo(65)
	  }
	}
  }

  private func applyTabBarShadow() {
	let color = UIColor.mobitColors(.borderPrimary).resolvedColor(with: traitCollection)
	switch style {
	case .standard:
	  // 상단 경계에 길게 떨어지는 음영으로 위 콘텐츠와 분리감 표현
	  mobitTabBar.layer.applyShadow(color: color, alpha: 0.22, x: 0, y: -4, blur: 16)
	case .floating:
	  // 카드가 떠 있는 느낌의 사방 그림자
	  mobitTabBar.layer.applyShadow(color: color, alpha: 0.3, x: 0, y: 0, blur: 12)
	}
  }
  
  func setViewControllers(_ controllers: [UIViewController], selectedIndex: Int = 0) {
	self.viewControllers = controllers
	let normalizedIndex = max(0, min(selectedIndex, controllers.count - 1))
	switchToTab(index: normalizedIndex)
  }
  
  func switchToTab(index: Int) {
	guard viewControllers.indices.contains(index) else { return }
	let newVC = viewControllers[index]
    if currentViewController != nil && selectedIndex != index { finishForegroundIndicator() }
	
	if currentViewController != nil {
	  currentViewController?.willMove(toParent: nil)
	  currentViewController?.view.removeFromSuperview()
	  currentViewController?.removeFromParent()
	}
	
	addChild(newVC)
	view.addSubview(newVC.view)
	newVC.view.translatesAutoresizingMaskIntoConstraints = false
	self.view.bringSubviewToFront(mobitTabBar)
    self.view.bringSubviewToFront(productControl)
	
	newVC.view.snp.makeConstraints { make in
	  make.top.bottom.leading.trailing.equalToSuperview()
	}
	
	newVC.didMove(toParent: self)
	currentViewController = newVC
	self.selectedIndex = index
    mobitTabBar.selectItem(at: index)
    updateProductVisibility()
  }
  
  func controlSocket(appState: AppState) {
	// 현물 투자내역은 자체 소켓이 없어 보유 자산을 갱신하는 메인 소켓을 대신 제어한다.
	let current = (currentViewController as? UINavigationController)?.visibleViewController as? SocketControllable
	// 상세 화면의 자체 소켓이 있다면 메인 소켓을 중복 연결하지 않는다.
	let fallback = ExchangeSelectionStore.currentProduct == .spot
	  ? (viewControllers.first as? UINavigationController)?.viewControllers.first as? SocketControllable : nil
	if let vc = current ?? fallback {
	  appState == .foreground ? vc.resumeSocket() : vc.pauseSocket()
	}
  }
}

extension CALayer {
  // Sketch 스타일의 그림자를 생성하는 유틸리티 함수
  func applyShadow(
	color: UIColor = .mobitColors(.borderPrimary),
	alpha: Float = 0.5,
	x: CGFloat = 0,
	y: CGFloat = 2,
	blur: CGFloat = 4
  ) {
	shadowColor = color.cgColor
	shadowOpacity = alpha
	shadowOffset = CGSize(width: x, height: y)
	shadowRadius = blur / 2.0
  }
}

extension UITabBar {
  // 기본 그림자 스타일을 초기화해야 커스텀 스타일을 적용할 수 있다.
  static func clearShadow() {
	UITabBar.appearance().shadowImage = UIImage()
	UITabBar.appearance().backgroundImage = UIImage()
	UITabBar.appearance().backgroundColor = .mobitColors(.surfacePrimary)
  }
}

private final class TradingProductControl: UIControl {
  var selectedSegmentIndex = 0 { didSet { updateSelection() } }
  private let buttons: [UIButton] = ["futures_spot", "futures_product"].map { key in
    let button = TradingProductButton(type: .system)
    // 번역 문구의 자연 너비에 기본 좌우 32pt를 더해 각 선택 영역을 만든다.
    var configuration = UIButton.Configuration.plain()
    configuration.title = FuturesText.text(key)
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 8,
      leading: TradingProductButton.horizontalContentInset,
      bottom: 8,
      trailing: TradingProductButton.horizontalContentInset
    )
    configuration.titleLineBreakMode = .byTruncatingTail
    configuration.background.backgroundColor = .clear
    button.configuration = configuration
    button.titleLabel?.adjustsFontForContentSizeCategory = true
    button.snp.makeConstraints { $0.width.height.greaterThanOrEqualTo(44) }
    return button
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .mobitColors(.surfacePrimary)
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.14
    layer.shadowRadius = 12
    layer.shadowOffset = CGSize(width: 0, height: 4)
    let stack = UIStackView(arrangedSubviews: buttons)
    stack.distribution = .fillProportionally
    addSubview(stack)
    stack.snp.makeConstraints { $0.edges.equalToSuperview().inset(4) }
    for (index, button) in buttons.enumerated() {
      button.addAction(UIAction { [weak self] _ in
        self?.selectedSegmentIndex = index
        self?.sendActions(for: .valueChanged)
      }, for: .touchUpInside)
    }
    updateSelection()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = bounds.height / 2
  }

  private func updateSelection() {
    for (index, button) in buttons.enumerated() {
      let selected = index == selectedSegmentIndex
      button.backgroundColor = selected ? .mobitColors(.accountAction) : .clear
      button.configuration?.baseForegroundColor = selected ? .white : .mobitColors(.textPrimary)
      // 선택 변경은 UIButton 상태를 바꾸지 않으므로 고정된 글자색도 다시 갱신한다.
      button.setNeedsUpdateConfiguration()
      button.accessibilityTraits = selected ? [.button, .selected] : [.button]
      button.accessibilityIdentifier = index == 0 ? "selectSpot" : "selectFutures"
    }
  }
}

private final class TradingProductButton: UIButton {
  // 여유 공간이 있을 때 각 항목의 좌우에 확보할 기본 여백이다.
  static let horizontalContentInset: CGFloat = 32
  // 최대 너비에 도달해도 읽을 수 있도록 허용할 최소 글자 배율이다.
  private static let minimumTitleScale: CGFloat = 0.55

  override var intrinsicContentSize: CGSize {
    // 좁은 화면에서 여백을 줄여도 자연 너비는 기본 32pt를 기준으로 유지한다.
    var size = super.intrinsicContentSize
    if let insets = configuration?.contentInsets {
      size.width += Self.horizontalContentInset * 2 - insets.leading - insets.trailing
    }
    return size
  }

  override func updateConfiguration() {
    super.updateConfiguration()
    // 최대 너비에서는 55%까지 축소하고 그래도 긴 번역은 말줄임한다.
    let font = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traitCollection)
    // 액션시트의 tint 보정이 선택 상태의 글자색을 회색으로 바꾸지 않게 한다.
    let titleColor = configuration?.baseForegroundColor ?? .mobitColors(.textPrimary)
    configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      // 시스템 글자 크기가 바뀌면 버튼의 자연 너비도 함께 갱신한다.
      var attributes = incoming
      attributes.font = font
      attributes.foregroundColor = titleColor
      return attributes
    }
    titleLabel?.numberOfLines = 1
    titleLabel?.adjustsFontSizeToFitWidth = true
    titleLabel?.minimumScaleFactor = Self.minimumTitleScale
    titleLabel?.lineBreakMode = .byTruncatingTail
    // 폰트 갱신 후 Auto Layout이 이전 글자 크기의 너비를 계속 사용하지 않게 한다.
    invalidateIntrinsicContentSize()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    setNeedsUpdateConfiguration()
  }

  override func layoutSubviews() {
    if bounds.width > 0, var updated = configuration {
      // 중앙 정렬로 폭이 제한되면 글자보다 여백을 먼저 줄인다.
      let font = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traitCollection)
      // 원래 글자 크기를 유지하는 데 필요한 너비를 구한다.
      let titleWidth = (updated.title ?? "").size(withAttributes: [.font: font]).width
      // 일반 화면은 32pt, 좁은 화면은 최소 12pt까지 여백을 줄인다.
      let inset = min(Self.horizontalContentInset, max(12, ((bounds.width - titleWidth) / 2).rounded()))
      if updated.contentInsets.leading != inset || updated.contentInsets.trailing != inset {
        updated.contentInsets.leading = inset
        updated.contentInsets.trailing = inset
        configuration = updated
      }
    }
    super.layoutSubviews()
    layer.cornerRadius = bounds.height / 2
  }
}
