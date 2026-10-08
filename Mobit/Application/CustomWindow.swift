//
//  CustomWindow.swift
//  Mobit
//
//  Created by 조성재 on 4/10/25.
//

import Foundation
import UIKit

enum AppState {
  case foreground, background
}

class CustomWindow: UIWindow {
  override init(frame: CGRect) {
	super.init(frame: frame)
	tintColor = .mobitColors(.accentPrimary)
	
	setupObservers()
  }
  
  required init?(coder: NSCoder) {
	super.init(coder: coder)
	tintColor = .mobitColors(.accentPrimary)
	
	setupObservers()
  }
  
  /// [Background & Foreground] Observers
  private func setupObservers() {
	NotificationCenter.default.addObserver(
	  self,
	  selector: #selector(mobitDidBecomeActive),
	  name: UIApplication.didBecomeActiveNotification,
	  object: nil
	)
	NotificationCenter.default.addObserver(
	  self,
	  selector: #selector(mobitWillResignActive),
	  name: UIApplication.willResignActiveNotification,
	  object: nil
	)
  }
  
  // 앱이 Foreground로 돌아올 때
  @objc private func mobitDidBecomeActive() {
	DispatchQueue.main.async {
	  guard let controllable = self.prepareSocketControllableController(appState: .foreground) else { return }
	  controllable.resumeSocket()
	}
	//	getVisibleController()?.resumeSocket()
  }
  
  // 앱이 백그라운드로 전환될 때
  @objc private func mobitWillResignActive() {
	DispatchQueue.main.async {
	  guard let controllableVC = self.prepareSocketControllableController(appState: .background) else { return }
	  controllableVC.pauseSocket()
	}
	//	getVisibleController()?.pauseSocket()
  }
  
  private func getVisibleController(from vc: UIViewController?) -> UIViewController? {
	if let nav = vc as? UINavigationController {
	  return getVisibleController(from: nav.visibleViewController)
	} else if let tab = vc as? UITabBarController {
	  return getVisibleController(from: tab.selectedViewController)
	} else if let presented = vc?.presentedViewController {
	  return getVisibleController(from: presented)
	} else {
	  return vc
	}
  }
  
  // 현재 화면의 소켓 제어 대상을 찾고 탭 화면은 소켓 상태도 반영한다.
  private func prepareSocketControllableController(appState: AppState) -> SocketControllable? {
	guard let rootVC = UIApplication.shared.connectedScenes
	  .compactMap({ $0 as? UIWindowScene })
	  .flatMap({ $0.windows })
	  .first(where: { $0.isKeyWindow })?.rootViewController else {
	  return nil
	}
	
	let visibleVC = getVisibleController(from: rootVC)
	
	if let vc = visibleVC as? MobitTabBarViewController {
	  vc.controlSocket(appState: appState)
	  return nil
	}
	
	return visibleVC as? SocketControllable
  }
}
