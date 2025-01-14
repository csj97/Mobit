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
    }
  }
  
  enum MobitColors {
    case askLightBlue
    case askDeepBlue
    case bidLightRed
    case bidDeepRed
    case lightGrayBG
  }
}
