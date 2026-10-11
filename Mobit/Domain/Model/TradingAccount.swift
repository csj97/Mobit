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
    TradingRules.availability(for: self)
  }

  func supports(_ instrument: TradingInstrumentID, preservingStoredPosition: Bool = false) -> Bool {
    guard TradingRules.Futures.supportsAccount(self, preservingStoredPosition: preservingStoredPosition),
          instrument.exchange == exchange, instrument.product == product,
          instrument.settlementCurrency == currency else { return false }
    if TradingRules.isDomesticExchange(exchange) {
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
    TradingRules.DomesticFutures.maximumLeverage(for: self)
  }

  var usesDomesticSpotPrice: Bool {
    TradingRules.DomesticFutures.usesSpotPrice(for: self)
  }
}

enum TradingAvailability {
  case available
  case preparing
  case unsupported
}

enum TradingFundingPolicy {
  // 기존 호출 API는 유지하되 지급액의 정의는 거래 규약 한곳에서 관리한다.
  static let initialKRWBalance = TradingRules.Funding.initialKRWBalance

  static func initialGrant(for account: TradingAccountID) -> Decimal {
    TradingRules.Funding.initialGrant(for: account)
  }

  static func advertisementReward(for account: TradingAccountID) -> Decimal? {
    TradingRules.Funding.advertisementReward(for: account)
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

  // 포지션별 검증 완료 시점과 청산 결과를 보관한다.
  let historyCheckStates: [FuturesHistoryCheckState]
  let closedPositions: [FuturesClosedPosition]

  init(schemaVersion: Int = 6, revision: UInt64, accounts: [FuturesCashAccount], rewardClaims: [AdRewardClaim] = [],
       positions: [FuturesPosition] = [], ledger: [FuturesLedgerEntry] = [],
       historyCheckStates: [FuturesHistoryCheckState] = [], closedPositions: [FuturesClosedPosition] = []) {
    self.schemaVersion = schemaVersion
    self.revision = revision
    self.accounts = accounts
    self.rewardClaims = rewardClaims
    self.positions = positions
    self.ledger = ledger
    self.historyCheckStates = historyCheckStates
    self.closedPositions = closedPositions
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, revision, accounts, rewardClaims, positions, ledger, closedPositions
    case historyCheckStates = "reconciliations"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    revision = try container.decode(UInt64.self, forKey: .revision)
    accounts = try container.decode([FuturesCashAccount].self, forKey: .accounts)
    rewardClaims = schemaVersion == 1 ? [] : try container.decode([AdRewardClaim].self, forKey: .rewardClaims)
    positions = schemaVersion < 3 ? [] : try container.decode([FuturesPosition].self, forKey: .positions)
    ledger = schemaVersion < 3 ? [] : try container.decode([FuturesLedgerEntry].self, forKey: .ledger)
    closedPositions = schemaVersion < 5 ? [] : try container.decode([FuturesClosedPosition].self, forKey: .closedPositions)
    // 저장 형식 버전에 맞춰 복원한 포지션별 검증 상태다.
    let decodedHistoryCheckStates = schemaVersion < 4
      ? try positions.map { try FuturesHistoryCheckState.initial(for: $0) }
      : try container.decode([FuturesHistoryCheckState].self, forKey: .historyCheckStates)
    let storedVersion = schemaVersion
    let decodedPositions = positions
    historyCheckStates = try decodedHistoryCheckStates.map { decoded in
      var state = decoded
      if storedVersion < 5, state.lastVerifiedMark == nil, state.liquidation == nil,
         let position = decodedPositions.first(where: { $0.id == state.positionID }) {
        let entry = try FuturesHistoryCheckState.milliseconds(position.lastExecutionAt)
        // 이전 ceil 변환의 부동소수 오차 1ms는 아직 미검증인 진입 경계에서만 다시 검사한다.
        if state.verifiedThrough == entry + 1 { state.verifiedThrough = entry }
      }
      return state
    }
  }

  func isActive(_ position: FuturesPosition) -> Bool {
    !closedPositions.contains(where: { $0.order.positionID == position.id }) &&
      historyCheckStates.first(where: { $0.positionID == position.id })?.liquidation == nil
  }

  static let empty = Self(revision: 0, accounts: [])
}

extension Notification.Name {
  static let futuresAccountDidChange = Notification.Name("futuresAccountDidChange")
}
