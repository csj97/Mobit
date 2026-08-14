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
    @IBOutlet weak var titleLabel: UILabel!
  @IBOutlet weak var sheetView: UIView!
  @IBOutlet weak var stackView: UIStackView!
  @IBOutlet weak var sheetViewTopConstraint: NSLayoutConstraint!
  var titleString: String
  var contentList: [String]
  var selectedIndex: Int = 0
  var sortType: InvestSortType = .name
  var delegate: MobitBottomSheetDelegate?
  var callBack: ((Int) -> ())? = nil
  
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
	self.view.backgroundColor = .clear
	self.dimView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
	self.sheetView.backgroundColor = .mobitColors(.surfaceElevated)
	self.stackView.backgroundColor = .mobitColors(.surfaceElevated)
	self.titleLabel.textColor = .mobitColors(.textPrimary)
	
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
	
	self.titleLabel.text = self.titleString
	
	for (index, title) in self.contentList.enumerated() {
	  let cell = self.makeCell(sortType: title, index: index)
	  self.stackView.addArrangedSubview(cell)
	}
	
	self.stackView.layoutIfNeeded()
  }
    
  private func makeCell(sortType: String, index: Int) -> UIView {
	
	let onImage: UIImage = UIImage(named: "button_check_on")!
	let offImage: UIImage = UIImage(named: "button_check_off")!
	let view: UIView = UIView()
	let label: UILabel = UILabel().then { label in
	  label.text = sortType
	  label.textColor = .mobitColors(.textPrimary)
	  label.font = .systemFont(ofSize: 14, weight: .medium)
	}
	let imageView: UIImageView = UIImageView().then { imageView in
	  imageView.image = self.sortType.rawValue == sortType ? onImage : offImage
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
	  make.top.bottom.equalToSuperview()
	  make.trailing.greaterThanOrEqualTo(imageView.snp.leading).offset(10)
	}
	
	imageView.snp.makeConstraints { make in
	  make.top.bottom.equalToSuperview()
	  make.trailing.equalToSuperview()
	}
	
	button.snp.makeConstraints { make in
	  make.top.bottom.leading.trailing.equalToSuperview()
	}
	
	return view
  }
  
  private func updateCellImages() {
	for (index, subview) in self.stackView.arrangedSubviews.enumerated() {
	  guard let imageView = subview.subviews.compactMap({ $0 as? UIImageView }).first else { continue }
	  imageView.image = index == selectedIndex
		  ? UIImage(named: "button_check_on")
		  : UIImage(named: "button_check_off")
	}
  }
    
  @objc func buttonTapped(_ sender: UIButton) {
	self.selectedIndex = sender.tag
	self.updateCellImages()
  }
  
  /// 확인 버튼 클릭
  @IBAction func tapOnConfirmButton(_ sender: UIButton) {
	self.callBack?(self.selectedIndex)
	self.dismiss(animated: true)
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
	
	self.present(mobitBottomSheetVC, animated: true, completion: nil)
  }
}
