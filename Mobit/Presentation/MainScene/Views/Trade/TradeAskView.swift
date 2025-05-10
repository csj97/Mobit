//
//  TradeAskView.swift
//  Mobit
//
//  Created by 조성재 on 2/7/25.
//

import UIKit
import RxSwift

class TradeAskView: UIView, ViewRule {
  
  
  @IBOutlet var marketNameLabels: [UILabel]!
  @IBOutlet weak var availableCrypto: UILabel!
  @IBOutlet weak var availableTradePrice: UILabel!
  @IBOutlet weak var inputTradeAmount: UITextField!
  @IBOutlet weak var currentPrice: UILabel!
  @IBOutlet weak var totalPriceTextField: UITextField!
  @IBOutlet weak var inputAmountTFView: UIView!
  
  weak var reactor: CryptoDetailReactor? = nil
  var callBack: ((OrderResult) -> ())? = nil
  var disposeBag = DisposeBag()
  var cryptoInfo: CryptoCellInfo? = nil {
	didSet {
	  self.updateCryptoData()
	}
  }
  var availableCryptoCount: Double = 0.0
  // 매도 수량
  var inputAmount: Double = 0.0
  var askCryptoIndex: Int? = nil
  
  deinit {
	print("deinit : \(String(describing: type(of: self)))")
  }
  
  static func instanceFromNib(
	reactor: CryptoDetailReactor,
	disposeBag: DisposeBag,
	callBack: @escaping (OrderResult) -> ()
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
	selfView.callBack = callBack
	selfView.setUI()
	selfView.setData()
	selfView.bind(reactor: reactor)
	
	return selfView
  }
  
  func setUI() {
	let marketName = self.reactor?.selectCrypto.market.components(separatedBy: "/").first
	self.marketNameLabels.forEach({ $0.text = marketName })
	self.inputTradeAmount.keyboardType = .decimalPad
	self.totalPriceTextField.keyboardType = .decimalPad
  }
  
  func setData() {
	self.inputTradeAmount.delegate = self
	self.totalPriceTextField.delegate = self
	self.updateCryptoData()
  }
  
  func updateCryptoData() {
	guard let crypto = UserDataManager.userCryptoList?
	  .compactMap({ $0 })
	  .first(where: { $0.staticData.marketName == self.reactor?.selectCrypto.market }),
		  let currentPrice = self.cryptoInfo?.tradePrice
	else { return }
	
	let krwAvailablePrice = currentPrice * crypto.staticData.holdingQuantity
	self.availableCryptoCount = crypto.staticData.holdingQuantity
	self.availableCrypto.text = String(self.availableCryptoCount.formatSignificantDigits())
	self.availableTradePrice.text = "≈ " + String(krwAvailablePrice.formatSignificantDigits())
  }
  
  func updateCalcUtil(updateCrypto: CryptoCellInfo?) {
	guard let currentPrice = updateCrypto?.tradePrice else { return }
	
  }
  
  /// 최대 수량 버튼
  @IBAction func tapOnMaxAmount(_ sender: UIButton) {
	guard let availableCrypto = UserDataManager.userCryptoList?
			.compactMap({ $0 })
			.first(where: { $0.staticData.marketName == self.reactor?.selectCrypto.market })
	else { return }
	
	self.inputTradeAmount.text = String(availableCrypto.staticData.holdingQuantity.formatSignificantDigits())
	self.inputAmount = availableCrypto.staticData.holdingQuantity
	self.totalPriceTextField.text = String(availableCrypto.staticData.buyAmount.formatSignificantDigits())
  }
  
  @IBAction func tapOnAskButton(_ sender: UIButton) {
	guard let totalPrice = self.totalPriceTextField.text,
		  let doubleTotalPrice = Double(totalPrice.replacingOccurrences(of: ",", with: "")),
		  let currentPrice = self.cryptoInfo?.tradePrice?.formatDigits(digits: 8),
		  let crypto = UserDataManager.userCryptoList?.compactMap({ $0 }).first(
			where: { $0.staticData.marketName == self.reactor?.selectCrypto.market }
		  )
	else {
	  self.callBack?(.alert(title: "알림", message: "매도 수량을 확인 해주세요."))
	  return
	}
	
	let userCryptoList = UserDataManager.userCryptoList
	var postStaticTransaction: CryptoTransactionDataModel.CryptoTransactionStaticData? = nil
	var postDynamicTransaction: CryptoTransactionDataModel.CryptoTransactionDynamicData? = nil
	var transactionIndex: Int = 0
	
	if let matchedIndex = userCryptoList?.compactMap({ $0 }).firstIndex(
	  where: { $0.staticData.marketName == crypto.staticData.marketName }
	) {
	  postStaticTransaction = UserDataManager.userCryptoList?[matchedIndex].staticData
	  postDynamicTransaction = UserDataManager.userCryptoList?[matchedIndex].dynamicData
	  transactionIndex = matchedIndex
	}
  
	// 체결 내역은 말그대로 체결된 내역이 전부 보여야 한다.
	// 매수 내역은 현재 가지고 있는 매매 기록에 대해서만 나와야한다.
	if let postStaticTransaction = postStaticTransaction {
	  if inputAmount > 0, inputAmount <= crypto.staticData.holdingQuantity {
		let formatter = DateFormatter()
		formatter.dateFormat = "MM.dd HH:mm"
		formatter.locale = Locale(identifier: "ko_KR") // 한국 시간 기준
		let currentTime = Date()
		let executedDate = formatter.string(from: currentTime)
		
		self.callBack?(.alert(title: "알림", message: "매도 되었습니다."))
		
		let newTransaction: TransactionInfo = TransactionInfo(
		  marketName: crypto.staticData.marketName,
		  orderType: .ask,
		  executedDate: executedDate,
		  executedPrice: currentPrice,
		  executedQuantity: self.inputAmount,
		  executedAmount: currentPrice * self.inputAmount
		)
		
		print("팔기 전")
		print(crypto.dynamicData.evaluationProfitLoss)
		UserDataManager.userTransactionList?.append(newTransaction)
		
		if self.inputAmount < postStaticTransaction.holdingQuantity {
		  let newHoldingQuantity = postStaticTransaction.holdingQuantity - self.inputAmount
		  let newBuyAmount = newHoldingQuantity * postStaticTransaction.averageBuyPrice
		
		  let newCryptoStaticData = CryptoTransactionDataModel.CryptoTransactionStaticData(
			marketName: crypto.staticData.marketName,
			holdingQuantity: newHoldingQuantity,
			averageBuyPrice: postStaticTransaction.averageBuyPrice,
			buyAmount: newBuyAmount
		  )
		  
		  // 매도 후, 보유하고 있는 코인 매매정보 업데이트
		  MarketDataServiceUtil.shared.fetchData(
			data: newCryptoStaticData,
			currentPrice: currentPrice
		  )
		  
		  // 사용자 계좌 반영
		  print("-----------매도 후-------------")
		  print(crypto.dynamicData.evaluationProfitLoss)
//		  UserDataManager.userAvailableBalance += crypto.dynamicData.evaluationProfitLoss
		} else {
		  // 전량 매도
		  UserDataManager.userCryptoList?.remove(at: transactionIndex)
		}
		
		self.callBack?(.updateHistory)
		
	  } else {
		self.callBack?(.alert(title: "알림", message: "주문 수량을 재설정 해주세요."))
	  }
	}
  }
  
  func bind(reactor: CryptoDetailReactor) {
	// TODO: reactor에서 값이 변경될 때마다 UserDataManager에 새로 계산해서 업데이트 해주기
	reactor.state.map { $0.cryptoInfo }
	  .distinctUntilChanged()
	  .observe(on: MainScheduler.instance)
	  .subscribe(onNext: { [weak self] cellInfo in
		guard let self = self else { return }
		self.cryptoInfo = cellInfo
		self.currentPrice.text = cellInfo?.tradePrice?.formatSignificantDigits()
	  })
	  .disposed(by: self.disposeBag)
  }
}

extension TradeAskView: UITextFieldDelegate {
  func textFieldDidChangeSelection(_ textField: UITextField) {
	guard let currentPrice = self.cryptoInfo?.tradePrice else { return }
	
	if textField == self.inputTradeAmount {
	  self.inputAmount = Double(textField.text ?? "0")?.formatDigits(digits: 8) ?? 0
	  let totalPrice = floor(
		currentPrice.formatDigits(digits: 8) * inputAmount.formatDigits(digits: 8)
	  )
	  self.totalPriceTextField.text = totalPrice.formatSignificantDigits()
	} else if textField == self.totalPriceTextField {
	  let inputTotalPrice = Double(textField.text ?? "0")?.formatDigits(digits: 8) ?? 0
	  let quantity = Double(inputTotalPrice / currentPrice).formatSignificantDigits()
	  
	  self.inputTradeAmount.text = quantity.addComma()
	}
  }
}
