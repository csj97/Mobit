//
//  SocketManager.swift
//  Mobit
//
//  Created by 조성재 on 11/5/24.
//

import Foundation
import Starscream
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

final class UpbitWebSocketClient: WebSocketDelegate, WebSocketClientProtocol {
  private let socket: WebSocket
  private let socketType: SocketType
  private let connectedSubject = PublishSubject<Void>()
  private let dataSubject = PublishSubject<Data>()
  
  private(set) var isConnected = false
  private var isConnecting = false
  private var isUserInitiatedDisconnect = false
  
  init(socketType: SocketType) {
	self.socketType = socketType
	
	let url = URL(string: "wss://api.upbit.com/websocket/v1")!
	var request = URLRequest(url: url)
	request.timeoutInterval = 5
	
	self.socket = WebSocket(request: request)
	self.socket.delegate = self
  }
  
  var onConnected: Observable<Void> {
	connectedSubject.asObservable()
  }
  
  var rawDataStream: Observable<Data> {
	dataSubject.asObservable()
  }
  
  func connect() {
	guard !isConnected, !isConnecting else { return }
	isUserInitiatedDisconnect = false
	isConnecting = true
	socket.connect()
  }
  
  func disconnect(userInitiated: Bool = false) {
	isUserInitiatedDisconnect = userInitiated
	guard isConnected || isConnecting else { return }
	
	Log.info("Disconnecting \(socketType.rawValue) socket...")
    isConnecting = false
	socket.disconnect()
  }
  
  func reconnectIfNeeded() {
	guard !isUserInitiatedDisconnect, !isConnected else { return }
	Log.info("Reconnecting \(socketType.rawValue) socket...")
	connect()
  }
  
  func sendSubscription(codes: [String]) {
	guard isConnected, !codes.isEmpty else { return }
	
	let ticket = ["ticket": UUID().uuidString]
	let subscribe: [String: Any] = [
	  "type": socketType.rawValue,
	  "codes": codes
	]
	let messages = [ticket, subscribe]
	
	guard let data = try? JSONSerialization.data(withJSONObject: messages) else {
	  return
	}
	
	socket.write(data: data) {
	  Log.info("\(self.socketType.rawValue) subscription sent")
	}
  }
  
  func didReceive(
	event: Starscream.WebSocketEvent,
	client: any Starscream.WebSocketClient
  ) {
	switch event {
	case .connected:
      isConnecting = false
	  isConnected = true
	  logConnectionEvent("connected")
	  connectedSubject.onNext(())
	  
	case .disconnected(let reason, let code):
      isConnecting = false
	  isConnected = false
	  logConnectionEvent("disconnected: \(reason) with code: \(code)")
	  
	case .text(let text):
	  Log.info("Received \(socketType.rawValue) text: \(text)")
	  
	case .binary(let data):
	  dataSubject.onNext(data)
	  
	case .error(let error):
      isConnecting = false
	  isConnected = false
	  Log.info("\(socketType.rawValue) socket error: \(String(describing: error))")
	  
	case .cancelled:
      isConnecting = false
	  isConnected = false
	  logConnectionEvent("cancelled")
	  
	case .ping, .pong:
	  break
	  
	case .viabilityChanged(let isViable):
	  Log.info("\(socketType.rawValue) viability changed: \(isViable)")
	  
	case .reconnectSuggested(let shouldReconnect):
	  Log.info("\(socketType.rawValue) reconnect suggested: \(shouldReconnect)")
	  
	case .peerClosed:
	  Log.info("\(socketType.rawValue) peer closed connection")
	}
  }
  
  private func logConnectionEvent(_ message: String) {
	let dateFormatter = DateFormatter()
	dateFormatter.timeZone = TimeZone(identifier: "Asia/Seoul")
	dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
	
	let koreaTimeString = dateFormatter.string(from: Date())
	Log.info("------------------------------------------------------")
	Log.info("현재시간 : \(koreaTimeString)")
	Log.info("\(socketType.rawValue) socket \(message)")
	Log.info("------------------------------------------------------")
  }
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
		  Log.error("Ticker websocket decode error: \(error.localizedDescription)")
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
		  Log.error("Orderbook websocket decode error: \(error.localizedDescription)")
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
