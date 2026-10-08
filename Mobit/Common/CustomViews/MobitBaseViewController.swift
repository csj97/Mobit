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

class MobitBaseViewController: UIViewController, MobitAlertDelegate, MobitBottomSheetDelegate, LoadingIndicatorProtocol,
  ViewRule
{
  private weak var loadingIndicatorWindow: UIWindow?
  private var indicatorViewTag: Int { return 999_999 }  // 유일한 태그로 구분

  func showLoadingIndicator() {
	DispatchQueue.main.async {
	  let activeWindow =
		(UIApplication.shared.connectedScenes
		.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene)?
		.windows.first(where: { $0.isKeyWindow })
	  guard let window = self.viewIfLoaded?.window ?? activeWindow else { return }
	  self.loadingIndicatorWindow = window
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
	  // 광고가 key window를 바꾸거나 Scene이 비활성화돼도 생성한 창에서 제거한다.
	  let window = self.loadingIndicatorWindow ?? self.viewIfLoaded?.window
	  if let overlay = window?.viewWithTag(self.indicatorViewTag) as? MobitLottieView {
		overlay.stopLottie()
		overlay.removeFromSuperview()
	  }
	  self.loadingIndicatorWindow = nil
	}
  }
}
