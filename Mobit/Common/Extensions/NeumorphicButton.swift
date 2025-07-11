//
//  NeumorphicButton.swift
//  Mobit
//
//  Created by 조성재 on 7/10/25.
//

import Foundation
import UIKit

class NeumorphicButton: UIButton {
  
  override init(frame: CGRect) {
	super.init(frame: frame)
	setupNeumorphicStyle()
  }
  
  required init?(coder: NSCoder) {
	super.init(coder: coder)
	setupNeumorphicStyle()
  }
  
  private func setupNeumorphicStyle() {
	// 기본 스타일
	backgroundColor = UIColor(red: 0.925, green: 0.941, blue: 0.953, alpha: 1.0) // #ecf0f3
	layer.cornerRadius = 16
	layer.masksToBounds = false
	
	// 그림자 1: 아래쪽 (어두운 음영)
	layer.shadowColor = UIColor(red: 0.6, green: 0.6, blue: 0.7, alpha: 1.0).cgColor
	layer.shadowOffset = CGSize(width: 6, height: 6)
	layer.shadowOpacity = 0.7
	layer.shadowRadius = 6
	
	// 그림자 2: 위쪽 (밝은 빛)
	let lightShadow = CALayer()
	lightShadow.frame = bounds
	lightShadow.backgroundColor = backgroundColor?.cgColor
	lightShadow.shadowColor = UIColor.white.cgColor
	lightShadow.shadowOffset = CGSize(width: -6, height: -6)
	lightShadow.shadowOpacity = 1.0
	lightShadow.shadowRadius = 6
	lightShadow.cornerRadius = 16
	layer.insertSublayer(lightShadow, at: 0)
  }
  
  // 크기 변경 시 그림자 레이어도 업데이트
  override func layoutSubviews() {
	super.layoutSubviews()
	layer.sublayers?.first?.frame = bounds
	layer.sublayers?.first?.cornerRadius = layer.cornerRadius
  }
  
  // 눌렀을 때 오목한 효과
  override var isHighlighted: Bool {
	didSet {
	  if isHighlighted {
		animatePressedIn()
	  } else {
		animatePressedOut()
	  }
	}
  }
  
  private func animatePressedIn() {
	UIView.animate(withDuration: 0.1) {
	  self.layer.shadowOffset = CGSize(width: 2, height: 2)
	  self.layer.shadowOpacity = 0.2
	  self.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
	}
  }
  
  private func animatePressedOut() {
	UIView.animate(withDuration: 0.1) {
	  self.layer.shadowOffset = CGSize(width: 5, height: 5)
	  self.layer.shadowOpacity = 0.4
	  self.transform = .identity
	}
  }
}
