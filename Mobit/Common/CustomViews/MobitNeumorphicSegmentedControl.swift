//
//  MobitNeumorphicSegmentedControl.swift
//  Mobit
//
//  Created by 조성재 on 7/16/25.
//

import Foundation
import UIKit
import SnapKit

class MobitNeumorphicSegmentedControl: UIView {
  private var lightShadow: CALayer?
  
  // MARK: - Public API
  public var onSegmentChanged: ((Int) -> Void)?
  public var segments: [String] = [] {
	didSet {
	  configureSegments()
	}
  }
  public var selectedIndex: Int = 0 {
	didSet {
	  updateSelectedIndex(animated: true)
	}
  }
  
  // MARK: - Private
  private let stackView = UIStackView()
  private var buttons: [UIButton] = []
  
  // MARK: - Init
  override init(frame: CGRect) {
	super.init(frame: frame)
	setupBaseStyle()
  }
  
  required init?(coder: NSCoder) {
	super.init(coder: coder)
	setupBaseStyle()
  }
  
  private func setupBaseStyle() {
	backgroundColor = UIColor(hex: "#FBFBFB")
	layer.cornerRadius = 18
	layer.maskedCorners = CACornerMask(arrayLiteral: .layerMinXMinYCorner, .layerMaxXMinYCorner)
	layer.masksToBounds = false
	
	// 그림자: 바깥 양각 효과
	layer.shadowColor = UIColor(red: 0.6, green: 0.6, blue: 0.7, alpha: 1.0).cgColor
	layer.shadowOffset = CGSize(width: 6, height: 6)
	layer.shadowOpacity = 0.7
	clipsToBounds = false
	
	let lightShadow = CALayer()
	lightShadow.frame = bounds
	lightShadow.backgroundColor = backgroundColor?.cgColor
	lightShadow.shadowColor = UIColor.white.cgColor
	lightShadow.shadowOffset = CGSize(width: -6, height: -6)
	lightShadow.shadowOpacity = 1.0
	lightShadow.shadowRadius = 18
	lightShadow.cornerRadius = 18
	lightShadow.maskedCorners = CACornerMask(arrayLiteral: .layerMinXMinYCorner, .layerMaxXMinYCorner)
	layer.insertSublayer(lightShadow, at: 0)
	self.lightShadow = lightShadow
	
	stackView.axis = .horizontal
	stackView.distribution = .fillEqually
	stackView.alignment = .fill
	stackView.spacing = 0
	stackView.translatesAutoresizingMaskIntoConstraints = false
	
	addSubview(stackView)
	
	stackView.snp.makeConstraints { make in
	  make.edges.equalToSuperview()
	}
  }
  
  private func configureSegments() {
	buttons.forEach { $0.removeFromSuperview() }
	buttons.removeAll()
	
	for (index, title) in segments.enumerated() {
	  let container = UIView()
	  let button = UIButton(type: .custom)
	  button.setTitle(title, for: .normal)
	  button.setTitleColor(.label, for: .normal)
	  button.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
	  button.contentHorizontalAlignment = .center
	  button.tag = index
	  button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
	  button.layer.masksToBounds = false
	  
	  container.addSubview(button)
	  
	  if index < segments.count - 1 {
		// 🔥 마지막 인덱스가 아닐 경우에만 separator 추가
		let separator = UIView()
		separator.backgroundColor = .mobitColors(.lineLightGray)
		container.addSubview(separator)
		
		button.snp.makeConstraints { make in
		  make.top.leading.bottom.equalToSuperview()
		  make.trailing.equalTo(separator.snp.leading)
		}
		
		separator.snp.makeConstraints { make in
		  make.top.bottom.equalToSuperview().inset(10)
		  make.trailing.equalToSuperview()
		  make.width.equalTo(1)
		}
	  } else {
		// 마지막 버튼은 separator 없이 full width
		button.snp.makeConstraints { make in
		  make.edges.equalToSuperview()
		}
	  }
	  
	  buttons.append(button)
	  stackView.addArrangedSubview(container)
	}
	
	layoutIfNeeded()
	updateSelectedIndex(animated: false)
  }
  
  @objc private func buttonTapped(_ sender: UIButton) {
	selectedIndex = sender.tag
	onSegmentChanged?(selectedIndex)
  }
  
  private func updateSelectedIndex(animated: Bool) {
	guard selectedIndex < buttons.count else { return }
	
	for (index, button) in buttons.enumerated() {
	  let isSelected = (index == selectedIndex)
	  button.setTitleColor(isSelected ? .darkGray : .lightGray, for: .normal)
	  button.titleLabel?.font = isSelected
	  ? .systemFont(ofSize: 16, weight: .bold)
	  : .systemFont(ofSize: 14, weight: .regular)
	}
  }
  
  override func layoutSubviews() {
	super.layoutSubviews()
	
	DispatchQueue.main.async {
	  self.updateSelectedIndex(animated: false)
	  if let shadowLayer = self.lightShadow {
		shadowLayer.frame = self.bounds
		shadowLayer.cornerRadius = self.layer.cornerRadius
	  }
	}
  }
}
