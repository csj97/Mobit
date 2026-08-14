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
	case .backgroundPrimary:
	  return UIColor(named: "background_primary")!
	case .surfacePrimary:
	  return UIColor(named: "surface_primary")!
	case .surfaceElevated:
	  return UIColor(named: "surface_elevated")!
	case .borderPrimary:
	  return UIColor(named: "border_primary")!
	case .textPrimary:
	  return UIColor(named: "text_primary")!
	case .textSecondary:
	  return UIColor(named: "text_secondary")!
	case .textTertiary:
	  return UIColor(named: "text_tertiary")!
	case .accentPrimary:
	  return UIColor(named: "accent_primary")!
	case .chartBackground:
	  return UIColor(named: "chart_background")!
	case .chartGrid:
	  return UIColor(named: "chart_grid")!
    case .askLightBlue:
      return UIColor(named: "ask_light_blue")!
    case .askActionBlue:
      return UIColor(named: "ask_action_blue")!
    case .askDeepBlue:
      return UIColor(named: "ask_deep_blue")!
    case .bidLightRed:
      return UIColor(named: "bid_light_red")!
    case .bidActionRed:
      return UIColor(named: "bid_action_red")!
    case .bidDeepRed:
      return UIColor(named: "bid_deep_red")!
    case .lightGrayBG:
      return UIColor(named: "bg_light_gray")!
	case .lightYellowBG:
	  return UIColor(named: "bg_light_yellow")!
	case .yellowBG:
	  return UIColor(named: "bg_yellow")!
	case .lineLightGray:
	  return UIColor(named: "line_light_gray")!
	case .mobitPrimary:
	  return UIColor(named: "mobit_primary")!
	case .white_FBFBFB:
	  return UIColor(named: "white_FBFBFB")!
	case .white_F8FAFC:
	  return UIColor(named: "white_F8FAFC")!
	case .blue_E8F9FF:
	  return UIColor(named: "blue_E8F9FF")!
    }
  }
  
  enum MobitColors {
	case backgroundPrimary
	case surfacePrimary
	case surfaceElevated
	case borderPrimary
	case textPrimary
	case textSecondary
	case textTertiary
	case accentPrimary
	case chartBackground
	case chartGrid
    case askLightBlue
    case askActionBlue
    case askDeepBlue
    case bidLightRed
    case bidActionRed
    case bidDeepRed
    case lightGrayBG
	case lightYellowBG
	case yellowBG
	case lineLightGray
	case mobitPrimary
	case white_FBFBFB
	case white_F8FAFC
	case blue_E8F9FF
  }
  
  static func hexStringToUIColor (hex:String) -> UIColor {
	var cString:String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
	
	if (cString.hasPrefix("#")) {
	  cString.remove(at: cString.startIndex)
	}
	
	if ((cString.count) != 6) {
	  return UIColor.gray
	}
	
	var rgbValue:UInt64 = 0
	Scanner(string: cString).scanHexInt64(&rgbValue)
	
	return UIColor(
	  red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
	  green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
	  blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
	  alpha: CGFloat(1.0)
	)
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
