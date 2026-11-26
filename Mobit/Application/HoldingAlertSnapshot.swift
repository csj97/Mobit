import Foundation

/// 커밋된 모의투자 원장에서 개인 알림 RPC가 요구하는 값만 추출한다.
struct HoldingAlertSnapshot: Codable, Equatable {
  // 보유 건이 전량 종료된 뒤 재진입하면 새 UUID가 생긴다.
  let id: UUID
  // 가격을 조회할 국내 거래소와 원본 마켓 코드다.
  let exchange: String, market: String
  // 현물 또는 선물 방향을 구분한다.
  let side: String
  // 현물 평단 또는 선물 수량·원가·증거금의 동일 배율 계수다.
  let average: String?, units: String?, cost: String?, margin: String?
  // 체결 이전 가격을 새 포지션의 성과로 오인하지 않도록 기준을 남긴다.
  let effectiveAt: Date, fill: String

  func hasSameBasis(as other: Self) -> Bool {
    id == other.id && exchange == other.exchange && market == other.market && side == other.side
      && average == other.average && units == other.units && cost == other.cost && margin == other.margin
  }

  static func spot(_ holdings: [CryptoTransactionDataModel], trades: [TransactionInfo]) -> [Self] {
    // 가장 최근의 해당 마켓 체결을 한 번만 조회한다.
    var latest: [ExchangePairID: (price: Double, timestamp: Int64?)] = [:]
    for trade in trades {
      latest[trade.exchangePairID] = (trade.executedPrice, trade.executedTimestamp)
      // BTC 마켓 체결로 정산 자산 BTC의 원화 평단이 변한 경우에도 해당 시각의 환율을 쓴다.
      if trade.exchangePairID.rawMarketCode?.hasPrefix("BTC-") == true, let rate = trade.settlementRateKRW, rate > 0 {
        latest[ExchangePairID(exchange: trade.exchange, rawMarketCode: "KRW-BTC")] =
          (NSDecimalNumber(decimal: rate).doubleValue, trade.executedTimestamp)
      }
    }
    return holdings.compactMap { holding in
      // 보유 중인 원본 현물의 가격과 거래소 식별자다.
      let asset = holding.staticData
      guard TradingRules.isDomesticExchange(asset.exchange), asset.holdingQuantity > 0,
            asset.averageBuyPrice.isFinite, asset.averageBuyPrice > 0,
            let market = asset.exchangePairID.rawMarketCode,
            market.range(of: "^(KRW|BTC)-[A-Z0-9]{1,20}$", options: .regularExpression) != nil else { return nil }
      // 직접 매매 또는 BTC 정산으로 이 자산에 영향을 준 최신 체결이다.
      let trade = latest[asset.exchangePairID]
      // 구버전 자산은 당시 저장된 평가 단가를 사용하고 없으면 평단에서 감시를 시작한다.
      let snapshotPrice = holding.dynamicData.settlementPriceSnapshot?.price
      // 알림의 최초 기준 단계에 사용할 단가다.
      let price = [trade?.price, snapshotPrice].compactMap { $0 }.first { $0.isFinite && $0 > 0 } ?? asset.averageBuyPrice
      // 기존 데이터에 체결 시각이 없으면 등록 시각부터 감시한다.
      let time = trade?.timestamp.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? Date()
      return Self(
        id: holding.identifier,
        exchange: asset.exchange.rawValue,
        market: market,
        side: "spot",
        average: String(asset.averageBuyPrice),
        units: nil,
        cost: nil,
        margin: nil,
        effectiveAt: time,
        fill: String(price)
      )
    }
  }

  static func futures(_ account: FuturesAccountSnapshot) throws -> [Self] {
    try account.positions.filter { $0.order.instrument.usesDomesticSpotPrice && account.isActive($0) }.map { position in
      // 어떤 체결이 마지막이었는지에 맞춰 추가 진입과 부분 종료 단가를 구분한다.
      let last = position.executions.last ?? position.order
      // 일부 종료가 마지막 거래면 종료 가격을 기준으로 등록한다.
      let closing = position.partialClosings?.last?.order
      // 앱의 과거 검증이 끝난 경우 검증 가격으로 갱신한다.
      var price = closing.flatMap { $0.executedAt >= last.executedAt ? $0.executionPrice : nil } ?? last.executionPrice
      // 마지막 체결이나 검증보다 과거인 관측은 제외한다.
      var time = position.lastExecutionAt
      if let state = account.historyCheckStates.first(where: { $0.positionID == position.id }),
         let mark = state.lastVerifiedMark {
        // 원장에 커밋된 마지막 이력 확인 경계다.
        let checked = Date(timeIntervalSince1970: Double(state.verifiedThrough) / 1000)
        if checked > time { time = checked; price = mark }
      }
      // 세 수를 같은 10의 거듭제곱으로 이동해 순환소수 나눗셈이나 수량 원본 전송을 피한다.
      var scale: Int16 = 0
      // 공통 배율을 정해 수량의 유효 숫자를 보존한다.
      var quantity = NSDecimalNumber(decimal: position.quantity)
      while quantity.compare(1) == .orderedAscending { quantity = quantity.multiplying(byPowerOf10: 1); scale += 1 }
      while quantity.compare(10) != .orderedAscending { quantity = quantity.multiplying(byPowerOf10: -1); scale -= 1 }
      return Self(
        id: position.id,
        exchange: position.order.account.exchange.rawValue,
        market: position.order.instrument.rawSymbol,
        side: position.order.side.rawValue,
        average: nil,
        units: quantity.stringValue,
        cost: NSDecimalNumber(decimal: position.entryTradeAmount).multiplying(byPowerOf10: scale).stringValue,
        margin: NSDecimalNumber(decimal: try position.margin).multiplying(byPowerOf10: scale).stringValue,
        effectiveAt: time,
        fill: NSDecimalNumber(decimal: price).stringValue
      )
    }
  }
}
