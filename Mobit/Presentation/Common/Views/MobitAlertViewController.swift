//
//  MobitAlertViewController.swift
//  Mobit
//
//  Created by 조성재 on 5/18/25.
//

import UIKit

enum AlertType {
  case onlyConfirm    // 확인 버튼
  case canCancel      // 확인 + 취소 버튼
}

class MobitAlertViewController: UIViewController {
  @IBOutlet weak var labelStackView: UIStackView!
  @IBOutlet weak var buttonStackView: UIStackView!
  @IBOutlet weak var titleLabel: UILabel!
  @IBOutlet weak var contentLabel: UILabel!
  @IBOutlet weak var cancelButton: UIButton!
  @IBOutlet weak var confirmButton: UIButton!
  @IBOutlet weak var dimView: UIView!
  
  var callBack: ((Bool) -> ())? = nil
  var delegate: MobitAlertDelegate?
  
  var alertType: AlertType
  var titleString: String
  var content: String
  
  init(alertType: AlertType, title: String, content: String, callBack: ((Bool) -> ())?) {
	self.alertType = alertType
	self.titleString = title
	self.content = content
	self.callBack = callBack

	super.init(nibName: "MobitAlertViewController", bundle: nil)

  }
  
  required init?(coder: NSCoder) {
	fatalError("init(coder:) has not been implemented")
  }
  
  override func viewDidLoad() {
	super.viewDidLoad()
	
	self.configure(alertType: alertType, title: titleString, content: content, callBack: callBack)
  }
  
  func configure(
	alertType: AlertType,
	title: String?,
	content: String,
	callBack: ((Bool) -> ())?
  ) {
	self.callBack = callBack
	
	if alertType == .onlyConfirm {
	  self.cancelButton.isHidden = true
	}
	
	if title == nil {
	  self.titleLabel.isHidden = true
	} else {
	  self.titleLabel.text = title
	}
	self.contentLabel.text = content
  }
  
  @IBAction func tapOnCancelButton(_ sender: UIButton) {
	self.dismiss(animated: true) {
	  self.callBack?(false)
	}
  }
  
  @IBAction func tapOnConfirmButton(_ sender: UIButton) {
	self.dismiss(animated: true) {
	  self.callBack?(true)
	}
  }
}

protocol MobitAlertDelegate {
//  func show(alertType: AlertType, title: String, content: String, callBack: ((Bool) -> ())?)
}

extension MobitAlertDelegate where Self: UIViewController {
  func show(
	alertType: AlertType,
	title: String? = nil,
	content: String,
	callBack: ((Bool) -> ())?
  ) {
	
	let mobitAlertViewController = MobitAlertViewController(
	  alertType: alertType, title: title ?? "", content: content, callBack: callBack
	)
	mobitAlertViewController.delegate = self
	
	mobitAlertViewController.modalPresentationStyle = .overFullScreen
	mobitAlertViewController.modalTransitionStyle = .crossDissolve
	
	self.present(mobitAlertViewController, animated: true, completion: nil)
  }
}
