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

protocol TickerSocketServiceProtocol: SocketConnectable {
  var stream: Observable<CryptoSocketTicker> { get }
  func subscribe(markets: [String])
}

protocol OrderBookSocketServiceProtocol: SocketConnectable {
  var stream: Observable<Orderbook> { get }
  func subscribe(market: String)
}

final class UpbitWebSocketClient: WebSocketDelegate, SocketConnectable {
  private let socket: WebSocket
  private let socketType: SocketType
  private let connectedSubject = PublishSubject<Void>()
  private let dataSubject = PublishSubject<Data>()
  
  private(set) var isConnected = false
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
	guard !isConnected else { return }
	isUserInitiatedDisconnect = false
	socket.connect()
  }
  
  func disconnect(userInitiated: Bool = false) {
	isUserInitiatedDisconnect = userInitiated
	guard isConnected else { return }
	
	Log.info("Disconnecting \(socketType.rawValue) socket...")
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
	  isConnected = true
	  logConnectionEvent("connected")
	  connectedSubject.onNext(())
	  
	case .disconnected(let reason, let code):
	  isConnected = false
	  logConnectionEvent("disconnected: \(reason) with code: \(code)")
	  
	case .text(let text):
	  Log.info("Received \(socketType.rawValue) text: \(text)")
	  
	case .binary(let data):
	  dataSubject.onNext(data)
	  
	case .error(let error):
	  isConnected = false
	  Log.info("\(socketType.rawValue) socket error: \(String(describing: error))")
	  
	case .cancelled:
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
  private let client: UpbitWebSocketClient
  private let disposeBag = DisposeBag()
  private let decoder = JSONDecoder()
  private var subscribedMarkets: [String] = []
  
  lazy var stream: Observable<CryptoSocketTicker> = {
	client.rawDataStream
	  .compactMap { [weak self] data in
		guard let self = self else { return nil }
		
		do {
		  let dto = try self.decoder.decode(CryptoSocketTickerDTO.self, from: data)
		  return dto.toDomain()
		} catch {
		  Log.error("Ticker websocket decode error: \(error.localizedDescription)")
		  return nil
		}
	  }
	  .share()
  }()
  
  init(client: UpbitWebSocketClient = UpbitWebSocketClient(socketType: .ticker)) {
	self.client = client
	
	client.onConnected
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
	client.disconnect(userInitiated: userInitiated)
  }
  
  func reconnectIfNeeded() {
	client.reconnectIfNeeded()
  }
  
  func subscribe(markets: [String]) {
	subscribedMarkets = Array(Set(markets)).sorted()
	guard client.isConnected else { return }
	client.sendSubscription(codes: subscribedMarkets)
  }
  
  private func resubscribeIfNeeded() {
	guard !subscribedMarkets.isEmpty else { return }
	client.sendSubscription(codes: subscribedMarkets)
  }
}

final class OrderBookSocketService: OrderBookSocketServiceProtocol {
  private let client: UpbitWebSocketClient
  private let disposeBag = DisposeBag()
  private let decoder = JSONDecoder()
  private var subscribedMarket: String?
  
  lazy var stream: Observable<Orderbook> = {
	client.rawDataStream
	  .compactMap { [weak self] data in
		guard let self = self else { return nil }
		
		do {
		  let dto = try self.decoder.decode(OrderbookDTO.self, from: data)
		  return dto.toDomain()
		} catch {
		  Log.error("Orderbook websocket decode error: \(error.localizedDescription)")
		  return nil
		}
	  }
	  .share()
  }()
  
  init(client: UpbitWebSocketClient = UpbitWebSocketClient(socketType: .orderbook)) {
	self.client = client
	
	client.onConnected
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
	client.disconnect(userInitiated: userInitiated)
  }
  
  func reconnectIfNeeded() {
	client.reconnectIfNeeded()
  }
  
  func subscribe(market: String) {
	subscribedMarket = market
	guard client.isConnected else { return }
	client.sendSubscription(codes: [market])
  }
  
  private func resubscribeIfNeeded() {
	guard let subscribedMarket else { return }
	client.sendSubscription(codes: [subscribedMarket])
  }
}
