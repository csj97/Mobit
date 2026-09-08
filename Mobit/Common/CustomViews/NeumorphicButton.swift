//
//  NeumorphicButton.swift
//  Mobit
//
//  Created by 조성재 on 7/10/25.
//

import Foundation
import UIKit

class NeumorphicButton: UIButton {
  private let ambientShadow = CALayer()
  private let lightShadow = CALayer()
  
  override init(frame: CGRect) {
	super.init(frame: frame)
	setupNeumorphicStyle()
  }
  
  required init?(coder: NSCoder) {
	super.init(coder: coder)
	setupNeumorphicStyle()
  }
  
  private func setupNeumorphicStyle() {
	layer.cornerRadius = 16
	layer.masksToBounds = false
	layer.borderWidth = 1

	layer.shadowOffset = CGSize(width: 8, height: 8)
	layer.shadowOpacity = 0.58
	layer.shadowRadius = 12

	ambientShadow.frame = bounds
	ambientShadow.shadowOffset = .zero
	ambientShadow.shadowOpacity = 0.28
	ambientShadow.shadowRadius = 14
	ambientShadow.cornerRadius = 16
	layer.insertSublayer(ambientShadow, at: 0)

	lightShadow.frame = bounds
	lightShadow.shadowOffset = CGSize(width: -7, height: -7)
	lightShadow.shadowOpacity = 0.78
	lightShadow.shadowRadius = 11
	lightShadow.cornerRadius = 16
	layer.insertSublayer(lightShadow, above: ambientShadow)
	updateResolvedColors()
  }
  
  // 크기 변경 시 그림자 레이어도 업데이트
  override func layoutSubviews() {
	super.layoutSubviews()
	ambientShadow.frame = bounds
	ambientShadow.cornerRadius = layer.cornerRadius
	lightShadow.frame = bounds
	lightShadow.cornerRadius = layer.cornerRadius
	let shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
	layer.shadowPath = shadowPath
	ambientShadow.shadowPath = shadowPath
	lightShadow.shadowPath = shadowPath
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
	updateResolvedColors()
  }

  private func updateResolvedColors() {
	let surfaceColor = UIColor.mobitColors(.neumorphicButtonBackground).resolvedColor(with: traitCollection)
	let textColor = UIColor.mobitColors(.neumorphicButtonText).resolvedColor(with: traitCollection)
	backgroundColor = surfaceColor
	tintColor = textColor
	setTitleColor(textColor, for: .normal)
	titleLabel?.backgroundColor = .clear
	titleLabel?.isOpaque = false
	layer.borderColor = UIColor.mobitColors(.neumorphicButtonBorder).resolvedColor(with: traitCollection).cgColor
	layer.shadowColor = UIColor.mobitColors(.neumorphicButtonDarkShadow).resolvedColor(with: traitCollection).cgColor
	ambientShadow.backgroundColor = surfaceColor.cgColor
	ambientShadow.shadowColor = UIColor.mobitColors(.neumorphicButtonDarkShadow).resolvedColor(with: traitCollection).cgColor
	lightShadow.backgroundColor = surfaceColor.cgColor
	lightShadow.shadowColor = UIColor.mobitColors(.neumorphicButtonLightShadow).resolvedColor(with: traitCollection).cgColor
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
	  self.layer.shadowOffset = CGSize(width: 3, height: 3)
	  self.layer.shadowOpacity = 0.25
	  self.ambientShadow.shadowOpacity = 0.12
	  self.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
	}
  }
  
  private func animatePressedOut() {
	UIView.animate(withDuration: 0.1) {
	  self.layer.shadowOffset = CGSize(width: 8, height: 8)
	  self.layer.shadowOpacity = 0.58
	  self.ambientShadow.shadowOpacity = 0.28
	  self.transform = .identity
	}
  }
}
