import XCTest
@testable import Mobit

final class TradingRulesTests: XCTestCase {
  func testAccountAvailabilityCoversEveryExchangeProductAndCurrency() {
    for exchange in Exchange.allCases {
      for product in [TradingProduct.spot, .perpetual] {
        for currency in [TradingCurrency.krw, .btc, .usdt] {
          // 모든 조합을 확인해 신규 거래소가 기존 국내 규칙을 묵시적으로 받지 않게 한다.
          let account = TradingAccountID(exchange: exchange, product: product, currency: currency)
          switch (exchange, product, currency) {
          case (.upbit, _, .krw), (.bithumb, _, .krw):
            XCTAssertEqual(account.availability, .available)
          case (.binance, .perpetual, .usdt), (.okx, .perpetual, .usdt):
            XCTAssertEqual(account.availability, .preparing)
          default:
            XCTAssertEqual(account.availability, .unsupported)
          }
          XCTAssertEqual(
            TradingRules.DomesticFutures.supports(account),
            (exchange == .upbit || exchange == .bithumb) && product == .perpetual && currency == .krw
          )
        }
      }
    }
  }

  func testBothDomesticExchangesShareExactLeverageAndContractRules() throws {
    // RNDR과 RENDER 등 유사한 심볼도 별개의 규칙으로 고정한다.
    let limits = [
      "BTC": 100, "ETH": 100,
      "SOL": 50, "XRP": 50, "ADA": 50, "AVAX": 50, "NEAR": 50, "SUI": 50,
      "DOGE": 50, "SHIB": 50, "LINK": 50, "UNI": 50, "AAVE": 50, "RNDR": 50,
      "RENDER": 20, "ETC": 20, "OTHER": 20
    ]
    for exchange in [Exchange.upbit, .bithumb] {
      for (symbol, maximum) in limits {
        // 실제 주문 도메인이 규약의 계약 조건을 그대로 참조하는지 확인한다.
        let instrument = domesticFuturesOrder(exchange: exchange, symbol: "KRW-" + symbol).instrument
        // UseCase가 생성하는 수량 단위와 최소 주문금액이다.
        let contract = try XCTUnwrap(TradingRules.DomesticFutures.contractRules(for: instrument))
        XCTAssertEqual(instrument.maximumPaperLeverage, maximum)
        XCTAssertEqual(contract.maximumLeverage, maximum)
        XCTAssertEqual(contract.quantityStep, Decimal(sign: .plus, exponent: -8, significand: 1))
        XCTAssertEqual(contract.minimumQuantity, contract.quantityStep)
        XCTAssertEqual(contract.minimumOrderAmount, 500)
      }
    }
    XCTAssertEqual(TradingRules.DomesticFutures.feeRate, 0)
    XCTAssertEqual(TradingRules.DomesticFutures.fundingRate, 0)
  }

  func testSpotAndOverseasInstrumentsDoNotReceiveDomesticFuturesContracts() {
    for exchange in Exchange.allCases {
      for product in [TradingProduct.spot, .perpetual] {
        // 해외 USDT 모형은 기존 저장 호환용이고 국내 선물 계약을 적용하면 안 된다.
        let instrument = TradingInstrumentID(
          exchange: exchange,
          product: product,
          rawSymbol: "BTCUSDT",
          settlementCurrency: .usdt
        )
        XCTAssertNil(TradingRules.DomesticFutures.contractRules(for: instrument))
      }
    }
    // 과거 국내 BTC 포지션의 가격 출처는 보존하지만 새 주문은 허용하지 않는다.
    let legacy = domesticFuturesOrder(currency: .btc, symbol: "BTC-ETH", margin: 1, price: 1).instrument
    XCTAssertTrue(legacy.usesDomesticSpotPrice)
    XCTAssertNil(TradingRules.DomesticFutures.contractRules(for: legacy))
  }

  func testSpotNeverLiquidatesAndFuturesUseUnroundedEquityBoundary() {
    for equity in [Decimal(-100), -1, 0, Decimal(sign: .plus, exponent: -8, significand: 1), 100] {
      XCTAssertFalse(TradingRules.liquidationRule(for: .spot).shouldLiquidate(remainingEquity: equity))
      XCTAssertEqual(TradingRules.liquidationRule(for: .perpetual).shouldLiquidate(remainingEquity: equity), equity <= 0)
    }
  }

  func testAdditionalEntryRequiresSameExchangeMarketDirectionAndLeverage() {
    // 체결 식별자가 달라도 같은 방향·배수의 진입만 합산할 수 있다.
    let existing = domesticFuturesOrder()
    XCTAssertTrue(TradingRules.canCombine(domesticFuturesOrder(), with: existing))
    XCTAssertFalse(TradingRules.canCombine(domesticFuturesOrder(exchange: .bithumb), with: existing))
    XCTAssertFalse(TradingRules.canCombine(domesticFuturesOrder(symbol: "KRW-ETH"), with: existing))
    XCTAssertFalse(TradingRules.canCombine(domesticFuturesOrder(side: .short), with: existing))
    XCTAssertFalse(TradingRules.canCombine(domesticFuturesOrder(leverage: 20), with: existing))
  }

  func testIntroPolicyKeepsMinimumAndMaximumDisplayWaitSeparate() {
    XCTAssertEqual(TradingRules.DomesticFutures.HistoryCheck.minimumIntroMilliseconds, 1_500)
    XCTAssertEqual(TradingRules.DomesticFutures.HistoryCheck.maximumIntroSeconds, 5)
  }

  func testFundingAndAccountRestorePoliciesPreserveAllExistingCombinations() throws {
    for exchange in Exchange.allCases {
      for product in [TradingProduct.spot, .perpetual] {
        for currency in [TradingCurrency.krw, .btc, .usdt] {
          // 기존 정책의 조합별 결과를 규약 이전 전과 동일하게 유지한다.
          let account = TradingAccountID(exchange: exchange, product: product, currency: currency)
          // 신규 지원 여부와 별개였던 기존 지급액 조회 결과다.
          let reward: Decimal? = currency == .krw ? 10_000_000 : (product == .perpetual && currency == .usdt ? 1_000 : nil)
          // 구형 국내 BTC·USDT 파일을 읽던 예외 조건을 그대로 고정한다.
          let legacyBTC = (exchange == .upbit || exchange == .bithumb) && currency == .btc
          XCTAssertEqual(TradingFundingPolicy.advertisementReward(for: account), reward)
          XCTAssertEqual(TradingRules.Funding.advertisementReward(for: account), reward)
          XCTAssertEqual(TradingFundingPolicy.initialGrant(for: account), account == .spot(for: .upbit) ? 1_000_000 : 0)
          XCTAssertEqual(TradingRules.Futures.canCreateAccount(account), product == .perpetual && account.availability != .unsupported)
          XCTAssertEqual(
            TradingRules.Futures.canRestoreAccount(account),
            product == .perpetual && (currency == .usdt || account.availability != .unsupported || legacyBTC)
          )
          XCTAssertEqual(
            TradingRules.Futures.supportsAccount(account, preservingStoredPosition: true),
            product == .perpetual && (account.availability != .unsupported || legacyBTC)
          )
          if account.availability == .unsupported || reward == nil {
            XCTAssertThrowsError(try AdRewardClaim(account: account))
          } else {
            // 준비 중인 구형 USDT 보상도 기존 버전과 지급 조건으로 유지한다.
            let claim = try AdRewardClaim(account: account)
            XCTAssertEqual(claim.policyVersion, 1)
            XCTAssertNoThrow(try claim.validate())
          }
        }
      }
    }
    XCTAssertEqual(TradingFundingPolicy.initialKRWBalance, 1_000_000)
    XCTAssertEqual(TradingRules.Funding.initialGrantAccount, .spot(for: .upbit))
    XCTAssertEqual(TradingRules.Funding.unfundedAccountBalance, 0)
  }

  func testSpotSettlementPoliciesKeepMinimumPrecisionAndBTCAsset() {
    XCTAssertEqual(SettlementCurrency.krw.minimumOrderAmount, 500)
    XCTAssertEqual(SettlementCurrency.btc.minimumOrderAmount, 0.00005)
    XCTAssertEqual(SettlementCurrency.krw.amountFractionDigits, 0)
    XCTAssertEqual(SettlementCurrency.btc.amountFractionDigits, 8)
    XCTAssertNil(SettlementCurrency.krw.holdingDisplayMarket)
    XCTAssertEqual(SettlementCurrency.btc.holdingDisplayMarket, "BTC/KRW")
    XCTAssertEqual(PortfolioCalculator.quantityTolerance, 0.00000001)
    XCTAssertEqual(TradingRules.Spot.profitRateFractionDigits, 2)
    XCTAssertEqual(TradingRules.Spot.evaluationFractionDigits, 8)
  }

  func testFuturesCapabilitiesPreserveDomesticAndLegacyBehavior() {
    for exchange in Exchange.allCases {
      for product in [TradingProduct.spot, .perpetual] {
        for currency in [TradingCurrency.krw, .btc, .usdt] {
          // 기능 허용은 기존 가격 출처·상품 판정과 같고 KRW 현재가 청산은 별도로 제한한다.
          let instrument = TradingInstrumentID(exchange: exchange, product: product, rawSymbol: "KRW-BTC", settlementCurrency: currency)
          // 기존 국내 선물의 가격 출처 판정이며 BTC 복원 데이터도 포함한다.
          let domesticFutures = product == .perpetual && (exchange == .upbit || exchange == .bithumb)
          XCTAssertEqual(TradingRules.Futures.allowsAdditionalEntry(for: instrument), domesticFutures)
          XCTAssertEqual(TradingRules.Futures.allowsPartialClosing(for: instrument), domesticFutures)
          XCTAssertEqual(TradingRules.Futures.allowsFunding(for: instrument), product == .perpetual && !domesticFutures)
          XCTAssertEqual(TradingRules.Futures.HistoryCheck.allowsDetailedHistory(for: instrument), domesticFutures)
          XCTAssertEqual(TradingRules.Futures.HistoryCheck.usesLockedExecutionTime(for: instrument), domesticFutures)
          XCTAssertEqual(TradingRules.Futures.allowsObservedLiquidation(for: instrument), domesticFutures && currency == .krw)
          XCTAssertEqual(TradingRules.Futures.closingFeeRate(for: instrument), 0)
        }
      }
      XCTAssertEqual(TradingRules.Futures.HistoryCheck.allowsEntrySecondCloseFallback(for: exchange), exchange == .upbit)
    }
  }

  func testModePoliciesKeepMarketVisibilityAndRefreshTriggers() {
    XCTAssertEqual(TradingRules.visibleMarketCurrencies(for: .spot), [.krw, .btc])
    XCTAssertEqual(TradingRules.visibleMarketCurrencies(for: .perpetual), [.krw])
    for market in ["BTC/KRW", "ETH/BTC", "BTC/USDT", "UNKNOWN"] {
      XCTAssertTrue(TradingRules.isVisibleMarket(market, product: .spot))
      XCTAssertEqual(TradingRules.isVisibleMarket(market, product: .perpetual), market.hasSuffix("/KRW"))
    }
    for product in [TradingProduct.spot, .perpetual] {
      XCTAssertTrue(TradingRules.Futures.HistoryCheck.shouldRefresh(on: .appForeground, selectedProduct: product))
      XCTAssertTrue(TradingRules.Futures.HistoryCheck.shouldRefresh(on: .exchangeSelection, selectedProduct: product))
      XCTAssertEqual(TradingRules.Futures.HistoryCheck.shouldRefresh(on: .productSelection, selectedProduct: product), product == .perpetual)
    }
    // 완료·조회 실패·작업 분할 보류 모두 같은 주문·평가 준비 정책을 확인한다.
    let holds: [FuturesHistoryCheckHold?] = [nil, .currentInterval, .requestFailed, .workLimit]
    for liquidated in [true, false] {
      for hold in holds {
        XCTAssertEqual(TradingRules.Futures.HistoryCheck.isPositionReady(liquidated: liquidated, hold: hold), !liquidated && hold == nil)
      }
    }
  }

  func testOrderPriceValidityKeepsInclusiveFiveSecondBoundary() throws {
    // 주문 준비 가격만의 유효 시간을 인트로 대기와 혼동하지 않는지 확인한다.
    let order = domesticFuturesOrder(margin: 100, price: 100)
    // 포지션이 없는 계좌도 기존 주문 가격 신선도 검사를 그대로 적용한다.
    let snapshot = FuturesAccountSnapshot(revision: 0, accounts: [.init(id: order.account, availableBalance: 1_000)])
    for age in [Int64(0), 5_000, 5_001, -1] {
      // 경계와 미래 시각을 포함해 기존 5초 주문 규칙을 고정한다.
      let check = FuturesOrderCheck(
        account: order.account,
        instrument: order.instrument,
        revision: snapshot.revision,
        mark: .init(instrument: order.instrument, price: 100, timestamp: 120_000 - age)
      )
      if (0...5_000).contains(age) {
        XCTAssertNoThrow(try check.validate(snapshot: snapshot, now: Date(timeIntervalSince1970: 120)))
      } else {
        XCTAssertThrowsError(try check.validate(snapshot: snapshot, now: Date(timeIntervalSince1970: 120))) {
          XCTAssertEqual($0 as? FuturesOrderCheckError, .staleQuote)
        }
      }
    }
    XCTAssertEqual(TradingRules.Futures.HistoryCheck.quoteMaximumAgeMilliseconds, 30_000)
    XCTAssertEqual(TradingRules.Futures.HistoryCheck.restClockAheadMilliseconds, 5_000)
    XCTAssertEqual(TradingRules.Futures.minimumDisplayedEquity, 0)
    XCTAssertEqual(TradingRules.Futures.minimumDisplayedReturnPercent, -100)
  }

  func testObservedLiquidationKeepsInclusiveThirtySecondBoundary() throws {
    // 경계별로 독립 계좌를 사용해 앞선 청산 저장이 다음 사례에 영향을 주지 않게 한다.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    for age in [Int64(30_000), 30_001] {
      // 과거 검증의 완료 경계를 포함한 실제 저장소 경로로 확인한다.
      let repository = LocalFuturesAccountRepository(fileURL: directory.appendingPathComponent("\(age).json"))
      // 청산 시 기존 현물이나 다른 증거금을 차감하지 않는 국내 포지션이다.
      let order = domesticFuturesOrder(margin: 100, price: 100)
      try repository.applyAdvertisementReward(AdRewardClaim(account: order.account))
      _ = try repository.openTestPosition(order, expectedRevision: repository.snapshot().revision)
      // 진입 직후 수신한 가격의 실제 경과 시간을 비교한다.
      let quote = FuturesMarkQuote(instrument: order.instrument, price: 80, timestamp: 60_001)
      // 밀리초 경계에서 부동소수 날짜 오차를 피하는 기존 Date 변환을 함께 사용한다.
      let settledAt = Date(timeIntervalSince1970: Double(quote.timestamp + age) / 1_000)
      if age == 30_000 {
        XCTAssertEqual(try repository.liquidateObservedQuote(quote, settledAt: settledAt).count, 1)
      } else {
        XCTAssertThrowsError(try repository.liquidateObservedQuote(quote, settledAt: settledAt)) {
          XCTAssertEqual($0 as? FuturesOrderCheckError, .staleQuote)
        }
        XCTAssertNil(try repository.snapshot().historyCheckStates[0].liquidation)
      }
    }
  }

  func testLiquidationNoticeRequiresMatchingExchangeAndFuturesMode() {
    for exchange in [Exchange.upbit, .bithumb] {
      for product in [TradingProduct.spot, .perpetual] {
        // 청산 계좌와 현재 화면의 선택을 별개로 확인한다.
        let account = TradingAccountID(exchange: exchange, product: product, currency: .krw)
        for selectedExchange in Exchange.allCases {
          for selectedProduct in [TradingProduct.spot, .perpetual] {
            XCTAssertEqual(
              TradingRules.canShowLiquidationNotice(
                for: account,
                selectedExchange: selectedExchange,
                selectedProduct: selectedProduct
              ),
              product == .perpetual && exchange == selectedExchange && selectedProduct == .perpetual
            )
          }
        }
      }
    }
  }
}
