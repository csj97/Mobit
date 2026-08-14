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
	setPlaceholderColor(.mobitColors(.textTertiary))
  }
}
