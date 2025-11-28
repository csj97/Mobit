//
//  ViewControllerExtension.swift
//  Mobit
//
//  Created by 조성재 on 11/28/25.
//

import Foundation
import UIKit
import SnapKit

extension UIViewController {
  
  func presentAverageCalcView(_ customView: UIView, animated: Bool = true) {
	// 반투명 배경 뷰 생성
	let dimView = UIView()
	dimView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
	dimView.alpha = 0.0
	view.addSubview(dimView)
	
	// SnapKit을 사용한 전체 화면 레이아웃
	dimView.snp.makeConstraints { make in
	  make.edges.equalToSuperview()
	}
	
	// 커스텀 뷰 추가
	dimView.addSubview(customView)
	
	// SnapKit을 사용한 커스텀 뷰 레이아웃 (중앙 정렬)
	customView.snp.makeConstraints { make in
	  make.center.equalToSuperview()
	  make.width.equalToSuperview().multipliedBy(0.85)
	}
	
	// 애니메이션
	if animated {
	  customView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
	  UIView.animate(withDuration: 0.3,
					 delay: 0,
					 usingSpringWithDamping: 0.7,
					 initialSpringVelocity: 0.5,
					 options: .curveEaseInOut) {
		dimView.alpha = 1.0
		customView.transform = .identity
	  }
	} else {
	  dimView.alpha = 1.0
	}
	
	// 닫기 콜백 연결
	if let tradeView = customView as? TradeAverageCalcView {
	  tradeView.onClose = { [weak self] in
		self?.dismissCustomAlertView(dimView)
	  }
	}
	
	// 키보드 옵저버 추가
	NotificationCenter.default.addObserver(
	  forName: UIResponder.keyboardWillShowNotification,
	  object: nil,
	  queue: .main
	) { [weak self] notification in
	  self?.handleKeyboardShow(notification, customView: customView)
	}
	
	NotificationCenter.default.addObserver(
	  forName: UIResponder.keyboardWillHideNotification,
	  object: nil,
	  queue: .main
	) { [weak self] notification in
	  self?.handleKeyboardHide(notification, customView: customView)
	}
  }
  
  private func handleKeyboardShow(_ notification: Notification, customView: UIView) {
	guard let userInfo = notification.userInfo,
		  let keyboardFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
		  let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
		  let curve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else { return }
	
	// 키보드 높이
	let keyboardHeight = keyboardFrame.height
	
	// 커스텀 뷰의 최저점이 키보드 상단보다 아래로 오도록 조정
	UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve)) {
	  customView.snp.remakeConstraints { make in
		  make.centerX.equalToSuperview()
		  make.centerY.equalToSuperview().offset(-keyboardHeight / 2)
		  make.width.equalToSuperview().multipliedBy(0.85)
	  }
	  self.view.layoutIfNeeded()
	}
  }
  
  private func handleKeyboardHide(_ notification: Notification, customView: UIView) {
	guard let userInfo = notification.userInfo,
		  let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
		  let curve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else { return }
	
	UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve)) {
	  customView.snp.remakeConstraints { make in
		  make.center.equalToSuperview()
		  make.width.equalToSuperview().multipliedBy(0.85)
	  }
	  self.view.layoutIfNeeded()
	}
  }
  
  private func dismissCustomAlertView(_ dimView: UIView) {
	UIView.animate(withDuration: 0.2, animations: {
	  dimView.alpha = 0.0
	}) { _ in
	  dimView.removeFromSuperview()
	}
  }
}
