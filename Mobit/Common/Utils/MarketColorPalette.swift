//
//  MarketColorPalette.swift
//  Mobit
//
//  Created by OpenAI on 7/5/26.
//

import SwiftUI
import UIKit

enum MarketColorPalette {
  // 원본 hex를 단일 소스로 둔다 (UIColor + 차트 override 공용)
  static let riseRedFallBlueRiseHex = "#E71A06"  // 상승 = 빨강
  static let riseRedFallBlueFallHex = "#125ECE"  // 하락 = 파랑
  static let riseGreenFallRedRiseHex = "#0A9981"
  static let riseGreenFallRedFallHex = "#F23545"

  static let riseRedFallBlueRiseColor = UIColor(hex: riseRedFallBlueRiseHex)
  static let riseRedFallBlueFallColor = UIColor(hex: riseRedFallBlueFallHex)
  static let riseGreenFallRedRiseColor = UIColor(hex: riseGreenFallRedRiseHex)
  static let riseGreenFallRedFallColor = UIColor(hex: riseGreenFallRedFallHex)

  // 차트(TradingView) 등 hex 문자열이 필요한 곳에서 사용
  static var riseColorHex: String {
	switch UserDataManager.marketColorTheme {
	case .riseRedFallBlue:
	  return self.riseRedFallBlueRiseHex
	case .riseGreenFallRed:
	  return self.riseGreenFallRedRiseHex
	}
  }

  static var fallColorHex: String {
	switch UserDataManager.marketColorTheme {
	case .riseRedFallBlue:
	  return self.riseRedFallBlueFallHex
	case .riseGreenFallRed:
	  return self.riseGreenFallRedFallHex
	}
  }

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
  
  static var neutralColor: UIColor { .mobitColors(.textPrimary) }

  static var riseBackgroundColor: UIColor { orderBookBackgroundColor(for: riseColor) }
  static var fallBackgroundColor: UIColor { orderBookBackgroundColor(for: fallColor) }
  static var riseBarColor: UIColor { riseColor.withAlphaComponent(0.24) }
  static var fallBarColor: UIColor { fallColor.withAlphaComponent(0.24) }
  
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

  // 라이트 모드 호가 배경은 더 연하게 표시
  private static func orderBookBackgroundColor(for color: UIColor) -> UIColor {
	UIColor { traitCollection in
	  let alpha: CGFloat = traitCollection.userInterfaceStyle == .dark ? 0.08 : 0.05
	  return color.withAlphaComponent(alpha)
	}
  }

}
