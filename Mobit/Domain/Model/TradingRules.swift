import Foundation

// 실제 거래소 약관이 아니라 MOBIT 모의거래의 실행 규약이다. 계좌 간 자산은 공유하지 않는다.
enum TradingRules {
  static func isDomesticExchange(_ exchange: Exchange) -> Bool {
    exchange == .upbit || exchange == .bithumb
  }

  static func availability(for account: TradingAccountID) -> TradingAvailability {
    switch (account.exchange, account.product, account.currency) {
    // 현물 BTC 마켓은 보유 BTC로 결제하며 별도의 BTC 현금 계좌를 만들지 않는다.
    case (.upbit, .spot, .krw), (.bithumb, .spot, .krw),
         (.upbit, .perpetual, .krw), (.bithumb, .perpetual, .krw): return .available
    // 저장 데이터 호환용이며 현재 국내 선물 화면의 주문 대상으로 사용하지 않는다.
    case (.binance, .perpetual, .usdt), (.okx, .perpetual, .usdt): return .preparing
    default: return .unsupported
    }
  }

  enum LiquidationRule {
    // 현물 손실은 보유 수량을 제거하는 청산 사유가 아니다.
    case disabled
    // 표시 수익률의 반올림이 아니라 증거금과 실제 손익의 합계로 판단한다.
    case marginExhausted

    func shouldLiquidate(remainingEquity: Decimal) -> Bool {
      switch self {
      case .disabled: return false
      case .marginExhausted: return remainingEquity <= 0
      }
    }
  }

  static func liquidationRule(for product: TradingProduct) -> LiquidationRule {
    switch product {
    case .spot: return .disabled
    case .perpetual: return .marginExhausted
    }
  }

  // 정산은 화면 선택과 무관하게 진행하되 안내는 현재 거래소의 선물 모드에서만 표시한다.
  static func canShowLiquidationNotice(
    for account: TradingAccountID,
    selectedExchange: Exchange,
    selectedProduct: TradingProduct
  ) -> Bool {
    account.product == .perpetual && account.exchange == selectedExchange && account.product == selectedProduct
  }

  // 방향·레버리지를 바꾸는 신규 진입은 기존 포지션에 섞지 않는다.
  static func canCombine(_ order: FuturesOpeningOrder, with existing: FuturesOpeningOrder) -> Bool {
    order.account == existing.account && order.instrument == existing.instrument
      && order.side == existing.side && order.leverage == existing.leverage
  }

  // 현물 주문의 결제·정밀도 정책이며 계산과 보유 자산 저장은 기존 로직에서 수행한다.
  enum Spot {
    // 미세 잔량을 전량 매도 후 보유 자산으로 남기지 않는 기존 허용 오차다.
    static let quantityTolerance: Double = 0.00000001
    // 현물 손익률의 기존 소수점 표시·절삭 기준이다.
    static let profitRateFractionDigits = 2
    // 현물 평가금액 원본 계산에 적용하는 기존 소수점 절삭 기준이다.
    static let evaluationFractionDigits = 8

    static func minimumOrderAmount(for currency: SettlementCurrency) -> Double {
      switch currency {
      case .krw: return 500
      case .btc: return 0.00005
      }
    }

    static func amountFractionDigits(for currency: SettlementCurrency) -> Int {
      switch currency {
      case .krw: return 0
      case .btc: return 8
      }
    }

    static func holdingDisplayMarket(for currency: SettlementCurrency) -> String? {
      switch currency {
      case .krw: return nil
      case .btc: return "BTC/KRW"
      }
    }
  }

  enum Funding {
    // 최초 설치 시 업비트 현물에만 지급하며 초기화·다른 계좌 생성 때는 재지급하지 않는다.
    static let initialGrantAccount = TradingAccountID.spot(for: .upbit)
    // 기존 최초 지급액과 테스트의 금액 지정 API를 유지한다.
    static let initialKRWBalance: Double = 1_000_000
    // 미지급 계좌 생성·조회와 투자 초기화에는 별도 초기 자금을 만들지 않는다.
    static let unfundedAccountBalance: Double = 0
    // 저장된 광고 보상 요청의 버전 키와 검증 값을 바꾸지 않는다.
    static let advertisementRewardPolicyVersion = 1

    static func initialGrant(for account: TradingAccountID) -> Decimal {
      account == initialGrantAccount ? Decimal(initialKRWBalance) : Decimal(unfundedAccountBalance)
    }

    static func advertisementReward(for account: TradingAccountID) -> Decimal? {
      // 금액 조회와 계좌 지원 여부 검증은 구분해 기존 지급 대기·저장 호환성을 유지한다.
      switch (account.product, account.currency) {
      case (.spot, .krw), (.perpetual, .krw): return 10_000_000
      case (.perpetual, .usdt): return 1_000
      default: return nil
      }
    }
  }

  static func visibleMarketCurrencies(for product: TradingProduct) -> [SettlementCurrency] {
    switch product {
    case .spot: return [.krw, .btc]
    case .perpetual: return [.krw]
    }
  }

  static func isVisibleMarket(_ displayMarket: String, product: TradingProduct) -> Bool {
    switch product {
    case .spot: return true
    case .perpetual: return displayMarket.hasSuffix("/KRW")
    }
  }

  // 해외 저장 모형의 기존 계산 정책은 보존하고 국내 모의거래의 허용 조건을 구분한다.
  enum Futures {
    // 평가 표시만 증거금 손실로 제한하며 원본 손익·청산 근거는 유지한다.
    static let minimumDisplayedEquity: Decimal = 0
    // 청산 이후 표시 수익률이 증거금 손실 한도를 넘어가지 않는 기존 정책이다.
    static let minimumDisplayedReturnPercent: Decimal = -100
    // 주문 준비 시 고정한 가격·체결 시각을 저장 시 다시 확인하는 유효 시간이다.
    static let orderMaximumAgeMilliseconds: Int64 = 5_000

    static func supportsAccount(_ account: TradingAccountID, preservingStoredPosition: Bool = false) -> Bool {
      // 국내 BTC 포지션은 복원만 허용하며 새 계좌나 신규 주문으로 확장하지 않는다.
      let legacyBTC = preservingStoredPosition && TradingRules.isDomesticExchange(account.exchange) && account.currency == .btc
      return account.product == .perpetual && (TradingRules.availability(for: account) != .unsupported || legacyBTC)
    }

    static func canCreateAccount(_ account: TradingAccountID) -> Bool {
      account.product == .perpetual && TradingRules.availability(for: account) != .unsupported
    }

    static func canRestoreAccount(_ account: TradingAccountID) -> Bool {
      // 구형 USDT 계좌는 지원 판정과 별개로 읽을 수 있어야 기존 파일이 손상으로 처리되지 않는다.
      account.product == .perpetual && (account.currency == .usdt || TradingRules.availability(for: account) != .unsupported
        || (TradingRules.isDomesticExchange(account.exchange) && account.currency == .btc))
    }

    static func allowsAdditionalEntry(for instrument: TradingInstrumentID) -> Bool {
      TradingRules.DomesticFutures.usesSpotPrice(for: instrument)
    }

    static func allowsPartialClosing(for instrument: TradingInstrumentID) -> Bool {
      TradingRules.DomesticFutures.usesSpotPrice(for: instrument)
    }

    static func allowsFunding(for instrument: TradingInstrumentID) -> Bool {
      instrument.product == .perpetual && !TradingRules.DomesticFutures.usesSpotPrice(for: instrument)
    }

    static func closingFeeRate(for instrument: TradingInstrumentID) -> Decimal {
      // 기존 해외 저장 모형의 종료 수수료도 0으로 유지하며 진입 수수료 원본은 바꾸지 않는다.
      TradingRules.DomesticFutures.usesSpotPrice(for: instrument) ? TradingRules.DomesticFutures.feeRate : 0
    }

    static func allowsObservedLiquidation(for instrument: TradingInstrumentID) -> Bool {
      TradingRules.DomesticFutures.supportsHistoryInstrument(instrument)
    }

    enum HistoryCheck {
      // 검증·청산에 쓸 현재가의 기존 최대 경과 시간이다.
      static let quoteMaximumAgeMilliseconds: Int64 = 30_000
      // REST 응답과 체결 시각에만 허용하는 서버·기기 시계 차이다.
      static let restClockAheadMilliseconds: Int64 = 5_000

      enum RefreshTrigger {
        case appForeground
        case exchangeSelection
        case productSelection
      }

      static func shouldRefresh(on trigger: RefreshTrigger, selectedProduct: TradingProduct) -> Bool {
        switch trigger {
        // 현물 화면에서도 다른 계좌의 보유 선물 검증을 재개해야 한다.
        case .appForeground, .exchangeSelection: return true
        case .productSelection: return selectedProduct == .perpetual
        }
      }

      static func isPositionReady(liquidated: Bool, hold: FuturesHistoryCheckHold?) -> Bool {
        !liquidated && hold == nil
      }

      static func usesLockedExecutionTime(for instrument: TradingInstrumentID) -> Bool {
        TradingRules.DomesticFutures.usesSpotPrice(for: instrument)
      }

      static func allowsDetailedHistory(for instrument: TradingInstrumentID) -> Bool {
        TradingRules.DomesticFutures.usesSpotPrice(for: instrument)
      }

      static func allowsEntrySecondCloseFallback(for exchange: Exchange) -> Bool {
        exchange == .upbit
      }
    }
  }

  // 업비트·빗썸 KRW 현물 시세를 사용하는 내부 롱/숏 모의거래이며 실제 선물 주문은 보내지 않는다.
  enum DomesticFutures {
    // 진입·종료 모두 수수료를 부과하지 않는 현행 모의거래 정책이다.
    static let feeRate: Decimal = 0
    // 해외 선물 펀딩·MMR을 국내 현물 시세 기반 모의거래에 적용하지 않는다.
    static let fundingRate: Decimal = 0
    // 주문 수량은 기존 체결 정책에 맞춰 소수점 8자리 단위로 내린다.
    static let quantityStep = Decimal(sign: .plus, exponent: -8, significand: 1)

    static func usesSpotPrice(for instrument: TradingInstrumentID) -> Bool {
      // 기존 BTC 저장 포지션도 복원해야 하므로 가격 출처와 신규 주문 지원 여부는 구분한다.
      instrument.product == .perpetual && TradingRules.isDomesticExchange(instrument.exchange)
    }

    static func supports(_ account: TradingAccountID) -> Bool {
      account.product == .perpetual && account.currency == .krw && TradingRules.availability(for: account) == .available
    }

    static func supportsHistoryInstrument(_ instrument: TradingInstrumentID) -> Bool {
      usesSpotPrice(for: instrument) && instrument.settlementCurrency == .krw
    }

    static func maximumLeverage(for instrument: TradingInstrumentID) -> Int? {
      guard usesSpotPrice(for: instrument), instrument.settlementCurrency == .krw,
        instrument.rawSymbol.hasPrefix("KRW-") else { return nil }
      // 종목명 유사성이나 시가총액 대신 합의된 심볼 목록만 사용한다.
      let symbol = String(instrument.rawSymbol.dropFirst(4))
      switch symbol {
      case "BTC", "ETH": return 100
      case "SOL", "XRP", "ADA", "AVAX", "NEAR", "SUI", "DOGE", "SHIB", "LINK", "UNI", "AAVE", "RNDR": return 50
      default: return 20
      }
    }

    static func contractRules(for instrument: TradingInstrumentID) -> FuturesContractRules? {
      // 레버리지와 최소 체결 단위를 주문 생성과 검증에서 같은 규칙으로 사용한다.
      guard let maximum = maximumLeverage(for: instrument) else { return nil }
      return FuturesContractRules(
        maximumLeverage: maximum,
        quantityStep: quantityStep,
        minimumQuantity: quantityStep,
        minimumOrderAmount: Decimal(TradingRules.Spot.minimumOrderAmount(for: .krw))
      )
    }

  }
}
