//
//  DoubleExtension.swift
//  Mobit
//
//  Created by 조성재 on 3/8/25.
//
import Foundation

extension Double {
  func formatTradingValue() -> String {
    TradingNumberFormat.string(self)
  }

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

enum TradingNumberFormat {
  static let integerThreshold: Decimal = 1_000
  static let maximumFractionDigits = 8
  private static let locale = Locale(identifier: "en_US_POSIX")

  static func truncated(_ value: Decimal) -> Decimal {
    guard !value.isNaN else { return .nan }
    let scale = value >= integerThreshold || value <= -integerThreshold ? 0 : maximumFractionDigits
    var source = value
    var result = Decimal()
    // 음수 손익도 소수 부분만 제거해 표시 손실이 커지지 않도록 한다.
    NSDecimalRound(&result, &source, scale, value < 0 ? .up : .down)
    return result == 0 ? 0 : result
  }

  static func string(_ value: Decimal?) -> String {
    guard let value, !value.isNaN else { return "—" }
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = true
    formatter.groupingSize = 3
    formatter.secondaryGroupingSize = 3
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = maximumFractionDigits
    return formatter.string(from: NSDecimalNumber(decimal: truncated(value))) ?? "—"
  }

  static func string(_ value: Double) -> String {
    guard value.isFinite, let decimal = Decimal(string: String(value), locale: locale) else { return "—" }
    return string(decimal)
  }
}
