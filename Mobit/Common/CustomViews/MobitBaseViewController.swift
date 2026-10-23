//
//  MobitBaseViewController.swift
//  Mobit
//
//  Created by 조성재 on 7/22/25.
//

import Foundation
import UIKit

extension Notification.Name {
  // 같은 창의 안내가 전체 화면 인디케이터의 실제 표시·제거에 맞춰 대기하도록 한다.
  static let loadingIndicatorVisibilityDidChange = Notification.Name("loadingIndicatorVisibilityDidChange")
}

@objc protocol LoadingIndicatorProtocol {
  @objc optional func showLoadingIndicator()
  @objc optional func hideLoadingIndicator()
}

class MobitBaseViewController: UIViewController, MobitBottomSheetDelegate, LoadingIndicatorProtocol,
  ViewRule
{
  // 같은 창의 인디케이터에 등록한 자신의 표시 요청만 종료한다.
  private weak var loadingIndicatorView: LoadingIndicatorView?
  private var indicatorViewTag: Int { return 999_999 }  // 유일한 태그로 구분

  deinit {
    // 화면 해제 후 창에 남은 표시 요청도 메인 큐에서 회수한다.
    let overlay = loadingIndicatorView
    // 비동기 정리에 해제 중인 화면 자체를 캡처하지 않는다.
    let owner = ObjectIdentifier(self)
    DispatchQueue.main.async { overlay?.removeOwner(owner) }
  }

  static func isLoadingIndicatorVisible(in window: UIWindow) -> Bool {
    window.subviews.contains { $0 is LoadingIndicatorView }
  }

  func showLoadingIndicator() {
	DispatchQueue.main.async {
	  let activeWindow =
		(UIApplication.shared.connectedScenes
		.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene)?
		.windows.first(where: { $0.isKeyWindow })
	  guard let window = self.viewIfLoaded?.window ?? activeWindow else { return }
      // 창이 바뀐 화면의 이전 요청은 원래 창에서 종료한다.
      if self.loadingIndicatorView?.superview !== window {
        self.loadingIndicatorView?.removeOwner(ObjectIdentifier(self))
        self.loadingIndicatorView = nil
      }
      if let overlay = window.viewWithTag(self.indicatorViewTag) as? LoadingIndicatorView {
        overlay.addOwner(ObjectIdentifier(self))
        self.loadingIndicatorView = overlay
        return
      }

	  let overlay = LoadingIndicatorView(
		lottieName: "exchange_loading",
		loopMode: .loop,
		bgColor: UIColor.mobitColors(.backgroundPrimary).withAlphaComponent(0.6)
	  )
	  overlay.frame = window.bounds
	  overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
	  overlay.tag = self.indicatorViewTag
	  overlay.configure()

	  self.loadingIndicatorView = overlay
      overlay.addOwner(ObjectIdentifier(self))
	  window.addSubview(overlay)
	  overlay.playLottie()
      NotificationCenter.default.post(name: .loadingIndicatorVisibilityDidChange, object: window)
	}
  }

  func hideLoadingIndicator() {
	DispatchQueue.main.async {
      self.loadingIndicatorView?.removeOwner(ObjectIdentifier(self))
      self.loadingIndicatorView = nil
	}
  }
}

// 겹친 최초 조회·복귀 검증은 하나의 Lottie를 공유하고 각자 자신의 요청만 해제한다.
private final class LoadingIndicatorView: MobitLottieView {
  // 같은 화면의 반복 표시 호출이 종료 횟수를 늘리지 않도록 집합으로 관리한다.
  private var owners = Set<ObjectIdentifier>()

  func addOwner(_ owner: ObjectIdentifier) {
    owners.insert(owner)
  }

  func removeOwner(_ owner: ObjectIdentifier) {
    owners.remove(owner)
    guard owners.isEmpty else { return }
    // 마지막 소유 요청이 끝나 실제로 제거된 창에만 종료를 알린다.
    let window = superview as? UIWindow
    stopLottie()
    removeFromSuperview()
    if let window { NotificationCenter.default.post(name: .loadingIndicatorVisibilityDidChange, object: window) }
  }
}
