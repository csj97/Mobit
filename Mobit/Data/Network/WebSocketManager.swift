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

struct Payload: Claims {
  let accessKey: String
  let nonce: String
}

// Singleton
class WebSocketManager: NSObject {
  static let shared = WebSocketManager()
  
  private var timer: Timer? // 5초마다 ping
  private var webSocket: URLSessionWebSocketTask?
  private var isOpen: Bool = false // 소켓 연결 상태
  private var session: URLSession!
  var currentPriceSubject = PublishSubject<CurrentPriceList>() // 구독한 시점 이후부터 방출
  
  private var isConnecting = false
  private var retryCount = 0
  private let maxRetryCount = 5
  
  override init() {
    super.init()
    self.session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue.main)
  }
  
//  func openWebSocket() {
//    guard !isConnecting else { return }
//    self.isConnecting = true
//    
//    var request = URLRequest(url: URL(string: "wss://api.upbit.com/websocket/v1")!)
////    request.setValue("Bearer \(signedJWT)", forHTTPHeaderField: "Authorization")
//
//    if let existingWebSocket = self.webSocket {
//      existingWebSocket.cancel(with: .goingAway, reason: nil)
//    }
//    
//    self.webSocket = self.session.webSocketTask(with: request)
//    self.webSocket?.resume()
////    self.ping()
//    self.receive()
//  }
  
  private func handleConnectionFailure() {
    isConnecting = false
    if retryCount < maxRetryCount {
      retryCount += 1
      let delay = Double(retryCount) * 2.0 // 지수 백오프
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        self?.openWebSocket()
      }
    } else {
      print("최대 재시도 횟수에 도달했습니다.")
    }
  }
  
  func openWebSocket() {
    if let url = URL(string: "wss://api.upbit.com/websocket/v1") {
      
      let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
    
      self.webSocket = session.webSocketTask(with: url)
      self.webSocket?.resume()

      self.receive()  
//      self.ping()
    }
  }
  
  func closeWebSocket() {
    self.webSocket?.cancel(with: .goingAway, reason: nil)
    self.webSocket = nil
    
    self.timer?.invalidate()
    self.timer = nil
    
    self.isOpen = false
  }
  
  //  func getTickers(markets ticker: [String])
  
  func send(_ codes: String) {
    // ticket : 요청자를 식별할 수 있는 값
    // codes : crypto code list 대문자로 요청 (필수)
    // format : 수신할 format (DEFAULT 기본형, SIMPLE 축약형)
    let requestStr = """
    [{"ticket":"kando ticker"},{"type":"ticker","codes":["\(codes)"]}]
    """
    
    self.webSocket?.send(.string(requestStr), completionHandler: { error in
      if let error {
        print("WebSocket send Error ==> \(error.localizedDescription)")
      } else {
        print("WebSocket message sent successfully")  // 0000 메시지 전송 성공 로그 추가
      }
    })
  }
  
  func receive() {
    print(#function)
    guard isOpen else { return }
    self.webSocket?.receive(completionHandler: { [weak self] result in
      switch result {
      case .success(let success):
        print("WebSocket Receive Success : \(success)")
        switch success {
        case .data(let data):
          let decodeTarget = CurrentPriceListDTO.self
          
          do {
            let currentPriceListDTO = try JSONDecoder().decode(decodeTarget, from: data)
            self?.currentPriceSubject.onNext(currentPriceListDTO.toDomain())
          } catch {
            print("websocket receive decoding error : \(error.localizedDescription)")
          }
        case .string(let string):
          print("websocket receive success string : \(string)")
          
        @unknown default:
          fatalError()
        }
        
      case .failure(let error):
        print("WebSocket Receive fail : \(error.localizedDescription)")
        self?.closeWebSocket()
      }
      
      // 재귀 호출
      self?.receive()
    })
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
}

// MARK: Websocket Delegate
extension WebSocketManager: URLSessionWebSocketDelegate {
  func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
    print(#function)
    print("WebSocket OPEN")
    
    self.isOpen = true
    self.isConnecting = false
    self.retryCount = 0
    
    // 소켓 열리고 데이터 수신
    self.receive()
  }
  
  func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    print(#function)
    print("WebSocket CLOSE")
    
    self.isOpen = false
    self.handleConnectionFailure()
  }
  
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error = error {
      print("WebSocket task completed with error: \(error.localizedDescription)")
      self.handleConnectionFailure()
    } else {
      print("WebSocket task completed successfully")
      self.isConnecting = false
      self.retryCount = 0
    }
  }
}
