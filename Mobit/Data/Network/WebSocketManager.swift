//
//  WebSocketManager.swift
//  Mobit
//
//  Created by openobject on 2024/07/23.
//

import Foundation
import Alamofire
import SwiftJWT
import RxSwift
import RxRelay

enum SocketType: String {
  case ticker = "ticker"
  case orderbook = "orderbook"
}

// Singleton
class WebSocketManager: NSObject {
  static let shared = WebSocketManager()
  
  let tickerDataSubject = PublishSubject<Data>()
  let orderBookDataSubject = PublishSubject<Data>()
  private var tickerWebSocket: URLSessionWebSocketTask?
  private var obWebSocket: URLSessionWebSocketTask?
  private var timer: Timer? // 5초마다 ping
  private var tickerSession: URLSession!
  private var obSession: URLSession!
  private var isTConnected: Bool = false
  private var isObConnected: Bool = false
  
  var socketType: SocketType = .ticker
  
  override init() {
    super.init()
    self.tickerSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue.main)
    self.obSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue.main)
  }
  
  func connect(codes: [String], socketType: SocketType) {
    self.socketType = socketType
    // 이미 연결 상태라면, 새로운 요청만 전송
    guard !self.isTConnected else {
      print("isTConnect true")
      self.send(codes, .ticker)
      return
    }
    let url = URL(string: "wss://api.upbit.com/websocket/v1")!
    self.tickerWebSocket = self.tickerSession.webSocketTask(with: url)
    self.tickerWebSocket?.resume()
    self.isTConnected = true
    
    self.send(codes, .ticker)
    self.receiveMessage(task: self.tickerWebSocket)
  }
  
  func connectOrderBook(codes: [String], socketType: SocketType) {
    self.socketType = socketType
    guard !self.isObConnected else {
      self.send(codes, .orderbook)
      return
    }
    let url = URL(string: "wss://api.upbit.com/websocket/v1")!
    self.obWebSocket = obSession.webSocketTask(with: url)
    self.obWebSocket?.resume()
    self.isObConnected = true
    
    self.send(codes, .orderbook)
    self.receiveMessage(task: self.obWebSocket)
  }
  
  func disconnect(socketType: SocketType) {
    switch socketType {
    case .ticker:
      self.tickerWebSocket?.cancel(with: .goingAway, reason: nil)
      self.isTConnected = false
    case .orderbook:
      self.obWebSocket?.cancel(with: .goingAway, reason: nil)
      self.isObConnected = false
    }
    
  }
  
  func send(_ codes: [String], _ socketType: SocketType) {
    let ticket = ["ticket": "test"]
    var subscribe: [String: Any] = [:]
    
    switch socketType {
    case .ticker:
      subscribe = [
        "type": socketType.rawValue,
        "codes": codes
      ] as [String : Any]
      
      let messages = [ticket, subscribe]
      
      guard let data = try? JSONSerialization.data(withJSONObject: messages) else {
        return
      }
      
      self.tickerWebSocket?.send(.data(data)) { error in
        if let error = error {
          print("WebSocket send error: \(error)")
        }
      }
    case .orderbook:
      subscribe = [
        "type": self.socketType.rawValue,
        "codes": codes,
        "level": 10000
      ] as [String : Any]
      
      let messages = [ticket, subscribe]
      
      guard let data = try? JSONSerialization.data(withJSONObject: messages) else {
        return
      }
      
      self.obWebSocket?.send(.data(data)) { error in
        if let error = error {
          print("WebSocket send error: \(error)")
        }
      }
    }
  }
  
  private func receiveMessage(task: URLSessionWebSocketTask?) {
    task?.receive { [weak self] result in
      switch result {
      case .success(let message):
        switch message {
        case .data(let data):
          switch self?.socketType {
          case .ticker:
            self?.tickerDataSubject.onNext(data)
          case .orderbook:
            self?.orderBookDataSubject.onNext(data)
          case .none:
            break
          }
        case .string(let text):
          print("Received text: \(text)")
        @unknown default:
          fatalError()
        }
        self?.receiveMessage(task: task) // 재귀적으로 메시지를 계속 받기 위해 호출
      case .failure(let error):
        print("WebSocket receive error: \(error)")
      }
    }
  }
  
  private func ping() {
    // 5초 마다 반복
    // 120초 Time Out
    self.timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true, block: { [weak self] _ in
      self?.tickerWebSocket?.sendPing(pongReceiveHandler: { error in
        if let error {
          print("WebSocket Ping Error : \(error.localizedDescription)")
        } else {
          print("WebSocket Ping Success")
        }
      })
    })
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

// MARK: Websocket Delegate
extension WebSocketManager: URLSessionWebSocketDelegate {
  func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
    print(#function)
    print("WebSocket OPEN")
  }
  
  func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    print(#function)
    print("WebSocket CLOSE")
  }
  
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error = error {
      print("WebSocket task completed with error: \(error.localizedDescription)")
    } else {
      print("WebSocket task completed successfully")
    }
  }
}
