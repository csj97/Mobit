import Foundation
import RxSwift

struct FuturesMarkQuote: Equatable {
  let instrument: TradingInstrumentID
  let price: Decimal
  let timestamp: Int64
  // REST 서버 응답 시각으로 무체결 현재가도 새로 조회됐는지 확인한다.
  let responseTimestamp: Int64?

  init(
    instrument: TradingInstrumentID,
    price: Decimal,
    timestamp: Int64,
    responseTimestamp: Int64? = nil
  ) {
    self.instrument = instrument
    self.price = price
    self.timestamp = timestamp
    self.responseTimestamp = responseTimestamp
  }
}

struct FuturesMarkCandle: Codable, Equatable {
  let openTime: Int64
  let closeTime: Int64
  let open: Decimal
  let high: Decimal
  let low: Decimal
  let close: Decimal
}

struct FuturesFundingEvent: Codable, Equatable {
  let timestamp: Int64
  let rate: Decimal
  let markPrice: Decimal
}

struct FuturesHistoryPage<Value> {
  let instrument: TradingInstrumentID
  let values: [Value]
  let nextStartTime: Int64?
}

struct FuturesMarketContract: Equatable {
  let instrument: TradingInstrumentID
  let quantityStep: Decimal
  let minimumQuantity: Decimal
  let maximumQuantity: Decimal
  // 주문에 필요한 최소 거래금액으로, 증거금과 구분한다.
  let minimumOrderAmount: Decimal
  let priceTick: Decimal
}

enum FuturesMarketDataError: Error, Equatable {
  case unsupportedInstrument
  case invalidRequest
  case invalidResponse
  case incompleteHistory
  case workLimit
  case httpStatus(Int)
}

protocol FuturesMarketDataProviding {
  func markQuote(_ instrument: TradingInstrumentID) -> Single<FuturesMarkQuote>
  func contract(_ instrument: TradingInstrumentID) -> Single<FuturesMarketContract>
  func markCandles(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<FuturesHistoryPage<FuturesMarkCandle>>
  func funding(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<FuturesHistoryPage<FuturesFundingEvent>>
}

struct FuturesTradeTick: Equatable {
  let id: String
  let timestamp: Int64
  let price: Decimal
}

struct FuturesTradePage {
  let instrument: TradingInstrumentID
  let trades: [FuturesTradeTick]
  let nextCursor: String?
  var serverTimestamp: Int64? = nil
}

protocol FuturesDetailedMarketDataProviding: FuturesMarketDataProviding {
  func boundaryHistory(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64,
                       initialEntry: Bool) -> Single<FuturesReplayBatch>
}
