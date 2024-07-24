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

// Singleton
class WebSocketManager: NSObject {
  static let shared = WebSocketManager()
  
  private var webSocket: URLSessionWebSocketTask?
  private var timer: Timer? // 5초마다 ping
  private var session: URLSession!
  
  var currentPriceSubject = PublishRelay<CurrentPrice>() // 구독한 시점 이후부터 방출
  
  override init() {
    super.init()
    self.session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue.main)
  }
  
  func connect(codes: [String]) {
    let url = URL(string: "wss://api.upbit.com/websocket/v1")!
    self.webSocket = session.webSocketTask(with: url)
    self.webSocket?.resume()
    self.send(codes)
    self.receiveMessage()
  }
  
  func disconnect() {
    self.webSocket?.cancel(with: .goingAway, reason: nil)
  }
  
  func send(_ codes: [String]) {
    let ticket = ["ticket": "test"]
    let subscribe = [
      "type": "ticker",
      "codes": codes
    ] as [String : Any]
    
    let messages = [ticket, subscribe]
    
    guard let data = try? JSONSerialization.data(withJSONObject: messages) else {
      return
    }
    
    self.webSocket?.send(.data(data)) { error in
      if let error = error {
        print("WebSocket send error: \(error)")
      }
    }
  }
  
  private func receiveMessage() {
    self.webSocket?.receive { [weak self] result in
      switch result {
      case .success(let message):
        switch message {
        case .data(let data):
          self?.handleReceivedData(data)
        case .string(let text):
          print("Received text: \(text)")
        @unknown default:
          fatalError()
        }
        self?.receiveMessage() // 재귀적으로 메시지를 계속 받기 위해 호출
      case .failure(let error):
        print("WebSocket receive error: \(error)")
      }
    }
  }
  
  private func ping() {
    // 5초 마다 반복
    // 120초 Time Out
    self.timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true, block: { [weak self] _ in
      self?.webSocket?.sendPing(pongReceiveHandler: { error in
        if let error {
          print("WebSocket Ping Error : \(error.localizedDescription)")
        } else {
          print("WebSocket Ping Success")
        }
      })
    })
  }
  
  private func handleReceivedData(_ data: Data) {
    let decodeTarget = CurrentPriceDTO.self
    
    do {
      let currentPriceDTO = try JSONDecoder().decode(decodeTarget, from: data)
      self.currentPriceSubject.accept(currentPriceDTO.toDomain())
//      print("심마니~~ : \(currentPriceDTO.toDomain())")
    } catch {
      print("websocket receive decoding error : \(error.localizedDescription)")
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
