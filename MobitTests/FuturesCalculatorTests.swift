import XCTest
@testable import Mobit

final class FuturesCalculatorTests: XCTestCase {
  func testLeverageDeterminesQuantityWithoutMultiplyingPnLTwice() throws {
    for leverage in [1, 2, 5, 10] {
      for side in [FuturesSide.long, .short] {
        let position = try FuturesCalculator.open(futuresOrder(side: side, leverage: leverage))
        let value = try FuturesCalculator.evaluate(position, markPrice: 101)
        XCTAssertEqual(position.quantity, Decimal(leverage))
        XCTAssertEqual(value.tradingPnL, Decimal(side == .long ? leverage : -leverage))
        XCTAssertEqual(value.roePercent, value.tradingPnL)
      }
    }
  }

  func testLiquidationBoundaryUsesEquityForBothDirections() throws {
    for side in [FuturesSide.long, .short] {
      let position = try FuturesCalculator.open(futuresOrder(side: side))
      let boundary: Decimal = side == .long ? 90 : 110
      let safe = boundary + (side == .long ? Decimal(string: "0.01")! : Decimal(string: "-0.01")!)
      XCTAssertFalse(try FuturesCalculator.evaluate(position, markPrice: safe).shouldLiquidate)
      XCTAssertTrue(try FuturesCalculator.evaluate(position, markPrice: boundary).shouldLiquidate)
      XCTAssertEqual(try FuturesCalculator.estimatedLiquidationPrice(position), boundary)
      XCTAssertThrowsError(try FuturesCalculator.liquidationQuote(position, markPrice: 100))
      XCTAssertEqual(try FuturesCalculator.liquidationQuote(position, markPrice: boundary).realizedPnL, -100)
    }
    XCTAssertNil(try FuturesCalculator.estimatedLiquidationPrice(FuturesCalculator.open(futuresOrder(leverage: 1))))
  }

  func testRoundingKeepsReservedMarginAndNeverIncreasesNotional() throws {
    let position = try FuturesCalculator.open(futuresOrder(margin: 10, leverage: 2, price: 3, step: Decimal(string: "0.1")!))
    XCTAssertEqual(position.quantity, Decimal(string: "6.6"))
    XCTAssertEqual(position.entryNotional, Decimal(string: "19.8"))
    XCTAssertEqual(position.order.margin, 10)
    let repeating = try FuturesCalculator.open(futuresOrder(margin: 1, leverage: 1, price: 3, step: Decimal(string: "0.001")!, minimumQuantity: Decimal(string: "0.001")!))
    XCTAssertEqual(repeating.quantity, Decimal(string: "0.333"))
    XCTAssertLessThanOrEqual(repeating.entryNotional, 1)
  }

  func testFeesFundingAndSettlementReconcile() throws {
    let position = try FuturesCalculator.open(futuresOrder(fee: Decimal(string: "0.001")!))
    XCTAssertEqual(position.entryFee, 1)
    let value = try FuturesCalculator.evaluate(position, markPrice: 101, netFunding: -2)
    XCTAssertEqual(value.collateral, 97)
    XCTAssertEqual(value.netPnL, 7)
    XCTAssertEqual(try FuturesCalculator.estimatedLiquidationPrice(position, netFunding: -2), Decimal(string: "90.3"))
    let quote = try FuturesCalculator.closingQuote(position, executionPrice: 101, exitFeeRate: Decimal(string: "0.001")!, netFunding: -2)
    XCTAssertEqual(quote.returnedMargin, Decimal(string: "105.99"))
    XCTAssertEqual(quote.realizedPnL, Decimal(string: "5.99"))
    XCTAssertTrue(try FuturesCalculator.evaluate(position, markPrice: 100, netFunding: -99).shouldLiquidate)
  }

  func testFundingUsesActualNotionalAndSignedRate() throws {
    for side in [FuturesSide.long, .short] {
      let position = try FuturesCalculator.open(futuresOrder(side: side))
      let sign: Decimal = side == .long ? -1 : 1
      XCTAssertEqual(try FuturesCalculator.fundingPayment(position, markPrice: 110, rate: Decimal(string: "0.001")!), sign * Decimal(string: "1.1")!)
      XCTAssertEqual(try FuturesCalculator.fundingPayment(position, markPrice: 110, rate: Decimal(string: "-0.001")!), -sign * Decimal(string: "1.1")!)
      XCTAssertEqual(try FuturesCalculator.fundingPayment(position, markPrice: 110, rate: 0), 0)
    }
  }

  func testGapLossAndExitFeeNeverDebitOtherCollateral() throws {
    let position = try FuturesCalculator.open(futuresOrder())
    let gap = try FuturesCalculator.liquidationQuote(position, markPrice: 80)
    XCTAssertEqual(gap.absorbedLoss, 100)
    XCTAssertEqual(gap.returnedMargin, 0)
    XCTAssertEqual(gap.realizedPnL, -100)
    let close = try FuturesCalculator.closingQuote(position, executionPrice: Decimal(string: "90.01")!, exitFeeRate: Decimal(string: "0.01")!)
    XCTAssertGreaterThan(close.requestedExitFee, close.chargedExitFee)
    XCTAssertEqual(close.chargedExitFee, Decimal(string: "0.1"))
    for quote in [gap, close] {
      XCTAssertEqual(quote.returnedMargin, 100 + quote.tradingPnL + quote.netFunding - quote.entryFee - quote.chargedExitFee + quote.absorbedLoss)
      XCTAssertEqual(quote.realizedPnL, quote.returnedMargin - 100)
    }
  }

  func testInvalidNumbersLeverageAndContractAreRejected() throws {
    for number in [Decimal(0), -1, .nan] {
      XCTAssertThrowsError(try FuturesCalculator.open(futuresOrder(margin: number)))
      XCTAssertThrowsError(try FuturesCalculator.open(futuresOrder(price: number)))
      XCTAssertThrowsError(try FuturesCalculator.open(futuresOrder(step: number)))
    }
    for leverage in [-1, 0, 101] {
      XCTAssertThrowsError(try FuturesCalculator.open(futuresOrder(leverage: leverage)))
    }
    for fee in [Decimal(-1), 1, .nan] {
      XCTAssertThrowsError(try FuturesCalculator.open(futuresOrder(fee: fee)))
    }
    XCTAssertThrowsError(try FuturesCalculator.open(futuresOrder(fee: Decimal(string: "0.1")!)))
    XCTAssertThrowsError(try FuturesCalculator.open(futuresOrder(margin: 1, leverage: 1, step: 1)))
    XCTAssertThrowsError(try FuturesCalculator.open(futuresOrder(minimumQuantity: 11)))
    XCTAssertThrowsError(try FuturesCalculator.open(futuresOrder(minimumNotional: 1001)))
    XCTAssertThrowsError(try FuturesCalculator.open(futuresOrder(date: Date(timeIntervalSince1970: .nan))))
    XCTAssertThrowsError(try FuturesCalculator.open(futuresOrder(date: Date(timeIntervalSince1970: -1))))
    let position = try FuturesCalculator.open(futuresOrder())
    XCTAssertThrowsError(try FuturesCalculator.evaluate(position, markPrice: 0))
    XCTAssertThrowsError(try FuturesCalculator.evaluate(position, markPrice: 100, netFunding: .nan))
    XCTAssertThrowsError(try FuturesCalculator.closingQuote(position, executionPrice: 100, exitFeeRate: 0, netFunding: .nan))
    XCTAssertThrowsError(try FuturesCalculator.fundingPayment(position, markPrice: 100, rate: .nan))
  }

  func testDomesticKRWLongAndShortUseExecutionLeverage() throws {
    for exchange in [Exchange.upbit, .bithumb] {
      for side in [FuturesSide.long, .short] {
        let position = try FuturesCalculator.open(domesticFuturesOrder(exchange: exchange, side: side))
        XCTAssertEqual(position.quantity, Decimal(string: "0.01"))
        XCTAssertEqual(position.leverageAtExecution, 10)
        XCTAssertEqual(try FuturesCalculator.estimatedLiquidationPrice(position), side == .long ? 90_000_000 : 110_000_000)
        let profitablePrice: Decimal = side == .long ? 110_000_000 : 90_000_000
        let valuation = try FuturesCalculator.evaluate(position, markPrice: profitablePrice)
        XCTAssertEqual(valuation.tradingPnL, 100_000)
        XCTAssertEqual(valuation.roePercent, 100)
        XCTAssertFalse(valuation.shouldLiquidate)
        XCTAssertTrue(try FuturesCalculator.evaluate(position, markPrice: side == .long ? 90_000_000 : 110_000_000).shouldLiquidate)
        XCTAssertThrowsError(try FuturesCalculator.evaluate(position, markPrice: profitablePrice, netFunding: 1))
        XCTAssertThrowsError(try FuturesCalculator.fundingPayment(position, markPrice: profitablePrice, rate: Decimal(string: "0.001")!))
      }
    }
  }

  func testDomesticKRWOnlyAndSymbolLeverageLimits() throws {
    let groups: [(Int, [String])] = [(100, ["BTC", "ETH"]),
      (50, ["SOL", "XRP", "ADA", "AVAX", "NEAR", "SUI", "DOGE", "SHIB", "LINK", "UNI", "AAVE", "RNDR"]),
      (20, ["ETC", "OTHER", "RENDER"])]
    for exchange in [Exchange.upbit, .bithumb] {
      for (maximum, symbols) in groups {
        for symbol in symbols {
          XCTAssertNoThrow(try FuturesCalculator.open(domesticFuturesOrder(exchange: exchange, symbol: "KRW-" + symbol, leverage: maximum)))
          XCTAssertThrowsError(try FuturesCalculator.open(domesticFuturesOrder(exchange: exchange, symbol: "KRW-" + symbol, leverage: maximum + 1)))
        }
      }
      XCTAssertThrowsError(try FuturesCalculator.open(domesticFuturesOrder(exchange: exchange, currency: .btc, symbol: "BTC-ETH")))
      XCTAssertThrowsError(try FuturesCalculator.open(domesticFuturesOrder(exchange: exchange, fee: Decimal(string: "0.001")!)))
      let position = try FuturesCalculator.open(domesticFuturesOrder(exchange: exchange))
      XCTAssertThrowsError(try FuturesCalculator.closingQuote(position, executionPrice: 100_000_000, exitFeeRate: Decimal(string: "0.001")!))
    }
    for symbol in ["BTCUSDT", "KRW-", "KRW-BTC-ETH", "KRW-btc", "KRW-KRW", "BTC-ETH"] {
      XCTAssertThrowsError(try FuturesCalculator.open(domesticFuturesOrder(symbol: symbol)))
    }
  }

  func testArithmeticOverflowUnderflowAndZeroDivisionThrow() throws {
    let huge = try XCTUnwrap(Decimal(string: "1e127"))
    let tiny = try XCTUnwrap(Decimal(string: "1e-128"))
    XCTAssertThrowsError(try FuturesDecimal.multiply(huge, huge))
    XCTAssertThrowsError(try FuturesDecimal.multiply(tiny, tiny))
    XCTAssertThrowsError(try FuturesDecimal.divide(tiny, huge))
    XCTAssertEqual(try FuturesDecimal.multiply(tiny, 0), 0)
    XCTAssertThrowsError(try FuturesDecimal.divide(1, 0))
    XCTAssertThrowsError(try FuturesDecimal.add(1, .nan))
    XCTAssertNoThrow(try FuturesDecimal.divide(1, 3))
  }

  func testPositionRoundTripRequiresExecutionLeverageAndValidQuantity() throws {
    let position = try FuturesCalculator.open(futuresOrder(leverage: 7))
    let bytes = try JSONEncoder().encode(position)
    let restored = try JSONDecoder().decode(FuturesPosition.self, from: bytes)
    XCTAssertEqual(restored, position)
    XCTAssertEqual(restored.leverageAtExecution, 7)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    var order = try XCTUnwrap(object["order"] as? [String: Any])
    order["leverage"] = NSNull()
    object["order"] = order
    XCTAssertThrowsError(try JSONDecoder().decode(FuturesPosition.self, from: JSONSerialization.data(withJSONObject: object)))
    let tampered = FuturesPosition(order: position.order, quantity: 1000, entryNotional: position.entryNotional,
                                   entryFee: position.entryFee, ruleVersion: .simpleMarginV1)
    XCTAssertThrowsError(try FuturesCalculator.validate(tampered))
  }
}

func futuresOrder(id: UUID = UUID(), side: FuturesSide = .long, margin: Decimal = 100, leverage: Int = 10,
                  price: Decimal = 100, fee: Decimal = 0, step: Decimal = 1,
                  minimumQuantity: Decimal = 1, minimumNotional: Decimal = 0,
                  date: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> FuturesOpeningOrder {
  FuturesOpeningOrder(requestID: id, account: .init(exchange: .binance, product: .perpetual, currency: .usdt),
                      instrument: .init(exchange: .binance, product: .perpetual, rawSymbol: "BTCUSDT", settlementCurrency: .usdt),
                      side: side, margin: margin, leverage: leverage, executionPrice: price, entryFeeRate: fee,
                      executedAt: date, contractRules: .init(maximumLeverage: 100, quantityStep: step,
                                                           minimumQuantity: minimumQuantity, minimumNotional: minimumNotional))
}

func domesticFuturesOrder(exchange: Exchange = .upbit, currency: TradingCurrency = .krw,
                          symbol: String = "KRW-BTC", side: FuturesSide = .long, leverage: Int = 10, fee: Decimal = 0,
                          margin: Decimal = 100_000, price: Decimal = 100_000_000,
                          date: Date = Date(timeIntervalSince1970: 60)) -> FuturesOpeningOrder {
  FuturesOpeningOrder(requestID: UUID(), account: .init(exchange: exchange, product: .perpetual, currency: currency),
    instrument: .init(exchange: exchange, product: .perpetual, rawSymbol: symbol, settlementCurrency: currency),
    side: side, margin: margin, leverage: leverage, executionPrice: price, entryFeeRate: fee, executedAt: date,
    contractRules: .init(maximumLeverage: 1000, quantityStep: Decimal(string: "0.00000001")!,
                        minimumQuantity: Decimal(string: "0.00000001")!, minimumNotional: 0))
}
