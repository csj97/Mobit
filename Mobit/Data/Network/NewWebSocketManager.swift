//
//  NewWebSocketManager.swift
//  Mobit
//
//  Created by 조성재 on 11/5/24.
//

import Foundation
import Starscream
import RxSwift

enum SocketType: String {
  case ticker = "ticker"
  case orderbook = "orderbook"
}

class NewWebSocketManager: WebSocketDelegate {

  static let shared = NewWebSocketManager()
  
  var callBack: (() -> ())? = nil
  let tickerDataSubject = PublishSubject<Data>()
  let orderBookDataSubject = PublishSubject<Data>()
  var sockets: [String: WebSocket] = [:]
  // 각 URL에 대한 메시지 큐 저장
  private var messageQueue: [String: [String]] = [:]
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
    socket.connect()
  }
  
  func disconnect() {
    socket.disconnect()
  }
  
  /// Message 전송
  func sendMessage(codes: [String], socketType: SocketType) {
    guard isConnected else {
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
      callBack?()
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


  
  
  
  
  
  
  
  
//  // WebSocket 연결
//  func connectSocket(url: String,
//                     sendData: [String]) {
//    queue.sync(flags: .barrier) {
//      if let socket = sockets[url] {
//        return socket
//      } else {
//        var request = URLRequest(url: URL(string: url)!)
//        request.timeoutInterval = 5
//        let socket = WebSocket(request: request)
//        socket.delegate = self
//        socket.connect()
//        self.send(socket: socket, sendData) {
//          print("socket data sent")
//        }
//        
//        sockets[url] = socket
//        
//        return socket
//      }
//    }
//  }
//  
//  func send(
//    socket: WebSocket,
//    _ codes: [String],
//    onSuccess: @escaping ()-> Void
//  ) {
//    let ticket = ["ticket": "test"]
//    let subscribe: [String: Any] = [
//      "type": "ticker",
//      "codes": codes
//    ]
//    
//    let messages = [ticket, subscribe]
//    
//    guard JSONSerialization.isValidJSONObject(messages) else {
//      print("[WEBSOCKET] Value is not a valid JSON object.\n \(messages)")
//      return
//    }
//    
//    do {
//      let data = try JSONSerialization.data(withJSONObject: messages, options: [])
////      socket.write(data: data) {
////        onSuccess()
////      }
//      socket.write(string: "HELLO SUNGJAE") {
//        onSuccess()
//      }
//    } catch let error {
//      print("[WEBSOCKET] Error serializing JSON:\n\(error)")
//    }
//  }
//  
//  func disconnectSocket(url: String) {
//    queue.sync(flags: .barrier) {
//      if let socket = sockets[url] {
//        socket.disconnect()
//        sockets.removeValue(forKey: url)
//      }
//    }
//  }
//  
////  func connectMultipleSockets(urls: [String]) -> [WebSocket] {
////    return urls.map { connectSocket(url: $0) }
////  }
//
//}
//
//// MARK: - WebSocketDelegate
//extension NewWebSocketManager: WebSocketDelegate {
//  
//  func didReceive(
//    event: WebSocketEvent,
//    client: WebSocketClient
//  ) {
//    switch event {
//    case .connected:
//      print("Connected to \(client)")
//      client.write(string: "안녕 조성재")
//    case .disconnected(let reason, _):
//      print("Disconnected: \(reason)")
//      // 필요시 자동 재연결 코드 추가 가능
//    case .binary(let data):
////      if let text = String(data: data, encoding: .utf8) {
////        print("Received Text: \(text)")
////      } else {
////        print("Unable to decode binary data to String.")
////      }
//      do {
//        // 디코딩 시도
//        if let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? Any {
//          print("Decoded JSON Array: \(jsonArray)")
//        } else {
//          print("Failed to cast JSON object to [[String: Any]].")
//        }
//      } catch {
//        print("JSON decoding error: \(error.localizedDescription)")
//      }
//      
//      print("Received binary data: \(data)")
//    case .text(let text):
//      print("Received text: \(text)")
//    case .error(let error):
//      if let error = error {
//        print("WebSocket error: \(error)")
//      }
//    default:
//      break
//    }
//  }
//}
