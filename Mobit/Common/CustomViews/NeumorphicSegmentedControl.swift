//
//  NeumorphicSegmentedControl.swift
//  Mobit
//
//  Created by 조성재 on 7/11/25.
//

import UIKit
import SnapKit

class NeumorphicSegmentedControl: UIView {
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
  private let highlightView = UIView()
  
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
//	backgroundColor = UIColor.systemGray6
//	layer.cornerRadius = 18
//	layer.shadowColor = UIColor.white.cgColor
//	layer.shadowOffset = CGSize(width: -2, height: -2)
//	layer.shadowOpacity = 1
//	layer.shadowRadius = 2
//	clipsToBounds = false
//	
//	// 그림자 대비용 inner shadow
//	let innerShadow = CALayer()
//	innerShadow.frame = bounds
//	innerShadow.shadowColor = UIColor.black.cgColor
//	innerShadow.shadowOffset = CGSize(width: 2, height: 2)
//	innerShadow.shadowOpacity = 0.07
//	innerShadow.shadowRadius = 2
//	innerShadow.backgroundColor = UIColor.clear.cgColor
//	layer.addSublayer(innerShadow)
	
	// 기본 스타일
	layer.cornerRadius = 18
	layer.masksToBounds = false
	
	// 그림자 1: 전체 방향 (어두운 음영)
	layer.shadowOffset = .zero
	layer.shadowOpacity = 0.7
	layer.shadowRadius = 8
	clipsToBounds = false
	
	// 그림자 2: 위쪽 (밝은 빛)
	let lightShadow = CALayer()
	lightShadow.frame = bounds
	lightShadow.shadowOffset = CGSize(width: -6, height: -6)
	lightShadow.shadowOpacity = 1.0
	lightShadow.shadowRadius = 8
	lightShadow.cornerRadius = 18
	layer.insertSublayer(lightShadow, at: 0)
	self.lightShadow = lightShadow
	updateResolvedColors()
	
	stackView.axis = .horizontal
	stackView.distribution = .fillEqually
	stackView.spacing = 0
	stackView.translatesAutoresizingMaskIntoConstraints = false
	
	highlightView.backgroundColor = MarketColorPalette.riseColor.withAlphaComponent(0.15)
	highlightView.layer.cornerRadius = 18
	highlightView.isUserInteractionEnabled = false
	addSubview(highlightView)
	addSubview(stackView)
	
	stackView.snp.makeConstraints { make in
	  make.leading.equalToSuperview().inset(4)
	  make.trailing.equalToSuperview().inset(4)
	  make.top.equalToSuperview().inset(4)
	  make.bottom.equalToSuperview().inset(4)
	}
  }
  
  private func configureSegments() {
	// 이전 버튼 제거
	buttons.forEach { $0.removeFromSuperview() }
	buttons.removeAll()
	
	for (index, title) in segments.enumerated() {
	  let button = UIButton(type: .custom)
	  button.setTitle(title, for: .normal)
	  button.setTitleColor(.mobitColors(.tradeTextPrimary), for: .normal)
	  button.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
	  button.contentHorizontalAlignment = .center
	  button.tag = index
	  button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
	  buttons.append(button)
	  stackView.addArrangedSubview(button)
	}
	
	// 초기 선택 반영
	layoutIfNeeded()
	updateSelectedIndex(animated: false)
  }
  
  @objc private func buttonTapped(_ sender: UIButton) {
	selectedIndex = sender.tag
	onSegmentChanged?(selectedIndex)
  }
  
  private func updateSelectedIndex(animated: Bool) {
	guard selectedIndex < buttons.count else { return }
	
	if selectedIndex == 0 {
	  highlightView.backgroundColor = MarketColorPalette.riseColor
	} else if selectedIndex == 1 {
	  highlightView.backgroundColor = MarketColorPalette.fallColor
	} else {
	  highlightView.backgroundColor = UIColor { traitCollection in
		traitCollection.userInterfaceStyle == .dark
		  ? .mobitColors(.tradeControlSurface)
		  : .mobitColors(.borderPrimary)
	  }
	}
	
	for (index, button) in buttons.enumerated() {
	  let isSelected = (index == selectedIndex)
	  button.setTitleColor(isSelected ? .white : .mobitColors(.tradeTextPrimary), for: .normal)
	  button.titleLabel?.font = isSelected ? .systemFont(ofSize: 14, weight: .bold) : .systemFont(ofSize: 12, weight: .regular)
		}

		let selectedButton = buttons[selectedIndex]
		let targetFrame = selectedButton.convert(selectedButton.bounds, to: self)

		if animated {
		  UIView.animate(withDuration: 0.25) {
			self.highlightView.frame = targetFrame
		self.highlightView.layer.cornerRadius = targetFrame.height / 2
	  }
		} else {
		  self.highlightView.frame = targetFrame
		  self.highlightView.layer.cornerRadius = targetFrame.height / 2
	  }
  }

  func refreshMarketColors() {
	updateSelectedIndex(animated: false)
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

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
	updateResolvedColors()
	updateSelectedIndex(animated: false)
  }

  private func updateResolvedColors() {
	let surfaceColor = UIColor.mobitColors(.tradeSurface).resolvedColor(with: traitCollection)
	backgroundColor = surfaceColor
	layer.shadowColor = UIColor.mobitColors(.tradeSeparator).resolvedColor(with: traitCollection).cgColor
	lightShadow?.backgroundColor = surfaceColor.cgColor
	lightShadow?.shadowColor = UIColor.mobitColors(.tradeControlSurface).resolvedColor(with: traitCollection).cgColor
  }
}
