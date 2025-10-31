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
	guard let doubleValue = Double(self) else {
	  return self // 숫자로 변환 실패 시 원본 반환
	}
	
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
		numberFormatter.negativeFormat = "-\(formatter)\(zeroCount)"
	  }
	}
	
	return numberFormatter.string(from: NSNumber(value: doubleValue)) ?? self
  }
  
  /// 숫자만 거르기
  var digitsOnlyDouble: Double {
	let filtered = self.filter { "0123456789.".contains($0) }
	return Double(filtered) ?? 0
  }
  
  /// Localized String
  var localized: String {
	  return NSLocalizedString(self, tableName: nil, bundle: Bundle.main, value: "", comment: "")
  }
  
  /// Localized Format String
  func localized(with lists: [CVarArg] = []) -> String {
	  return String(format: self.localized, lists)
  }
}
