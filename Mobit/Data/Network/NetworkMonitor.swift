//
//  NetworkMonitor.swift
//  Mobit
//
//  Created by 조성재 on 10/29/25.
//

import Foundation
import Network
import RxSwift

extension Notification.Name {
  static let networkStatusChanged = Notification.Name("networkStatusChanged")
}

final class NetworkMonitor {
  static let shared = NetworkMonitor()
  private let monitor = NWPathMonitor()
  private var isConnected: Bool = false
  // 최초 경로 확인 전을 오프라인으로 오인하지 않고 늦게 열린 화면에도 상태를 전달한다.
  private(set) var currentAvailability: Bool?

  // 현재 경로를 재생하고 기존 알림으로 후속 연결 변화를 전달한다.
  var availability: Observable<Bool> {
    Observable.deferred {
      // 기존 유실 알림과 같은 이벤트를 사용해 화면별 연결 판정이 어긋나지 않게 한다.
      let changes = NotificationCenter.default.rx.notification(.networkStatusChanged)
        .compactMap { $0.userInfo?["isConnected"] as? Bool }
      return self.currentAvailability.map { changes.startWith($0) } ?? changes
    }.distinctUntilChanged()
  }
  private var connectionType: NWInterface.InterfaceType = .other
  
  private init() { }
  // 네트워크 경로에 맞춰 현재 연결 방식(Wi-Fi·셀룰러 등)을 갱신한다.
  private func updateConnectionType(_ path: NWPath) {
	if path.usesInterfaceType(.wifi) {
	  connectionType = .wifi
	} else if path.usesInterfaceType(.cellular) {
	  connectionType = .cellular
	} else if path.usesInterfaceType(.wiredEthernet) {
	  connectionType = .wiredEthernet
	} else {
	  connectionType = .other
	}
  }
  
  func startNetworkMonitoring() {
	monitor.pathUpdateHandler = { [weak self] path in
	  guard let self = self else { return }
	  
	  DispatchQueue.main.async {
			self.isConnected = path.status == .satisfied
            self.currentAvailability = self.isConnected
			self.updateConnectionType(path)

			let networkStatus = self.isConnected ? "✅연결됨" : "⛔️끊김"
			print("Network 연결 상태 : \(networkStatus)")
		
		NotificationCenter.default.post(
		  name: .networkStatusChanged,
		  object: nil,
		  userInfo: ["isConnected": self.isConnected]
		)
	  }
	}
	
	let queue = DispatchQueue.global(qos: .background)
	monitor.start(queue: queue)
  }
  
  func stopNetworkMonitoring() {
	monitor.cancel()
  }
  
  func isNetworkAvailable() -> Bool {
	return self.isConnected
  }
  
  func getCurrentConnectionType() -> NWInterface.InterfaceType {
	return self.connectionType
  }
}
