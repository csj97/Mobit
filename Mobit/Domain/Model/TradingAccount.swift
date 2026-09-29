import Foundation

enum TradingProduct: String, Codable, Hashable {
  case spot
  case perpetual
}

// 현물 SettlementCurrency의 주문 규칙에 미지원 USDT를 섞지 않는다.
enum TradingCurrency: String, Codable, Hashable {
  case krw = "KRW"
  case btc = "BTC"
  case usdt = "USDT"
}

struct TradingAccountID: Codable, Hashable {
  let exchange: Exchange
  let product: TradingProduct
  let currency: TradingCurrency

  static func spot(for exchange: Exchange) -> Self {
    Self(exchange: exchange, product: .spot, currency: .krw)
  }

  var availability: TradingAvailability {
    switch (exchange, product, currency) {
    case (.upbit, .spot, .krw), (.bithumb, .spot, .krw): return .available
    case (.upbit, .perpetual, .krw), (.bithumb, .perpetual, .krw),
         (.binance, .perpetual, .usdt), (.okx, .perpetual, .usdt): return .preparing
    default: return .unsupported
    }
  }

  func supports(_ instrument: TradingInstrumentID, preservingStoredPosition: Bool = false) -> Bool {
    let legacyBTC = preservingStoredPosition && (exchange == .upbit || exchange == .bithumb) && currency == .btc
    guard product == .perpetual, (availability != .unsupported || legacyBTC),
          instrument.exchange == exchange, instrument.product == product,
          instrument.settlementCurrency == currency else { return false }
    if exchange == .upbit || exchange == .bithumb {
      let components = instrument.rawSymbol.split(separator: "-", omittingEmptySubsequences: false)
      return components.count == 2 && components[0] == currency.rawValue &&
        !components[1].isEmpty && components[1] != components[0] &&
        components[1].utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) }
    }
    return !instrument.rawSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

struct TradingInstrumentID: Codable, Hashable {
  let exchange: Exchange
  let product: TradingProduct
  let rawSymbol: String
  let settlementCurrency: TradingCurrency

  var maximumPaperLeverage: Int? {
    guard usesDomesticSpotPrice, settlementCurrency == .krw, rawSymbol.hasPrefix("KRW-") else { return nil }
    let coin = String(rawSymbol.dropFirst(4))
    if ["BTC", "ETH"].contains(coin) { return 100 }
    if ["SOL", "XRP", "ADA", "AVAX", "NEAR", "SUI", "DOGE", "SHIB", "LINK", "UNI", "AAVE", "RNDR"].contains(coin) { return 50 }
    return 20
  }

  var usesDomesticSpotPrice: Bool {
    product == .perpetual && (exchange == .upbit || exchange == .bithumb)
  }
}

enum TradingAvailability {
  case available
  case preparing
  case unsupported
}

enum TradingFundingPolicy {
  static let initialKRWBalance: Double = 1_000_000

  static func initialGrant(for account: TradingAccountID) -> Decimal {
    account == .spot(for: .upbit) ? Decimal(initialKRWBalance) : 0
  }

  static func advertisementReward(for account: TradingAccountID) -> Decimal? {
    switch (account.product, account.currency) {
    case (.spot, .krw), (.perpetual, .krw): return 10_000_000
    case (.perpetual, .usdt): return 1_000
    default: return nil
    }
  }
}

struct FuturesCashAccount: Codable, Equatable {
  let id: TradingAccountID
  var availableBalance: Decimal
}

struct FuturesAccountSnapshot: Codable, Equatable {
  let schemaVersion: Int
  let revision: UInt64
  var accounts: [FuturesCashAccount]
  let rewardClaims: [AdRewardClaim]

  let positions: [FuturesPosition]
  let ledger: [FuturesLedgerEntry]

  let reconciliations: [FuturesReconciliationState]
  let closedPositions: [FuturesClosedPosition]

  init(schemaVersion: Int = 5, revision: UInt64, accounts: [FuturesCashAccount], rewardClaims: [AdRewardClaim] = [],
       positions: [FuturesPosition] = [], ledger: [FuturesLedgerEntry] = [],
       reconciliations: [FuturesReconciliationState] = [], closedPositions: [FuturesClosedPosition] = []) {
    self.schemaVersion = schemaVersion
    self.revision = revision
    self.accounts = accounts
    self.rewardClaims = rewardClaims
    self.positions = positions
    self.ledger = ledger
    self.reconciliations = reconciliations
    self.closedPositions = closedPositions
  }

  private enum CodingKeys: String, CodingKey { case schemaVersion, revision, accounts, rewardClaims, positions, ledger, reconciliations, closedPositions }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    revision = try container.decode(UInt64.self, forKey: .revision)
    accounts = try container.decode([FuturesCashAccount].self, forKey: .accounts)
    rewardClaims = schemaVersion == 1 ? [] : try container.decode([AdRewardClaim].self, forKey: .rewardClaims)
    positions = schemaVersion < 3 ? [] : try container.decode([FuturesPosition].self, forKey: .positions)
    ledger = schemaVersion < 3 ? [] : try container.decode([FuturesLedgerEntry].self, forKey: .ledger)
    closedPositions = schemaVersion < 5 ? [] : try container.decode([FuturesClosedPosition].self, forKey: .closedPositions)
    let decodedReconciliations = schemaVersion < 4
      ? try positions.map { try FuturesReconciliationState.initial(for: $0) }
      : try container.decode([FuturesReconciliationState].self, forKey: .reconciliations)
    let storedVersion = schemaVersion
    let decodedPositions = positions
    reconciliations = try decodedReconciliations.map { decoded in
      var state = decoded
      if storedVersion < 5, state.lastVerifiedMark == nil, state.liquidation == nil,
         let position = decodedPositions.first(where: { $0.id == state.positionID }) {
        let entry = try FuturesReconciliationState.milliseconds(position.lastExecutionAt)
        // 이전 ceil 변환의 부동소수 오차 1ms는 아직 미검증인 진입 경계에서만 다시 검사한다.
        if state.verifiedThrough == entry + 1 { state.verifiedThrough = entry }
      }
      return state
    }
  }

  func isActive(_ position: FuturesPosition) -> Bool {
    !closedPositions.contains(where: { $0.order.positionID == position.id }) &&
      reconciliations.first(where: { $0.positionID == position.id })?.liquidation == nil
  }

  static let empty = Self(revision: 0, accounts: [])
}
