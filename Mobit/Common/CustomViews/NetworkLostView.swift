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
	// 공통 뷰는 화면 계층에 의존하지 않고 기존 언어 테이블을 직접 읽는다.
    let table = Locale.preferredLanguages.first?.hasPrefix("ko") == true ? "Localizable(KO)" : "Localizable(EN)"
    label.text = NSLocalizedString(
      "network_lost",
      tableName: table,
      bundle: .main,
      value: "network_lost",
      comment: ""
    )
	label.font = UIFont(name: "esamanruOTFMedium", size: 18)
	label.numberOfLines = 0
    label.adjustsFontForContentSizeCategory = true
    label.accessibilityIdentifier = "network.lost.message"
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
	  make.centerY.equalToSuperview().offset(-60)
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
