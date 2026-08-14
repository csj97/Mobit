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

	  let overlay = MobitLottieView(
		lottieName: "exchange_loading",
		loopMode: .loop,
		bgColor: UIColor.mobitColors(.backgroundPrimary).withAlphaComponent(0.6)
	  )
	  overlay.frame = window.bounds
	  overlay.tag = self.indicatorViewTag
	  overlay.configure()

	  window.addSubview(overlay)
	  overlay.playLottie()
	}
  }

  func hideLoadingIndicator() {
	DispatchQueue.main.async {
	  guard let windowScene = UIApplication.shared.connectedScenes
		.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
			let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
		return
	  }
	  if let overlay = window.viewWithTag(self.indicatorViewTag) as? MobitLottieView {
		overlay.stopLottie()
		overlay.removeFromSuperview()
	  }
	}
  }
}
