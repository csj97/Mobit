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
  @IBOutlet weak var dividerView: UIView!
  @IBOutlet weak var buttonDividerView: UIView!
  @IBOutlet weak var dimView: UIView!
  
  var callBack: ((Bool) -> ())? = nil
  var delegate: MobitAlertDelegate?
  
  var alertType: AlertType
  var titleString: String
  var content: String
  var titleAlignment: NSTextAlignment = .left
  var contentAlignment: NSTextAlignment = .left
  
  init(
	alertType: AlertType,
	titleAlignment: NSTextAlignment = .left,
	title: String,
	contentAlignment: NSTextAlignment = .left,
	content: String,
	callBack: ((Bool) -> ())?
  ) {
	self.alertType = alertType
	self.titleString = title
	self.content = content
	self.callBack = callBack
	self.titleAlignment = titleAlignment
	self.contentAlignment = contentAlignment

	super.init(nibName: "MobitAlertViewController", bundle: nil)

  }
  
  required init?(coder: NSCoder) {
	fatalError("init(coder:) has not been implemented")
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
	applyThemeColors()
    self.configure(alertType: alertType, title: titleString, content: content, callBack: callBack)
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
	applyThemeColors()
  }

  private func applyThemeColors() {
    self.view.backgroundColor = .clear
	self.dimView.alpha = 1
	let dimAlpha: CGFloat = traitCollection.userInterfaceStyle == .dark ? 0.22 : 0.42
	self.dimView.backgroundColor = UIColor.black.withAlphaComponent(dimAlpha)
	self.labelStackView.superview?.backgroundColor = .mobitColors(.surfaceElevated)
	self.labelStackView.backgroundColor = .clear
	self.labelStackView.arrangedSubviews
	  .filter { $0 !== self.titleLabel && $0 !== self.contentLabel && $0 !== self.dividerView }
	  .forEach { $0.backgroundColor = .clear }
    self.titleLabel.textColor = .mobitColors(.textPrimary)
	self.contentLabel.textColor = .mobitColors(.textSecondary)
    self.dividerView.backgroundColor = .mobitColors(.borderPrimary)
	self.buttonStackView.backgroundColor = .clear
	self.buttonStackView.superview?.subviews
	  .filter { $0 !== self.labelStackView && $0 !== self.buttonStackView }
	  .forEach { $0.backgroundColor = .mobitColors(.borderPrimary) }
	self.buttonStackView.arrangedSubviews
	  .filter { !($0 is UIButton) }
	  .forEach { $0.backgroundColor = .mobitColors(.borderPrimary) }
	self.cancelButton.backgroundColor = .mobitColors(.surfaceElevated)
	self.confirmButton.backgroundColor = .mobitColors(.surfaceElevated)
	self.cancelButton.setTitleColor(MarketColorPalette.fallColor, for: .normal)
    self.confirmButton.setTitleColor(.mobitColors(.accentPrimary), for: .normal)
	self.cancelButton.configuration?.baseForegroundColor = MarketColorPalette.fallColor
	self.confirmButton.configuration?.baseForegroundColor = .mobitColors(.accentPrimary)
  }
  
  func configure(
	alertType: AlertType,
	title: String?,
	content: String,
	callBack: ((Bool) -> ())?
  ) {
	self.callBack = callBack
	
	self.titleLabel.textAlignment = titleAlignment
	self.contentLabel.textAlignment = contentAlignment
	
	if alertType == .onlyConfirm {
	  self.cancelButton.isHidden = true
	  self.buttonDividerView.isHidden = true
	}
	
	if title == "" {
	  self.titleLabel.isHidden = true
	  self.dividerView.isHidden = true
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
	titleAlignment: NSTextAlignment = .left,
	title: String? = nil,
	contentAlignment: NSTextAlignment = .left,
	content: String,
	callBack: ((Bool) -> ())?
  ) {
	
	let mobitAlertViewController = MobitAlertViewController(
	  alertType: alertType,
	  titleAlignment: titleAlignment,
	  title: title ?? "",
	  contentAlignment: contentAlignment,
	  content: content,
	  callBack: callBack
	)
	mobitAlertViewController.delegate = self
	
	mobitAlertViewController.modalPresentationStyle = .overFullScreen
	mobitAlertViewController.modalTransitionStyle = .crossDissolve
	
	self.present(mobitAlertViewController, animated: true, completion: nil)
  }
}
