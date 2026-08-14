//
//  MobitTextField.swift
//  Mobit
//
//  Created by 조성재 on 3/3/25.
//

import Foundation
import UIKit

class MobitTextField: UITextField {
  private let bottomLine = CALayer()
  
  override init(frame: CGRect) {
	super.init(frame: frame)
	setupTextField()
  }
  
  required init?(coder: NSCoder) {
	super.init(coder: coder)
	setupTextField()
  }
  
  private func setupTextField() {
	// 기본 스타일 설정
	borderStyle = .none
	
	addBottomBorder()
	addDoneButtonOnKeyboard()
  }
  
  private func addBottomBorder() {
	bottomLine.backgroundColor = UIColor.mobitColors(.borderPrimary).cgColor
	layer.addSublayer(bottomLine)
  }
  
  override func layoutSubviews() {
	super.layoutSubviews()
	bottomLine.frame = CGRect(
	  x: 0, y: bounds.height - 4,
	  width: bounds.width, height: 1
	)
  }
  
  private func addDoneButtonOnKeyboard() {
	let toolbar = UIToolbar()
	toolbar.sizeToFit()
	
	let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
	let doneButton = UIBarButtonItem(title: "완료", style: .plain, target: self, action: #selector(dismissKeyboard))
	
	toolbar.setItems([flexSpace, doneButton], animated: false)
	inputAccessoryView = toolbar
  }
  
  @objc private func dismissKeyboard() {
	resignFirstResponder()
  }
}
