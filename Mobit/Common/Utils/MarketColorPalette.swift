//
//  MarketColorPalette.swift
//  Mobit
//
//  Created by OpenAI on 7/5/26.
//

import SwiftUI
import UIKit

enum MarketColorPalette {
  static let riseRedFallBlueRiseColor = UIColor(hex: "#F04452")
  static let riseRedFallBlueFallColor = UIColor(hex: "#3B82F6")
  static let riseGreenFallRedRiseColor = UIColor(hex: "#20C997")
  static let riseGreenFallRedFallColor = UIColor(hex: "#EB4D72")
  
  static var riseColor: UIColor {
	switch UserDataManager.marketColorTheme {
	case .riseRedFallBlue:
	  return self.riseRedFallBlueRiseColor
	case .riseGreenFallRed:
	  return self.riseGreenFallRedRiseColor
	}
  }
  
  static var fallColor: UIColor {
	switch UserDataManager.marketColorTheme {
	case .riseRedFallBlue:
	  return self.riseRedFallBlueFallColor
	case .riseGreenFallRed:
	  return self.riseGreenFallRedFallColor
	}
  }
  
  static var neutralColor: UIColor { .black }
  
  static var riseSwiftUIColor: Color { Color(uiColor: riseColor) }
  static var fallSwiftUIColor: Color { Color(uiColor: fallColor) }
  
  static func color(forSignedValue value: Double) -> UIColor {
	if value > 0 { return riseColor }
	if value < 0 { return fallColor }
	return neutralColor
  }
  
  static func color(forChange change: String) -> UIColor? {
	switch change {
	case "RISE":
	  return riseColor
	case "FALL":
	  return fallColor
	default:
	  return nil
	}
  }
}
