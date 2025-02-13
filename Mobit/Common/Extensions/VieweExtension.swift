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
}
