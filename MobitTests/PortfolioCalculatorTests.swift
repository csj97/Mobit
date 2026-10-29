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

  func testBTCExecutionUsesDecimalBeforeEightDigitFloor() {
    // 이진 곱셈 뒤 내림하면 0.00029999가 되던 체결 금액이다.
    let amount = PortfolioCalculator.executedAmount(price: 0.01, quantity: 0.03, currency: .btc)
    XCTAssertEqual(amount, 0.0003)
    XCTAssertEqual(PortfolioCalculator.executedAmount(price: 0.000001, quantity: 0.12345678, currency: .btc), 0.00000012)
    XCTAssertEqual(PortfolioCalculator.executedAmount(price: 333.33, quantity: 3, currency: .krw), 999)
    XCTAssertEqual(PortfolioCalculator.executedAmount(price: -1.123456789, quantity: 1, currency: .btc), -1.12345679)
  }

  func testHoldingCalculationsUseDecimalBeforeReturningDouble() {
    XCTAssertEqual(PortfolioCalculator.cumulativeHoldingQuantity(previousQuantity: 0.1, newQuantity: 0.2), 0.3)
    XCTAssertEqual(
      PortfolioCalculator.cumulativeBuyAmount(previousBuyAmount: 0.0001, price: 0.01, quantity: 0.03, currency: .btc),
      0.0004
    )
    XCTAssertEqual(
      PortfolioCalculator.weightedAverageBuyPrice(
        previousQuantity: 0.1,
        previousAveragePrice: 1,
        addedQuantity: 0.2,
        addedPrice: 1.75
      ),
      1.5
    )
  }

  func testValuationAndProfitUseDecimalBeforeRounding() {
    XCTAssertEqual(PortfolioCalculator.evaluationPrice(currentPrice: 0.01, holdingQuantity: 0.03), 0.0003)
    XCTAssertEqual(PortfolioCalculator.evaluationProfitLoss(currentPrice: 0.3, holdingQuantity: 3, averageBuyPrice: 0.1), 0.6)
    XCTAssertEqual(PortfolioCalculator.realizedProfitLoss(entryPrice: 0.1, exitPrice: 0.3, quantity: 3), 0.6)
    XCTAssertEqual(PortfolioCalculator.profitRate(currentPrice: 0.3, averageBuyPrice: 0.1), 200)
    XCTAssertEqual(PortfolioCalculator.profitRate(currentPrice: 0.1, averageBuyPrice: 0.3), -66.67)
    XCTAssertEqual(PortfolioCalculator.totalProfitRate(totalProfitLoss: 0.3, totalAssetValue: 0.1), 300)
    XCTAssertEqual(PortfolioCalculator.krwValue(amount: 0.1, currency: .btc, btcKRWPrice: 3), 0.3)
  }

  func testExecutionPreservesDoubleFallbackOutsideDecimalRange() {
    XCTAssertEqual(PortfolioCalculator.executedAmount(price: 1e150, quantity: 1, currency: .krw), 1e150)
    XCTAssertTrue(PortfolioCalculator.executedAmount(price: .infinity, quantity: 1, currency: .krw).isInfinite)
  }

  func testExtremeExponentsFallBackToDoubleArithmetic() {
    // Foundation Decimal 곱셈의 지수 범위를 벗어나는 작은 값이다.
    let small = 1e-100
    XCTAssertEqual(PortfolioCalculator.evaluationPrice(currentPrice: small, holdingQuantity: small), 0)
    XCTAssertEqual(PortfolioCalculator.executedAmount(price: small, quantity: small), 0)
    XCTAssertEqual(PortfolioCalculator.evaluationProfitLoss(currentPrice: small, holdingQuantity: small, averageBuyPrice: 0), small * small)
    XCTAssertEqual(PortfolioCalculator.realizedProfitLoss(entryPrice: 0, exitPrice: small, quantity: small), small * small)
    XCTAssertEqual(PortfolioCalculator.krwValue(amount: small, currency: .btc, btcKRWPrice: small), small * small)
    XCTAssertEqual(
      PortfolioCalculator.weightedAverageBuyPrice(previousQuantity: small, previousAveragePrice: small, addedQuantity: 0, addedPrice: 0),
      small * small / small
    )
    // 거래 수량보다 충분히 작은 경계에서도 십진수 계산은 그대로 사용한다.
    XCTAssertEqual(PortfolioCalculator.krwValue(amount: 1e-20, currency: .btc, btcKRWPrice: 1e-20), 1e-40)
    // 원화 환산 결과를 Decimal로 표현하지 못하면 잘못된 큰 숫자 대신 표시하지 않는다.
    let crypto = makeCrypto(evaluationPrice: small, evaluationProfitLoss: 0, buyAmount: 0, marketName: "ETH/BTC", costBasisKRW: 1)
    XCTAssertNil(PortfolioCalculator.valuation(of: crypto, btcKRWPrice: small).evaluationKRW)
  }

  func testDecimalResultsConvertToNearestDoubleAtStorageBoundary() throws {
    // 가중평균처럼 반복 소수가 되는 십진수 결과다.
    let value = try XCTUnwrap(Decimal(string: "3.05")) / XCTUnwrap(Decimal(string: "0.3"))
    XCTAssertEqual(PortfolioCalculator.double(value), 10.166666666666666)
    XCTAssertEqual(PortfolioCalculator.double(-value), -10.166666666666666)
    XCTAssertEqual(PortfolioCalculator.double(0), 0)
    XCTAssertEqual(PortfolioCalculator.double(try XCTUnwrap(Decimal(string: "1e127"))), 1e127)
    XCTAssertTrue(PortfolioCalculator.double(.nan).isNaN)
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

  func testLargeDecimalCostAndTotalsPreserveSingleWon() throws {
    // Double로 바꾸면 1원이 손실되는 저장 원가다.
    let largeCost = try XCTUnwrap(Decimal(string: "9007199254740993"))
    // 합산 후에는 Double로도 정확히 표현 가능한 값을 만든다.
    let holdings = [
      makeCrypto(evaluationPrice: 10, evaluationProfitLoss: 0, buyAmount: 0, costBasisKRW: largeCost),
      makeCrypto(evaluationPrice: 1, evaluationProfitLoss: 0, buyAmount: 0, marketName: "ETH/KRW", costBasisKRW: 1)
    ]
    XCTAssertEqual(PortfolioCalculator.valuation(of: holdings[0], btcKRWPrice: nil).costBasisKRW, largeCost)
    XCTAssertEqual(PortfolioCalculator.totalBuyAmountDecimal(cryptos: holdings, btcKRWPrice: nil), largeCost + 1)
    XCTAssertEqual(PortfolioCalculator.totalBuyAmount(cryptos: holdings, btcKRWPrice: nil), 9_007_199_254_740_994)

    // 실제 셀에서 단위와 접근성 설명까지 정확한 원가를 표시한다.
    let cell = try XCTUnwrap(UINib(nibName: "InvestmentTableViewCell", bundle: Bundle.main)
      .instantiate(withOwner: nil).first as? InvestmentTableViewCell)
    cell.configure(crypto: holdings[0], isLast: true)
    XCTAssertEqual(cell.cryptoBuyPrice.accessibilityLabel, "9,007,199,254,740,993 KRW")
  }

  @MainActor
  func testInvestmentSortPreservesSingleWonAndKeepsUnknownAndTiesStable() throws {
    // 서로 1원 차이의 원가는 Double에서 같은 값이 된다.
    let largerCost = try XCTUnwrap(Decimal(string: "9007199254740993"))
    // 두 자산의 같은 평가금액에서 원가 차이가 손익 차이가 된다.
    let smallerCost = largerCost - 1
    // 투자 목록 정렬만 검증하고 화면을 로드하지 않는다.
    let reactor = InvestReactor(mainUseCase: MainUseCase(mainRepository: MainRepository()))
    // 각 항목의 마켓 이름으로 정렬 결과를 확인한다.
    let controller = InvestmentViewController(reactor: reactor)
    // 지원하지 않는 결제 통화의 환율은 없으므로 평가손익이 nil이다.
    let holdings = [
      makeCrypto(evaluationPrice: 10, evaluationProfitLoss: 0, buyAmount: 0, marketName: "A/KRW", costBasisKRW: largerCost),
      makeCrypto(evaluationPrice: 10, evaluationProfitLoss: 0, buyAmount: 0, marketName: "B/KRW", costBasisKRW: smallerCost),
      makeCrypto(evaluationPrice: 10, evaluationProfitLoss: 0, buyAmount: 0, marketName: "C/KRW", costBasisKRW: smallerCost),
      makeCrypto(evaluationPrice: 10, evaluationProfitLoss: 0, buyAmount: 0, marketName: "D/USDT", costBasisKRW: 1),
      makeCrypto(evaluationPrice: 10, evaluationProfitLoss: 0, buyAmount: 0, marketName: "E/USDT", costBasisKRW: 1)
    ]
    XCTAssertEqual(
      controller.sortCryptos(sortType: .evalProfitLossHighToLow, cryptos: holdings).map { $0.staticData.marketName },
      ["B/KRW", "C/KRW", "A/KRW", "D/USDT", "E/USDT"]
    )
    XCTAssertEqual(
      controller.sortCryptos(sortType: .evalProfitLossLowToHigh, cryptos: holdings).map { $0.staticData.marketName },
      ["A/KRW", "B/KRW", "C/KRW", "D/USDT", "E/USDT"]
    )
    XCTAssertEqual(
      controller.sortCryptos(sortType: .evalPriceHighToLow, cryptos: holdings).map { $0.staticData.marketName },
      ["A/KRW", "B/KRW", "C/KRW", "D/USDT", "E/USDT"]
    )
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
      XCTAssertEqual(cell.cryptoName.text, crypto.staticData.cryptoName)
      XCTAssertEqual(cell.marketSymbolLabel.text, "ETH/BTC")
      XCTAssertEqual(cell.cryptoBuyPrice.accessibilityLabel, "5,000,000 KRW")
      XCTAssertEqual(cell.cryptoEvalPrice.accessibilityLabel, "6,000,000 KRW")
      XCTAssertEqual(cell.cryptoEvalLoss.text, "+1,000,000")
      XCTAssertEqual(cell.cryptoProfitRate.text, "+20%")
      XCTAssertEqual(cell.cryptoAveragePrice.accessibilityLabel, "0.05 BTC")
    }

    let legacyCrypto = makeCrypto(
      evaluationPrice: 6_000_000,
      evaluationProfitLoss: 0,
      buyAmount: 4_000_000,
      marketName: "ETH/BTC"
    )
    cell.configure(crypto: legacyCrypto, isLast: false)
    XCTAssertEqual(cell.cryptoBuyPrice.accessibilityLabel, "— KRW")
    XCTAssertEqual(cell.cryptoEvalPrice.accessibilityLabel, "6,000,000 KRW")
    XCTAssertEqual(cell.cryptoProfitRate.text, "—")
  }

  func testUnsupportedInvestmentCellShowsOpaqueStatusDesign() throws {
    func descendants(of view: UIView) -> [UIView] {
      view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
    let cell = try XCTUnwrap(UINib(nibName: "InvestmentTableViewCell", bundle: Bundle.main)
      .instantiate(withOwner: nil).first as? InvestmentTableViewCell)
    let crypto = makeCrypto(
      evaluationPrice: 5_340,
      evaluationProfitLoss: 340,
      buyAmount: 5_000,
      marketName: "GEOD/KRW",
      costBasisKRW: 5_000
    )

    cell.frame = CGRect(x: 0, y: 0, width: 390, height: 1)
    cell.configure(crypto: crypto, isLast: true, isTradingUnsupported: false)
    let normalHeight = cell.contentView.systemLayoutSizeFitting(
      CGSize(width: 390, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height

    cell.configure(crypto: crypto, isLast: true, isTradingUnsupported: true)
    let unsupportedHeight = cell.contentView.systemLayoutSizeFitting(
      CGSize(width: 390, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height

    let badge = try XCTUnwrap(
      descendants(of: cell.bgView).first { $0.accessibilityLabel == FuturesText.text("investment_unsupported_badge") }
    )
    let notice = try XCTUnwrap(
      descendants(of: cell.bgView).first { $0.accessibilityLabel == FuturesText.text("investment_unsupported_notice") }
    )
    XCTAssertFalse(badge.isHidden)
    XCTAssertFalse(notice.isHidden)
    XCTAssertGreaterThan(unsupportedHeight, normalHeight)

    for style in [UIUserInterfaceStyle.light, .dark] {
      let traits = UITraitCollection(userInterfaceStyle: style)
      XCTAssertEqual(badge.backgroundColor?.resolvedColor(with: traits).cgColor.alpha, 1)
      XCTAssertEqual(notice.backgroundColor?.resolvedColor(with: traits).cgColor.alpha, 1)
    }

    cell.prepareForReuse()
    XCTAssertTrue(badge.isHidden)
    XCTAssertTrue(notice.isHidden)
    cell.configure(crypto: crypto, isLast: false)
    XCTAssertTrue(badge.isHidden)
    XCTAssertTrue(notice.isHidden)
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
    XCTAssertEqual(cell.tradeTotalPrice.text, "600,000 원")
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
    history.costBasisKRW = 3_000_000

    cell.configure(pnlHistory: history)

    XCTAssertEqual(cell.marketNameLabel.text, "ETH/BTC")
    XCTAssertEqual(cell.pnlLabel.accessibilityLabel, "+1,500,000 " + FuturesText.text("currency_krw_unit"))
    XCTAssertEqual(cell.roiLabel.accessibilityLabel, "+50%")
    XCTAssertTrue(cell.positionBadgeView.isHidden)
    XCTAssertTrue(cell.statusLabel.isHidden)
    XCTAssertTrue(cell.marginView.isHidden)
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

    cell.configure(pnlHistory: UserPNLHistoryModel(
      marketName: "BTC/KRW",
      entryPrice: 100,
      exitPrice: 110,
      transactionTimestamp: 1_700_000_000_000,
      orderQuantity: 1,
      pnl: 10
    ))
    cell.configure(pnlHistory: history)

    XCTAssertEqual(cell.pnlLabel.accessibilityLabel, "-")
    XCTAssertEqual(cell.roiLabel.accessibilityLabel, "-")
    XCTAssertEqual(cell.pnlLabel.textColor, UIColor.mobitColors(.textSecondary))
  }

  func testPNLCellShowsNativeSpotReturnWithoutKRWCostBasis() throws {
    // 원화 원가가 없는 기존 기록도 진입·종료 가격 기준 수익률을 표시한다.
    let cell = try XCTUnwrap(
      UINib(nibName: "PNLTableViewCell", bundle: Bundle.main)
        .instantiate(withOwner: nil).first as? PNLTableViewCell
    )
    // 저장된 현물 거래의 가격 수익률은 25%다.
    let history = UserPNLHistoryModel(
      marketName: "BTC/KRW",
      entryPrice: 100,
      exitPrice: 125,
      transactionTimestamp: 1_700_000_000_000,
      orderQuantity: 2,
      pnl: 50
    )

    cell.configure(pnlHistory: history)

    XCTAssertEqual(cell.pnlLabel.accessibilityLabel, "+50 " + FuturesText.text("currency_krw_unit"))
    XCTAssertEqual(cell.roiLabel.accessibilityLabel, "+25%")
    XCTAssertTrue(cell.marginView.isHidden)
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
