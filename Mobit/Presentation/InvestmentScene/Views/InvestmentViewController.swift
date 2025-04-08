//
//  InvestmentViewController.swift
//  Mobit
//
//  Created by 조성재 on 4/8/25.
//

import FlexLayout
import RxCocoa
import RxSwift
import PinLayout
import ReactorKit
import UIKit

class InvestmentViewController: UIViewController {
  @IBOutlet weak var label1: UILabel!
  @IBOutlet weak var label2: UILabel!
  @IBOutlet weak var label3: UILabel!
  
  weak var coordinator: InvestmentCoordinator?
  var disposeBag = DisposeBag()
  var reactor: InvestReactor
  
  init(reactor: InvestReactor) {
	self.reactor = reactor
	super.init(nibName: nil, bundle: nil)
  }
  
  required init?(coder: NSCoder) {
	fatalError("init(coder:) has not been implemented")
  }
  
  override func viewDidLoad() {
	super.viewDidLoad()
//	self.view.backgroundColor = .yellow
	self.bind(reactor: self.reactor)
	self.reactor.action.onNext(.loadTransactions)
  }
  
  override func viewDidLayoutSubviews() {
	super.viewDidLayoutSubviews()
  }
  
  func updateLabels(crypto: CryptoTransactionDataModel) {
	self.label1.text = "\(crypto.dynamicData.profitRate)"
	self.label2.text = "\(crypto.dynamicData.evaluationPrice)"
	self.label3.text = "\(crypto.dynamicData.evaluationProfitLoss)"
  }
}

// MARK: Reactor - View
extension InvestmentViewController: View {
  func bind(reactor: InvestReactor) {
	reactor.state.map { $0.crypto }
	  .compactMap { $0 }
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { crypto in
		guard let crypto = crypto.first else { return }
		self.updateLabels(crypto: crypto)
		print(crypto)
	  })
	  .disposed(by: self.disposeBag)
  }
}
