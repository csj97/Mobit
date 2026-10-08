import Foundation
import Moya
import RxSwift

final class BinanceFuturesMarketRepository: FuturesMarketDataProviding {
  private let provider: MoyaProvider<BinanceFuturesNetworkService>

  init(provider: MoyaProvider<BinanceFuturesNetworkService> = MoyaProvider<BinanceFuturesNetworkService>()) {
    self.provider = provider
  }

  func markQuote(_ instrument: TradingInstrumentID) -> Single<FuturesMarkQuote> {
    request(.mark(instrument.rawSymbol), instrument: instrument).map { data in
      let dto = try JSONDecoder().decode(MarkDTO.self, from: data)
      guard dto.symbol == instrument.rawSymbol, dto.time > 0 else { throw FuturesMarketDataError.invalidResponse }
      return FuturesMarkQuote(instrument: instrument, price: try Self.number(dto.markPrice, positive: true), timestamp: dto.time)
    }
  }

  func contract(_ instrument: TradingInstrumentID) -> Single<FuturesMarketContract> {
    request(.exchangeInfo, instrument: instrument).map { data in
      let matches = try JSONDecoder().decode(ExchangeDTO.self, from: data).symbols.filter { $0.symbol == instrument.rawSymbol }
      guard matches.count == 1, let dto = matches.first, dto.status == "TRADING",
            dto.contractType == "PERPETUAL", dto.quoteAsset == "USDT", dto.marginAsset == "USDT" else {
        throw FuturesMarketDataError.unsupportedInstrument
      }
      func filter(_ type: String) throws -> FilterDTO {
        let matches = dto.filters.filter { $0.filterType == type }
        guard matches.count == 1, let result = matches.first else { throw FuturesMarketDataError.invalidResponse }
        return result
      }
      let lot = try filter("MARKET_LOT_SIZE")
      let minimum = try Self.number(lot.minQty, positive: true)
      let maximum = try Self.number(lot.maxQty, positive: true)
      guard minimum <= maximum else { throw FuturesMarketDataError.invalidResponse }
      return FuturesMarketContract(instrument: instrument, quantityStep: try Self.number(lot.stepSize, positive: true),
                                   minimumQuantity: minimum, maximumQuantity: maximum,
                                   minimumOrderAmount: try Self.number(filter("MIN_NOTIONAL").minimumOrderAmount, positive: true),
                                   priceTick: try Self.number(filter("PRICE_FILTER").tickSize, positive: true))
    }
  }

  // 완전히 닫힌 1분 구간만 요청한다. 부분 봉을 잘라서 검증 완료로 만들지 않는다.
  func markCandles(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<FuturesHistoryPage<FuturesMarkCandle>> {
    guard Self.validRange(start, endExclusive), start % 60_000 == 0, endExclusive % 60_000 == 0 else {
      return .error(FuturesMarketDataError.invalidRequest)
    }
    let pageEnd = start + min(endExclusive - start, 499 * 60_000)
    return request(.serverTime, instrument: instrument).flatMap { [self] data -> Single<Data> in
      let time = try JSONDecoder().decode(ServerTimeDTO.self, from: data).serverTime
      guard time > 0, pageEnd <= time - time % 60_000 else { throw FuturesMarketDataError.incompleteHistory }
      return request(.candles(instrument.rawSymbol, start, pageEnd), instrument: instrument)
    }.map { data in
      let rows = try JSONDecoder().decode([CandleDTO].self, from: data)
      let candles = try rows.map { try $0.domain() }.sorted { $0.openTime < $1.openTime }
      guard candles.count == Int((pageEnd - start) / 60_000) else { throw FuturesMarketDataError.incompleteHistory }
      for (index, candle) in candles.enumerated() {
        guard candle.openTime == start + Int64(index) * 60_000,
              candle.closeTime == candle.openTime + 59_999 else { throw FuturesMarketDataError.incompleteHistory }
      }
      return FuturesHistoryPage(instrument: instrument, values: candles, nextStartTime: pageEnd < endExclusive ? pageEnd : nil)
    }
  }

  // 조회 완료는 API 페이지 소진만 의미하며 펀딩 일정의 완전성 증명은 아니다.
  func funding(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<FuturesHistoryPage<FuturesFundingEvent>> {
    guard Self.validRange(start, endExclusive) else { return .error(FuturesMarketDataError.invalidRequest) }
    return request(.funding(instrument.rawSymbol, start, endExclusive), instrument: instrument).map { data in
      let rows = try JSONDecoder().decode([FundingDTO].self, from: data)
      guard rows.count <= 1000 else { throw FuturesMarketDataError.invalidResponse }
      let events = try rows.map { row -> FuturesFundingEvent in
        guard row.symbol == instrument.rawSymbol, row.fundingTime >= start, row.fundingTime < endExclusive,
              row.rateType == nil || row.rateType == "Regular" else { throw FuturesMarketDataError.invalidResponse }
        return FuturesFundingEvent(timestamp: row.fundingTime, rate: try Self.number(row.fundingRate),
                                   markPrice: try Self.number(row.markPrice, positive: true))
      }.sorted { $0.timestamp < $1.timestamp }
      guard Set(events.map(\.timestamp)).count == events.count else { throw FuturesMarketDataError.invalidResponse }
      let next = rows.count == 1000 ? events.last.map { $0.timestamp + 1 } : nil
      return FuturesHistoryPage(instrument: instrument, values: events, nextStartTime: next.flatMap { $0 < endExclusive ? $0 : nil })
    }
  }

  private func request(_ target: BinanceFuturesNetworkService, instrument: TradingInstrumentID) -> Single<Data> {
    guard instrument.exchange == .binance, instrument.product == .perpetual, instrument.settlementCurrency == .usdt,
          !instrument.rawSymbol.isEmpty,
          instrument.rawSymbol.range(of: "^[A-Z0-9]+USDT$", options: .regularExpression) != nil else {
      return .error(FuturesMarketDataError.unsupportedInstrument)
    }
    // 429/418을 포함한 실패는 상위 재시도 정책으로 전달하며 빈 성공으로 바꾸지 않는다.
    return Single.deferred { [provider] in provider.rx.request(target) }.map { response in
      guard (200..<300).contains(response.statusCode) else { throw FuturesMarketDataError.httpStatus(response.statusCode) }
      return response.data
    }
  }

  private static func validRange(_ start: Int64, _ end: Int64) -> Bool {
    start > 0 && end > start && end <= 253_402_300_799_000
  }

  fileprivate static func number(_ text: String?, positive: Bool = false) throws -> Decimal {
    guard let text, text.range(of: "^-?[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
          text.filter({ $0.isNumber }).count <= 38,
          let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN,
          !positive || value > 0 else { throw FuturesMarketDataError.invalidResponse }
    return value
  }
}

private struct ServerTimeDTO: Decodable { let serverTime: Int64 }
private struct MarkDTO: Decodable {
  let symbol: String
  let markPrice: String
  let time: Int64
}
private struct FundingDTO: Decodable {
  let symbol: String
  let fundingTime: Int64
  let fundingRate: String
  let markPrice: String
  let rateType: String?
}
private struct ExchangeDTO: Decodable { let symbols: [ContractDTO] }
private struct ContractDTO: Decodable {
  let symbol: String
  let status: String
  let contractType: String
  let quoteAsset: String
  let marginAsset: String
  let filters: [FilterDTO]
}
private struct FilterDTO: Decodable {
  let filterType: String
  let minQty: String?
  let maxQty: String?
  let stepSize: String?
  // 계약의 최소 주문금액으로 변환할 거래소 응답 문자열이다.
  let minimumOrderAmount: String?
  let tickSize: String?

  private enum CodingKeys: String, CodingKey {
    case filterType, minQty, maxQty, stepSize, tickSize
    case minimumOrderAmount = "notional"
  }
}
private struct CandleDTO: Decodable {
  let openTime: Int64
  let closeTime: Int64
  let open: String
  let high: String
  let low: String
  let close: String

  init(from decoder: Decoder) throws {
    var row = try decoder.unkeyedContainer()
    guard row.count == 12 else { throw FuturesMarketDataError.invalidResponse }
    openTime = try row.decode(Int64.self)
    open = try row.decode(String.self)
    high = try row.decode(String.self)
    low = try row.decode(String.self)
    close = try row.decode(String.self)
    _ = try row.decode(String.self)
    closeTime = try row.decode(Int64.self)
    _ = try row.decode(String.self)
    _ = try row.decode(Int.self)
    _ = try row.decode(String.self)
    _ = try row.decode(String.self)
    _ = try row.decode(String.self)
  }

  func domain() throws -> FuturesMarkCandle {
    let open = try BinanceFuturesMarketRepository.number(open, positive: true)
    let high = try BinanceFuturesMarketRepository.number(high, positive: true)
    let low = try BinanceFuturesMarketRepository.number(low, positive: true)
    let close = try BinanceFuturesMarketRepository.number(close, positive: true)
    guard low <= min(open, close), high >= max(open, close) else { throw FuturesMarketDataError.invalidResponse }
    return FuturesMarkCandle(openTime: openTime, closeTime: closeTime, open: open, high: high, low: low, close: close)
  }
}
