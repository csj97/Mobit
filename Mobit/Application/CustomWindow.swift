//
//  CustomWindow.swift
//  Mobit
//
//  Created by 조성재 on 4/10/25.
//

import Foundation
import UIKit

class CustomWindow: UIWindow {
  override init(frame: CGRect) {
	super.init(frame: frame)
	
	setupObservers()
  }
  
  required init?(coder: NSCoder) {
	super.init(coder: coder)
	
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
	  guard let controllable = self.getSocketControllableController() else { return }
	  controllable.resumeSocket()
	}
	//	getVisibleController()?.resumeSocket()
  }
  
  // 앱이 백그라운드로 전환될 때
  @objc private func mobitWillResignActive() {
	DispatchQueue.main.async {
	  guard let controllableVC = self.getSocketControllableController() else { return }
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
  
  private func getSocketControllableController() -> SocketControllable? {
	guard let rootVC = UIApplication.shared.connectedScenes
	  .compactMap({ $0 as? UIWindowScene })
	  .flatMap({ $0.windows })
	  .first(where: { $0.isKeyWindow })?.rootViewController else {
	  return nil
	}
	
	let visibleVC = getVisibleController(from: rootVC)
	return visibleVC as? SocketControllable
  }
}
