//
//  TradeBidView.swift
//  Mobit
//
//  Created by 조성재 on 2/7/25.
//

import UIKit
import RxSwift

class TradeBidView: UIView, ViewRule {
  
  @IBOutlet weak var availableTradePrice: UILabel!
  @IBOutlet weak var inputTradeAmount: UITextField!
  @IBOutlet weak var currentPrice: UILabel!
  @IBOutlet weak var totalPriceTextField: UITextField!
  @IBOutlet weak var inputAmountTFView: UIView!
  @IBOutlet weak var inputMarketName: UILabel!
  
  weak var reactor: CryptoDetailReactor? = nil
  var callBack: ((OrderResult) -> ())? = nil
  var disposeBag = DisposeBag()
  var cryptoInfo: CryptoCellInfo? = nil
  // 매수 수량
  var inputAmount: Double = 0.0
  
  deinit {
	print("deinit : \(String(describing: type(of: self)))")
  }
  
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
	print(#function)
  }
  
  static func instanceFromNib(
	reactor: CryptoDetailReactor,
	disposeBag: DisposeBag,
	callBack: @escaping (OrderResult) -> ()
  ) -> TradeBidView {
	
	let selfView = UINib(
	  nibName: String(describing: self),
	  bundle: nil
	).instantiate(
	  withOwner: self, options: nil
	).first as? TradeBidView
	
	guard let selfView = selfView else {
	  return TradeBidView()
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
	self.inputMarketName.text = self.reactor?.selectCrypto.market.components(separatedBy: "/").first
	self.inputTradeAmount.keyboardType = .decimalPad
	self.totalPriceTextField.keyboardType = .decimalPad
  }
  
  func setData() {
	self.inputTradeAmount.delegate = self
	self.totalPriceTextField.delegate = self
	
	guard let userBalance = UserDataManager.userInformation?.userAvailableBalance
	else { return }
	
	self.availableTradePrice.text = userBalance.formatSignificantDigits()
  }
  
  @IBAction func tapOnMaxAmount(_ sender: UIButton) {
	guard let currentPrice = self.cryptoInfo?.tradePrice?.formatDigits(digits: 8),
		  let userBalance = UserDataManager.userInformation?.userAvailableBalance
	else { return }
	
	inputAmount = (userBalance / currentPrice)
	
	let calcUtil = CalculationUtil(currentPrice: currentPrice, newHoldingQuantity: inputAmount)
	let totalPrice = calcUtil.calcBuyAmount().formatSignificantDigits()
	self.inputTradeAmount.text = inputAmount.formatSignificantDigits()
	self.totalPriceTextField.text = String(totalPrice)
  }
  
  @IBAction func tapOnBidButton(_ sender: UIButton) {
	guard let marketName = self.cryptoInfo?.market,
		  let userBalance = UserDataManager.userInformation?.userAvailableBalance,
		  let totalPrice = self.totalPriceTextField.text,
		  let doubleTotalPrice = Double(totalPrice.replacingOccurrences(
			of: ",", with: ""
		  ))
	else {
	  callBack?(.alert(title: "알림", message: "매수 금액을 입력해주세요"))
	  return
	}
	
	if doubleTotalPrice > 0.0, userBalance > doubleTotalPrice {
	  self.updateTransaction(marketName: marketName) {
		self.initTextFieldValue()
		self.callBack?(.alert(title: "알림", message: "매수 되었습니다."))
		self.callBack?(.updateHistory)
	  }
	} else {
	  callBack?(.alert(title: "알림", message: "매수 금액을 확인해 주세요"))
	}
  }
  
  func updateTransaction(marketName: String, completion: @escaping () -> ()) {
	
	guard let currentPrice = self.cryptoInfo?.tradePrice?.formatDigits(digits: 8),
		  let userBalance = UserDataManager.userInformation?.userAvailableBalance
	else { return }
	
	let formatter = DateFormatter()
	formatter.dateFormat = "MM.dd HH:mm"
	formatter.locale = Locale(identifier: "ko_KR") // 한국 시간 기준
	let currentTime = Date()
	let executedDate = formatter.string(from: currentTime)
	
	var availableBalance: Double = userBalance
	var userCryptoList = UserDataManager.userCryptoList
	var newStaticTransaction: CryptoTransactionDataModel.CryptoTransactionStaticData? = nil
	var postStaticTransaction: CryptoTransactionDataModel.CryptoTransactionStaticData? = nil
	var newDynamicTransaction: CryptoTransactionDataModel.CryptoTransactionDynamicData? = nil
	var transactionList: [CryptoTransactionDataModel.CryptoTransactionStaticData.TransactionInfo] = []
	var transactionIndex: Int = 0
	
	if let matchedIndex = userCryptoList?.compactMap({ $0 })
	  .firstIndex(where: { $0.staticData.marketName == marketName }) {
	  transactionList = UserDataManager.userCryptoList?[matchedIndex].staticData.transactionHistoryList ?? []
	  postStaticTransaction = UserDataManager.userCryptoList?[matchedIndex].staticData
	  transactionIndex = matchedIndex
	}
	
	// 체결 내역은 말그대로 체결된 내역이 전부 보여야 한다.
	// 매수 내역은 현재 가지고 있는 매매 기록에 대해서만 나와야한다.
	if let postStaticTransaction = postStaticTransaction {
	  let calcUtil = CalculationUtil(
		currentPrice: currentPrice.formatDigits(digits: 8),
		prevHoldingQuantity: postStaticTransaction.holdingQuantity,
		prevAverageBuyPrice: postStaticTransaction.averageBuyPrice,
		prevBuyAmount: postStaticTransaction.buyAmount,
		newHoldingQuantity: self.inputAmount
	  )
	  
	  let averageBuyPrice = calcUtil.calcAverBuyPrice()
	  let currentBuyAmount = calcUtil.calcBuyAmount()
	  let cumulBuyAmount = calcUtil.cumulCalcBuyAmount()
	  let holdingQuantity = calcUtil.calcHoldingQuantity()
	  
//	  let profitRate = MarketDataServiceUtil.shared.fetchProfitRate(
//		for: marketName,
//		currentPrice: currentPrice,
//		averageBuyPrice: averageBuyPrice
//	  )
//	  let evaluationProfitLoss = MarketDataServiceUtil.shared.fetchEvalProfitLoss(
//		for: marketName,
//		currentPrice: currentPrice,
//		newHoldingQuantity: self.inputAmount,
//		averageBuyPrice: averageBuyPrice,
//		tradingFee: calcUtil.calcTradingFee(tradingPrice: currentPrice)	// tradingFee 평가손익에서 어떻게 처리할지 다시 생각해봐야할듯
//	  )
//	  let evaluationPrice = MarketDataServiceUtil.shared.fetchEvalPrice(
//		for: marketName,
//		currentPrice: currentPrice,
//		cumulHoldingQuantity: holdingQuantity
//	  )
//	  
//	  newDynamicTransaction = CryptoTransactionDataModel.CryptoTransactionDynamicData(
//		marketName: marketName,
//		profitRate: profitRate,
//		evaluationProfitLoss: evaluationProfitLoss,
//		evaluationPrice: evaluationPrice
//	  )
	  
	  let newTransactionInfo = CryptoTransactionDataModel.CryptoTransactionStaticData.TransactionInfo(
		executedDate: executedDate,
		executedPrice: currentPrice,
		executedQuantity: self.inputAmount,
		executedAmount: currentBuyAmount
	  )
	  transactionList.append(newTransactionInfo)
	  
	  newStaticTransaction = CryptoTransactionDataModel.CryptoTransactionStaticData(
		marketName: marketName,
		holdingQuantity: holdingQuantity,
		averageBuyPrice: averageBuyPrice,
		buyAmount: cumulBuyAmount,
		transactionHistoryList: transactionList
	  )
	  
	  guard let newStaticTransaction = newStaticTransaction else { return }
	  print("매수 업데이트 완료!!")
	  userCryptoList?[transactionIndex].staticData = newStaticTransaction
//	  userCryptoList?[transactionIndex].dynamicData = newDynamicTransaction
	  UserDataManager.userCryptoList = userCryptoList
	  
	  availableBalance = userBalance - newStaticTransaction.buyAmount
	} else {
	  
	  let calcUtil = CalculationUtil(
		currentPrice: currentPrice,
		newHoldingQuantity: self.inputAmount
	  )
	  
	  // 이전 매수 기록 없음
	  let averageBuyPrice = calcUtil.calcAverBuyPrice()
	  let buyAmount = calcUtil.calcBuyAmount()
	  let holdingQuantity = calcUtil.calcHoldingQuantity()
	  let profitRate = MarketDataServiceUtil.shared.fetchProfitRate(
		for: marketName,
		currentPrice: currentPrice,
		averageBuyPrice: averageBuyPrice
	  )
	  let evaluationProfitLoss = MarketDataServiceUtil.shared.fetchEvalProfitLoss(
		for: marketName,
		currentPrice: currentPrice,
		cumulHoldingQuantity: self.inputAmount,
		averageBuyPrice: averageBuyPrice
	  )
	  let evaluationPrice = MarketDataServiceUtil.shared.fetchEvalPrice(
		for: marketName,
		currentPrice: currentPrice,
		cumulHoldingQuantity: holdingQuantity
	  )
	  
	  newDynamicTransaction = CryptoTransactionDataModel.CryptoTransactionDynamicData(
		marketName: marketName,
		profitRate: profitRate,
		evaluationProfitLoss: evaluationProfitLoss,
		evaluationPrice: evaluationPrice
	  )
	  
	  let newTransactionInfo = CryptoTransactionDataModel.CryptoTransactionStaticData.TransactionInfo(
		executedDate: executedDate,
		executedPrice: currentPrice,
		executedQuantity: self.inputAmount,
		executedAmount: buyAmount
	  )
	  
	  transactionList.append(newTransactionInfo)
	  
	  newStaticTransaction = CryptoTransactionDataModel.CryptoTransactionStaticData(
		marketName: marketName,
		holdingQuantity: holdingQuantity,
		averageBuyPrice: averageBuyPrice,
		buyAmount: buyAmount,
		transactionHistoryList: transactionList
	  )
	  
	  guard let newStaticTransaction = newStaticTransaction,
			let newDynamicTransaction = newDynamicTransaction else { return }
	  print("첫 매수 완료!!")
	  userCryptoList?.append(
		CryptoTransactionDataModel(
		  staticData: newStaticTransaction,
		  dynamicData: newDynamicTransaction
		)
	  )
	  UserDataManager.userCryptoList = userCryptoList
	  
	  availableBalance = userBalance - newStaticTransaction.buyAmount
	}
	
	self.availableTradePrice.text = availableBalance.formatSignificantDigits()
	updateUserInformation(availableBalance: availableBalance)
	
	completion()
  }
  
  func updateUserInformation(availableBalance: Double) {
	UserDataManager.userInformation = MobitUserInformation(
	  userAvailableBalance: availableBalance
	)
  }
  
  func initTextFieldValue() {
	self.inputTradeAmount.text = nil
	self.totalPriceTextField.text = nil
  }
  
  func bind(reactor: CryptoDetailReactor) {
	
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

extension TradeBidView: UITextFieldDelegate {
  func textFieldDidChangeSelection(_ textField: UITextField) {
	// TODO: 수량 및 총액 입력시, 같이 수정 되어야 함.
	guard let currentPrice = self.cryptoInfo?.tradePrice else { return }
	
	if textField == self.inputTradeAmount {
	  self.inputAmount = Double(textField.text ?? "0") ?? 0
	  let totalPrice = floor(
		currentPrice.formatDigits(digits: 8) * inputAmount.formatDigits(digits: 8)
	  )
	  self.totalPriceTextField.text = totalPrice.formatSignificantDigits()
	} else if textField == self.totalPriceTextField {
	  
	}
  }
}
