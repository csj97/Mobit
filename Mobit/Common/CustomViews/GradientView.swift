//
//  GradientView.swift
//  Mobit
//
//  Created by 조성재 on 7/15/25.
//

import Foundation
import UIKit

class GradientView: UIView {
  private let gradientLayer = CAGradientLayer()
  
  override init(frame: CGRect) {
	super.init(frame: frame)
	setupGradient()
  }

  required init?(coder: NSCoder) {
	super.init(coder: coder)
	setupGradient()
  }
  
  private func setupGradient() {
	gradientLayer.frame = self.bounds
	
	// 방향 위에서 아래로
	gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
	gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
	
	self.layer.insertSublayer(gradientLayer, at: 0)
	updateResolvedColors()
  }

  override func layoutSubviews() {
	super.layoutSubviews()
	gradientLayer.frame = bounds // 뷰 크기 바뀔 때마다 업데이트
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
	updateResolvedColors()
  }

  private func updateResolvedColors() {
	gradientLayer.colors = [
	  UIColor.mobitColors(.surfacePrimary).resolvedColor(with: traitCollection).cgColor,
	  UIColor.mobitColors(.backgroundPrimary).resolvedColor(with: traitCollection).cgColor,
	]
  }
}
