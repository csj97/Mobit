//
//  NoticeForceUpdateViewControlelrViewController.swift
//  Mobit
//
//  Created by 조성재 on 7/6/25.
//

import UIKit

class NoticeForceUpdateViewControlelrViewController: UIViewController {
  
  weak var coordinator: NoticeAppUpdateCoordinator?
  weak var delegate: MainCoordinatorDelegate?
  
  override func viewWillAppear(_ animated: Bool) {
	super.viewWillAppear(animated)
  }
  
  override func viewDidLoad() {
	super.viewDidLoad()
  }
  
  /// 앱 업데이트 버튼 클릭 시, 앱스토어 화면으로 이동
  @IBAction func tapOnUpdateButton(_ sender: UIButton) {
	// 모의비트 앱스토어 링크
	if let url = URL(string: "https://apps.apple.com/app/id6747009759") {
	  UIApplication.shared.open(url)
	}
  }
  
}
