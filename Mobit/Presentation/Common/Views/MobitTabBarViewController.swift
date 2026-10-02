//
//  MobitTabBarViewController.swift
//  Mobit
//
//  Created by 조성재 on 6/15/25.
//

import UIKit
import SnapKit

class MobitTabBarViewController: UIViewController {
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
    currentViewController?.additionalSafeAreaInsets.bottom = visible ? 76 : 0
  }

  @objc private func selectProduct() {
    onProductSelected?(productControl.selectedSegmentIndex == 0 ? .spot : .perpetual)
  }

  func alignTradingAccessory(_ accessory: UIView) {
    accessory.snp.remakeConstraints {
      $0.trailing.equalTo(view.safeAreaLayoutGuide).offset(-16)
      $0.centerY.equalTo(productControl)
      $0.width.height.equalTo(56)
    }
  }

  var onTabSelected: ((Int) -> Void)?

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
      $0.centerX.equalToSuperview()
      $0.bottom.equalTo(mobitTabBar.snp.top).offset(-12)
      $0.width.equalTo(216).priority(750)
      // 작은 화면에서도 우측 공포·탐욕 버튼과 겹치지 않도록 공간을 확보한다.
      $0.width.lessThanOrEqualTo(view.safeAreaLayoutGuide).offset(-152)
      $0.height.greaterThanOrEqualTo(56)
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
	if let vc = (currentViewController as? UINavigationController)?.visibleViewController as? SocketControllable {
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
    button.setTitle(FuturesText.text(key), for: .normal)
    button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    button.titleLabel?.adjustsFontForContentSizeCategory = true
    return button
  }

  override var intrinsicContentSize: CGSize {
    CGSize(width: 216, height: max(56, UIFont.preferredFont(forTextStyle: .headline).lineHeight + 28))
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .mobitColors(.surfacePrimary)
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.14
    layer.shadowRadius = 12
    layer.shadowOffset = CGSize(width: 0, height: 4)
    let stack = UIStackView(arrangedSubviews: buttons)
    stack.distribution = .fillEqually
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

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    invalidateIntrinsicContentSize()
  }

  private func updateSelection() {
    for (index, button) in buttons.enumerated() {
      let selected = index == selectedSegmentIndex
      button.backgroundColor = selected ? .systemBlue : .clear
      button.setTitleColor(selected ? .white : .mobitColors(.textPrimary), for: .normal)
      button.accessibilityTraits = selected ? [.button, .selected] : [.button]
      button.accessibilityIdentifier = index == 0 ? "selectSpot" : "selectFutures"
    }
  }
}

private final class TradingProductButton: UIButton {
  override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = bounds.height / 2
  }
}
