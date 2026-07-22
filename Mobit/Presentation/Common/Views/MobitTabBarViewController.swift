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

  private func setupUI() {
	view.backgroundColor = .clear
	view.addSubview(mobitTabBar)
	UITabBar.clearShadow()

	mobitTabBar.translatesAutoresizingMaskIntoConstraints = false

	switch style {
	case .standard:
	  // 상단 경계에 길게 떨어지는 음영으로 위 콘텐츠와 분리감 표현
	  mobitTabBar.layer.applyShadow(color: .gray, alpha: 0.22, x: 0, y: -4, blur: 16)
	  mobitTabBar.snp.makeConstraints { make in
		make.leading.trailing.bottom.equalToSuperview()
		// 탭 콘텐츠 65pt + 하단 safe area(홈 인디케이터)는 배경으로 채움
		make.top.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(-65)
	  }
	case .floating:
	  // 카드가 떠 있는 느낌의 사방 그림자
	  mobitTabBar.layer.applyShadow(color: .gray, alpha: 0.3, x: 0, y: 0, blur: 12)
	  mobitTabBar.snp.makeConstraints { make in
		make.leading.equalToSuperview().offset(10)
		make.trailing.equalToSuperview().offset(-10)
		make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-10)
		make.height.equalTo(65)
	  }
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
	
	newVC.view.snp.makeConstraints { make in
	  make.top.bottom.leading.trailing.equalToSuperview()
	}
	
	newVC.didMove(toParent: self)
	currentViewController = newVC
	self.selectedIndex = index
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
	color: UIColor = .black,
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
	UITabBar.appearance().backgroundColor = UIColor.white
  }
}
