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
  
  @IBOutlet weak var stackView: UIStackView!
  var titleString: String
  var contentList: [String]
  var selectedIndex: Int = 0
  var delegate: MobitBottomSheetDelegate?
  var callBack: ((Int) -> ())? = nil
  
  init(titleString: String, contentList: [String]) {
	self.titleString = titleString
	self.contentList = contentList
	super.init(nibName: "MobitBottomSheetViewController", bundle: nil)
  }
  
  required init?(coder: NSCoder) {
	fatalError("init(coder:) has not been implemented")
  }
  
  override func viewDidLoad() {
	super.viewDidLoad()
	
	for (index, title) in self.contentList.enumerated() {
	  let cell = self.makeCell(text: title, index: index)
	  self.stackView.addArrangedSubview(cell)
	}
	
	self.stackView.layoutIfNeeded()
  }
    
  private func makeCell(text: String, index: Int) -> UIView {
	
	let onImage: UIImage = UIImage(named: "button_check_on")!
	let offImage: UIImage = UIImage(named: "button_check_off")!
	let view: UIView = UIView()
	let label: UILabel = UILabel().then { label in
	  label.text = text
	  label.textColor = .black
	  label.font = .systemFont(ofSize: 14, weight: .medium)
	}
	let imageView: UIImageView = UIImageView().then { imageView in
	  imageView.image = index == 0 ? onImage : offImage
	}
	let button: UIButton = UIButton()
	
	button.tag = index
	button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
	
	view.addSubview(label)
	view.addSubview(imageView)
	view.addSubview(button)
	
	label.setContentHuggingPriority(.defaultLow, for: .horizontal)
	imageView.setContentHuggingPriority(.required, for: .horizontal)
	
	label.snp.makeConstraints { make in
	  make.leading.equalToSuperview().offset(16)
	  make.top.bottom.equalToSuperview()
	  make.trailing.greaterThanOrEqualTo(imageView.snp.leading).offset(10)
	}
	
	imageView.snp.makeConstraints { make in
	  make.top.bottom.equalToSuperview()
	  make.trailing.equalToSuperview().offset(-16)
	}
	
	button.snp.makeConstraints { make in
	  make.top.bottom.leading.trailing.equalTo(imageView)
	}
	
	return view
  }
    
  @objc func buttonTapped(_ sender: UIButton) {
	self.selectedIndex = sender.tag
  }
  
  /// 확인 버튼 클릭
  @IBAction func tapOnConfirmButton(_ sender: UIButton) {
	self.callBack?(self.selectedIndex)
  }
    
}

protocol MobitBottomSheetDelegate { }

extension MobitBottomSheetDelegate where Self: UIViewController {
  func showBottomSheet(
	title: String,
	contentList: [String],
	callBack: ((Int) -> ())?
  ) {
	let mobitBottomSheetVC = MobitBottomSheetViewController(
	  titleString: title,
	  contentList: contentList
	)
	mobitBottomSheetVC.delegate = self
	
	mobitBottomSheetVC.modalPresentationStyle = .overFullScreen
	mobitBottomSheetVC.modalTransitionStyle = .crossDissolve
	
	self.present(mobitBottomSheetVC, animated: true, completion: nil)
  }
}
