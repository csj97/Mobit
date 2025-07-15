//
//  UIVieweExtension.swift
//  Mobit
//
//  Created by 조성재 on 2/10/25.
//

import UIKit

extension UIView {
  @IBInspectable var cornerRadius: CGFloat {
	get {
	  return self.layer.cornerRadius
	}
	set {
	  self.layer.cornerRadius = newValue
	  self.layer.masksToBounds = true
	}
  }
  
  
  @IBInspectable var shadowRadius: CGFloat {
	get {
	  return layer.shadowRadius
	}
	set {
	  layer.shadowRadius = newValue
	}
  }
  
  @IBInspectable var shadowOpacity: Float {
	get {
	  return layer.shadowOpacity
	}
	set {
	  layer.shadowOpacity = newValue
	}
  }
  
  @IBInspectable var shadowOffset: CGSize {
	get {
	  return layer.shadowOffset
	}
	set {
	  layer.shadowOffset = newValue
	}
  }
  
//  @IBInspectable var shadowColor : UIColor {
//	get{
//	  if let shadowColor = self.layer.shadowColor {
//		return UIColor(cgColor: shadowColor)
//	  }
//	  return UIColor.clear
//	}
//	set{
//	  self.layer.shadowOffset = CGSize(width: 0, height: 0)
//	  self.layer.shadowColor = newValue.cgColor
//	}
//  }
  
  @IBInspectable var shadowColor: UIColor? {
	get {
	  return layer.shadowColor.map { UIColor(cgColor: $0) }
	}
	set {
	  layer.shadowColor = newValue?.cgColor
	}
  }
  
  @IBInspectable var maskToBound : Bool{
	get{
	  return self.layer.masksToBounds
	}
	set{
	  self.layer.masksToBounds = newValue
	}
  }
  
  func setGradientView() {
	let gradientLayer = CAGradientLayer()
	gradientLayer.frame = self.bounds
	
	// 색상 설정 (흰색 투명 -> 흰색 불투명)
	gradientLayer.colors = [
	  UIColor.white.withAlphaComponent(0.0).cgColor, // #ffffff, 0% 투명
	  UIColor.white.withAlphaComponent(1.0).cgColor  // #ffffff, 100% 불투명
	]
	
	// 방향 위에서 아래로
	gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
	gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
	
	self.layer.insertSublayer(gradientLayer, at: 0)
  }
}
