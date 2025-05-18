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
  
  var callBack: (() -> ())? = nil
  var delegate: MobitAlertDelegate?
  
  override func viewDidLoad() {
	super.viewDidLoad()
	
  }
  
  func configure(
	alertType: AlertType,
	title: String?,
	content: String
  ) {
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
    
  }
  
  @IBAction func tapOnConfirmButton(_ sender: UIButton) {
    
  }
}

protocol MobitAlertDelegate {
//  func show(alertType: AlertType, title: String, content: String)
}

extension MobitAlertDelegate where Self: UIViewController {
	func show(
		alertType: AlertType,
		title: String? = nil,
		content: String
	) {
	  
	  let mobitAlertStoryboard = UIStoryboard(name: "MobitAlertViewController", bundle: nil)
	  let mobitAlertViewController = mobitAlertStoryboard.instantiateViewController(
		withIdentifier: "MobitAlertViewController"
	  ) as! MobitAlertViewController
	  
	  mobitAlertViewController.delegate = self
	  
	  mobitAlertViewController.modalPresentationStyle = .overFullScreen
	  mobitAlertViewController.modalTransitionStyle = .crossDissolve
	  mobitAlertViewController.configure(alertType: alertType, title: title, content: content)
	  
	  self.present(mobitAlertViewController, animated: true, completion: nil)
	}
}
