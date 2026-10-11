import Foundation
import Moya
import RxSwift

final class DomesticFuturesMarketRepository: FuturesDetailedMarketDataProviding {
  private let provider: MoyaProvider<DomesticFuturesNetworkService>
  private let now: () -> Date
  private let delay: RxTimeInterval
  private let scheduler = SerialDispatchQueueScheduler(qos: .utility)

  init(provider: MoyaProvider<DomesticFuturesNetworkService> = MoyaProvider<DomesticFuturesNetworkService>(),
       now: @escaping () -> Date = Date.init, requestDelay: RxTimeInterval = .milliseconds(150)) {
    self.provider = provider
    self.now = now
    self.delay = requestDelay
  }

  func markQuote(_ instrument: TradingInstrumentID) -> Single<FuturesMarkQuote> {
    request(.ticker, instrument: instrument).map { response in
      let rows = try JSONDecoder().decode([DomesticTickerDTO].self, from: response.data)
      guard rows.count == 1, let row = rows.first, row.market == instrument.rawSymbol, row.timestamp > 0 else {
        throw FuturesMarketDataError.invalidResponse
      }
      try Self.validatePrice(row.trade_price)
      return FuturesMarkQuote(
        instrument: instrument,
        price: row.trade_price,
        timestamp: row.calculateQuoteTimestamp(exchange: instrument.exchange),
        responseTimestamp: Self.serverTime(response)
      )
    }
  }

  // 국내 거래소의 실제 선물 계약 규칙은 없다. 모의 주문 규칙을 API에서 만들어내지 않는다.
  func contract(_ instrument: TradingInstrumentID) -> Single<FuturesMarketContract> {
    .error(FuturesMarketDataError.invalidRequest)
  }

  func funding(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<FuturesHistoryPage<FuturesFundingEvent>> {
    guard Self.supports(instrument), Self.validRange(start, endExclusive) else {
      return .error(FuturesMarketDataError.invalidRequest)
    }
    return .just(.init(instrument: instrument, values: [], nextStartTime: nil))
  }

  func markCandles(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<FuturesHistoryPage<FuturesMarkCandle>> {
    guard Self.validRange(start, endExclusive), start % 60_000 == 0, endExclusive % 60_000 == 0,
          endExclusive - start <= 499 * 60_000 else { return .error(FuturesMarketDataError.invalidRequest) }
    return minuteChunks(instrument, start: start, end: endExclusive).map {
      .init(instrument: instrument, values: $0, nextStartTime: nil)
    }
  }

  private func minuteChunks(_ instrument: TradingInstrumentID, start: Int64, end: Int64) -> Single<[FuturesMarkCandle]> {
    let pageEnd = min(end, start + 199 * 60_000)
    return candles(instrument, seconds: false, start: start, end: pageEnd).flatMap { [self] values in
      if pageEnd == end { return .just(values) }
      return minuteChunks(instrument, start: pageEnd, end: end).map { values + $0 }
    }
  }

  func secondCandles(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64) -> Single<FuturesHistoryPage<FuturesMarkCandle>> {
    guard instrument.exchange == .upbit, Self.validRange(start, endExclusive), start % 1000 == 0,
          endExclusive % 1000 == 0, endExclusive - start <= 199_000 else {
      return .error(FuturesMarketDataError.invalidRequest)
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let earliest = calendar.date(byAdding: .month, value: -3, to: now()),
          Double(start) / 1000 >= earliest.timeIntervalSince1970 else {
      return .error(FuturesMarketDataError.incompleteHistory)
    }
    return candles(instrument, seconds: true, start: start, end: endExclusive).map {
      .init(instrument: instrument, values: $0, nextStartTime: nil)
    }
  }

  private func candles(_ instrument: TradingInstrumentID, seconds: Bool, start: Int64, end: Int64) -> Single<[FuturesMarkCandle]> {
    request(.candles(seconds: seconds, to: end, count: 200), instrument: instrument).map { response in
      let unit: Int64 = seconds ? 1000 : 60_000
      // 로컬 시계가 빠르더라도 진행 중인 봉을 완료된 과거로 저장하지 않는다.
      guard let serverTime = Self.serverTime(response), end <= serverTime - serverTime % unit else {
        throw FuturesMarketDataError.incompleteHistory
      }
      let rows = try JSONDecoder().decode([DomesticCandleDTO].self, from: response.data)
      guard !rows.isEmpty, rows.count <= 200 else { throw FuturesMarketDataError.incompleteHistory }
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
      formatter.isLenient = false
      let values = try rows.map { try $0.domain(instrument: instrument, unit: unit, formatter: formatter) }.sorted { $0.openTime < $1.openTime }
      guard Set(values.map(\.openTime)).count == values.count, values.allSatisfy({ $0.openTime < end }) else {
        throw FuturesMarketDataError.invalidResponse
      }
      // 범위 시작 이전의 봉까지 확보해야 빈 구간을 무체결로 해석할 수 있다.
      guard let anchor = values.last(where: { $0.openTime < start }) else {
        throw FuturesMarketDataError.incompleteHistory
      }
      var previousClose = anchor.close
      let lookup = Dictionary(uniqueKeysWithValues: values.map { ($0.openTime, $0) })
      return stride(from: start, to: end, by: Int(unit)).map { time in
        if let candle = lookup[time] { previousClose = candle.close; return candle }
        return FuturesMarkCandle(openTime: time, closeTime: time + unit - 1,
          open: previousClose, high: previousClose, low: previousClose, close: previousClose)
      }
    }
  }

  // 한 페이지는 전체 기간 검증을 의미하지 않는다. 호출자가 cursor 소진/경계 도달을 확인한다.
  func tradePage(_ instrument: TradingInstrumentID, to: String? = nil, daysAgo: Int? = nil,
                 cursor: String? = nil) -> Single<FuturesTradePage> {
    guard daysAgo.map({ (1...7).contains($0) }) ?? true,
          cursor.map({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) ?? true,
          to.map(Self.validTradeTime) ?? true else { return .error(FuturesMarketDataError.invalidRequest) }
    return request(.trades(to: to, daysAgo: daysAgo, cursor: cursor), instrument: instrument).map { response in
      let rows = try JSONDecoder().decode([DomesticTradeDTO].self, from: response.data)
      guard rows.count <= 500 else { throw FuturesMarketDataError.invalidResponse }
      let ticks = try rows.map { row -> FuturesTradeTick in
        guard row.market == instrument.rawSymbol, row.timestamp > 0, row.sequential_id > 0 else {
          throw FuturesMarketDataError.invalidResponse
        }
        try Self.validatePrice(row.trade_price)
        return FuturesTradeTick(id: String(row.sequential_id), timestamp: row.timestamp, price: row.trade_price)
      }
      guard instrument.exchange == .bithumb || Set(ticks.map(\.id)).count == ticks.count else { throw FuturesMarketDataError.invalidResponse }
      for (a, b) in zip(ticks, ticks.dropFirst()) where a.timestamp < b.timestamp {
        throw FuturesMarketDataError.invalidResponse
      }
      if let cursor, ticks.contains(where: { $0.id == cursor }) { throw FuturesMarketDataError.incompleteHistory }
      return FuturesTradePage(instrument: instrument, trades: ticks,
        nextCursor: ticks.count == 500 ? ticks.last?.id : nil, serverTimestamp: Self.serverTime(response))
    }
  }

  func boundaryHistory(_ instrument: TradingInstrumentID, start: Int64, endExclusive: Int64,
                       initialEntry: Bool) -> Single<FuturesReplayBatch> {
    guard Self.supports(instrument), Self.validRange(start, endExclusive), endExclusive - start <= 60_000 else {
      return .error(FuturesMarketDataError.invalidRequest)
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: instrument.exchange == .upbit ? 0 : 9 * 3600)!
    let today = calendar.startOfDay(for: now())
    let startDate = Date(timeIntervalSince1970: Double(start) / 1000)
    let age = calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: today).day ?? Int.max
    let batch: ( [FuturesMarkCandle] ) -> FuturesReplayBatch = { candles in
      .init(instrument: instrument, start: start, endExclusive: endExclusive,
        candles: candles, funding: [], detailed: true)
    }
    if instrument.exchange == .upbit, start % 1000 == 0, endExclusive % 1000 == 0,
       let earliest = calendar.date(byAdding: .month, value: -3, to: now()), startDate >= earliest {
      return secondCandles(instrument, start: start, endExclusive: endExclusive).map { batch($0.values) }
    }
    if (0...7).contains(age) {
      return tickHistory(instrument, start: start, end: endExclusive, calendar: calendar, attempts: 0).map(batch)
    }
	if TradingRules.Futures.HistoryCheck.allowsEntrySecondCloseFallback(for: instrument.exchange), initialEntry, start % 1000 != 0,
	   endExclusive == start - start % 60_000 + 60_000,
	   let earliest = calendar.date(byAdding: .month, value: -3, to: now()),
	   Double(start - start % 1000) / 1000 >= earliest.timeIntervalSince1970 {
	  // 복원 불가능한 진입 초만 종가로 보완하고 이후 온전한 초봉의 고저가는 검증한다.
	  return secondCandles(
		instrument,
		start: start - start % 1000,
		endExclusive: endExclusive
	  ).map { page in
		guard let first = page.values.first else { throw FuturesMarketDataError.incompleteHistory }
		let boundary = FuturesMarkCandle(
		  openTime: start,
		  closeTime: first.closeTime,
		  open: first.close,
		  high: first.close,
		  low: first.close,
		  close: first.close
		)
		return .init(
		  instrument: instrument,
		  start: start,
		  endExclusive: endExclusive,
		  candles: [boundary] + page.values.dropFirst(),
		  funding: [],
		  detailed: true,
		  entryCloseFallback: true
		)
	  }
	}
    // 보존 기간이 지난 최초 진입 분에만 합의한 마감가 규칙을 적용한다. API 오류는 대체하지 않는다.
    guard initialEntry, start % 60_000 != 0, endExclusive == start - start % 60_000 + 60_000 else {
      return .error(FuturesMarketDataError.incompleteHistory)
    }
    return markCandles(instrument, start: start - start % 60_000, endExclusive: endExclusive).map { page in
      guard let close = page.values.last?.close else { throw FuturesMarketDataError.incompleteHistory }
      return .init(instrument: instrument, start: start, endExclusive: endExclusive,
        candles: [.init(openTime: start, closeTime: endExclusive - 1, open: close, high: close, low: close, close: close)],
        funding: [], detailed: true, entryCloseFallback: true)
    }
  }

  private func tickHistory(_ instrument: TradingInstrumentID, start: Int64, end: Int64,
                           calendar: Calendar, attempts: Int) -> Single<[FuturesMarkCandle]> {
    if instrument.exchange == .bithumb, end - start > 5_000 {
      let middle = min(end, (start / 1000) * 1000 + 5_000)
      return tickHistory(instrument, start: start, end: middle, calendar: calendar, attempts: attempts).flatMap { [self] first in
        tickHistory(instrument, start: middle, end: end, calendar: calendar, attempts: attempts).map { first + $0 }
      }
    }
    let upper = ((end + 999) / 1000) * 1000
    let upperDate = Date(timeIntervalSince1970: Double(upper) / 1000)
    let queryDate = instrument.exchange == .upbit ? upperDate.addingTimeInterval(-0.001) : upperDate
    let requestDay = calendar.startOfDay(for: now())
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: queryDate), to: requestDay).day ?? -1
    guard (0...7).contains(days) else { return .error(FuturesMarketDataError.incompleteHistory) }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "HHmmss"
    let midnight = calendar.startOfDay(for: upperDate) == upperDate
    let to: String? = instrument.exchange == .upbit && midnight ? nil : formatter.string(from: upperDate)
    return collectTrades(instrument, start: start, upper: upper, to: to, days: days == 0 ? nil : days,
      cursor: nil, collected: [], pages: 0, requestDay: requestDay, calendar: calendar).flatMap { [self] ticks, server in
      guard server >= upper else {
        guard attempts < 2 else { return .error(FuturesMarketDataError.incompleteHistory) }
        return Single.just(()).delay(.seconds(1), scheduler: scheduler).flatMap {
          self.tickHistory(instrument, start: start, end: end, calendar: calendar, attempts: attempts + 1)
        }
      }
      if let anchor = ticks.first(where: { $0.timestamp < start }) {
        return .just(try Self.tickCandles(ticks, start: start, end: end, anchor: anchor.price))
      }
      // 일자별 API가 전날 체결을 생략해도 이전 완료 분봉의 종가로 시작 가격을 확보한다.
      let floor = start - start % 60_000
      return markCandles(instrument, start: floor - 60_000, endExclusive: floor).map { page in
        guard let price = page.values.last?.close else { throw FuturesMarketDataError.incompleteHistory }
        return try Self.tickCandles(ticks, start: start, end: end, anchor: price)
      }
    }
  }

  private func collectTrades(_ instrument: TradingInstrumentID, start: Int64, upper: Int64, to: String?, days: Int?,
                             cursor: String?, collected: [FuturesTradeTick], pages: Int,
                             requestDay: Date, calendar: Calendar) -> Single<([FuturesTradeTick], Int64)> {
    guard pages < 20 else { return .error(FuturesMarketDataError.workLimit) }
    return tradePage(instrument, to: to, daysAgo: days, cursor: cursor).flatMap { [self] page in
      guard let server = page.serverTimestamp,
            calendar.startOfDay(for: Date(timeIntervalSince1970: Double(server) / 1000)) == requestDay,
            page.trades.allSatisfy({ $0.timestamp < upper }),
            Set(collected.map(\.id)).isDisjoint(with: Set(page.trades.map(\.id))),
            page.trades.first.map({ $0.timestamp <= (collected.last?.timestamp ?? Int64.max) }) ?? true else {
        throw FuturesMarketDataError.incompleteHistory
      }
      let ticks = collected + page.trades
      if page.trades.last.map({ $0.timestamp < start }) == true || page.nextCursor == nil {
        return .just((ticks, server))
      }
      // 빗썸 cursor는 같은 밀리초 체결끼리 중복된다. 잘린 밀리초를 건너뛰어 안전 판정하지 않는다.
      guard instrument.exchange != .bithumb else { throw FuturesMarketDataError.incompleteHistory }
      return collectTrades(instrument, start: start, upper: upper, to: to, days: days,
        cursor: page.nextCursor, collected: ticks, pages: pages + 1, requestDay: requestDay, calendar: calendar)
    }
  }

  private static func tickCandles(_ ticks: [FuturesTradeTick], start: Int64, end: Int64,
                                  anchor: Decimal) throws -> [FuturesMarkCandle] {
    try validatePrice(anchor)
    let groups = Dictionary(grouping: ticks.filter { $0.timestamp >= start && $0.timestamp < end }, by: \.timestamp)
    var cursor = start
    var price = anchor
    var candles: [FuturesMarkCandle] = []
    for time in groups.keys.sorted() {
      if cursor < time {
        candles.append(.init(openTime: cursor, closeTime: time - 1, open: price, high: price, low: price, close: price))
      }
      guard let trades = groups[time], let latest = trades.first, let earliest = trades.last,
            let low = trades.map(\.price).min(), let high = trades.map(\.price).max() else {
        throw FuturesMarketDataError.invalidResponse
      }
      candles.append(.init(openTime: time, closeTime: time, open: earliest.price, high: high, low: low, close: latest.price))
      cursor = time + 1
      price = latest.price
    }
    if cursor < end {
      candles.append(.init(openTime: cursor, closeTime: end - 1, open: price, high: price, low: price, close: price))
    }
    return candles
  }

  private func request(_ query: DomesticFuturesNetworkService.Query, instrument: TradingInstrumentID) -> Single<Response> {
    guard Self.supports(instrument) else { return .error(FuturesMarketDataError.unsupportedInstrument) }
    let target = DomesticFuturesNetworkService(exchange: instrument.exchange, market: instrument.rawSymbol, query: query)
    return Single.deferred { [provider] in provider.rx.request(target) }
      .delaySubscription(delay, scheduler: scheduler).observe(on: scheduler).map { response in
        guard (200..<300).contains(response.statusCode) else { throw FuturesMarketDataError.httpStatus(response.statusCode) }
        return response
      }
  }

  private static func supports(_ instrument: TradingInstrumentID) -> Bool {
    TradingRules.DomesticFutures.supportsHistoryInstrument(instrument) &&
      TradingAccountID(exchange: instrument.exchange, product: .perpetual, currency: .krw).supports(instrument)
  }
  private static func validRange(_ start: Int64, _ end: Int64) -> Bool {
    start > 0 && end > start && end <= 253_402_300_799_000
  }
  private static func validTradeTime(_ value: String) -> Bool {
    guard value.range(of: "^(?:[0-9]{6}|[0-9]{2}:[0-9]{2}:[0-9]{2})$", options: .regularExpression) != nil else { return false }
    let parts = value.replacingOccurrences(of: ":", with: "")
    guard parts.count == 6, parts.utf8.allSatisfy({ (48...57).contains($0) }),
          let hour = Int(parts.prefix(2)), let minute = Int(parts.dropFirst(2).prefix(2)), let second = Int(parts.suffix(2)) else { return false }
    return hour < 24 && minute < 60 && second < 60
  }
  fileprivate static func validatePrice(_ price: Decimal) throws {
    guard !price.isNaN, price > 0 else { throw FuturesMarketDataError.invalidResponse }
  }
  private static func serverTime(_ response: Response) -> Int64? {
    guard let header = response.response?.value(forHTTPHeaderField: "Date") else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    guard let date = formatter.date(from: header) else { return nil }
    return try? FuturesHistoryCheckState.milliseconds(date)
  }
}

private struct DomesticTickerDTO: Decodable {
  let market: String
  let trade_price: Decimal
  let timestamp: Int64
  // 빗썸의 시각 오프셋을 실제 UTC 체결 일시와 대조한다.
  let trade_date: String?
  // UTC 체결 일자와 합쳐 초 단위 경계를 복원한다.
  let trade_time: String?
  // 현재가 생성 시각에도 같은 오프셋이 있는지 확인한다.
  let trade_timestamp: Int64?

  func calculateQuoteTimestamp(exchange: Exchange) -> Int64 {
    guard exchange == .bithumb, let trade_date, let trade_time, let trade_timestamp else { return timestamp }
    // UTC 문자열로 9시간 오프셋이 입증된 응답만 보정해 실제 미래 시세는 계속 거절한다.
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMddHHmmss"
    formatter.isLenient = false
    // API의 UTC 체결 일시를 손실 없이 검증할 문자열이다.
    let tradeTime = trade_date + trade_time
    guard let date = formatter.date(from: tradeTime), formatter.string(from: date) == tradeTime,
      let utcTimestamp = try? FuturesHistoryCheckState.milliseconds(date)
    else { return timestamp }
    // 빗썸이 KST를 Unix timestamp로 인코딩한 경우에만 제거할 오프셋이다.
    let offset: Int64 = 9 * 60 * 60 * 1000
    guard trade_timestamp - trade_timestamp % 1000 == utcTimestamp + offset,
      timestamp - timestamp % 1000 == utcTimestamp + offset
    else { return timestamp }
    return timestamp - offset
  }
}
private struct DomesticTradeDTO: Decodable {
  let market: String
  let trade_price: Decimal
  let timestamp: Int64
  let sequential_id: Int64
}
private struct DomesticCandleDTO: Decodable {
  let market: String
  let candle_date_time_utc: String
  let opening_price: Decimal
  let high_price: Decimal
  let low_price: Decimal
  let trade_price: Decimal
  let unit: Int?

  func domain(instrument: TradingInstrumentID, unit duration: Int64, formatter: DateFormatter) throws -> FuturesMarkCandle {
    guard market == instrument.rawSymbol, (duration == 1000 || unit == 1),
          let date = formatter.date(from: candle_date_time_utc), formatter.string(from: date) == candle_date_time_utc else {
      throw FuturesMarketDataError.invalidResponse
    }
    let start = try FuturesHistoryCheckState.milliseconds(date)
    guard start % duration == 0 else { throw FuturesMarketDataError.invalidResponse }
    for value in [opening_price, high_price, low_price, trade_price] { try DomesticFuturesMarketRepository.validatePrice(value) }
    guard low_price <= min(opening_price, trade_price), high_price >= max(opening_price, trade_price) else {
      throw FuturesMarketDataError.invalidResponse
    }
    return FuturesMarkCandle(openTime: start, closeTime: start + duration - 1,
      open: opening_price, high: high_price, low: low_price, close: trade_price)
  }
}
