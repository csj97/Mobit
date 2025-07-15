//
//  LabelExtension.swift
//  Mobit
//
//  Created by 조성재 on 7/14/25.
//

import UIKit

extension UILabel {
  
  /// 특정 구간 Bold 처리
  func applyBoldAttribute(for subString: String, fontSize: CGFloat) {
	guard let text = self.text, let range = text.range(of: subString) else { return }
	let nsRange = NSRange(range, in: text)
	
	let attributedString = NSMutableAttributedString(string: text, attributes: [
	  .font: self.font ?? UIFont(name: "Pretendard-Regular", size: fontSize)!
	])
	
	let boldFont = UIFont(name: "Pretendard-Bold", size: fontSize)!
	attributedString.addAttribute(NSAttributedString.Key.font, value: boldFont, range: nsRange)
	
	self.attributedText = attributedString
  }
}
