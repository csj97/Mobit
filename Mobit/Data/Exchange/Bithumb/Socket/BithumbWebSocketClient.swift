//
//  BithumbWebSocketClient.swift
//  Mobit
//
//  Created by 조성재 on 7/9/26.
//

import Foundation
import RxSwift
import Starscream

final class BithumbWebSocketClient: WebSocketDelegate, WebSocketClientProtocol {
  private static let reconnectDelay: TimeInterval = 1

  private enum SubscriptionType: String {
    case ticker
    case orderbook
  }

  private let socket: WebSocket
  private let socketType: SocketType
  private let connectedSubject = PublishSubject<Void>()
  private let dataSubject = PublishSubject<Data>()

  private(set) var isConnected = false
  private var isConnecting = false
  private var isUserInitiatedDisconnect = false
  private var reconnectWorkItem: DispatchWorkItem?

  init(socketType: SocketType) {
    self.socketType = socketType

    var request = URLRequest(url: URL(string: "wss://ws-api.bithumb.com/websocket/v1")!)
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
    reconnectWorkItem?.cancel()
    reconnectWorkItem = nil
    isUserInitiatedDisconnect = false
    isConnecting = true
    socket.connect()
  }

  func disconnect(userInitiated: Bool = false) {
    isUserInitiatedDisconnect = userInitiated
    if userInitiated {
      reconnectWorkItem?.cancel()
      reconnectWorkItem = nil
    }
    guard isConnected || isConnecting else { return }

    Log.info("Disconnecting bithumb \(socketType.rawValue) socket...")
    isConnecting = false
    isConnected = false
    socket.disconnect()
  }

  func reconnectIfNeeded() {
    guard !isUserInitiatedDisconnect, !isConnected else { return }
    Log.info("Reconnecting bithumb \(socketType.rawValue) socket...")
    connect()
  }

  func sendSubscription(codes: [String]) {
    guard isConnected, !codes.isEmpty else { return }

    let payload = self.subscriptionPayload(codes: codes)
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
      return
    }

    socket.write(data: data) {
      Log.info("bithumb \(self.socketType.rawValue) subscription sent")
    }
  }

  func didReceive(
    event: Starscream.WebSocketEvent,
    client: any Starscream.WebSocketClient
  ) {
    switch event {
    case .connected:
      reconnectWorkItem?.cancel()
      reconnectWorkItem = nil
      isConnecting = false
      isConnected = true
      connectedSubject.onNext(())

    case .binary(let data):
      dataSubject.onNext(data)

    case .text(let text):
      guard let data = text.data(using: .utf8) else { return }
      dataSubject.onNext(data)

    case .disconnected:
      isConnecting = false
      isConnected = false
      scheduleReconnectIfNeeded()

    case .error:
      isConnecting = false
      isConnected = false
      scheduleReconnectIfNeeded()

    case .cancelled:
      isConnecting = false
      isConnected = false
      scheduleReconnectIfNeeded()

    case .reconnectSuggested(let shouldReconnect):
      guard shouldReconnect else { return }
      scheduleReconnectIfNeeded()

    case .peerClosed:
      isConnecting = false
      isConnected = false
      scheduleReconnectIfNeeded()

    case .ping, .pong, .viabilityChanged:
      break
    }
  }

  private func scheduleReconnectIfNeeded() {
    guard !isUserInitiatedDisconnect,
          !isConnected,
          !isConnecting,
          reconnectWorkItem == nil else { return }

    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.reconnectWorkItem = nil
      self.reconnectIfNeeded()
    }
    reconnectWorkItem = workItem
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.reconnectDelay,
      execute: workItem
    )
  }

  private func subscriptionPayload(codes: [String]) -> [[String: Any]] {
    switch socketType {
    case .ticker:
      return [
        ["ticket": UUID().uuidString],
        [
          "type": SubscriptionType.ticker.rawValue,
          "codes": codes
        ]
      ]

    case .orderbook:
      return [
        ["ticket": UUID().uuidString],
        [
          "type": SubscriptionType.orderbook.rawValue,
          "codes": codes
        ]
      ]
    }
  }
}
