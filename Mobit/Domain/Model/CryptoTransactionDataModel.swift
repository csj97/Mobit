//
//  BidCryptoInfo.swift
//  Mobit
//
//  Created by 조성재 on 2/19/25.
//

import Foundation

enum TradeTimestampFormatter {
  static func timestamp(from date: Date) -> Int64 {
    return Int64((date.timeIntervalSince1970 * 1000).rounded())
  }

  static func displayString(from timestamp: Int64) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy.MM.dd HH:mm"
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000))
  }
}

struct LegacyModel: Codable {
  let staticData: LegacyStatic
  let dynamicData: LegacyDynamic
}

struct LegacyStatic: Codable {
  let marketName: String
  let cryptoName: String?
  let holdingQuantity: Double
  let averageBuyPrice: Double
  let buyAmount: Double
}

struct LegacyDynamic: Codable {
  let marketName: String
  let profitRate: Double
  let evaluationProfitLoss: Double
  let evaluationPrice: Double
}

struct CryptoTransactionDataModel: Codable, Equatable, Hashable {
  var identifier: UUID = UUID()
  var staticData: CryptoTransactionStaticData
  var dynamicData: CryptoTransactionDynamicData

  enum CodingKeys: String, CodingKey {
    case identifier, staticData, dynamicData
  }

  init(
    identifier: UUID = UUID(),
    staticData: CryptoTransactionStaticData,
    dynamicData: CryptoTransactionDynamicData
  ) {
    self.identifier = identifier
    self.staticData = staticData
    self.dynamicData = dynamicData
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.identifier = try container.decodeIfPresent(UUID.self, forKey: .identifier) ?? UUID()
    self.staticData = try container.decode(CryptoTransactionStaticData.self, forKey: .staticData)
    self.dynamicData = try container.decode(CryptoTransactionDynamicData.self, forKey: .dynamicData)
  }
  
  /// 거래 정보 (정적)
  struct CryptoTransactionStaticData: Codable, Equatable, Hashable {
	var identifier: UUID = UUID()
	var exchange: Exchange = .upbit
	let marketName: String          // 코인 마켓 이름 (예: "BTC-USDT")
	var cryptoName: String?		 // 코인 이름 (예: "비트코인")
	var holdingQuantity: Double     // 보유 수량
	var averageBuyPrice: Double     // 매수 평균가
	var buyAmount: Double           // 매수 총액
    var costBasisKRW: Decimal? = nil
	
	enum CodingKeys: String, CodingKey {
		case exchange, marketName, cryptoName, holdingQuantity, averageBuyPrice, buyAmount, costBasisKRW
	}

	init(
	  exchange: Exchange = .upbit,
	  identifier: UUID = UUID(),
	  marketName: String,
	  cryptoName: String?,
	  holdingQuantity: Double,
	  averageBuyPrice: Double,
	  buyAmount: Double,
    costBasisKRW: Decimal? = nil
	) {
	  self.exchange = exchange
	  self.identifier = identifier
	  self.marketName = marketName
	  self.cryptoName = cryptoName
	  self.holdingQuantity = holdingQuantity
	  self.averageBuyPrice = averageBuyPrice
	  self.buyAmount = buyAmount
      self.costBasisKRW = costBasisKRW
	}

	init(from decoder: Decoder) throws {
	  let container = try decoder.container(keyedBy: CodingKeys.self)
	  self.exchange = try container.decodeIfPresent(Exchange.self, forKey: .exchange) ?? .upbit
	  self.marketName = try container.decode(String.self, forKey: .marketName)
	  self.cryptoName = try container.decodeIfPresent(String.self, forKey: .cryptoName)
	  self.holdingQuantity = try container.decode(Double.self, forKey: .holdingQuantity)
	  self.averageBuyPrice = try container.decode(Double.self, forKey: .averageBuyPrice)
	  self.buyAmount = try container.decode(Double.self, forKey: .buyAmount)
      self.costBasisKRW = try container.decodeIfPresent(Decimal.self, forKey: .costBasisKRW)
	}
  }

  /// 거래 정보 (동적) - 실시간성 업데이트
  struct CryptoTransactionDynamicData: Codable, Equatable, Hashable {
	var identifier: UUID = UUID()
	var exchange: Exchange = .upbit
	let marketName: String
	var profitRate: Double          // 수익률
	var evaluationProfitLoss: Double // 평가손익 (얼마 손해, 이익 중인지)
	var evaluationPrice: Double     // 평가금액	(지금 얼마인지)

	enum CodingKeys: String, CodingKey {
	  case identifier, exchange, marketName, profitRate, evaluationProfitLoss, evaluationPrice
	}

	init(
	  exchange: Exchange = .upbit,
	  identifier: UUID = UUID(),
	  marketName: String,
	  profitRate: Double,
	  evaluationProfitLoss: Double,
	  evaluationPrice: Double
	) {
	  self.exchange = exchange
	  self.identifier = identifier
	  self.marketName = marketName
	  self.profitRate = profitRate
	  self.evaluationProfitLoss = evaluationProfitLoss
	  self.evaluationPrice = evaluationPrice
	}

	init(from decoder: Decoder) throws {
	  let container = try decoder.container(keyedBy: CodingKeys.self)
	  self.identifier = try container.decodeIfPresent(UUID.self, forKey: .identifier) ?? UUID()
	  self.exchange = try container.decodeIfPresent(Exchange.self, forKey: .exchange) ?? .upbit
	  self.marketName = try container.decode(String.self, forKey: .marketName)
	  self.profitRate = try container.decode(Double.self, forKey: .profitRate)
	  self.evaluationProfitLoss = try container.decode(Double.self, forKey: .evaluationProfitLoss)
	  self.evaluationPrice = try container.decode(Double.self, forKey: .evaluationPrice)
	}
  }
}

enum TransactionRecordType: String, Codable {
  case userOrder
  case legacyBTCSettlement
  case delistingSettlement
}

struct TransactionInfo: Codable, Equatable {
  var exchange: Exchange = .upbit
  let marketName: String          // 코인 마켓 이름 (예: "BTC-USDT")
  let orderType: OrderType		// 주문 타입 (매도, 매수)
  let recordType: TransactionRecordType
  let executedTimestamp: Int64? // 체결 시각 timestamp(ms)
  let executedPrice: Double   // 체결 가격
  let executedQuantity: Double // 체결 수량
  let executedAmount: Double  // 체결 금액 (가격 * 수량)
  var settlementRateKRW: Decimal? = nil
  var settlementProfitLossKRW: Decimal? = nil
  var executedAmountKRW: Decimal? {
    settlementRateKRW.map { PortfolioCalculator.decimal(executedAmount) * $0 }
  }
  private let legacyExecutedDate: String?

  enum CodingKeys: String, CodingKey {
    case exchange, marketName, orderType, recordType, executedTimestamp, executedDate, executedPrice, executedQuantity, executedAmount, settlementRateKRW, settlementProfitLossKRW
  }

  var executedDate: String {
    if let executedTimestamp {
      return TradeTimestampFormatter.displayString(from: executedTimestamp)
    }
    return legacyExecutedDate ?? ""
  }

  init(
    exchange: Exchange = .upbit,
    marketName: String,
    orderType: OrderType,
    executedTimestamp: Int64,
    executedPrice: Double,
    executedQuantity: Double,
    executedAmount: Double,
    recordType: TransactionRecordType = .userOrder
  ) {
    self.exchange = exchange
    self.marketName = marketName
    self.orderType = orderType
    self.recordType = recordType
    self.executedTimestamp = executedTimestamp
    self.executedPrice = executedPrice
    self.executedQuantity = executedQuantity
    self.executedAmount = executedAmount
    self.legacyExecutedDate = nil
  }

  init(
    exchange: Exchange = .upbit,
    marketName: String,
    orderType: OrderType,
    executedDate: String,
    executedPrice: Double,
    executedQuantity: Double,
    executedAmount: Double,
    recordType: TransactionRecordType = .userOrder
  ) {
    self.exchange = exchange
    self.marketName = marketName
    self.orderType = orderType
    self.recordType = recordType
    self.executedTimestamp = nil
    self.executedPrice = executedPrice
    self.executedQuantity = executedQuantity
    self.executedAmount = executedAmount
    self.legacyExecutedDate = executedDate
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.exchange = try container.decodeIfPresent(Exchange.self, forKey: .exchange) ?? .upbit
    self.marketName = try container.decode(String.self, forKey: .marketName)
    self.orderType = try container.decode(OrderType.self, forKey: .orderType)
    self.recordType = try container.decodeIfPresent(TransactionRecordType.self, forKey: .recordType) ?? .userOrder
    self.executedTimestamp = try container.decodeIfPresent(Int64.self, forKey: .executedTimestamp)
    self.legacyExecutedDate = try container.decodeIfPresent(String.self, forKey: .executedDate)
    self.executedPrice = try container.decode(Double.self, forKey: .executedPrice)
    self.executedQuantity = try container.decode(Double.self, forKey: .executedQuantity)
    self.executedAmount = try container.decode(Double.self, forKey: .executedAmount)
    self.settlementRateKRW = try container.decodeIfPresent(Decimal.self, forKey: .settlementRateKRW)
    self.settlementProfitLossKRW = try container.decodeIfPresent(Decimal.self, forKey: .settlementProfitLossKRW)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(exchange, forKey: .exchange)
    try container.encode(marketName, forKey: .marketName)
    try container.encode(orderType, forKey: .orderType)
    try container.encode(recordType, forKey: .recordType)
    try container.encodeIfPresent(executedTimestamp, forKey: .executedTimestamp)
    try container.encodeIfPresent(legacyExecutedDate, forKey: .executedDate)
    try container.encode(executedPrice, forKey: .executedPrice)
    try container.encode(executedQuantity, forKey: .executedQuantity)
    try container.encode(executedAmount, forKey: .executedAmount)
    try container.encodeIfPresent(settlementRateKRW, forKey: .settlementRateKRW)
    try container.encodeIfPresent(settlementProfitLossKRW, forKey: .settlementProfitLossKRW)
  }
}

/// 유효한 거래내역 (현재 보유하고 있는 건에 대한 매수 내역, 총보유수량이 0이 되면 해당 코인 내역 통으로 날림)
struct ValidTransactionInfo: Codable, Equatable {
  var exchange: Exchange = .upbit
  let marketName: String
  var transaction: [Transaction]

  enum CodingKeys: String, CodingKey {
    case exchange, marketName, transaction
  }

  init(
    exchange: Exchange = .upbit,
    marketName: String,
    transaction: [Transaction]
  ) {
    self.exchange = exchange
    self.marketName = marketName
    self.transaction = transaction
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.exchange = try container.decodeIfPresent(Exchange.self, forKey: .exchange) ?? .upbit
    self.marketName = try container.decode(String.self, forKey: .marketName)
    self.transaction = try container.decode([Transaction].self, forKey: .transaction)
  }
  
  // 매수 & 매도 +- 계산해서 토탈 0이 되면 통으로 삭제
  struct Transaction: Codable, Equatable {
	let orderType: OrderType
	var quantity: Double
	let buyPrice: Double
    let timestamp: Int64?

    init(
      orderType: OrderType,
      quantity: Double,
      buyPrice: Double,
      timestamp: Int64? = nil
    ) {
      self.orderType = orderType
      self.quantity = quantity
      self.buyPrice = buyPrice
      self.timestamp = timestamp
    }
  }
}

extension ValidTransactionInfo {

  var totalHoldingQuantity: Double {
    // 체결 수량을 십진수로 합산해 전량 매도 뒤 미세 잔량이 남지 않게 한다.
    let total: Decimal? = transaction.reduce(Decimal.zero as Decimal?) { result, item in
      guard let result, let quantity = Self.decimalValue(item.quantity) else { return nil }
      // 이력 순서와 매수·매도 부호는 기존 계산을 유지한다.
      let next = item.orderType == .bid ? result + quantity : result - quantity
      return next.isNaN ? nil : next
    }
    if let total { return PortfolioCalculator.double(total) }
    // 십진수로 표현할 수 없는 기존 데이터는 기존 부동소수 계산을 유지한다.
    return transaction.reduce(0.0) { result, item in
      item.orderType == .bid ? result + item.quantity : result - item.quantity
    }
  }

  var averageBuyPrice: Double? {
    // 매도 내역을 제외한 매수 체결만 기존 가중평균에 사용한다.
    let buyTransactions = transaction.filter { $0.orderType == .bid }
    // 체결 금액과 수량을 합산하는 동안 십진수 정밀도를 유지한다.
    let totals = buyTransactions.reduce(
      (amount: Decimal.zero, quantity: Decimal.zero) as (amount: Decimal, quantity: Decimal)?
    ) { result, item in
      guard let result, let price = Self.decimalValue(item.buyPrice),
            let quantity = Self.decimalValue(item.quantity) else { return nil }
      // Decimal 지수 범위를 넘으면 곱셈 결과가 잘못된 거대 값이 될 수 있다.
      guard (-128...127).contains(price.exponent + quantity.exponent) else { return nil }
      // 각 체결의 원가와 수량을 같은 십진수 기준으로 합산한다.
      let amount = result.amount + price * quantity
      // 가중평균의 분모가 되는 매수 수량이다.
      let totalQuantity = result.quantity + quantity
      return amount.isNaN || totalQuantity.isNaN ? nil : (amount, totalQuantity)
    }
    if let totals {
      guard totals.quantity > 0 else { return nil }
      if (-128...127).contains(totals.amount.exponent - totals.quantity.exponent) {
        // 결과는 기존 화면과 저장 경계에서 사용하는 Double로 반환한다.
        let average = totals.amount / totals.quantity
        if !average.isNaN { return PortfolioCalculator.double(average) }
      }
    }
    // 기존 숫자 범위 밖이나 비유한 데이터는 이전 계산 결과를 유지한다.
    let totalBuyAmount = buyTransactions.reduce(0.0) { $0 + ($1.buyPrice * $1.quantity) }
    // 이전 방식으로 계산한 가중평균 분모다.
    let totalBuyQuantity = buyTransactions.reduce(0.0) { $0 + $1.quantity }
    return totalBuyQuantity > 0 ? totalBuyAmount / totalBuyQuantity : nil
  }

  var isFullySoldOut: Bool {
    totalHoldingQuantity <= 0
  }

  private static func decimalValue(_ value: Double) -> Decimal? {
    guard value.isFinite else { return nil }
    // 기존 Double 저장값의 십진수 문자열을 사용해 변환 오차를 늘리지 않는다.
    let decimal = PortfolioCalculator.decimal(value)
    guard !decimal.isNaN else { return nil }
    return decimal
  }
}
