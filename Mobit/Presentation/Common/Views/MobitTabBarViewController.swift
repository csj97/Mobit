//
//  MobitTabBarViewController.swift
//  Mobit
//
//  Created by 조성재 on 6/15/25.
//

import UIKit
import SnapKit

class MobitTabBarViewController: UIViewController {
  let mobitTabBar = MobitTabBar(tabItems: [.exchange, .wallet, .more])
  private var currentViewController: UIViewController?
  private var viewControllers: [UIViewController] = []
  
  var onTabSelected: ((Int) -> Void)?
  
  override func viewDidLoad() {
	super.viewDidLoad()
	setupUI()
	
	mobitTabBar.didSelectItem = { [weak self] index in
	  self?.switchToTab(index: index)
	  self?.onTabSelected?(index)
	}
  }
  
  /// 탭바 상단 Radius 처리
  override func viewDidLayoutSubviews() {
	super.viewDidLayoutSubviews()
	mobitTabBar.layer.cornerRadius = 20
//	mobitTabBar.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
  }
  
  private func setupUI() {
	view.backgroundColor = .clear
	view.addSubview(mobitTabBar)
  
	UITabBar.clearShadow()
	mobitTabBar.layer.applyShadow(color: .gray, alpha: 0.3, x: 0, y: 0, blur: 12)
	
	mobitTabBar.translatesAutoresizingMaskIntoConstraints = false
	mobitTabBar.snp.makeConstraints { make in
	  make.leading.equalToSuperview().offset(10)
	  make.trailing.equalToSuperview().offset(-10)
	  make.bottom.equalToSuperview().offset(-20)
	  make.height.equalTo(80)
	}
  }
  
  func setViewControllers(_ controllers: [UIViewController]) {
	self.viewControllers = controllers
	switchToTab(index: 0)
  }
  
  private func switchToTab(index: Int) {
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
//	  make.bottom.equalTo(mobitTabBar.snp.top)
	}
	
	newVC.didMove(toParent: self)
	currentViewController = newVC
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
