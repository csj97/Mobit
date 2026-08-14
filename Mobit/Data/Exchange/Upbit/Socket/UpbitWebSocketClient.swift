//
//  UpbitWebSocketClient.swift
//  Mobit
//
//  Created by Codex on 7/9/26.
//

import Foundation
import RxSwift
import Starscream

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
