//
//  NetworkMonitor.swift
//  Mobit
//
//  Created by 조성재 on 10/29/25.
//

import Foundation
import Network

extension Notification.Name {
  static let networkStatusChanged = Notification.Name("networkStatusChanged")
}

final class NetworkMonitor {
  static let shared = NetworkMonitor()
  private let monitor = NWPathMonitor()
  private var isConnected: Bool = false
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
