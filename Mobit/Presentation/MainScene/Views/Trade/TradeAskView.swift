//
//  TradeAskView.swift
//  Mobit
//
//  Created by 조성재 on 2/7/25.
//

import UIKit
import RxSwift

class TradeAskView: UIView, ViewRule {
  
  @IBOutlet weak var availableTradePrice: UILabel!
  @IBOutlet weak var inputTradeAmount: UITextField!
  @IBOutlet weak var currentPrice: UILabel!
  @IBOutlet weak var totalPriceTextField: UITextField!
  @IBOutlet weak var inputAmountTFView: UIView!
  
  var disposeBag = DisposeBag()
  weak var reactor: CryptoDetailReactor? = nil
  
  deinit {
	print("deinit : \(String(describing: type(of: self)))")
  }
  
  static func instanceFromNib(
	reactor: CryptoDetailReactor,
	disposeBag: DisposeBag,
	result: @escaping () -> ()
  ) ->  TradeAskView {
	
	let selfView = UINib(
	  nibName: String(describing: self),
	  bundle: nil
	).instantiate(
	  withOwner: self, options: nil
	).first as? TradeAskView
	
	guard let selfView = selfView else {
	  return TradeAskView()
	}
	
	selfView.reactor = reactor
	selfView.disposeBag = disposeBag
	selfView.setUI()
	selfView.setData()
	
	return selfView
  }
  
  func setUI() {
	
  }
  
  func setData() {
	
  }
  
  /// 최대 수량 버튼
  @IBAction func tapOnMaxAmount(_ sender: UIButton) {
  }
  
  @IBAction func tapOnAskButton(_ sender: UIButton) {
  }
  
}
