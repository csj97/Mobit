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
  var callBack: (() -> ())? = nil
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
	callBack: @escaping () -> ()
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
	self.inputTradeAmount.keyboardType = .numberPad
	self.totalPriceTextField.keyboardType = .numberPad
//    self.inputAmountTFView.layer.borderWidth = 1
//	self.inputAmountTFView.layer.borderColor = UIColor.mobitColors(.lineLightGray).cgColor
  }
  
  func setData() {
	  guard let userBalance = UserDataManager.userInformation?.userAvailableBalance
	  else { return }
	  
	  self.availableTradePrice.text = userBalance.formatSignificantDigits()
  }
  
  @IBAction func tapOnMaxAmount(_ sender: UIButton) {
	guard let currentPrice = self.cryptoInfo?.tradePrice?.formatDigits(digits: 8),
		  let userBalance = UserDataManager.userInformation?.userAvailableBalance
	else { return }
	
	inputAmount = (userBalance / currentPrice)
	
	let calcUtil = CalculationUtils(currentPrice: currentPrice, newHoldingQuantity: inputAmount)
	let totalPrice = calcUtil.calcBuyAmount().formatDigits(digits: 0)
	self.inputTradeAmount.text = inputAmount.formatSignificantDigits()
	self.totalPriceTextField.text = String(totalPrice)
  }
  
  @IBAction func tapOnBidButton(_ sender: UIButton) {
	guard let marketName = self.cryptoInfo?.market else { return }
	self.updateTransaction(marketName: marketName)
  }
  
  func updateTransaction(marketName: String) {
	
	guard let currentPrice = self.cryptoInfo?.tradePrice?.formatDigits(digits: 8),
		  let userBalance = UserDataManager.userInformation?.userAvailableBalance
	else { return }
	
	let formatter = DateFormatter()
	formatter.dateFormat = "MM.dd HH:mm"
	formatter.locale = Locale(identifier: "ko_KR") // 한국 시간 기준
	let currentTime = Date()
	let executedDate = formatter.string(from: currentTime)
	
	var bidCryptoList = UserDataManager.bidCryptoList
	var newTransaction: CryptoTransaction? = nil
	var postTransaction: CryptoTransaction? = nil
	var transactionList: [CryptoTransaction.TransactionInfo?] = []
	var transactionIndex: Int = 0
	
	if let matchedIndex = UserDataManager.bidCryptoList
	  .compactMap({ $0 })
	  .firstIndex(where: { $0.marketName == marketName }) {
	  transactionList = UserDataManager.bidCryptoList[matchedIndex]?.transactionHistoryList ?? []
	  postTransaction = UserDataManager.bidCryptoList[matchedIndex]
	  transactionIndex = matchedIndex
	}
	
	// 체결 내역은 말그대로 체결된 내역이 전부 보여야 한다.
	// 매수 내역은 현재 가지고 있는 매매 기록에 대해서만 나와야한다.
	if let postTransaction = postTransaction {
	  let calcUtil = CalculationUtils(
		currentPrice: currentPrice.formatDigits(digits: 8),
		prevHoldingQuantity: postTransaction.holdingQuantity,
		prevAverageBuyPrice: postTransaction.averageBuyPrice,
		prevBuyAmount: postTransaction.buyAmount,
		newHoldingQuantity: self.inputAmount
	  )
	  
	  let averageBuyPrice = calcUtil.calcAverBuyPrice()
	  let profitRate = calcUtil.calcProfitRate()
	  let evaluationProfitLoss = calcUtil.calcEvalProfitLoss()
	  let evaluationPrice = calcUtil.calcEvalPrice()
	  let buyAmount = calcUtil.calcBuyAmount()
	  let holdingQuantity = calcUtil.calcHoldingQuantity()
	  let newTransactionInfo = CryptoTransaction.TransactionInfo(
		executedDate: executedDate,
		executedPrice: currentPrice,
		executedQuantity: self.inputAmount,
		executedAmount: buyAmount
	  )
	  transactionList.append(newTransactionInfo)
	  
	  newTransaction = CryptoTransaction(
		marketName: marketName,
		holdingQuantity: holdingQuantity,
		profitRate: profitRate,
		evaluationProfitLoss: evaluationProfitLoss,
		evaluationPrice: evaluationPrice,
		averageBuyPrice: averageBuyPrice,
		buyAmount: buyAmount,
		transactionHistoryList: transactionList
	  )
	  
	  guard let newTransaction = newTransaction else { return }
	  print("매수 업데이트 완료!!")
	  bidCryptoList[transactionIndex] = newTransaction
	  UserDataManager.bidCryptoList = bidCryptoList

	  let availableBalance = userBalance - newTransaction.buyAmount
	  updateUserInformation(availableBalance: availableBalance)
	} else {
	  
	  let calcUtil = CalculationUtils(
		currentPrice: currentPrice,
		newHoldingQuantity: self.inputAmount
	  )
	  
	  // 이전 매수 기록 없음
	  let averageBuyPrice = calcUtil.calcAverBuyPrice()
	  let profitRate = calcUtil.calcProfitRate()
	  let evaluationProfitLoss = calcUtil.calcEvalProfitLoss()
	  let evaluationPrice = calcUtil.calcEvalPrice()
	  let buyAmount = calcUtil.calcBuyAmount()
	  let holdingQuantity = calcUtil.calcHoldingQuantity()
	  
	  let newTransactionInfo = CryptoTransaction.TransactionInfo(
		executedDate: executedDate,
		executedPrice: currentPrice,
		executedQuantity: holdingQuantity,
		executedAmount: buyAmount
	  )
	  
	  transactionList.append(newTransactionInfo)
	  
	  newTransaction = CryptoTransaction(
		marketName: marketName,
		holdingQuantity: holdingQuantity,
		profitRate: profitRate,
		evaluationProfitLoss: evaluationProfitLoss,
		evaluationPrice: evaluationPrice,
		averageBuyPrice: averageBuyPrice,
		buyAmount: buyAmount,
		transactionHistoryList: transactionList
	  )
	  
	  guard let newTransaction = newTransaction else { return }
	  print("첫 매수 완료!!")
	  
	  bidCryptoList.append(newTransaction)
	  UserDataManager.bidCryptoList = bidCryptoList
	  
	  let availableBalance = userBalance - newTransaction.buyAmount
	  updateUserInformation(availableBalance: availableBalance)
	}
	
	self.callBack?()
  }
  
  func updateUserInformation(availableBalance: Double) {
	UserDataManager.userInformation = MobitUserInformation(
	  userAvailableBalance: availableBalance
	)
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
	guard let currentPrice = self.cryptoInfo?.tradePrice,
		  let userBalance = UserDataManager.userInformation?.userAvailableBalance
	else { return }
	
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

extension Double {
  /// 자릿수 끊어내기
  func formatDigits(digits: Int) -> Double {
	let digitStandard = Double(Int(pow(10.0, Double(digits))))
	let formattedValue = floor(self * digitStandard) / digitStandard
	return formattedValue
  }
  
  func formatSignificantDigits() -> String {
	// 1. 최대 소수점 8자리까지만 유지 (반올림 없이 자르기)
	let formattedValue = floor(self * 100_000_000) / 100_000_000
	
	// 2. 소수점 포함 숫자를 문자열로 변환
	var formattedString = String(format: "%.\(8)f", formattedValue)
	
	// 3. 불필요한 소수점 이하 0 제거
	while formattedString.last == "0" {
	  formattedString.removeLast()
	}
	if formattedString.last == "." {
	  formattedString.removeLast()
	}
	
	// 4. 콤마 추가 (소수점 앞부분만)
	if let dotIndex = formattedString.firstIndex(of: ".") {
	  let integerPart = formattedString[..<dotIndex]
	  let decimalPart = formattedString[dotIndex...]
	  let formattedInteger = integerPart.replacingOccurrences(
		of: "(?<=\\d)(?=(\\d{3})+(?!\\d))",
		with: ",",
		options: .regularExpression
	  )
	  return formattedInteger + decimalPart
	  
	} else {
	  
	  return formattedString.replacingOccurrences(
		of: "(?<=\\d)(?=(\\d{3})+(?!\\d))",
		with: ",",
		options: .regularExpression
	  )
	}
  }
}
