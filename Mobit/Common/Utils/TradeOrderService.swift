//
//  TradeOrderService.swift
//  Mobit
//
//  Created by Codex on 6/30/26.
//

import Foundation

enum TradeOrderService {
  struct Execution {
    let marketName: String
    let executedAmount: Double
    let availableBalance: Double
  }

  static func executeBid(
    marketName: String,
    cryptoName: String?,
    currentPrice: Double,
    quantity: Double,
    exchange: Exchange = ExchangeSelectionStore.currentExchange,
    executedAt: Date = Date()
  ) -> Result<Execution, TradeOrderValidator.ValidationError> {
    let validation = TradeOrderValidator.validateBid(
      price: currentPrice,
      quantity: quantity,
      availableBalance: UserDataManager.userInformation?.userAvailableBalance
    )

    guard case .success(let executedAmount) = validation else {
      if case .failure(let error) = validation {
        return .failure(error)
      }
      return .failure(.invalidQuantity)
    }

    let targetPairID = ExchangeMarketCodeConverter.pairID(
      fromDisplayMarket: marketName,
      exchange: exchange
    )
    let executedDate = formattedDate(executedAt)
    let existingStaticData = UserDataManager.userCryptoList?
      .first(where: { $0.staticData.exchangePairID == targetPairID })?
      .staticData

    let validTransaction = ValidTransactionInfo.Transaction(
      orderType: .bid,
      quantity: quantity,
      buyPrice: currentPrice
    )

    MarketDataServiceUtil.shared.addValidTransactionData(
      for: marketName,
      orderType: .bid,
      postValidTransactionList: UserDataManager.userValidTransactionList,
      newValidTransactionData: validTransaction,
      exchange: exchange
    )

    let transaction = TransactionInfo(
      exchange: exchange,
      marketName: marketName,
      orderType: .bid,
      executedDate: executedDate,
      executedPrice: currentPrice,
      executedQuantity: quantity,
      executedAmount: executedAmount
    )

    MarketDataServiceUtil.shared.addTransactionData(
      postTransactionList: UserDataManager.userTransactionList,
      data: transaction
    )

    if let existingStaticData {
      let averageBuyPrice = UserDataManager.userValidTransactionList?
        .first(where: { $0.exchangePairID == targetPairID })?
        .averageBuyPrice ?? 0
      let holdingQuantity = PortfolioCalculator.cumulativeHoldingQuantity(
        previousQuantity: existingStaticData.holdingQuantity,
        newQuantity: quantity
      )
      let buyAmount = PortfolioCalculator.cumulativeBuyAmount(
        previousBuyAmount: existingStaticData.buyAmount,
        price: currentPrice,
        quantity: quantity
      )

      let staticData = CryptoTransactionDataModel.CryptoTransactionStaticData(
        exchange: exchange,
        marketName: marketName,
        cryptoName: cryptoName,
        holdingQuantity: holdingQuantity,
        averageBuyPrice: averageBuyPrice,
        buyAmount: buyAmount
      )

      MarketDataServiceUtil.shared.fetchData(
        data: staticData,
        currentPrice: currentPrice
      )
    } else {
      let staticData = CryptoTransactionDataModel.CryptoTransactionStaticData(
        exchange: exchange,
        marketName: marketName,
        cryptoName: cryptoName,
        holdingQuantity: quantity,
        averageBuyPrice: currentPrice,
        buyAmount: executedAmount
      )

      MarketDataServiceUtil.shared.addCryptoFirstData(
        for: marketName,
        staticData: staticData,
        currentPrice: currentPrice
      )
    }

    let availableBalance = (UserDataManager.userInformation?.userAvailableBalance ?? 0) - executedAmount
    UserDataManager.userInformation = MobitUserInformation(
      userAvailableBalance: availableBalance
    )

    return .success(
      Execution(
        marketName: marketName,
        executedAmount: executedAmount,
        availableBalance: availableBalance
      )
    )
  }

  static func executeAsk(
    marketName: String,
    currentPrice: Double,
    quantity: Double,
    exchange: Exchange = ExchangeSelectionStore.currentExchange,
    executedAt: Date = Date()
  ) -> Result<Execution, TradeOrderValidator.ValidationError> {
    let targetPairID = ExchangeMarketCodeConverter.pairID(
      fromDisplayMarket: marketName,
      exchange: exchange
    )
    guard let cryptoIndex = UserDataManager.userCryptoList?
      .firstIndex(where: { $0.staticData.exchangePairID == targetPairID }),
      let crypto = UserDataManager.userCryptoList?[cryptoIndex]
    else {
      return .failure(.insufficientHolding)
    }

    let validation = TradeOrderValidator.validateAsk(
      price: currentPrice,
      quantity: quantity,
      holdingQuantity: crypto.staticData.holdingQuantity
    )

    guard case .success(let executedAmount) = validation else {
      if case .failure(let error) = validation {
        return .failure(error)
      }
      return .failure(.invalidQuantity)
    }

    let executedDate = formattedDate(executedAt)
    let transaction = TransactionInfo(
      exchange: exchange,
      marketName: marketName,
      orderType: .ask,
      executedDate: executedDate,
      executedPrice: currentPrice,
      executedQuantity: quantity,
      executedAmount: executedAmount
    )

    MarketDataServiceUtil.shared.addTransactionData(
      postTransactionList: UserDataManager.userTransactionList,
      data: transaction
    )

    let validTransaction = ValidTransactionInfo.Transaction(
      orderType: .ask,
      quantity: quantity,
      buyPrice: currentPrice
    )

    MarketDataServiceUtil.shared.addValidTransactionData(
      for: marketName,
      orderType: .ask,
      postValidTransactionList: UserDataManager.userValidTransactionList,
      newValidTransactionData: validTransaction,
      exchange: exchange
    )

    let staticData = crypto.staticData
    if quantity < staticData.holdingQuantity {
      let newHoldingQuantity = staticData.holdingQuantity - quantity
      let newBuyAmount = newHoldingQuantity * staticData.averageBuyPrice
      let newStaticData = CryptoTransactionDataModel.CryptoTransactionStaticData(
        exchange: staticData.exchange,
        marketName: staticData.marketName,
        cryptoName: staticData.cryptoName,
        holdingQuantity: newHoldingQuantity,
        averageBuyPrice: staticData.averageBuyPrice,
        buyAmount: newBuyAmount
      )

      MarketDataServiceUtil.shared.fetchData(
        data: newStaticData,
        currentPrice: currentPrice
      )
    } else {
      UserDataManager.userCryptoList?.remove(at: cryptoIndex)
    }

    let pnl = PortfolioCalculator.realizedProfitLoss(
      entryPrice: staticData.averageBuyPrice,
      exitPrice: currentPrice,
      quantity: quantity
    )

    let pnlHistory = UserPNLHistoryModel(
      exchange: exchange,
      marketName: staticData.marketName,
      entryPrice: staticData.averageBuyPrice,
      exitPrice: currentPrice,
      transactionDate: executedDate,
      orderQuantity: quantity,
      pnl: pnl
    )
    UserDataManager.userPNLHistory?.append(pnlHistory)

    let availableBalance = (UserDataManager.userInformation?.userAvailableBalance ?? 0) + executedAmount
    UserDataManager.userInformation = MobitUserInformation(
      userAvailableBalance: availableBalance
    )

    return .success(
      Execution(
        marketName: marketName,
        executedAmount: executedAmount,
        availableBalance: availableBalance
      )
    )
  }

  private static func formattedDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MM.dd HH:mm"
    formatter.locale = Locale(identifier: "ko_KR")
    return formatter.string(from: date)
  }
}
