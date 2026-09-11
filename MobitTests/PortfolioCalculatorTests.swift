//
//  PortfolioCalculatorTests.swift
//  MobitTests
//
//  Created by Codex on 6/29/26.
//

import XCTest
import UIKit
@testable import Mobit

final class PortfolioCalculatorTests: XCTestCase {
  func testExecutedAmountFloorsFractionalValue() {
    let amount = PortfolioCalculator.executedAmount(price: 12.34, quantity: 3.2)

    XCTAssertEqual(amount, 39)
  }

  func testProfitRateTruncatesToTwoDigits() {
    let rate = PortfolioCalculator.profitRate(
      currentPrice: 123,
      averageBuyPrice: 100
    )

    XCTAssertEqual(rate, 23)
  }

  func testProfitRateReturnsZeroWhenAverageBuyPriceIsZero() {
    let rate = PortfolioCalculator.profitRate(
      currentPrice: 123,
      averageBuyPrice: 0
    )

    XCTAssertEqual(rate, 0)
  }

  func testEvaluationValues() {
    let evaluationPrice = PortfolioCalculator.evaluationPrice(
      currentPrice: 11.123456789,
      holdingQuantity: 2
    )
    let profitLoss = PortfolioCalculator.evaluationProfitLoss(
      currentPrice: 120,
      holdingQuantity: 3,
      averageBuyPrice: 100
    )

    XCTAssertEqual(evaluationPrice, 22.24691357)
    XCTAssertEqual(profitLoss, 60)
  }

  func testPortfolioTotals() {
    let cryptos = [
      makeCrypto(evaluationPrice: 1_200, evaluationProfitLoss: 200, buyAmount: 1_000),
      makeCrypto(evaluationPrice: 500, evaluationProfitLoss: -100, buyAmount: 600)
    ]

    let totalAsset = PortfolioCalculator.totalAssetValue(
      availableBalance: 300,
      cryptos: cryptos,
      btcKRWPrice: nil
    )
    let totalProfitLoss = PortfolioCalculator.totalEvaluationProfitLoss(
      cryptos: cryptos,
      btcKRWPrice: nil
    )
    let totalEvaluationPrice = PortfolioCalculator.totalEvaluationPrice(
      cryptos: cryptos,
      btcKRWPrice: nil
    )
    let totalBuyAmount = PortfolioCalculator.totalBuyAmount(
      cryptos: cryptos,
      btcKRWPrice: nil
    )
    let totalProfitRate = PortfolioCalculator.totalProfitRate(
      totalProfitLoss: totalProfitLoss ?? 0,
      totalAssetValue: totalAsset ?? 0
    )

    // 원화 마켓만 있으면 환산 시세가 없어도 기존과 동일하게 합산된다.
    XCTAssertEqual(totalAsset, 2_000)
    XCTAssertEqual(totalProfitLoss, 100)
    XCTAssertEqual(totalEvaluationPrice, 1_700)
    XCTAssertEqual(totalBuyAmount, 1_600)
    XCTAssertEqual(totalProfitRate, 5)
  }

  func testPortfolioTotalsConvertBTCMarketHoldingToKRW() {
    let cryptos = [
      makeCrypto(evaluationPrice: 1_000_000, evaluationProfitLoss: 200_000, buyAmount: 800_000),
      makeCrypto(
        evaluationPrice: 0.035,
        evaluationProfitLoss: 0.0035,
        buyAmount: 0.0315,
        marketName: "ETH/BTC",
        costBasisKRW: 3_150_000
      )
    ]

    let totalAsset = PortfolioCalculator.totalAssetValue(
      availableBalance: 500_000,
      cryptos: cryptos,
      btcKRWPrice: 100_000_000
    )
    let totalProfitLoss = PortfolioCalculator.totalEvaluationProfitLoss(
      cryptos: cryptos,
      btcKRWPrice: 100_000_000
    )
    let totalBuyAmount = PortfolioCalculator.totalBuyAmount(
      cryptos: cryptos,
      btcKRWPrice: 100_000_000
    )

    XCTAssertEqual(try XCTUnwrap(totalAsset), 500_000 + 1_000_000 + 3_500_000, accuracy: 1)
    XCTAssertEqual(try XCTUnwrap(totalProfitLoss), 200_000 + 350_000, accuracy: 1)
    XCTAssertEqual(try XCTUnwrap(totalBuyAmount), 800_000 + 3_150_000, accuracy: 1)
  }

  func testPortfolioTotalsReturnNilWhenBTCRateIsMissing() {
    let cryptos = [
      makeCrypto(evaluationPrice: 1_000_000, evaluationProfitLoss: 0, buyAmount: 1_000_000),
      makeCrypto(
        evaluationPrice: 0.035,
        evaluationProfitLoss: 0,
        buyAmount: 0.0315,
        marketName: "ETH/BTC",
        costBasisKRW: 3_150_000
      )
    ]

    // 평가금액은 환산 불가지만 저장된 원화 원가는 BTC/KRW 시세 없이도 유지된다.
    XCTAssertNil(
      PortfolioCalculator.totalAssetValue(
        availableBalance: 0,
        cryptos: cryptos,
        btcKRWPrice: nil
      )
    )
    XCTAssertEqual(
      PortfolioCalculator.totalBuyAmount(cryptos: cryptos, btcKRWPrice: nil),
      4_150_000
    )
  }

  func testKRWValueLeavesKRWAmountUntouched() {
    XCTAssertEqual(
      PortfolioCalculator.krwValue(amount: 1_234, currency: .krw, btcKRWPrice: nil),
      1_234
    )
    XCTAssertEqual(
      PortfolioCalculator.krwValue(amount: 0.5, currency: .btc, btcKRWPrice: 100_000_000),
      50_000_000
    )
    XCTAssertNil(
      PortfolioCalculator.krwValue(amount: 0.5, currency: .btc, btcKRWPrice: 0)
    )
  }

  func testFixedCostDoesNotChangeWhenOnlyBTCRateChanges() throws {
    let crypto = makeCrypto(evaluationPrice: 0.05, evaluationProfitLoss: 0,
                            buyAmount: 0.05, marketName: "ETH/BTC", costBasisKRW: 5_000_000)
    let valued = PortfolioCalculator.valuation(of: crypto, btcKRWPrice: 120_000_000)
    XCTAssertEqual(valued.costBasisKRW, 5_000_000)
    XCTAssertEqual(valued.evaluationKRW, 6_000_000)
    XCTAssertEqual(valued.profitLossKRW, 1_000_000)
    XCTAssertEqual(valued.profitRate, 20)
    let missingRate = PortfolioCalculator.valuation(of: crypto, btcKRWPrice: nil)
    XCTAssertEqual(missingRate.costBasisKRW, 5_000_000)
    XCTAssertNil(missingRate.evaluationKRW)
    XCTAssertNil(missingRate.profitLossKRW)
  }

  func testLegacyBTCHoldingKeepsLegacyKRWDisplayValueUntilSettlement() throws {
    let crypto = makeCrypto(evaluationPrice: 0.05, evaluationProfitLoss: 0,
                            buyAmount: 0.05, marketName: "ETH/BTC")
    let decoded = try JSONDecoder().decode(CryptoTransactionDataModel.self, from: JSONEncoder().encode(crypto))
    let value = PortfolioCalculator.valuation(of: decoded, btcKRWPrice: 120_000_000)
    XCTAssertNil(value.costBasisKRW)
    XCTAssertNil(value.profitLossKRW)
    XCTAssertEqual(value.evaluationKRW, 0.05)
    XCTAssertNil(PortfolioCalculator.totalBuyAmount(cryptos: [decoded], btcKRWPrice: 120_000_000))
  }

  func testFutureUSDTValuationNeedsExplicitRateAndDoesNotFallbackToKRW() {
    let crypto = makeCrypto(evaluationPrice: 2_000, evaluationProfitLoss: 0,
                            buyAmount: 1_800, marketName: "ETH/USDT", costBasisKRW: 2_500_000)
    XCTAssertNil(PortfolioCalculator.valuation(of: crypto, btcKRWPrice: 120_000_000).evaluationKRW)
    let value = PortfolioCalculator.valuation(of: crypto, quoteKRWPrices: ["USDT": 1_400])
    XCTAssertEqual(value.evaluationKRW, 2_800_000)
    XCTAssertEqual(value.profitLossKRW, 300_000)
    XCTAssertEqual(value.profitRate, 12)
  }

  func testMixedHoldingsTotalsAndUnknownSorting() throws {
    let cryptos = [
      makeCrypto(evaluationPrice: 6_000_000, evaluationProfitLoss: 1_000_000, buyAmount: 5_000_000),
      makeCrypto(evaluationPrice: 6_000_000, evaluationProfitLoss: 2_000_000, buyAmount: 4_000_000, marketName: "ETH/KRW"),
      makeCrypto(evaluationPrice: 0.05, evaluationProfitLoss: 0, buyAmount: 0.05, marketName: "ETH/BTC", costBasisKRW: 5_000_000)
    ]
    XCTAssertEqual(PortfolioCalculator.totalAssetValue(availableBalance: 1_000_000, cryptos: cryptos, btcKRWPrice: 120_000_000), 19_000_000)
    XCTAssertEqual(PortfolioCalculator.totalBuyAmount(cryptos: cryptos, btcKRWPrice: nil), 14_000_000)
    XCTAssertEqual(PortfolioCalculator.totalEvaluationProfitLoss(cryptos: cryptos, btcKRWPrice: 120_000_000), 4_000_000)
    for ascending in [true, false] {
      XCTAssertTrue(PortfolioCalculator.orderedBefore(-1, nil, ascending: ascending))
      XCTAssertFalse(PortfolioCalculator.orderedBefore(nil, 0, ascending: ascending))
    }
  }

  func testInvestmentCellDisplaysFixedCostAndKRWProfit() throws {
    let cell = try XCTUnwrap(UINib(nibName: "InvestmentTableViewCell", bundle: Bundle.main)
      .instantiate(withOwner: nil).first as? InvestmentTableViewCell)
    var crypto = makeCrypto(evaluationPrice: 0.05, evaluationProfitLoss: 0,
                            buyAmount: 0.05, marketName: "ETH/BTC", costBasisKRW: 5_000_000)
    for exchange in [Exchange.upbit, .bithumb] {
      crypto.staticData.exchange = exchange
      AppDataManager.shared.updateBTCKRWPrice(120_000_000, for: exchange)
      cell.configure(crypto: crypto, isLast: true)
      XCTAssertEqual(cell.cryptoName.text, "ETH/BTC")
      XCTAssertEqual(cell.cryptoBuyPrice.text, "5,000,000")
      XCTAssertEqual(cell.cryptoEvalPrice.text, "6,000,000")
      XCTAssertEqual(cell.cryptoEvalLoss.text, "1,000,000")
      XCTAssertEqual(cell.cryptoProfitRate.text, "20 %")
      XCTAssertEqual(cell.cryptoAveragePrice.text, "0.05")
    }

    let legacyCrypto = makeCrypto(
      evaluationPrice: 6_000_000,
      evaluationProfitLoss: 0,
      buyAmount: 4_000_000,
      marketName: "ETH/BTC"
    )
    cell.configure(crypto: legacyCrypto, isLast: false)
    XCTAssertEqual(cell.cryptoBuyPrice.text, "-")
    XCTAssertEqual(cell.cryptoEvalPrice.text, "6,000,000")
    XCTAssertEqual(cell.cryptoProfitRate.text, "-")
  }

  func testTradeHoldingViewDisplaysBTCMarketAveragePriceInBTC() throws {
    let view = try XCTUnwrap(
      UINib(nibName: "TradeOrderView", bundle: Bundle.main)
        .instantiate(withOwner: nil).first as? TradeOrderView
    )
    let crypto = makeCrypto(
      evaluationPrice: 0.05,
      evaluationProfitLoss: 0,
      buyAmount: 0.05,
      marketName: "ETH/BTC",
      costBasisKRW: 5_000_000
    )

    AppDataManager.shared.updateBTCKRWPrice(120_000_000, for: .upbit)
    view.setInvestLiveData(data: crypto)

    XCTAssertEqual(view.cryptoAveragePrice.text, "0.05")
  }

  func testTradeHistoryCellDisplaysLegacySettlementInKRW() throws {
    let cell = try XCTUnwrap(
      UINib(nibName: "TradeHistoryTableViewCell", bundle: Bundle.main)
        .instantiate(withOwner: nil).first as? TradeHistoryTableViewCell
    )
    let transaction = TransactionInfo(
      marketName: "ETH/BTC",
      orderType: .ask,
      executedDate: "07.09 12:00",
      executedPrice: 0.00003,
      executedQuantity: 20_000_000_000,
      executedAmount: 600_000,
      recordType: .legacyBTCSettlement
    )

    cell.configure(marketName: "ETH/BTC", transactionInfo: transaction)

    XCTAssertEqual(cell.orderTypeLabel.text, "시스템 정산")
    XCTAssertEqual(cell.tradeCryptoPrice.text, "0.00003 BTC")
    XCTAssertEqual(cell.tradeTotalPrice.text, "600,000 KRW")
  }

  func testPNLCellDisplaysBTCMarketAndRealizedProfitInKRW() throws {
    let cell = try XCTUnwrap(
      UINib(nibName: "PNLTableViewCell", bundle: Bundle.main)
        .instantiate(withOwner: nil).first as? PNLTableViewCell
    )
    var history = UserPNLHistoryModel(
      exchange: .bithumb,
      marketName: "ETH/BTC",
      entryPrice: 0.04,
      exitPrice: 0.05,
      transactionTimestamp: 1_700_000_000_000,
      orderQuantity: 1,
      pnl: 0.01
    )
    history.realizedProfitLossKRW = 1_500_000

    cell.configure(pnlHistory: history)

    XCTAssertEqual(cell.marketNameLabel.text, "ETH/BTC")
    XCTAssertEqual(cell.pnlLabel.text, "1,500,000 원")
  }

  func testPNLCellDoesNotDisplayNativeBTCProfitWhenKRWProfitIsMissing() throws {
    let cell = try XCTUnwrap(
      UINib(nibName: "PNLTableViewCell", bundle: Bundle.main)
        .instantiate(withOwner: nil).first as? PNLTableViewCell
    )
    let history = UserPNLHistoryModel(
      marketName: "ETH/BTC",
      entryPrice: 0.04,
      exitPrice: 0.05,
      transactionTimestamp: 1_700_000_000_000,
      orderQuantity: 1,
      pnl: 0.01
    )

    cell.configure(pnlHistory: history)

    XCTAssertEqual(cell.pnlLabel.text, "-")
  }

  func testTradeInputsRemoveGroupingSeparatorsBeforeEditing() {
    let bidTextField = UITextField()
    bidTextField.text = "1,500,000"
    TradeBidView().textFieldDidBeginEditing(bidTextField)

    let askTextField = UITextField()
    askTextField.text = "1,500,000"
    TradeAskView().textFieldDidBeginEditing(askTextField)

    XCTAssertEqual(bidTextField.text, "1500000")
    XCTAssertEqual(askTextField.text, "1500000")
  }

  func testBTCKRWPriceExpiresAfterLiveQuoteWindow() {
    let receivedAt = Date(timeIntervalSince1970: 1_000)
    AppDataManager.shared.updateBTCKRWPrice(
      120_000_000,
      for: .upbit,
      updatedAt: receivedAt
    )

    XCTAssertFalse(
      AppDataManager.shared.needsBTCKRWPriceRefresh(
        for: .upbit,
        at: receivedAt.addingTimeInterval(AppDataManager.btcKRWPriceRefreshAge)
      )
    )

    XCTAssertEqual(
      AppDataManager.shared.btcKRWPrice(
        for: .upbit,
        at: receivedAt.addingTimeInterval(AppDataManager.btcKRWPriceMaxAge)
      ),
      120_000_000
    )
    XCTAssertTrue(
      AppDataManager.shared.needsBTCKRWPriceRefresh(
        for: .upbit,
        at: receivedAt.addingTimeInterval(AppDataManager.btcKRWPriceRefreshAge + 0.001)
      )
    )
    XCTAssertNil(
      AppDataManager.shared.btcKRWPrice(
        for: .upbit,
        at: receivedAt.addingTimeInterval(AppDataManager.btcKRWPriceMaxAge + 0.001)
      )
    )
    XCTAssertEqual(
      AppDataManager.shared.lastBTCKRWPrice(for: .upbit),
      120_000_000
    )
    XCTAssertNil(
      AppDataManager.shared.freshBTCKRWPrice(
        for: .upbit,
        at: receivedAt.addingTimeInterval(AppDataManager.btcKRWPriceRefreshAge + 0.001)
      )
    )
    AppDataManager.shared.invalidateBTCKRWPrice(for: .upbit)
  }

  private func makeCrypto(
    evaluationPrice: Double,
    evaluationProfitLoss: Double,
    buyAmount: Double,
    marketName: String = "BTC/KRW",
    costBasisKRW: Decimal? = nil
  ) -> CryptoTransactionDataModel {
    CryptoTransactionDataModel(
      staticData: .init(
        marketName: marketName,
        cryptoName: "비트코인",
        holdingQuantity: 1,
        averageBuyPrice: buyAmount,
        buyAmount: buyAmount,
        costBasisKRW: costBasisKRW
      ),
      dynamicData: .init(
        marketName: marketName,
        profitRate: 0,
        evaluationProfitLoss: evaluationProfitLoss,
        evaluationPrice: evaluationPrice
      )
    )
  }
}
