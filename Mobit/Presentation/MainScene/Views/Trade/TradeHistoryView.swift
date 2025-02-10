//
//  TradeHistoryView.swift
//  Mobit
//
//  Created by 조성재 on 2/9/25.
//

import UIKit
import RxSwift

class TradeHistoryView: UIView, ViewRule {
  
  @IBOutlet weak var segmentedControl: UISegmentedControl!
  @IBOutlet weak var segmentedContainerView: UIView!
  @IBOutlet weak var historyTableView: UITableView!
  
  var disposeBag = DisposeBag()
  var reactor: CryptoDetailReactor? = nil
  
  deinit {
	print("deinit : \(String(describing: type(of: self)))")
  }
  
  static func instanceFromNib(
	reactor: CryptoDetailReactor,
	result: @escaping () -> ()
  ) -> TradeHistoryView {
	
	let selfView = UINib(
	  nibName: String(describing: self),
	  bundle: nil
	).instantiate(
	  withOwner: self, options: nil
	).first as? TradeHistoryView
	
	guard let selfView = selfView else {
	  return TradeHistoryView()
	}
	
	selfView.reactor = reactor
	selfView.setUI()
	selfView.setData()
	
	return selfView
  }
  
  func setUI() {
	
  }
  
  func setData() {
//    self.historyTableView.delegate = self
  }
  
}

//extension TradeHistoryView: UITableViewDelegate, UITableViewDataSource {
//  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
//    if self.segmentedControl.selectedSegmentIndex == 0 {
//      return 0
//    } else {
//      return 0
//    }
//  }
//  
//  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
//    <#code#>
//  }
//  
//  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
//    <#code#>
//  }
//}
