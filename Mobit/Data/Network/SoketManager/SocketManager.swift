//
//  SocketManager.swift
//  Mobit
//
//  Created by 조성재 on 11/5/24.
//

import Foundation
import RxSwift

protocol SocketControllable {
  func pauseSocket()
  func resumeSocket()
}

enum SocketType: String {
  case ticker = "ticker"
  case orderbook = "orderbook"
}

protocol SocketConnectable: AnyObject {
  var isConnected: Bool { get }
  func connect()
  func disconnect(userInitiated: Bool)
  func reconnectIfNeeded()
}

protocol WebSocketClientProtocol: SocketConnectable {
  var onConnected: Observable<Void> { get }
  var rawDataStream: Observable<Data> { get }
  func sendSubscription(codes: [String])
}

protocol TickerSocketServiceProtocol: SocketConnectable {
  var stream: Observable<CryptoSocketTicker> { get }
  func subscribe(markets: [String])
}

protocol OrderBookSocketServiceProtocol: SocketConnectable {
  var stream: Observable<Orderbook> { get }
  func subscribe(market: String)
}

final class TickerSocketService: TickerSocketServiceProtocol {
  private let client: WebSocketClientProtocol
  private let exchangeProvider: ExchangeMarketDataProviding
  private let disposeBag = DisposeBag()
  private var subscribedMarkets: [String] = []
  private var sentMarkets: [String] = []
  
  lazy var stream: Observable<CryptoSocketTicker> = {
	client.rawDataStream
	  .compactMap { [weak self] data in
		guard let self = self else { return nil }
		
		do {
		  return try self.exchangeProvider.decodeTickerWebSocketMessage(
            from: data
          )
		} catch {
		  Log.error(SocketDecodeLog.message(
            title: "Ticker websocket decode error",
            error: error,
            data: data
          ))
		  return nil
		}
	  }
	  .share()
  }()
  
  init(
    client: WebSocketClientProtocol? = nil,
    exchangeProvider: ExchangeMarketDataProviding = ExchangeAdapterRegistry.default
  ) {
    self.exchangeProvider = exchangeProvider
	self.client = client ?? exchangeProvider.makeTickerWebSocketClient()
	
	self.client.onConnected
	  .subscribe(onNext: { [weak self] in
		self?.resubscribeIfNeeded()
	  })
	  .disposed(by: disposeBag)
  }
  
  var isConnected: Bool {
	client.isConnected
  }
  
  func connect() {
	client.connect()
  }
  
  func disconnect(userInitiated: Bool = false) {
    if userInitiated {
      subscribedMarkets = []
      sentMarkets = []
    }
	client.disconnect(userInitiated: userInitiated)
  }
  
  func reconnectIfNeeded() {
	client.reconnectIfNeeded()
  }
  
  func subscribe(markets: [String]) {
	let markets = Array(Set(markets)).sorted()
    guard subscribedMarkets != markets || sentMarkets != markets else { return }
    subscribedMarkets = markets
	guard client.isConnected else { return }
    sendSubscriptionIfNeeded(force: false)
  }
  
  private func resubscribeIfNeeded() {
	guard !subscribedMarkets.isEmpty else { return }
	sendSubscriptionIfNeeded(force: true)
  }

  private func sendSubscriptionIfNeeded(force: Bool) {
    guard client.isConnected, !subscribedMarkets.isEmpty else { return }
    guard force || sentMarkets != subscribedMarkets else { return }
    client.sendSubscription(codes: subscribedMarkets)
    sentMarkets = subscribedMarkets
  }
}

final class OrderBookSocketService: OrderBookSocketServiceProtocol {
  private let client: WebSocketClientProtocol
  private let exchangeProvider: ExchangeMarketDataProviding
  private let disposeBag = DisposeBag()
  private var subscribedMarket: String?
  private var sentMarket: String?
  
  lazy var stream: Observable<Orderbook> = {
	client.rawDataStream
	  .compactMap { [weak self] data in
		guard let self = self else { return nil }
		
		do {
		  return try self.exchangeProvider.decodeOrderBookWebSocketMessage(
            from: data
          )
		} catch {
		  Log.error(SocketDecodeLog.message(
            title: "Orderbook websocket decode error",
            error: error,
            data: data
          ))
		  return nil
		}
	  }
	  .share()
  }()
  
  init(
    client: WebSocketClientProtocol? = nil,
    exchangeProvider: ExchangeMarketDataProviding = ExchangeAdapterRegistry.default
  ) {
    self.exchangeProvider = exchangeProvider
	self.client = client ?? exchangeProvider.makeOrderBookWebSocketClient()
	
	self.client.onConnected
	  .subscribe(onNext: { [weak self] in
		self?.resubscribeIfNeeded()
	  })
	  .disposed(by: disposeBag)
  }
  
  var isConnected: Bool {
	client.isConnected
  }
  
  func connect() {
	client.connect()
  }
  
  func disconnect(userInitiated: Bool = false) {
    if userInitiated {
      subscribedMarket = nil
      sentMarket = nil
    }
	client.disconnect(userInitiated: userInitiated)
  }
  
  func reconnectIfNeeded() {
	client.reconnectIfNeeded()
  }
  
  func subscribe(market: String) {
    guard subscribedMarket != market || sentMarket != market else { return }
	subscribedMarket = market
	guard client.isConnected else { return }
	sendSubscriptionIfNeeded(force: false)
  }
  
  private func resubscribeIfNeeded() {
	guard subscribedMarket != nil else { return }
	sendSubscriptionIfNeeded(force: true)
  }

  private func sendSubscriptionIfNeeded(force: Bool) {
    guard client.isConnected, let subscribedMarket else { return }
    guard force || sentMarket != subscribedMarket else { return }
    client.sendSubscription(codes: [subscribedMarket])
    sentMarket = subscribedMarket
  }
}

private enum SocketDecodeLog {
  static func message(
    title: String,
    error: Error,
    data: Data
  ) -> String {
    "\(title): \(self.errorDescription(error)) | payload: \(self.payloadPreview(from: data))"
  }

  private static func errorDescription(_ error: Error) -> String {
    guard let decodingError = error as? DecodingError else {
      return error.localizedDescription
    }

    switch decodingError {
    case .keyNotFound(let key, let context):
      return "keyNotFound(\(key.stringValue)) path=\(self.pathDescription(context.codingPath)) description=\(context.debugDescription)"

    case .typeMismatch(let type, let context):
      return "typeMismatch(\(type)) path=\(self.pathDescription(context.codingPath)) description=\(context.debugDescription)"

    case .valueNotFound(let type, let context):
      return "valueNotFound(\(type)) path=\(self.pathDescription(context.codingPath)) description=\(context.debugDescription)"

    case .dataCorrupted(let context):
      return "dataCorrupted path=\(self.pathDescription(context.codingPath)) description=\(context.debugDescription)"

    @unknown default:
      return error.localizedDescription
    }
  }

  private static func pathDescription(_ codingPath: [CodingKey]) -> String {
    guard !codingPath.isEmpty else { return "(root)" }
    return codingPath.map { $0.stringValue }.joined(separator: ".")
  }

  private static func payloadPreview(from data: Data) -> String {
    guard let rawString = String(data: data, encoding: .utf8) else {
      return "<\(data.count) bytes binary>"
    }
    let maxLength = 500
    guard rawString.count > maxLength else { return rawString }
    return String(rawString.prefix(maxLength)) + "...<truncated>"
  }
}
