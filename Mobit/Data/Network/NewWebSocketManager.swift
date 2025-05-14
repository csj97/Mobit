//
//  NewWebSocketManager.swift
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

class NewWebSocketManager: WebSocketDelegate {

  static let shared = NewWebSocketManager()
  
  var onConnected: (() -> ())? = nil
  let tickerDataSubject = PublishSubject<Data>()
  let orderBookDataSubject = PublishSubject<Data>()
  var sockets: [String: WebSocket] = [:]
  // 각 URL에 대한 메시지 큐 저장
  private var messageQueue: [String: [String]] = [:]
  // 사용자가 의도적으로 연결을 끊은 것인지 파악하기 위함
  private var isManuallyDisconnected = false
  private let queue = DispatchQueue(
    label: "WebSocket Queue",
    attributes: .concurrent
  )
  private var socket: WebSocket!
  private var isConnected = false
  var socketType: SocketType = .ticker
  
  convenience init(socketType: SocketType) {
    self.init()
    self.socketType = socketType
  }
  
  init() {
    // WebSocket 초기화 (URL을 연결할 서버의 URL로 변경)
    let url  = URL(string: "wss://api.upbit.com/websocket/v1")!
    var request = URLRequest(url: url)
    request.timeoutInterval = 5 // 연결 타임아웃 설정
    socket = WebSocket(request: request)
    socket.delegate = self
  }
  
  func connect() {
	guard socket != nil else { return }
    socket.connect()
  }
  
  func disconnect(manual: Bool = false) {
	guard socket != nil else { return }
	isManuallyDisconnected = manual
	print("Disconnecting...")
    socket.disconnect()
  }
  
  func reconnectIfNeeded() {
	guard !isManuallyDisconnected else { return }
	print("ReConnecting...")
	self.connect()
  }
  
  /// Message 전송
  func sendMessage(codes: [String], socketType: SocketType) {
	guard isConnected, socket != nil else {
      print("WebSocket is not connected")
      
      return
    }
    self.socketType = socketType
    
    let ticket = ["ticket": "teset"]
    let subscribe: [String: Any] = [
      "type": socketType.rawValue,
      "codes": codes
    ] as [String : Any]
    
    let messages = [ticket, subscribe]
    
    guard let data = try? JSONSerialization.data(withJSONObject: messages) else {
      return
    }
    
    socket.write(data: data) {
      print("code data send success")
    }
  }
  
  /// Event 수신
  func didReceive(
    event: Starscream.WebSocketEvent,
    client: any Starscream.WebSocketClient
  ) {
    switch event {
    case .connected:
      isConnected = true
	  onConnected?()
      print("WebSocket connected")
      
    case .disconnected(let reason, let code):
      isConnected = false
      print("WebSocket disconnected: \(reason) with code: \(code)")
      
    case .text(let text):
      print("Received text: \(text)")
      
    case .binary(let data):
      switch self.socketType {
      case .ticker:
        self.tickerDataSubject.onNext(data)
      case .orderbook:
        self.orderBookDataSubject.onNext(data)
      }
//      print("Received binary data: \(data)")
      
    case .error(let error):
      isConnected = false
      print("WebSocket error: \(String(describing: error))")
      
    case .cancelled:
      isConnected = false
      print("WebSocket connection cancelled")
      
    case .ping, .pong:
      break // Ping/Pong 이벤트는 보통 생략 가능
      
    case .viabilityChanged(let isViable):
      print("Connection viability changed: \(isViable)")
      
    case .reconnectSuggested(let shouldReconnect):
      print("Reconnect suggested: \(shouldReconnect)")
      
    case .peerClosed:
      print("Peer closed connection")
    }
  }
  
  // 수신한 데이터 observable 반환
  func observeReceivedData() -> Observable<Data> {
    switch self.socketType {
    case .ticker:
      return self.tickerDataSubject.asObservable()
    case .orderbook:
      return self.orderBookDataSubject.asObservable()
    }
  }
}
