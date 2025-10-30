//
//  MobitLaunchScreen.swift
//  Mobit
//
//  Created by 조성재 on 6/8/25.
//

import Foundation
import UIKit

class MobitLaunchScreen: UIViewController {
  
  @IBOutlet weak var label1: UILabel!
  @IBOutlet weak var label2: UILabel!
  @IBOutlet weak var mobitNameLabel: UILabel!
  @IBOutlet weak var label3: UILabel!
  @IBOutlet weak var label4: UILabel!
  
  override func viewDidLoad() {
	super.viewDidLoad()
//	for family in UIFont.familyNames {
//	  print(">> \(family)")
//	  for name in UIFont.fontNames(forFamilyName: family) {
//		print("   - \(name)")
//	  }
//	}
	mobitNameLabel.font = UIFont(name: "Partial-Sans-KR", size: 25)
	label1.font = UIFont(name: "esamanruOTFMedium", size: 18)
	label2.font = UIFont(name: "esamanruOTFLight", size: 16)
	label3.font = UIFont(name: "esamanruOTFLight", size: 16)
	label4.font = UIFont(name: "esamanruOTFLight", size: 14)
  }
}
