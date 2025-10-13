//
//  MobitBaseViewController.swift
//  Mobit
//
//  Created by 조성재 on 7/22/25.
//

import Foundation
import UIKit

@objc protocol LoadingIndicatorProtocol {
  @objc optional func showLoadingIndicator()
  @objc optional func hideLoadingIndicator()
}

class MobitBaseViewController: UIViewController, MobitAlertDelegate, MobitBottomSheetDelegate, LoadingIndicatorProtocol, ViewRule {
  private var indicatorViewTag: Int { return 999_999 }  // 유일한 태그로 구분

  func showLoadingIndicator() {
	DispatchQueue.main.async {
	  guard let windowScene = UIApplication.shared.connectedScenes
		.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
			let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
		return
	  }
	  // 이미 있는 경우 중복 생성 방지
	  if window.viewWithTag(self.indicatorViewTag) != nil { return }
	  
	  let overlay = UIView(frame: window.bounds)
	  overlay.backgroundColor = UIColor.black.withAlphaComponent(0.3)
	  overlay.tag = self.indicatorViewTag
	  
	  let spinner = UIActivityIndicatorView(style: .large)
	  spinner.color = .white
	  spinner.startAnimating()
	  spinner.center = overlay.center
	  
	  overlay.addSubview(spinner)
	  window.addSubview(overlay)
	}
  }
  
  func hideLoadingIndicator() {
	DispatchQueue.main.async {
	  guard let windowScene = UIApplication.shared.connectedScenes
		.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
			let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
		return
	  }
	  if let overlay = window.viewWithTag(self.indicatorViewTag) {
		overlay.removeFromSuperview()
	  }
	}
  }
}
