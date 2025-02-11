//
//  LeakAvoider.swift
//  Mobit
//
//  Created by 조성재 on 2/10/25.
//

import Foundation
import WebKit

class LeakAvoider: NSObject, WKScriptMessageHandler {
	weak var delegate: WKScriptMessageHandler?
	init(delegate: WKScriptMessageHandler) {
		self.delegate = delegate
		super.init()
	}

	func userContentController(
	  _ userContentController: WKUserContentController,
	  didReceive message: WKScriptMessage
	) {
		self.delegate?.userContentController(userContentController, didReceive: message)
	}
}
