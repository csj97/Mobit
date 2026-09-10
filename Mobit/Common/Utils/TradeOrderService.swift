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
    /// 결제 통화 기준 잔여. 원화 마켓은 원화 잔고, BTC 마켓은 남은 BTC 수량이다.
    let availableBalance: Double
    let settlementCurrency: SettlementCurrency
  }

  static func executeBid(
    marketName: String,
    cryptoName: String?,
    currentPrice: Double,
    quantity: Double,
    exchange: Exchange = ExchangeSelectionStore.currentExchange,
    executedAt: Date = Date(),
    btcKRWPrice: Double? = nil
  ) -> Result<Execution, TradeOrderValidator.ValidationError> {
    do {
      return .success(try UserDataManager.performAtomicInvestmentUpdate {
        try executeBidInTransaction(
          marketName: marketName,
          cryptoName: cryptoName,
          currentPrice: currentPrice,
          quantity: quantity,
          exchange: exchange,
          executedAt: executedAt,
          btcKRWPrice: btcKRWPrice
        ).get()
      })
    } catch let error as TradeOrderValidator.ValidationError {
      return .failure(error)
    } catch {
      return .failure(.invalidStoredData)
    }
  }

  private static func executeBidInTransaction(
    marketName: String,
    cryptoName: String?,
    currentPrice: Double,
    quantity: Double,
    exchange: Exchange,
    executedAt: Date,
    btcKRWPrice: Double?
  ) -> Result<Execution, TradeOrderValidator.ValidationError> {
    guard let currency = ExchangeMarketCodeConverter.settlementCurrency(
      fromDisplayMarket: marketName,
      exchange: exchange
    ) else {
      return .failure(.unsupportedMarket)
    }

    // BTC 마켓은 결제 자산의 원화 평가를 갱신해야 하므로 BTC/KRW 시세 없이는 체결하지 않는다.
    if currency == .btc, !(btcKRWPrice.map { $0.isFinite && $0 > 0 } ?? false) {
      return .failure(.missingSettlementRate)
    }

    guard UserDataManager.userCryptoList != nil,
          UserDataManager.userValidTransactionList != nil,
          UserDataManager.userTransactionList != nil,
          UserDataManager.userPNLHistory != nil else { return .failure(.invalidStoredData) }

    let validation = TradeOrderValidator.validateBid(
      price: currentPrice,
      quantity: quantity,
      availableBalance: self.availableSettlementBalance(
        currency: currency,
        exchange: exchange
      ),
      currency: currency
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

    let rate = PortfolioCalculator.decimal(currency == .krw ? 1 : (btcKRWPrice ?? 0))
    let acquiredCost = PortfolioCalculator.decimal(executedAmount) * rate
    guard !acquiredCost.isNaN else { return .failure(.invalidQuantity) }
    let previousCost = existingStaticData.flatMap { PortfolioCalculator.costBasisKRW(of: $0) }
    if existingStaticData != nil, previousCost == nil { return .failure(.missingCostBasis) }
    let settlementProfit: Decimal?
    if currency == .btc {
      guard let holding = settlementHolding(currency: .btc, exchange: exchange),
            let cost = PortfolioCalculator.costBasisKRW(of: holding.staticData) else {
        return .failure(.missingCostBasis)
      }
      settlementProfit = acquiredCost - cost * PortfolioCalculator.decimal(executedAmount)
        / PortfolioCalculator.decimal(holding.staticData.holdingQuantity)
    } else {
      settlementProfit = nil
    }

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

    var transaction = TransactionInfo(
      exchange: exchange,
      marketName: marketName,
      orderType: .bid,
      executedTimestamp: executedTimestamp,
      executedPrice: currentPrice,
      executedQuantity: quantity,
      executedAmount: executedAmount
    )

    transaction.settlementRateKRW = rate
    transaction.settlementProfitLossKRW = settlementProfit

    MarketDataServiceUtil.shared.addTransactionData(
      postTransactionList: UserDataManager.userTransactionList,
      data: transaction
    )

    if let existingStaticData {
      let holdingQuantity = PortfolioCalculator.cumulativeHoldingQuantity(
        previousQuantity: existingStaticData.holdingQuantity,
        newQuantity: quantity
      )
      let buyAmount = PortfolioCalculator.cumulativeBuyAmount(
        previousBuyAmount: existingStaticData.buyAmount,
        price: currentPrice,
        quantity: quantity,
        currency: currency
      )

      let averageBuyPrice = buyAmount / holdingQuantity
      let staticData = CryptoTransactionDataModel.CryptoTransactionStaticData(
        exchange: exchange,
        marketName: marketName,
        cryptoName: cryptoName,
        holdingQuantity: holdingQuantity,
        averageBuyPrice: averageBuyPrice,
        buyAmount: buyAmount,
        costBasisKRW: (previousCost ?? 0) + acquiredCost
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
        buyAmount: executedAmount,
        costBasisKRW: acquiredCost
      )

      MarketDataServiceUtil.shared.addCryptoFirstData(
        for: marketName,
        staticData: staticData,
        currentPrice: currentPrice
      )
    }

    let availableBalance = self.debitSettlementAsset(
      amount: executedAmount,
      currency: currency,
      exchange: exchange,
      btcKRWPrice: btcKRWPrice
    )

    return .success(
      Execution(
        marketName: marketName,
        executedAmount: executedAmount,
        availableBalance: availableBalance,
        settlementCurrency: currency
      )
    )
  }

  static func executeAsk(
    marketName: String,
    currentPrice: Double,
    quantity: Double,
    exchange: Exchange = ExchangeSelectionStore.currentExchange,
    executedAt: Date = Date(),
    btcKRWPrice: Double? = nil
  ) -> Result<Execution, TradeOrderValidator.ValidationError> {
    do {
      return .success(try UserDataManager.performAtomicInvestmentUpdate {
        try executeAskInTransaction(
          marketName: marketName,
          currentPrice: currentPrice,
          quantity: quantity,
          exchange: exchange,
          executedAt: executedAt,
          btcKRWPrice: btcKRWPrice
        ).get()
      })
    } catch let error as TradeOrderValidator.ValidationError {
      return .failure(error)
    } catch {
      return .failure(.invalidStoredData)
    }
  }

  private static func executeAskInTransaction(
    marketName: String,
    currentPrice: Double,
    quantity: Double,
    exchange: Exchange,
    executedAt: Date,
    btcKRWPrice: Double?
  ) -> Result<Execution, TradeOrderValidator.ValidationError> {
    guard let currency = ExchangeMarketCodeConverter.settlementCurrency(
      fromDisplayMarket: marketName,
      exchange: exchange
    ) else {
      return .failure(.unsupportedMarket)
    }

    if currency == .btc, !(btcKRWPrice.map { $0.isFinite && $0 > 0 } ?? false) {
      return .failure(.missingSettlementRate)
    }

    guard UserDataManager.userCryptoList != nil,
          UserDataManager.userValidTransactionList != nil,
          UserDataManager.userTransactionList != nil,
          UserDataManager.userPNLHistory != nil else { return .failure(.invalidStoredData) }

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
      holdingQuantity: crypto.staticData.holdingQuantity,
      currency: currency
    )

    guard case .success = validation else {
      if case .failure(let error) = validation {
        return .failure(error)
      }
      return .failure(.invalidQuantity)
    }

    // 입력 수량은 화면 표시용으로 소수점 8자리까지만 넘어오므로, 남는 양이 허용 오차 이내면 보유 수량 전체를 체결시킨다.
    let staticData = crypto.staticData
    guard let originalCost = PortfolioCalculator.costBasisKRW(of: staticData) else {
      return .failure(.missingCostBasis)
    }
    let rate = PortfolioCalculator.decimal(currency == .krw ? 1 : (btcKRWPrice ?? 0))
    let isFullySold = PortfolioCalculator.isFullySold(
      holdingQuantity: staticData.holdingQuantity,
      sellQuantity: quantity
    )
    let executedQuantity = isFullySold ? staticData.holdingQuantity : quantity
    let executedAmount = PortfolioCalculator.executedAmount(
      price: currentPrice,
      quantity: executedQuantity,
      currency: currency
    )

    let allocatedCost = isFullySold ? originalCost : originalCost
      * PortfolioCalculator.decimal(executedQuantity) / PortfolioCalculator.decimal(staticData.holdingQuantity)
    let realizedKRW = PortfolioCalculator.decimal(executedAmount) * rate - allocatedCost
    let executedTimestamp = TradeTimestampFormatter.timestamp(from: executedAt)
    var transaction = TransactionInfo(
      exchange: exchange,
      marketName: marketName,
      orderType: .ask,
      executedTimestamp: executedTimestamp,
      executedPrice: currentPrice,
      executedQuantity: executedQuantity,
      executedAmount: executedAmount
    )

    transaction.settlementRateKRW = rate

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
      let newBuyAmount = staticData.buyAmount * newHoldingQuantity / staticData.holdingQuantity
      let newStaticData = CryptoTransactionDataModel.CryptoTransactionStaticData(
        exchange: staticData.exchange,
        marketName: staticData.marketName,
        cryptoName: staticData.cryptoName,
        holdingQuantity: newHoldingQuantity,
        averageBuyPrice: staticData.averageBuyPrice,
        buyAmount: newBuyAmount,
        costBasisKRW: originalCost - allocatedCost
      )

      MarketDataServiceUtil.shared.fetchData(
        data: newStaticData,
        currentPrice: currentPrice
      )
    } else if let removeIndex = UserDataManager.userCryptoList?
      .firstIndex(where: { $0.staticData.exchangePairID == targetPairID }) {
      UserDataManager.userCryptoList?.remove(at: removeIndex)
    }

    let pnl = PortfolioCalculator.realizedProfitLoss(
      entryPrice: staticData.averageBuyPrice,
      exitPrice: currentPrice,
      quantity: executedQuantity
    )

    var pnlHistory = UserPNLHistoryModel(
      exchange: exchange,
      marketName: staticData.marketName,
      entryPrice: staticData.averageBuyPrice,
      exitPrice: currentPrice,
      transactionTimestamp: executedTimestamp,
      orderQuantity: executedQuantity,
      pnl: pnl
    )
    pnlHistory.costBasisKRW = allocatedCost
    pnlHistory.realizedProfitLossKRW = realizedKRW
    pnlHistory.settlementRateKRW = rate
    UserDataManager.userPNLHistory?.append(pnlHistory)

    let availableBalance = self.creditSettlementAsset(
      amount: executedAmount,
      currency: currency,
      exchange: exchange,
      executedAt: executedAt,
      btcKRWPrice: btcKRWPrice
    )

    return .success(
      Execution(
        marketName: marketName,
        executedAmount: executedAmount,
        availableBalance: availableBalance,
        settlementCurrency: currency
      )
    )
  }
}

// MARK: - 결제 자산

extension TradeOrderService {
  /// 결제 통화의 주문 가능 수량. BTC 마켓은 보유 중인 BTC가 곧 주문 가능 금액이다.
  static func availableSettlementBalance(
    currency: SettlementCurrency,
    exchange: Exchange = ExchangeSelectionStore.currentExchange
  ) -> Double? {
    switch currency {
    case .krw:
      return UserDataManager.userInformation(for: exchange)?.userAvailableBalance

    case .btc:
      return self.settlementHolding(currency: currency, exchange: exchange)?
        .staticData.holdingQuantity ?? 0
    }
  }

  private static func settlementHolding(
    currency: SettlementCurrency,
    exchange: Exchange
  ) -> CryptoTransactionDataModel? {
    guard let displayMarket = currency.holdingDisplayMarket else { return nil }

    let pairID = ExchangeMarketCodeConverter.pairID(
      fromDisplayMarket: displayMarket,
      exchange: exchange
    )
    return UserDataManager.userCryptoList?
      .first(where: { $0.staticData.exchangePairID == pairID })
  }

  /// 매수 결제. 반환값은 차감 후 잔여 결제 자산이다.
  private static func debitSettlementAsset(
    amount: Double,
    currency: SettlementCurrency,
    exchange: Exchange,
    btcKRWPrice: Double?
  ) -> Double {
    switch currency {
    case .krw:
      let availableBalance = (UserDataManager.userInformation(for: exchange)?.userAvailableBalance ?? 0) - amount
      UserDataManager.updateUserInformation(
        MobitUserInformation(userAvailableBalance: availableBalance),
        for: exchange
      )
      return availableBalance

    case .btc:
      return self.debitBTCHolding(
        amount: amount,
        exchange: exchange,
        btcKRWPrice: btcKRWPrice ?? 0
      )
    }
  }

  /// 매도 대금 수령. 반환값은 반영 후 결제 자산이다.
  private static func creditSettlementAsset(
    amount: Double,
    currency: SettlementCurrency,
    exchange: Exchange,
    executedAt: Date,
    btcKRWPrice: Double?
  ) -> Double {
    switch currency {
    case .krw:
      let availableBalance = (UserDataManager.userInformation(for: exchange)?.userAvailableBalance ?? 0) + amount
      UserDataManager.updateUserInformation(
        MobitUserInformation(userAvailableBalance: availableBalance),
        for: exchange
      )
      return availableBalance

    case .btc:
      return self.creditBTCHolding(
        amount: amount,
        exchange: exchange,
        executedAt: executedAt,
        btcKRWPrice: btcKRWPrice ?? 0
      )
    }
  }

  /// 결제에 쓴 BTC 원가는 비례 차감하며 교환손익은 원 매수 거래에 연결해 보존한다.
  private static func debitBTCHolding(
    amount: Double,
    exchange: Exchange,
    btcKRWPrice: Double
  ) -> Double {
    guard let holdingMarket = SettlementCurrency.btc.holdingDisplayMarket,
          let holding = self.settlementHolding(currency: .btc, exchange: exchange)
    else {
      return 0
    }

    let staticData = holding.staticData
    let remainingQuantity = PortfolioCalculator.double(PortfolioCalculator.decimal(staticData.holdingQuantity) - PortfolioCalculator.decimal(amount))

    MarketDataServiceUtil.shared.addValidTransactionData(
      for: holdingMarket,
      orderType: .ask,
      postValidTransactionList: UserDataManager.userValidTransactionList,
      newValidTransactionData: ValidTransactionInfo.Transaction(
        orderType: .ask,
        quantity: amount,
        buyPrice: btcKRWPrice,
        timestamp: nil
      ),
      exchange: exchange
    )

    guard remainingQuantity > 0 else {
      let pairID = ExchangeMarketCodeConverter.pairID(
        fromDisplayMarket: holdingMarket,
        exchange: exchange
      )
      if let removeIndex = UserDataManager.userCryptoList?
        .firstIndex(where: { $0.staticData.exchangePairID == pairID }) {
        UserDataManager.userCryptoList?.remove(at: removeIndex)
      }
      return 0
    }

    let updatedStaticData = CryptoTransactionDataModel.CryptoTransactionStaticData(
      exchange: staticData.exchange,
      marketName: staticData.marketName,
      cryptoName: staticData.cryptoName,
      holdingQuantity: remainingQuantity,
      averageBuyPrice: staticData.averageBuyPrice,
      buyAmount: staticData.buyAmount * remainingQuantity / staticData.holdingQuantity,
      costBasisKRW: PortfolioCalculator.costBasisKRW(of: staticData).map {
        $0 * PortfolioCalculator.decimal(remainingQuantity) / PortfolioCalculator.decimal(staticData.holdingQuantity)
      }
    )

    MarketDataServiceUtil.shared.fetchData(
      data: updatedStaticData,
      currentPrice: btcKRWPrice
    )

    return remainingQuantity
  }

  /// 매도 대금으로 받은 BTC는 체결 시점 BTC/KRW 시세로 취득한 것으로 보고 원화 평단을 가중평균한다.
  private static func creditBTCHolding(
    amount: Double,
    exchange: Exchange,
    executedAt: Date,
    btcKRWPrice: Double
  ) -> Double {
    guard let holdingMarket = SettlementCurrency.btc.holdingDisplayMarket else { return 0 }

    let existingStaticData = self.settlementHolding(currency: .btc, exchange: exchange)?.staticData
    let previousQuantity = existingStaticData?.holdingQuantity ?? 0
    let newQuantity = previousQuantity + amount
    let newAveragePrice = PortfolioCalculator.weightedAverageBuyPrice(
      previousQuantity: previousQuantity,
      previousAveragePrice: existingStaticData?.averageBuyPrice ?? 0,
      addedQuantity: amount,
      addedPrice: btcKRWPrice
    )

    MarketDataServiceUtil.shared.addValidTransactionData(
      for: holdingMarket,
      orderType: .bid,
      postValidTransactionList: UserDataManager.userValidTransactionList,
      newValidTransactionData: ValidTransactionInfo.Transaction(
        orderType: .bid,
        quantity: amount,
        buyPrice: btcKRWPrice,
        timestamp: TradeTimestampFormatter.timestamp(from: executedAt)
      ),
      exchange: exchange
    )

    let updatedStaticData = CryptoTransactionDataModel.CryptoTransactionStaticData(
      exchange: exchange,
      marketName: existingStaticData?.marketName ?? holdingMarket,
      cryptoName: existingStaticData?.cryptoName ?? "비트코인",
      holdingQuantity: newQuantity,
      averageBuyPrice: newAveragePrice,
      buyAmount: newQuantity * newAveragePrice,
      costBasisKRW: (existingStaticData.flatMap { PortfolioCalculator.costBasisKRW(of: $0) } ?? 0)
        + PortfolioCalculator.decimal(amount) * PortfolioCalculator.decimal(btcKRWPrice)
    )

    if existingStaticData == nil {
      MarketDataServiceUtil.shared.addCryptoFirstData(
        for: updatedStaticData.marketName,
        staticData: updatedStaticData,
        currentPrice: btcKRWPrice
      )
    } else {
      MarketDataServiceUtil.shared.fetchData(
        data: updatedStaticData,
        currentPrice: btcKRWPrice
      )
    }

    return newQuantity
  }
}
