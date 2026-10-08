import UIKit

enum FuturesText {
  static func text(_ key: String) -> String {
	let table = Locale.preferredLanguages.first?.hasPrefix("ko") == true ? "Localizable(KO)" : "Localizable(EN)"
	return NSLocalizedString(key, tableName: table, bundle: .main, value: key, comment: "")
  }

  static func number(_ value: Decimal?, digits: Int? = nil) -> String {
	guard let digits else { return TradingNumberFormat.string(value) }
	guard let value, !value.isNaN else { return "—" }
	let formatter = NumberFormatter()
	formatter.numberStyle = .decimal
	formatter.maximumFractionDigits = digits
	return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
  }

  static func date(_ value: Date) -> String {
	let formatter = DateFormatter()
	formatter.dateFormat = "yyyy.MM.dd HH:mm:ss"
	return formatter.string(from: value)
  }

  static func occurrenceDate(_ record: FuturesTransactionRecord) -> String {
	// 청산 외 진입·부분 종료 내역은 기존 초 단위 시각을 유지한다.
	let value = Date(timeIntervalSince1970: Double(record.occurredMinute ?? record.intervalStart) / 1000)
	guard record.kind == .liquidation else { return date(value) }
	// 청산은 정밀 검증 범위나 뒤늦은 정산 시각 대신 실제 발생 분만 표시한다.
	let formatter = DateFormatter()
	formatter.locale = Locale(identifier: "en_US_POSIX")
	formatter.dateFormat = "yyyy.MM.dd HH:mm"
	return formatter.string(from: value)
  }

  static func side(_ value: FuturesSide) -> String { text(value == .long ? "futures_long" : "futures_short") }
  static func symbol(_ instrument: TradingInstrumentID) -> String {
	MarketFormat.displayMarket(fromAPIMarket: instrument.rawSymbol)
  }

  static func error(_ error: Error) -> String {
	if let error = error as? LocalFuturesAccountRepository.StoreError {
	  switch error {
	  case .insufficientBalance: return text("futures_insufficient")
	  case .positionClosed: return text("futures_position_closed")
	  case .positionAlreadyOpen, .conflictingOrder: return text("futures_same_conditions")
	  case .revisionConflict, .historyCheckRequired: return text("futures_retry_order")
	  default: return text("futures_storage_error")
	  }
	}
	if let error = error as? FuturesCalculationError {
	  switch error {
	  case .belowMinimumOrder: return text("futures_minimum")
	  case .invalidLeverage: return text("futures_leverage_error")
	  case .insufficientMargin: return text("futures_insufficient")
	  default: return text("futures_input_error")
	  }
	}
	if error as? FuturesOrderCheckError == .historyCheckInProgress { return text("futures_wait") }
	return text("futures_retry_order")
  }

  static func status(_ reactor: FuturesAccountReactor) -> String {
	if reactor.currentState.loadFailed { return text("futures_storage_error") }
	if reactor.currentState.submitting { return text("futures_submitting") }
	if case .storageFailed = reactor.currentState.status { return text("futures_storage_error") }
	return ""
  }

  static func shareUnit(_ record: FuturesTransactionRecord, position: FuturesPosition) throws -> PNLShareUnit {
	guard let pnl = record.realizedPnL else { throw FuturesHistoryCheckError.invalidState }
	let rate = try FuturesDecimal.multiply(FuturesDecimal.divide(pnl, record.margin ?? position.margin), 100)
	return PNLShareUnit(
	  marketName: "\(symbol(record.instrument)) · \(side(record.side)) \(record.leverage)×",
	  roi: NSDecimalNumber(decimal: rate).doubleValue,
	  pnl: NSDecimalNumber(decimal: pnl).doubleValue,
	  quantity: NSDecimalNumber(decimal: record.quantity).doubleValue,
	  entryPrice: NSDecimalNumber(decimal: try record.entryPrice ?? position.averageEntryPrice).doubleValue,
	  exitPrice: NSDecimalNumber(decimal: record.price).doubleValue,
	  transactionDate: record.kind == .liquidation ? occurrenceDate(record) : date(record.recordedAt),
	  currency: record.instrument.settlementCurrency.rawValue,
	  product: record.instrument.product,
	  exchange: record.instrument.exchange
	)
  }

  static func valuation(
	_ position: FuturesPosition,
	quotes: [TradingInstrumentID: FuturesMarkQuote]
  ) throws -> FuturesValuation? {
	// 기기·거래소 시계 차이 때문에 이미 받은 가격을 숨기지 않는다. 정산 검증은 별도다.
	guard let quote = quotes[position.order.instrument], quote.instrument == position.order.instrument
	else { return nil }
	return try FuturesCalculator.evaluate(position, markPrice: quote.price)
  }

  static func position(
	_ position: FuturesPosition,
	snapshot: FuturesAccountSnapshot,
	quotes: [TradingInstrumentID: FuturesMarkQuote]
  ) throws -> String {
	let instrument = position.order.instrument
	let quote = quotes[instrument]
	let value = try valuation(position, quotes: quotes)
	let liquidation = try FuturesCalculator.estimatedLiquidationPrice(position)
	return [
	  "\(symbol(instrument)) · \(side(position.order.side)) \(position.order.leverage)×",
	  "\(text("futures_pnl")) \(number(try value?.displayedPnL)) \(text("currency_krw_unit"))  ·  \(number(value?.displayedROEPercent, digits: 2))%",
	  "\(text("futures_entry")) \(number(try position.averageEntryPrice)) / \(text("futures_current")) \(number(value == nil ? nil : quote?.price))",
	  "\(text("futures_liquidation_price")) \(number(liquidation)) \(text("currency_krw_unit"))",
	  "\(text("futures_margin")) \(number(try position.margin)) \(text("currency_krw_unit")) · \(text("futures_quantity")) \(number(position.quantity))",
	  "\(text("futures_opened")) \(date(position.order.executedAt))"
	].joined(separator: "\n")
  }

  static func label(style: UIFont.TextStyle = .body) -> UILabel {
	let label = UILabel()
	label.font = .preferredFont(forTextStyle: style)
	label.adjustsFontForContentSizeCategory = true
	label.numberOfLines = 0
	label.textColor = .mobitColors(.textPrimary)
	return label
  }

  static func button(_ key: String, filled: Bool = false, action: @escaping () -> Void) -> UIButton {
	let button = UIButton(type: .system)
	var configuration = filled ? UIButton.Configuration.filled() : .tinted()
	configuration.title = text(key)
	configuration.baseBackgroundColor = .mobitColors(filled ? .accentButton : .accentPrimary)
	configuration.baseForegroundColor = filled ? .white : .mobitColors(.accentPrimary)
	configuration.cornerStyle = .fixed
	configuration.background.cornerRadius = 8
	configuration.contentInsets = .init(top: 12, leading: 16, bottom: 12, trailing: 16)
	button.configuration = configuration
	button.titleLabel?.adjustsFontForContentSizeCategory = true
	button.addAction(UIAction { _ in action() }, for: .touchUpInside)
	button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
	return button
  }
}
