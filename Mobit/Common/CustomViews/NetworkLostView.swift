//
//  NetworkLostView.swift
//  Mobit
//
//  Created by 조성재 on 10/29/25.
//

import Foundation
import UIKit
import Then

class NetworkLostView: UIView {
  let imageView = UIImageView().then { imageView in
	imageView.image = UIImage(systemName: "wifi.exclamationmark")
	imageView.tintColor = .mobitColors(.textSecondary)
  }
  
  let label = UILabel().then { label in
	label.text = "네트워크가 유실되었습니다.\n네트워크 연결 후 다시 시도해 주세요."
	label.font = UIFont(name: "esamanruOTFMedium", size: 18)
	label.textAlignment = .center
	label.textColor = .mobitColors(.textSecondary)
  }
  
  let view = UIView().then { view in
	view.backgroundColor = .mobitColors(.backgroundPrimary)
  }
  
  
  deinit {
	  print("deinit : " + String(describing: type(of: self)))
  }
  
  init() {
	super.init(frame: .zero)
  }
  
  required init?(coder: NSCoder) {
	fatalError("init(coder:) has not been implemented")
  }
  
  func configure() {
	self.addSubview(view)
	view.addSubview(imageView)
	view.addSubview(label)
	
	view.snp.makeConstraints { make in
	  make.edges.equalToSuperview()
	}
	
	imageView.snp.makeConstraints { make in
	  make.top.equalToSuperview().offset(300)
	  make.centerX.equalToSuperview()
	  make.width.equalTo(100)
	  make.height.equalTo(100)
	}
	
	label.snp.makeConstraints { make in
	  make.top.equalTo(imageView.snp.bottom).offset(40)
	  make.leading.equalToSuperview().offset(36)
	  make.trailing.equalToSuperview().offset(-36)
	}
  }
  
}
