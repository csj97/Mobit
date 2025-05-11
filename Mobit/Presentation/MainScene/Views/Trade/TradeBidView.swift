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
	var postStaticTransaction: CryptoTransactionDataModel.CryptoTransactionStaticData? = nil
	
	if let matchedIndex = UserDataManager.userCryptoList?.compactMap({ $0 })
	  .firstIndex(where: { $0.staticData.marketName == marketName }) {
	  postStaticTransaction = UserDataManager.userCryptoList?[matchedIndex].staticData
	}
	
	// 체결 내역은 말그대로 체결된 내역이 전부 보여야 한다.
	// 매수 내역은 현재 가지고 있는 매매 기록에 대해서만 나와야한다.
	if let postStaticTransaction = postStaticTransaction {
	  
	  // *****기존 매수 내역이 있는 상태*****
	  let calcUtil = CalculationUtil(
		currentPrice: currentPrice.formatDigits(digits: 8),
		prevHoldingQuantity: postStaticTransaction.holdingQuantity,
		prevAverageBuyPrice: postStaticTransaction.averageBuyPrice,
		prevBuyAmount: postStaticTransaction.buyAmount,
		newHoldingQuantity: self.inputAmount
	  )
	  
	  // 새 매수 거래내역
	  let newTransactionInfo = TransactionInfo(
		marketName: marketName,
		orderType: .bid,
		executedDate: executedDate,
		executedPrice: currentPrice,
		executedQuantity: self.inputAmount,
		executedAmount: currentPrice * self.inputAmount
	  )
	  
	  // 기존 매수 내역의 (평균매수가, 매수금액, 보유수량)
	  let averageBuyPrice = calcUtil.calcAverBuyPrice()
	  let buyAmount = calcUtil.calcBuyAmount()
	  let holdingQuantity = calcUtil.calcHoldingQuantity()
	  let newBuyAmount = floor(currentPrice * self.inputAmount)
	  
	  // 새 정적 데이터
	  let newCryptoStaticData = CryptoTransactionDataModel.CryptoTransactionStaticData(
		marketName: marketName,
		holdingQuantity: holdingQuantity,
		averageBuyPrice: averageBuyPrice,
		buyAmount: buyAmount
	  )
	  
	  // 새 매수 거래내역 추가
	  MarketDataServiceUtil.shared.addTransactionData(
		postTransactionList: UserDataManager.userTransactionList,
		data: newTransactionInfo
	  )
	  
	  // 새 데이터 업데이트
	  MarketDataServiceUtil.shared.fetchData(
		data: newCryptoStaticData,
		currentPrice: currentPrice
	  )
	  
	  // 사용자 거래 가능 금액 업데이트
	  MarketDataServiceUtil.shared.fetchUserAvailableBalance(
		orderType: .bid,
		balance: availableBalance,
		newBuyAmount: newBuyAmount
	  )
	  
	  availableBalance -= newBuyAmount
	  
	} else {
	  // *****이전 매수 기록 없음*****
	  let averageBuyPrice = currentPrice
	  let buyAmount = floor(currentPrice * self.inputAmount)
	  let holdingQuantity = self.inputAmount
	  
	  let newTransactionInfo = TransactionInfo(
		marketName: marketName,
		orderType: .bid,
		executedDate: executedDate,
		executedPrice: currentPrice,
		executedQuantity: holdingQuantity,
		executedAmount: buyAmount
	  )
	  
	  let newCryptoStaticData = CryptoTransactionDataModel.CryptoTransactionStaticData(
		marketName: marketName,
		holdingQuantity: holdingQuantity,
		averageBuyPrice: averageBuyPrice,
		buyAmount: buyAmount
	  )
	  
	  // 새 거래내역 추가
	  MarketDataServiceUtil.shared.addTransactionData(
		postTransactionList: UserDataManager.userTransactionList,
		data: newTransactionInfo
	  )
	  
	  // 이전 매매기록 없는 상황에서, 첫 데이터 등록
	  MarketDataServiceUtil.shared.addCryptoFirstData(
		for: marketName,
		staticData: newCryptoStaticData,
		currentPrice: currentPrice
	  )
	  
	  // 사용자 거래 가능 금액 업데이트
	  MarketDataServiceUtil.shared.fetchUserAvailableBalance(
		orderType: .bid,
		balance: availableBalance,
		newBuyAmount: buyAmount
	  )
	  
	  availableBalance -= buyAmount
	}
	
	self.availableTradePrice.text = availableBalance.formatSignificantDigits()
	
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
