//
//  MobitBottomSheetViewController.swift
//  Mobit
//
//  Created by 조성재 on 10/13/25.
//

import UIKit
import Then
import SnapKit

class MobitBottomSheetViewController: MobitBaseViewController {
  
    @IBOutlet weak var dimView: UIView!
  @IBOutlet weak var sheetView: UIView!
  @IBOutlet weak var stackView: UIStackView!
  @IBOutlet weak var confirmButton: UIButton!
  @IBOutlet weak var sheetViewTopConstraint: NSLayoutConstraint!
  var titleString: String
  var contentList: [String]
  var selectedIndex: Int = 0
  var sortType: InvestSortType = .name
  var delegate: MobitBottomSheetDelegate?
  var callBack: ((Int) -> ())? = nil
  private var isDismissing = false
  
  init(
	titleString: String,
	contentList: [String],
	sortType: InvestSortType,
	callBack: ((Int) -> ())?
  ) {
	self.titleString = titleString
	self.contentList = contentList
	self.sortType = sortType
	self.callBack = callBack
	super.init(nibName: "MobitBottomSheetViewController", bundle: nil)
  }
  
  required init?(coder: NSCoder) {
	fatalError("init(coder:) has not been implemented")
  }
  
  override func viewDidLoad() {
	super.viewDidLoad()
	applyThemeColors()
	self.dimView.alpha = 0
	self.dimView.addGestureRecognizer(
	  UITapGestureRecognizer(target: self, action: #selector(didTapDimView))
	)
	
	self.sheetView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
	self.sheetView.layer.cornerRadius = 20
	self.sheetView.clipsToBounds = false		// for shadow
	
	// shadow
	let shadowPath = UIBezierPath(
		roundedRect: sheetView.bounds,
		cornerRadius: 20
	)
	self.sheetView.layer.shadowPath = shadowPath.cgPath
	self.sheetView.layer.shadowColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.12).cgColor
	self.sheetView.layer.shadowOpacity = 1
	self.sheetView.layer.shadowRadius = 4
	self.sheetView.layer.shadowOffset = CGSize(width: 0, height: -4)
	
	for (index, title) in self.contentList.enumerated() {
	  let cell = self.makeCell(sortType: title, index: index)
	  self.stackView.addArrangedSubview(cell)
	}
	
	self.stackView.layoutIfNeeded()
  }

  override func viewWillAppear(_ animated: Bool) {
	super.viewWillAppear(animated)
	self.view.layoutIfNeeded()
	self.sheetView.transform = CGAffineTransform(translationX: 0, y: self.sheetView.bounds.height)
  }

  override func viewDidAppear(_ animated: Bool) {
	super.viewDidAppear(animated)
	UIView.animate(
	  withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.3,
	  delay: 0,
	  options: [.curveEaseOut, .beginFromCurrentState]
	) {
	  self.dimView.alpha = 1
	  self.sheetView.transform = .identity
	}
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
	applyThemeColors()
  }

  private func applyThemeColors() {
	self.view.backgroundColor = .clear
	self.dimView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
	self.sheetView.backgroundColor = .mobitColors(.surfaceElevated)
	self.stackView.backgroundColor = .mobitColors(.surfaceElevated)
	self.confirmButton.backgroundColor = MarketColorPalette.riseRedFallBlueFallColor
	self.stackView.arrangedSubviews.forEach { subview in
	  subview.backgroundColor = .mobitColors(.surfaceElevated)
	  subview.subviews.compactMap { $0 as? UILabel }.forEach {
		$0.textColor = .mobitColors(.textPrimary)
	  }
	}
  }
    
  private func makeCell(sortType: String, index: Int) -> UIView {
	let isSelected = self.sortType.rawValue == sortType
	let view: UIView = UIView()
	let label: UILabel = UILabel().then { label in
	  label.text = sortType
	  label.textColor = .mobitColors(.textPrimary)
	  label.font = .systemFont(ofSize: 14, weight: .regular)
	  label.numberOfLines = 0
	}
	let imageView: UIImageView = UIImageView().then { imageView in
	  imageView.image = self.radioImage(isSelected: isSelected)
	  imageView.tintColor = self.radioColor(isSelected: isSelected)
	  imageView.contentMode = .scaleAspectFit
	}
	let button: UIButton = UIButton()
	
	button.tag = index
	button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
	
	view.backgroundColor = .mobitColors(.surfaceElevated)
	view.addSubview(label)
	view.addSubview(imageView)
	view.addSubview(button)
	
	label.setContentHuggingPriority(.defaultLow, for: .horizontal)
	imageView.setContentHuggingPriority(.required, for: .horizontal)
	
	label.snp.makeConstraints { make in
	  make.leading.equalToSuperview()
	  make.top.bottom.equalToSuperview().inset(10)
	  make.trailing.greaterThanOrEqualTo(imageView.snp.leading).offset(10)
	}
	
	imageView.snp.makeConstraints { make in
	  make.centerY.equalToSuperview()
	  make.trailing.equalToSuperview().inset(2)
	  make.size.equalTo(20)
	}
	
	button.snp.makeConstraints { make in
	  make.top.bottom.leading.trailing.equalToSuperview()
	}

	view.snp.makeConstraints { make in
	  make.height.greaterThanOrEqualTo(48)
	}
	
	return view
  }
  
  private func updateCellImages() {
	for (index, subview) in self.stackView.arrangedSubviews.enumerated() {
	  guard let imageView = subview.subviews.compactMap({ $0 as? UIImageView }).first else { continue }
	  let isSelected = index == selectedIndex
	  imageView.image = self.radioImage(isSelected: isSelected)
	  imageView.tintColor = self.radioColor(isSelected: isSelected)
	}
  }

  private func radioImage(isSelected: Bool) -> UIImage? {
	let symbolName = isSelected ? "largecircle.fill.circle" : "circle"
	let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
	return UIImage(systemName: symbolName, withConfiguration: configuration)
  }

  private func radioColor(isSelected: Bool) -> UIColor {
	isSelected ? MarketColorPalette.riseRedFallBlueFallColor : .mobitColors(.borderPrimary)
  }
    
  @objc func buttonTapped(_ sender: UIButton) {
	self.selectedIndex = sender.tag
	self.updateCellImages()
  }

  @objc private func didTapDimView() {
	self.dismissBottomSheet()
  }

  private func dismissBottomSheet(completion: (() -> Void)? = nil) {
	guard !self.isDismissing else { return }
	self.isDismissing = true
	UIView.animate(
	  withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.25,
	  delay: 0,
	  options: [.curveEaseIn, .beginFromCurrentState]
	) {
	  self.dimView.alpha = 0
	  self.sheetView.transform = CGAffineTransform(translationX: 0, y: self.sheetView.bounds.height)
	} completion: { _ in
	  self.dismiss(animated: false, completion: completion)
	}
  }
  
  /// 확인 버튼 클릭
  @IBAction func tapOnConfirmButton(_ sender: UIButton) {
	self.callBack?(self.selectedIndex)
	self.dismissBottomSheet()
  }
    
}

protocol MobitBottomSheetDelegate { }

extension MobitBottomSheetDelegate where Self: UIViewController {
  func showBottomSheet(
	title: String,
	contentList: [String],
	sortType: InvestSortType,
	callBack: ((Int) -> ())?
  ) {
	let mobitBottomSheetVC = MobitBottomSheetViewController(
	  titleString: title,
	  contentList: contentList,
	  sortType: sortType,
	  callBack: callBack
	)
	mobitBottomSheetVC.delegate = self
	
	mobitBottomSheetVC.modalPresentationStyle = .overFullScreen
	
	self.present(mobitBottomSheetVC, animated: false, completion: nil)
  }
}
