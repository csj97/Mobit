//
//  TradeOrderService.swift
//  Mobit
//
//  Created by 조성재 on 6/30/26.
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
      availableBalance: UserDataManager.userInformation(for: exchange)?.userAvailableBalance
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
    let executedTimestamp = TradeTimestampFormatter.timestamp(from: executedAt)
    let existingStaticData = UserDataManager.userCryptoList?
      .first(where: { $0.staticData.exchangePairID == targetPairID })?
      .staticData

    let validTransaction = ValidTransactionInfo.Transaction(
      orderType: .bid,
      quantity: quantity,
      buyPrice: currentPrice,
      timestamp: executedTimestamp
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
      executedTimestamp: executedTimestamp,
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

    let availableBalance = (UserDataManager.userInformation(for: exchange)?.userAvailableBalance ?? 0) - executedAmount
    UserDataManager.updateUserInformation(
      MobitUserInformation(userAvailableBalance: availableBalance),
      for: exchange
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

    guard case .success = validation else {
      if case .failure(let error) = validation {
        return .failure(error)
      }
      return .failure(.invalidQuantity)
    }

    // 입력 수량은 화면 표시용으로 소수점 8자리까지만 넘어오므로, 남는 양이 허용 오차 이내면 보유 수량 전체를 체결시킨다.
    let staticData = crypto.staticData
    let isFullySold = PortfolioCalculator.isFullySold(
      holdingQuantity: staticData.holdingQuantity,
      sellQuantity: quantity
    )
    let executedQuantity = isFullySold ? staticData.holdingQuantity : quantity
    let executedAmount = PortfolioCalculator.executedAmount(
      price: currentPrice,
      quantity: executedQuantity
    )

    let executedTimestamp = TradeTimestampFormatter.timestamp(from: executedAt)
    let transaction = TransactionInfo(
      exchange: exchange,
      marketName: marketName,
      orderType: .ask,
      executedTimestamp: executedTimestamp,
      executedPrice: currentPrice,
      executedQuantity: executedQuantity,
      executedAmount: executedAmount
    )

    MarketDataServiceUtil.shared.addTransactionData(
      postTransactionList: UserDataManager.userTransactionList,
      data: transaction
    )

    let validTransaction = ValidTransactionInfo.Transaction(
      orderType: .ask,
      quantity: executedQuantity,
      buyPrice: currentPrice,
      timestamp: executedTimestamp
    )

    MarketDataServiceUtil.shared.addValidTransactionData(
      for: marketName,
      orderType: .ask,
      postValidTransactionList: UserDataManager.userValidTransactionList,
      newValidTransactionData: validTransaction,
      exchange: exchange
    )

    if !isFullySold {
      let newHoldingQuantity = staticData.holdingQuantity - executedQuantity
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
      quantity: executedQuantity
    )

    let pnlHistory = UserPNLHistoryModel(
      exchange: exchange,
      marketName: staticData.marketName,
      entryPrice: staticData.averageBuyPrice,
      exitPrice: currentPrice,
      transactionTimestamp: executedTimestamp,
      orderQuantity: executedQuantity,
      pnl: pnl
    )
    UserDataManager.userPNLHistory?.append(pnlHistory)

    let availableBalance = (UserDataManager.userInformation(for: exchange)?.userAvailableBalance ?? 0) + executedAmount
    UserDataManager.updateUserInformation(
      MobitUserInformation(userAvailableBalance: availableBalance),
      for: exchange
    )

    return .success(
      Execution(
        marketName: marketName,
        executedAmount: executedAmount,
        availableBalance: availableBalance
      )
    )
  }

}
