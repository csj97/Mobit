//
//  SegmentControlExtension.swift
//  Mobit
//
//  Created by 조성재 on 2/7/25.
//

import UIKit

class MobitSegmentedControl: UISegmentedControl {
  override init(items: [Any]?) {
	super.init(items: items)
  }
  
  required init?(coder: NSCoder) {
	super.init(coder: coder)
  }
  
  func setSegmentedControl(
	normalColor nColor: UIColor,
	selectedColor sColor: UIColor
  ) {
	// 전체 배경색 제거, 선택 색상만 white
	setBackgroundImage(imageWithColor(nColor), for: .normal, barMetrics: .default)
	setBackgroundImage(imageWithColor(sColor), for: .selected, barMetrics: .default)
	setBackgroundImage(imageWithColor(sColor), for: .highlighted, barMetrics: .default)
	
	// 세그먼트 간 구분선 제거
	setDividerImage(
	  imageWithColor(.clear),
	  forLeftSegmentState: .normal,
	  rightSegmentState: .normal,
	  barMetrics: .default
	)
	
	// 텍스트 색상 설정
	let normalAttributes: [NSAttributedString.Key: Any] = [
	  .foregroundColor: UIColor.mobitColors(.textPrimary),
	  .font: UIFont.systemFont(ofSize: 14, weight: .regular)
	]
	let selectedAttributes: [NSAttributedString.Key: Any] = [
	  .foregroundColor: UIColor.mobitColors(.textSecondary),
	  .font: UIFont.systemFont(ofSize: 16, weight: .bold)
	]
	
	setTitleTextAttributes(normalAttributes, for: .normal)
	setTitleTextAttributes(selectedAttributes, for: .selected)
	
	if #available(iOS 13.0, *) {
	  let backgroundView = subviews.first
	  backgroundView?.layer.cornerRadius = 0
	  backgroundView?.clipsToBounds = false
	}
	
	// 전체적인 모서리 둥근 효과 제거
	layer.cornerRadius = 0
	layer.masksToBounds = false
  }
  
  private func imageWithColor(_ color: UIColor) -> UIImage {
	let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
	UIGraphicsBeginImageContext(rect.size)
	let context = UIGraphicsGetCurrentContext()
	context?.setFillColor(color.cgColor)
	context?.fill(rect)
	let image = UIGraphicsGetImageFromCurrentImageContext()
	UIGraphicsEndImageContext()
	return image ?? UIImage()
  }
}
