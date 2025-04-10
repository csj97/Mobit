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
		  selector: #selector(appDidBecomeActive),
		  name: UIApplication.didBecomeActiveNotification,
		  object: nil
	  )
	  NotificationCenter.default.addObserver(
		  self,
		  selector: #selector(appWillResignActive),
		  name: UIApplication.willResignActiveNotification,
		  object: nil
	  )
  }
  
  
  // 앱이 Foreground로 돌아올 때
  @objc private func appDidBecomeActive() {
	getVisibleController()?.resumeSocket()
  }
  
  // 앱이 백그라운드로 전환될 때
  @objc private func appWillResignActive() {
	getVisibleController()?.pauseSocket()
  }
  
  private func getVisibleController() -> SocketControllable? {
	var vc = rootViewController
	while let presented = vc?.presentedViewController {
	  vc = presented
	}
	return vc as? SocketControllable
  }
}
