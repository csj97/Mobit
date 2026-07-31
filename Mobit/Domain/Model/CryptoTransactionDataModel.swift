//
//  BidCryptoInfo.swift
//  Mobit
//
//  Created by 조성재 on 2/19/25.
//

import Foundation

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
	
	enum CodingKeys: String, CodingKey {
		case exchange, marketName, cryptoName, holdingQuantity, averageBuyPrice, buyAmount
	}

	init(
	  exchange: Exchange = .upbit,
	  identifier: UUID = UUID(),
	  marketName: String,
	  cryptoName: String?,
	  holdingQuantity: Double,
	  averageBuyPrice: Double,
	  buyAmount: Double
	) {
	  self.exchange = exchange
	  self.identifier = identifier
	  self.marketName = marketName
	  self.cryptoName = cryptoName
	  self.holdingQuantity = holdingQuantity
	  self.averageBuyPrice = averageBuyPrice
	  self.buyAmount = buyAmount
	}

	init(from decoder: Decoder) throws {
	  let container = try decoder.container(keyedBy: CodingKeys.self)
	  self.exchange = try container.decodeIfPresent(Exchange.self, forKey: .exchange) ?? .upbit
	  self.marketName = try container.decode(String.self, forKey: .marketName)
	  self.cryptoName = try container.decodeIfPresent(String.self, forKey: .cryptoName)
	  self.holdingQuantity = try container.decode(Double.self, forKey: .holdingQuantity)
	  self.averageBuyPrice = try container.decode(Double.self, forKey: .averageBuyPrice)
	  self.buyAmount = try container.decode(Double.self, forKey: .buyAmount)
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

struct TransactionInfo: Codable, Equatable {
  var exchange: Exchange = .upbit
  let marketName: String          // 코인 마켓 이름 (예: "BTC-USDT")
  let orderType: OrderType		// 주문 타입 (매도, 매수)
  let executedDate: String    // 체결 시간
  let executedPrice: Double   // 체결 가격
  let executedQuantity: Double // 체결 수량
  let executedAmount: Double  // 체결 금액 (가격 * 수량)

  enum CodingKeys: String, CodingKey {
    case exchange, marketName, orderType, executedDate, executedPrice, executedQuantity, executedAmount
  }

  init(
    exchange: Exchange = .upbit,
    marketName: String,
    orderType: OrderType,
    executedDate: String,
    executedPrice: Double,
    executedQuantity: Double,
    executedAmount: Double
  ) {
    self.exchange = exchange
    self.marketName = marketName
    self.orderType = orderType
    self.executedDate = executedDate
    self.executedPrice = executedPrice
    self.executedQuantity = executedQuantity
    self.executedAmount = executedAmount
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.exchange = try container.decodeIfPresent(Exchange.self, forKey: .exchange) ?? .upbit
    self.marketName = try container.decode(String.self, forKey: .marketName)
    self.orderType = try container.decode(OrderType.self, forKey: .orderType)
    self.executedDate = try container.decode(String.self, forKey: .executedDate)
    self.executedPrice = try container.decode(Double.self, forKey: .executedPrice)
    self.executedQuantity = try container.decode(Double.self, forKey: .executedQuantity)
    self.executedAmount = try container.decode(Double.self, forKey: .executedAmount)
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
  }
}

extension ValidTransactionInfo {
  
  var totalHoldingQuantity: Double {
	transaction.reduce(0.0) { result, t in
	  switch t.orderType {
	  case .bid:
		return result + t.quantity
	  case .ask:
		return result - t.quantity
	  }
	}
  }
  
  var averageBuyPrice: Double? {
	let buyTransactions = transaction.filter { $0.orderType == .bid }
	
	let totalBuyAmount = buyTransactions.reduce(0.0) { $0 + ($1.buyPrice * $1.quantity) }
	let totalBuyQuantity = buyTransactions.reduce(0.0) { $0 + $1.quantity }
	
	return totalBuyQuantity > 0 ? totalBuyAmount / totalBuyQuantity : nil
  }
  
  var isFullySoldOut: Bool {
	abs(totalHoldingQuantity) < PortfolioCalculator.quantityTolerance
  }
}
