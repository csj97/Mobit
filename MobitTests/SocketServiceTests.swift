//
//  SocketServiceTests.swift
//  MobitTests
//
//  Created by Codex on 6/29/26.
//

import XCTest
import RxSwift
@testable import Mobit

final class SocketServiceTests: XCTestCase {
  func testTickerSubscribeSkipsDuplicateMarketSubscriptions() {
    let client = MockWebSocketClient()
    let service = TickerSocketService(client: client)

    client.connect()
    service.subscribe(markets: ["KRW-BTC", "KRW-ETH", "KRW-BTC"])
    service.subscribe(markets: ["KRW-ETH", "KRW-BTC"])

    XCTAssertEqual(client.sentSubscriptions, [["KRW-BTC", "KRW-ETH"]])
  }

  func testTickerResubscribesAfterNonUserInitiatedReconnect() {
    let client = MockWebSocketClient()
    let service = TickerSocketService(client: client)

    client.connect()
    service.subscribe(markets: ["KRW-BTC"])
    service.disconnect(userInitiated: false)
    client.connect()

    XCTAssertEqual(client.sentSubscriptions, [["KRW-BTC"], ["KRW-BTC"]])
  }

  func testTickerUserInitiatedDisconnectClearsPendingSubscription() {
    let client = MockWebSocketClient()
    let service = TickerSocketService(client: client)

    client.connect()
    service.subscribe(markets: ["KRW-BTC"])
    service.disconnect(userInitiated: true)
    client.connect()

    XCTAssertEqual(client.sentSubscriptions, [["KRW-BTC"]])
  }

  func testOrderBookSubscribeSkipsDuplicateMarketSubscriptions() {
    let client = MockWebSocketClient()
    let service = OrderBookSocketService(client: client)

    client.connect()
    service.subscribe(market: "KRW-BTC")
    service.subscribe(market: "KRW-BTC")

    XCTAssertEqual(client.sentSubscriptions, [["KRW-BTC"]])
  }

  func testOrderBookResubscribesAfterNonUserInitiatedReconnect() {
    let client = MockWebSocketClient()
    let service = OrderBookSocketService(client: client)

    client.connect()
    service.subscribe(market: "KRW-BTC")
    service.disconnect(userInitiated: false)
    client.connect()

    XCTAssertEqual(client.sentSubscriptions, [["KRW-BTC"], ["KRW-BTC"]])
  }
}

private final class MockWebSocketClient: WebSocketClientProtocol {
  private let connectedSubject = PublishSubject<Void>()
  private let dataSubject = PublishSubject<Data>()

  private(set) var isConnected = false
  private(set) var connectCallCount = 0
  private(set) var disconnectCallCount = 0
  private(set) var sentSubscriptions: [[String]] = []
  private var isUserInitiatedDisconnect = false

  var onConnected: Observable<Void> {
    connectedSubject.asObservable()
  }

  var rawDataStream: Observable<Data> {
    dataSubject.asObservable()
  }

  func connect() {
    guard !isConnected else { return }
    connectCallCount += 1
    isUserInitiatedDisconnect = false
    isConnected = true
    connectedSubject.onNext(())
  }

  func disconnect(userInitiated: Bool) {
    disconnectCallCount += 1
    isUserInitiatedDisconnect = userInitiated
    isConnected = false
  }

  func reconnectIfNeeded() {
    guard !isUserInitiatedDisconnect, !isConnected else { return }
    connect()
  }

  func sendSubscription(codes: [String]) {
    guard isConnected else { return }
    sentSubscriptions.append(codes)
  }
}
