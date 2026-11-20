//
//  TradeOrderService.swift
//  Mobit
//
//  Created by 조성재 on 6/30/26.
//

import Foundation

enum TradeOrderService {
  // 거래지원 종료 확인창과 실제 정산에서 동일하게 사용하는 정산 정보다.
  struct DelistingSettlementQuote: Equatable {
    // 정산할 마켓이다.
    let marketName: String
    // 보유 자산이 속한 거래소다.
    let exchange: Exchange
    // 전량 매도할 수량이다.
    let quantity: Double
    // 저장 시세 또는 구형 평가금액을 수량으로 나눈 거래내역 단가다.
    let settlementPrice: Double
    // 확인 후 매수 기준이 바뀌면 재확인하도록 저장한다.
    let averageBuyPrice: Double
    // 확인창 이후 평가손익이 변경됐는지 대조한다.
    let storedProfitLoss: Double
    // 구형 데이터의 정산 검증에 사용한 저장 평가금액이다.
    let storedEvaluationPrice: Double
    // 마지막 시세와 보유 상태가 함께 저장된 정산 기준이다.
    let storedPriceSnapshot: CryptoTransactionDataModel.SettlementPriceSnapshot?
    // 원화 취득원가가 없을 때 사용되는 매수금액 기준이다.
    let buyAmount: Double
    // 원화 실현손익의 취득원가 기준이다.
    let costBasisKRW: Decimal?
    // 결제 통화의 절삭 규칙을 적용한 반환 금액이다.
    let executedAmount: Double
    // 반환액은 정산에 사용할 때까지 십진수로 보존한다.
    let settlementAmount: Decimal
    // 반환 금액에 사용할 결제 통화다.
    let currency: SettlementCurrency
  }

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

      let averageBuyPrice = calculateAveragePrice(amount: buyAmount, quantity: holdingQuantity)
      let staticData = CryptoTransactionDataModel.CryptoTransactionStaticData(
        exchange: exchange,
        marketName: marketName,
        cryptoName: cryptoName,
        holdingQuantity: holdingQuantity,
        averageBuyPrice: averageBuyPrice,
        buyAmount: buyAmount,
        costBasisKRW: (previousCost ?? 0) + acquiredCost
      )

      MarketDataServiceUtil.shared.updateHoldingData(
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
          btcKRWPrice: btcKRWPrice,
          delistingQuote: nil
        ).get()
      })
    } catch let error as TradeOrderValidator.ValidationError {
      return .failure(error)
    } catch {
      return .failure(.invalidStoredData)
    }
  }

  // 미리보기와 실제 정산은 같은 단가와 결제 통화 절삭 규칙을 사용해야 한다.
  static func delistingSettlementQuote(
    for holding: CryptoTransactionDataModel
  ) -> Result<DelistingSettlementQuote, TradeOrderValidator.ValidationError> {
    // 저장된 보유 수량과 매수가를 정산 기준으로 사용한다.
    let staticData = holding.staticData
    guard let currency = ExchangeMarketCodeConverter.settlementCurrency(
      fromDisplayMarket: staticData.marketName,
      exchange: staticData.exchange
    ) else { return .failure(.unsupportedMarket) }
    // 해당 마켓의 전체 보유 수량이다.
    let quantity = staticData.holdingQuantity
    // 마지막으로 저장된 평가손익이다.
    let storedProfitLoss = holding.dynamicData.evaluationProfitLoss
    guard quantity.isFinite, quantity > 0,
          storedProfitLoss.isFinite, staticData.averageBuyPrice.isFinite,
          staticData.averageBuyPrice >= 0 else {
      return .failure(.missingPrice)
    }
    // 정산 금액과 손익은 동일 거래소·마켓의 보유분이어야 한다.
    guard staticData.exchange == holding.dynamicData.exchange,
          staticData.marketName == holding.dynamicData.marketName else {
      return .failure(.settlementUnverified)
    }
    // 저장 평가금액은 구형 정산 검증과 확인창 이후 변경 비교에 사용한다.
    let storedEvaluationPrice = holding.dynamicData.evaluationPrice
    guard storedEvaluationPrice.isFinite, storedEvaluationPrice >= 0 else {
      return .failure(.settlementUnverified)
    }
    // 평가 시세가 함께 저장된 최신 보유분이면 해당 원본으로 정산한다.
    let priceSnapshot = holding.dynamicData.settlementPriceSnapshot
    if let priceSnapshot {
      guard priceSnapshot.price.isFinite, priceSnapshot.price > 0,
            priceSnapshot.quantity.isFinite, priceSnapshot.quantity == quantity,
            priceSnapshot.averageBuyPrice.isFinite, priceSnapshot.averageBuyPrice == staticData.averageBuyPrice,
            priceSnapshot.evaluationProfitLoss.isFinite, priceSnapshot.evaluationProfitLoss == storedProfitLoss,
            priceSnapshot.evaluationPrice.isFinite, priceSnapshot.evaluationPrice == storedEvaluationPrice else {
        return .failure(.settlementUnverified)
      }
    }
    // 지급액과 거래내역 단가를 같은 보유 수량으로 계산한다.
    var decimalQuantity = PortfolioCalculator.decimal(quantity)
    guard !decimalQuantity.isNaN, decimalQuantity > 0 else { return .failure(.invalidQuantity) }
    // 절삭 전 반환 금액에서 정산 단가와 최종 반환 금액을 각각 구한다.
    var grossAmount = Decimal()
    // 보유 수량 하나당 거래내역에 남길 단가다.
    var price = Decimal()
    // 확인창과 거래내역에 공통으로 적용할 결제 통화 금액이다.
    var settlementAmount = Decimal()
    if let priceSnapshot {
      // 평가값을 생성한 두 기존 경로를 재계산해 시세 원본의 손상을 확인한다.
      let calculatedEvaluation = PortfolioCalculator.evaluationPrice(
        currentPrice: priceSnapshot.price,
        holdingQuantity: quantity
      )
      let calculatedProfit = PortfolioCalculator.evaluationProfitLoss(
        currentPrice: priceSnapshot.price,
        holdingQuantity: quantity,
        averageBuyPrice: staticData.averageBuyPrice
      )
      // 신규 보유 생성은 기존 Double 곱과 내림으로 평가했다.
      let previousEvaluation = priceSnapshot.price * quantity
      let previousProfit = previousEvaluation - staticData.averageBuyPrice * quantity
      let previousRoundedEvaluation = previousEvaluation.formatDigits(digits: TradingRules.Spot.evaluationFractionDigits)
      guard (calculatedEvaluation == storedEvaluationPrice && calculatedProfit == storedProfitLoss)
              || (previousRoundedEvaluation == storedEvaluationPrice && previousProfit == storedProfitLoss) else {
        return .failure(.settlementUnverified)
      }
      // 저장된 시세의 Decimal 곱을 마지막 평가에 사용한 수량에 적용한다.
      var savedPrice = PortfolioCalculator.decimal(priceSnapshot.price)
      guard !savedPrice.isNaN,
            (-128...127).contains(savedPrice.exponent + decimalQuantity.exponent),
            NSDecimalMultiply(&grossAmount, &savedPrice, &decimalQuantity, .plain) == .noError,
            !grossAmount.isNaN else { return .failure(.settlementUnverified) }
      price = savedPrice
      NSDecimalRound(&settlementAmount, &grossAmount, currency.amountFractionDigits, .down)
    } else {
      // 구형 손익은 저장 평가금액과 크게 어긋난 기록을 걸러낼 때만 쓴다.
      var average = PortfolioCalculator.decimal(staticData.averageBuyPrice)
      // 손익을 매입금액에 더해 이전 평가를 대조한다.
      var profitLoss = PortfolioCalculator.decimal(storedProfitLoss)
      // 구형 Double 기록으로 결제 최소 단위 하나를 구분할 수 있는지 확인한다.
      let minimumUnit = Decimal(sign: .plus, exponent: -currency.amountFractionDigits, significand: 1)
      // 기존 평단과 수량을 Double로 곱할 때의 정밀도도 함께 확인한다.
      let previousPurchase = staticData.averageBuyPrice * quantity
      guard !average.isNaN, !profitLoss.isNaN, previousPurchase.isFinite,
            2 * (storedEvaluationPrice.ulp + storedProfitLoss.ulp + previousPurchase.ulp)
              < PortfolioCalculator.double(minimumUnit),
            (-128...127).contains(average.exponent + decimalQuantity.exponent) else {
        return .failure(.settlementUnverified)
      }
      // 매수가와 수량을 곱한 값은 손익 검증용이며 지급액에 사용하지 않는다.
      var purchaseAmount = Decimal()
      guard NSDecimalMultiply(&purchaseAmount, &average, &decimalQuantity, .plain) == .noError else {
        return .failure(.settlementUnverified)
      }
      // 38자리를 넘는 합산의 끝자리 손실은 구형 Double 저장 정밀도보다 작다.
      let additionResult = NSDecimalAdd(&grossAmount, &purchaseAmount, &profitLoss, .plain)
      guard (additionResult == .noError || additionResult == .lossOfPrecision),
            !grossAmount.isNaN else { return .failure(.settlementUnverified) }
      if grossAmount < 0 {
        // 종전 정산식의 단가도 0이어야 실제 음수 데이터를 숨기지 않는다.
        let previousPrice = staticData.averageBuyPrice + storedProfitLoss / quantity
        guard previousPrice.isFinite, previousPurchase + storedProfitLoss == 0, previousPrice == 0 else {
          return .failure(.settlementUnverified)
        }
        grossAmount = 0
      }
      // 사용자가 확인할 금액과 손익에서 역산한 금액을 같은 결제 단위로 대조한다.
      var inferredSettlement = Decimal()
      NSDecimalRound(&inferredSettlement, &grossAmount, currency.amountFractionDigits, .down)
      grossAmount = PortfolioCalculator.decimal(storedEvaluationPrice)
      guard !grossAmount.isNaN else { return .failure(.settlementUnverified) }
      // 한 단위 차이는 구형 저장 평가금액을 우선하고, 더 큰 차이는 보류한다.
      NSDecimalRound(&settlementAmount, &grossAmount, currency.amountFractionDigits, .down)
      guard abs(settlementAmount - inferredSettlement) <= minimumUnit else {
        return .failure(.settlementUnverified)
      }
      // 거래내역 단가는 Double로 기록하므로 Decimal 몫의 반올림은 반환액에 영향을 주지 않는다.
      let divisionResult = NSDecimalDivide(&price, &grossAmount, &decimalQuantity, .plain)
      guard (divisionResult == .noError || divisionResult == .lossOfPrecision),
            !price.isNaN else { return .failure(.settlementUnverified) }
    }
    // 거래내역의 단가는 기존 Double 저장 형식에 맞춘다.
    let settlementPrice = PortfolioCalculator.double(price)
    // 화면과 기존 거래내역이 사용할 확정 반환액이다.
    let amount = PortfolioCalculator.double(settlementAmount)
    guard settlementPrice.isFinite, amount.isFinite,
          PortfolioCalculator.decimal(amount) == settlementAmount else {
      return .failure(.invalidQuantity)
    }
    return .success(
      DelistingSettlementQuote(
        marketName: staticData.marketName,
        exchange: staticData.exchange,
        quantity: quantity,
        settlementPrice: settlementPrice,
        averageBuyPrice: staticData.averageBuyPrice,
        storedProfitLoss: storedProfitLoss,
        storedEvaluationPrice: storedEvaluationPrice,
        storedPriceSnapshot: priceSnapshot,
        buyAmount: staticData.buyAmount,
        costBasisKRW: staticData.costBasisKRW,
        executedAmount: amount,
        settlementAmount: settlementAmount,
        currency: currency
      )
    )
  }

  /// 거래지원 종료 종목을 검증된 마지막 평가 기준으로 전량 정산한다.
  static func executeDelistingSettlement(
    marketName: String,
    exchange: Exchange = ExchangeSelectionStore.currentExchange,
    executedAt: Date = Date(),
    btcKRWPrice: Double? = nil,
    expectedQuote: DelistingSettlementQuote? = nil
  ) -> Result<Execution, TradeOrderValidator.ValidationError> {
    do {
      return .success(try UserDataManager.performAtomicInvestmentUpdate {
        let pairID = ExchangeMarketCodeConverter.pairID(
          fromDisplayMarket: marketName,
          exchange: exchange
        )
        guard let holding = UserDataManager.userCryptoList?.first(where: {
          $0.staticData.exchangePairID == pairID
        }) else {
          throw TradeOrderValidator.ValidationError.insufficientHolding
        }

        if let expectedQuote {
          // 기준 재계산이 실패하는 변경도 확인창에 안내한 상태 변경으로 처리한다.
          guard holding.staticData.holdingQuantity == expectedQuote.quantity,
                holding.staticData.averageBuyPrice == expectedQuote.averageBuyPrice,
                holding.staticData.buyAmount == expectedQuote.buyAmount,
                holding.staticData.costBasisKRW == expectedQuote.costBasisKRW,
                holding.dynamicData.evaluationProfitLoss == expectedQuote.storedProfitLoss,
                holding.dynamicData.evaluationPrice == expectedQuote.storedEvaluationPrice,
                holding.dynamicData.settlementPriceSnapshot == expectedQuote.storedPriceSnapshot else {
            throw TradeOrderValidator.ValidationError.settlementChanged
          }
        }
        // 저장된 현재 상태로 정산 기준을 다시 계산한다.
        let quote = try delistingSettlementQuote(for: holding).get()
        // 확인창 이후 보유량이나 정산 기준이 달라지면 안내한 금액으로 재확인해야 한다.
        if let expectedQuote, quote != expectedQuote {
          throw TradeOrderValidator.ValidationError.settlementChanged
        }

        return try executeAskInTransaction(
          marketName: marketName,
          currentPrice: quote.settlementPrice,
          quantity: quote.quantity,
          exchange: exchange,
          executedAt: executedAt,
          btcKRWPrice: btcKRWPrice,
          delistingQuote: quote
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
    btcKRWPrice: Double?,
    delistingQuote: DelistingSettlementQuote?
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

    if delistingQuote != nil {
      // 거래가 끝난 종목은 최소 주문금액 미만이나 0원 가치라도 보유내역을 정리할 수 있어야 한다.
      guard currentPrice.isFinite, currentPrice >= 0 else { return .failure(.missingPrice) }
      guard quantity.isFinite, quantity > 0 else { return .failure(.invalidQuantity) }
      guard quantity <= crypto.staticData.holdingQuantity else { return .failure(.insufficientHolding) }
    } else {
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
    let executedAmount = delistingQuote?.executedAmount ?? PortfolioCalculator.executedAmount(
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
      executedAmount: executedAmount,
      recordType: delistingQuote == nil ? .userOrder : .delistingSettlement
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
      let newHoldingQuantity = calculateDifference(staticData.holdingQuantity, executedQuantity)
      let newBuyAmount = calculateProportionalAmount(
        staticData.buyAmount,
        quantity: newHoldingQuantity,
        totalQuantity: staticData.holdingQuantity
      )
      let newStaticData = CryptoTransactionDataModel.CryptoTransactionStaticData(
        exchange: staticData.exchange,
        marketName: staticData.marketName,
        cryptoName: staticData.cryptoName,
        holdingQuantity: newHoldingQuantity,
        averageBuyPrice: staticData.averageBuyPrice,
        buyAmount: newBuyAmount,
        costBasisKRW: originalCost - allocatedCost
      )

      MarketDataServiceUtil.shared.updateHoldingData(
        data: newStaticData,
        currentPrice: currentPrice
      )
    } else if let removeIndex = UserDataManager.userCryptoList?
      .firstIndex(where: { $0.staticData.exchangePairID == targetPairID }) {
      UserDataManager.userCryptoList?.remove(at: removeIndex)
    }

    // 종료 정산의 손익은 단가를 다시 곱하지 않고 확정된 반환액으로 계산한다.
    let pnl: Double
    if let delistingQuote {
      pnl = PortfolioCalculator.double(
        delistingQuote.settlementAmount
          - PortfolioCalculator.decimal(staticData.averageBuyPrice) * PortfolioCalculator.decimal(executedQuantity)
      )
    } else {
      pnl = PortfolioCalculator.realizedProfitLoss(
        entryPrice: staticData.averageBuyPrice,
        exitPrice: currentPrice,
        quantity: executedQuantity
      )
    }

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
      let availableBalance = calculateDifference(
        UserDataManager.userInformation(for: exchange)?.userAvailableBalance ?? 0,
        amount
      )
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
      let availableBalance = calculateSum(
        UserDataManager.userInformation(for: exchange)?.userAvailableBalance ?? 0,
        amount
      )
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
    let remainingQuantity = calculateDifference(staticData.holdingQuantity, amount)

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
      buyAmount: calculateProportionalAmount(
        staticData.buyAmount,
        quantity: remainingQuantity,
        totalQuantity: staticData.holdingQuantity
      ),
      costBasisKRW: PortfolioCalculator.costBasisKRW(of: staticData).map {
        $0 * PortfolioCalculator.decimal(remainingQuantity) / PortfolioCalculator.decimal(staticData.holdingQuantity)
      }
    )

    MarketDataServiceUtil.shared.updateHoldingData(
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
    // 0 BTC 반환은 보유 항목이나 매수 기록을 만들지 않는다.
    guard amount != 0 else { return previousQuantity }
    let newQuantity = calculateSum(previousQuantity, amount)
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
      buyAmount: calculateProduct(newQuantity, newAveragePrice),
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
      MarketDataServiceUtil.shared.updateHoldingData(
        data: updatedStaticData,
        currentPrice: btcKRWPrice
      )
    }

    return newQuantity
  }

  private static func calculateSum(_ lhs: Double, _ rhs: Double) -> Double {
    guard lhs.isFinite, rhs.isFinite else { return lhs + rhs }
    // 십진수 범위를 벗어나면 기존 숫자 연산의 오류 흐름을 유지한다.
    let result = PortfolioCalculator.decimal(lhs) + PortfolioCalculator.decimal(rhs)
    return result.isNaN ? lhs + rhs : PortfolioCalculator.double(result)
  }

  private static func calculateDifference(_ lhs: Double, _ rhs: Double) -> Double {
    guard lhs.isFinite, rhs.isFinite else { return lhs - rhs }
    // 기존 잔고와 체결 수량의 소수 차이를 십진수로 계산한다.
    let result = PortfolioCalculator.decimal(lhs) - PortfolioCalculator.decimal(rhs)
    return result.isNaN ? lhs - rhs : PortfolioCalculator.double(result)
  }

  private static func calculateProduct(_ lhs: Double, _ rhs: Double) -> Double {
    guard lhs.isFinite, rhs.isFinite else { return lhs * rhs }
    // 결제 자산 원가 계산에서 중간 부동소수 오차를 줄인다.
    let left = PortfolioCalculator.decimal(lhs)
    let right = PortfolioCalculator.decimal(rhs)
    guard !left.isNaN, !right.isNaN,
          (-128...127).contains(left.exponent + right.exponent) else { return lhs * rhs }
    let result = left * right
    return result.isNaN ? lhs * rhs : PortfolioCalculator.double(result)
  }

  private static func calculateAveragePrice(amount: Double, quantity: Double) -> Double {
    guard amount.isFinite, quantity.isFinite, quantity != 0 else { return amount / quantity }
    // 기존 체결 금액과 수량의 비율을 저장 경계에서만 Double로 바꾼다.
    let decimalAmount = PortfolioCalculator.decimal(amount)
    let decimalQuantity = PortfolioCalculator.decimal(quantity)
    guard !decimalAmount.isNaN, !decimalQuantity.isNaN,
          (-128...127).contains(decimalAmount.exponent - decimalQuantity.exponent) else { return amount / quantity }
    let result = decimalAmount / decimalQuantity
    return result.isNaN ? amount / quantity : PortfolioCalculator.double(result)
  }

  private static func calculateProportionalAmount(
    _ amount: Double,
    quantity: Double,
    totalQuantity: Double
  ) -> Double {
    guard amount.isFinite, quantity.isFinite, totalQuantity.isFinite, totalQuantity != 0 else {
      return amount * quantity / totalQuantity
    }
    // 부분 매도 후 보유 수량에 비례하는 기존 매수 금액이다.
    let decimalAmount = PortfolioCalculator.decimal(amount)
    let decimalQuantity = PortfolioCalculator.decimal(quantity)
    let decimalTotal = PortfolioCalculator.decimal(totalQuantity)
    guard !decimalAmount.isNaN, !decimalQuantity.isNaN, !decimalTotal.isNaN,
          (-128...127).contains(decimalAmount.exponent + decimalQuantity.exponent) else {
      return amount * quantity / totalQuantity
    }
    // 지수 범위를 벗어나는 Decimal 중간값은 잘못된 큰 값으로 바뀔 수 있다.
    let product = decimalAmount * decimalQuantity
    guard !product.isNaN, (-128...127).contains(product.exponent - decimalTotal.exponent) else {
      return amount * quantity / totalQuantity
    }
    let result = product / decimalTotal
    return result.isNaN ? amount * quantity / totalQuantity : PortfolioCalculator.double(result)
  }
}
