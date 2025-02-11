//
//  StringExtension.swift
//  Mobit
//
//  Created by 조성재 on 2/11/25.
//

import Foundation

extension String {
  /// 콤마 (기본), origin default true
  func addComma(showOrigin: Bool = true) -> String {
	  let numberFormatter = NumberFormatter()
	  numberFormatter.numberStyle = .decimal
	  numberFormatter.locale = Locale(identifier: "en_US")
	  
	  if showOrigin {
		  var decimalCount: Int = 0
		  
		  let decimal = self.split(separator: ".")
		  if decimal.count > 1 {
			  decimalCount = decimal[1].count
		  }
		  
		  if decimalCount > 0 {
			  let formatter = "#,##0."
			  let zeroCount = Array(repeating: "0", count: decimalCount).joined()
			  numberFormatter.positiveFormat = formatter + zeroCount
		  }
	  }
	  
	  let result = numberFormatter.string(from: NSNumber(value: Double(self) ?? 0)) ?? ""
	  return result
  }
}
