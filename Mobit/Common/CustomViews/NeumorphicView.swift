//
//  NeumorphicView.swift
//  Mobit
//
//  Created by 조성재 on 7/30/25.
//

import UIKit

class NeumorphicView: UIView {
  
  override init(frame: CGRect) {
	super.init(frame: frame)
	setupNeumorphicStyle()
  }
  
  required init?(coder: NSCoder) {
	super.init(coder: coder)
	setupNeumorphicStyle()
  }
  
  private let lightShadow = CALayer()
  
  private func setupNeumorphicStyle() {
	backgroundColor = .mobitColors(.surfacePrimary)
	layer.cornerRadius = 16
	layer.masksToBounds = false
	
	// 아래쪽 어두운 그림자
	layer.shadowColor = UIColor.mobitColors(.borderPrimary).cgColor
	layer.shadowOffset = CGSize(width: 6, height: 6)
	layer.shadowOpacity = 0.7
	layer.shadowRadius = 6
	
	// 위쪽 밝은 그림자 레이어
	lightShadow.backgroundColor = backgroundColor?.cgColor
	lightShadow.shadowColor = UIColor.mobitColors(.surfaceElevated).cgColor
	lightShadow.shadowOffset = CGSize(width: -6, height: -6)
	lightShadow.shadowOpacity = 1.0
	lightShadow.shadowRadius = 6
	lightShadow.cornerRadius = 16
	layer.insertSublayer(lightShadow, at: 0)
  }
  
  override func layoutSubviews() {
	super.layoutSubviews()
	lightShadow.frame = bounds
	lightShadow.cornerRadius = layer.cornerRadius
  }
}
