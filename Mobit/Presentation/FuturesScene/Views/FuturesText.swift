import UIKit

enum FuturesText {
  static func text(_ key: String) -> String {
    let table = Locale.preferredLanguages.first?.hasPrefix("ko") == true ? "Localizable(KO)" : "Localizable(EN)"
    return NSLocalizedString(key, tableName: table, bundle: .main, value: key, comment: "")
  }

  static func number(_ value: Decimal?, digits: Int = 0) -> String {
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

  static func side(_ value: FuturesSide) -> String { text(value == .long ? "futures_long" : "futures_short") }
  static func symbol(_ instrument: TradingInstrumentID) -> String { MarketFormat.displayMarket(fromAPIMarket: instrument.rawSymbol) }

  static func error(_ error: Error) -> String {
    if let error = error as? LocalFuturesAccountRepository.StoreError {
      switch error {
      case .insufficientBalance: return text("futures_insufficient")
      case .positionClosed: return text("futures_position_closed")
      case .positionAlreadyOpen, .conflictingOrder: return text("futures_same_conditions")
      case .revisionConflict, .reconciliationRequired: return text("futures_retry_order")
      default: return text("futures_storage_error")
      }
    }
    if let error = error as? FuturesCalculationError {
      switch error {
      case .belowMinimumOrder: return text("futures_minimum")
      case .invalidLeverage: return text("futures_leverage_error")
      case .insufficientCollateral: return text("futures_insufficient")
      default: return text("futures_input_error")
      }
    }
    if error as? FuturesOrderPreflightError == .reconciliationInProgress { return text("futures_wait") }
    return text("futures_retry_order")
  }

  static func status(_ reactor: FuturesAccountReactor) -> String {
    if reactor.currentState.loadFailed { return text("futures_storage_error") }
    if reactor.currentState.submitting { return text("futures_submitting") }
    if case .storageFailed = reactor.currentState.status { return text("futures_storage_error") }
    return ""
  }

  static func shareUnit(_ record: FuturesTransactionRecord, position: FuturesPosition) throws -> PNLShareUnit {
    guard let pnl = record.realizedPnL else { throw FuturesReconciliationError.invalidState }
    let rate = try FuturesDecimal.multiply(FuturesDecimal.divide(pnl, position.margin), 100)
	return PNLShareUnit(
	  marketName: "\(symbol(record.instrument)) · \(side(record.side)) \(record.leverage)×",
	  roi: NSDecimalNumber(decimal: rate).doubleValue,
	  pnl: NSDecimalNumber(decimal: pnl).doubleValue,
	  quantity: NSDecimalNumber(decimal: record.quantity).doubleValue,
	  entryPrice: NSDecimalNumber(decimal: try position.averageEntryPrice).doubleValue,
	  exitPrice: NSDecimalNumber(decimal: record.price).doubleValue,
	  transactionDate: date(record.recordedAt),
	  currency: record.instrument.settlementCurrency.rawValue,
	  product: record.instrument.product,
	  exchange: record.instrument.exchange
	)
  }

  static func valuation(
	_ position: FuturesPosition,
	quotes: [TradingInstrumentID: FuturesMarkQuote],
	now: Date = Date()
  ) throws -> FuturesValuation? {
    let timestamp = try FuturesReconciliationState.milliseconds(now)
    guard let quote = quotes[position.order.instrument], quote.instrument == position.order.instrument,
          quote.timestamp > 0, quote.timestamp <= timestamp else { return nil }
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
      "\(text("futures_pnl")) \(number(try value?.displayedPnL)) KRW  ·  \(number(value?.displayedROEPercent, digits: 2))%",
      "\(text("futures_entry")) \(number(try position.averageEntryPrice, digits: 4)) / \(text("futures_current")) \(number(value == nil ? nil : quote?.price, digits: 4))",
      "\(text("futures_liquidation_price")) \(number(liquidation, digits: 4)) KRW",
      "\(text("futures_margin")) \(number(try position.margin)) KRW · \(text("futures_quantity")) \(number(position.quantity, digits: 8))",
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
    configuration.baseBackgroundColor = .systemBlue
    configuration.cornerStyle = .capsule
    configuration.contentInsets = .init(top: 12, leading: 16, bottom: 12, trailing: 16)
    button.configuration = configuration
    button.titleLabel?.adjustsFontForContentSizeCategory = true
    button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    return button
  }
}
