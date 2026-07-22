//
//  DoubleExtension.swift
//  Mobit
//
//  Created by 조성재 on 3/8/25.
//
import Foundation

extension Double {
  /// 자릿수 끊어내기
  func formatDigits(digits: Int) -> Double {
	let digitStandard = Double(Int(pow(10.0, Double(digits))))
	let formattedValue = floor(self * digitStandard) / digitStandard
	return formattedValue
  }
  
  func formatSignificantDigits(digits: Int = 8) -> String {
	// 1. 최대 소수점 digits자리까지만 유지 (반올림 없이 자르기)
	guard digits >= 0 else { return "0" }
	
	let digitStandard = pow(10.0, Double(digits))
	let formattedValue = floor(self * digitStandard) / digitStandard
	
	// 절댓값 1000 이상이면 무조건 정수로 변환 (음수 큰 손익도 동일하게 소수점 절삭)
	if abs(formattedValue) >= 1000 {
	  let stringValue = String(format: "%.0f", formattedValue)
		.replacingOccurrences(
		  of: "(?<=\\d)(?=(\\d{3})+(?!\\d))",
		  with: ",",
		  options: .regularExpression
		)
	  
	  return stringValue
	}
	
	// 2. 소수점 포함 숫자를 문자열로 변환
	var formattedString = String(format: "%.\(digits)f", formattedValue)
	
	// 3. 불필요한 소수점 이하 0 제거
	if formattedString.contains(".") {
	  while formattedString.last == "0" {
		formattedString.removeLast()
	  }
	  if formattedString.last == "." {
		formattedString.removeLast()
	  }
	}
	
	// 4. 콤마 추가 (소수점 앞부분만)
	if let dotIndex = formattedString.firstIndex(of: ".") {
	  let integerPart = formattedString[..<dotIndex]
	  let decimalPart = formattedString[dotIndex...]
	  let formattedInteger = integerPart.replacingOccurrences(
		of: "(?<=\\d)(?=(\\d{3})+(?!\\d))",
		with: ",",
		options: .regularExpression
	  )
	  return formattedInteger + decimalPart
	  
	} else {
	  
	  return formattedString.replacingOccurrences(
		of: "(?<=\\d)(?=(\\d{3})+(?!\\d))",
		with: ",",
		options: .regularExpression
	  )
	}
  }
}
