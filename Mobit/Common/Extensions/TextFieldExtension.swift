//
//  TextFieldExtension.swift
//  Mobit
//
//  Created by 조성재 on 12/1/25.
//

import Foundation
import UIKit

extension UITextField {
  func setPlaceholderColor(_ color: UIColor) {
	let placeholderText = self.placeholder ?? ""
	self.attributedPlaceholder = NSAttributedString(
	  string: placeholderText,
	  attributes: [NSAttributedString.Key.foregroundColor: color]
	)
  }
  
  func setAdaptivePlaceholderColor() {
	let adaptiveColor = UIColor { (traitCollection: UITraitCollection) -> UIColor in
	  if traitCollection.userInterfaceStyle == .dark {
		return UIColor.lightGray.withAlphaComponent(0.8)
	  } else {
		return UIColor.darkGray.withAlphaComponent(0.6)
	  }
	}
	setPlaceholderColor(adaptiveColor)
  }
}
