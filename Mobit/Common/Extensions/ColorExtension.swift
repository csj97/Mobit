//
//  ColorExtension.swift
//  Mobit
//
//  Created by 조성재 on 1/5/25.
//

import Foundation
import UIKit

extension UIColor {
  static func mobitColors(_ mobitColorName: MobitColors) -> UIColor {
    switch mobitColorName {
    case .askLightBlue:
      return UIColor(named: "ask_light_blue")!
    case .askDeepBlue:
      return UIColor(named: "ask_deep_blue")!
    case .bidLightRed:
      return UIColor(named: "bid_light_red")!
    case .bidDeepRed:
      return UIColor(named: "bid_deep_red")!
    case .lightGrayBG:
      return UIColor(named: "bg_light_gray")!
	case .lightYellowBG:
	  return UIColor(named: "bg_light_yellow")!
	case .yellowBG:
	  return UIColor(named: "bg_yellow")!
    }
  }
  
  enum MobitColors {
    case askLightBlue
    case askDeepBlue
    case bidLightRed
    case bidDeepRed
    case lightGrayBG
	case lightYellowBG
	case yellowBG
  }
  
  convenience init(hex: String) {
	var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
	hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
	
	var rgb: UInt64 = 0
	Scanner(string: hexSanitized).scanHexInt64(&rgb)
	
	let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
	let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
	let b = CGFloat(rgb & 0xFF) / 255.0
	
	self.init(red: r, green: g, blue: b, alpha: 1.0)
  }
}
