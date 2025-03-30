//
//  TradeChartView.swift
//  Mobit
//
//  Created by 조성재 on 2/5/25.
//

import UIKit
import WebKit

class TradeChartView: UIView, WKScriptMessageHandler {
  
  @IBOutlet weak var webView: WKWebView!
  
  var symbol: String? = nil
  var html: String? = nil
  var javascriptBridgeInterfaceName = "MobitTradingViewChart"
  
  deinit {
	print("deinit : \(String(describing: type(of: self)))")
  }
  
  static func instanceFromNib(
    symbol: String
  ) -> TradeChartView {
    
    let selfView = UINib(
      nibName: String(describing: self),
      bundle: nil
    ).instantiate(
      withOwner: self, options: nil
    ).first as? TradeChartView
    
    guard let selfView = selfView else {
      return TradeChartView()
    }
    
    selfView.symbol = symbol
	selfView.configureWebView()
    selfView.configure()
	selfView.loadLocalHTML(symbol: symbol)
    
    return selfView
  }
  
  func configure() {
  }
  
  func configureWebView() {
    let config = WKWebViewConfiguration()
    config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
	config.userContentController.add(LeakAvoider(delegate: self), name: javascriptBridgeInterfaceName)
    if #available(iOS 15.4, *) {
      config.preferences.isElementFullscreenEnabled = true
    }
	
	webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    webView.scrollView.contentInsetAdjustmentBehavior = .never
	webView.scrollView.isScrollEnabled = false
	webView.scrollView.delegate = self
    webView.navigationDelegate = self
    webView.uiDelegate = self
  }
  
  private func loadLocalHTML(symbol: String) {
	if let url = Bundle.main.url(forResource: "tradingview", withExtension: "html") {
	  webView.loadFileURL(url, allowingReadAccessTo: url)
	}
  }
  
  func toUpbitSymbol(symbol: String?) -> String {
	guard let symbol = symbol else { return "UPBIT:BTCKRW" }
	return "UPBIT:" + symbol.replacingOccurrences(of: "/", with: "")
  }
  
  func userContentController(
	_ userContentController: WKUserContentController,
	didReceive message: WKScriptMessage
  ) {
	if message.name == javascriptBridgeInterfaceName {
		guard
			let bridge = message.body as? [String: Any]
		else {
			return
		}
		
//		self.webViewBridgeAction?.action(bridge: bridge)
	}
  }
}

// MARK: - WKNavigationDelegate
extension TradeChartView: WKNavigationDelegate {
  func webView(
	_ webView: WKWebView,
	decidePolicyFor navigationAction: WKNavigationAction,
	decisionHandler: @escaping (WKNavigationActionPolicy
	) -> Void) {
	if navigationAction.navigationType == .other,
	   let url = navigationAction.request.url,
	   let host = url.host, host.hasPrefix("www.tradingview.com"),
	   UIApplication.shared.canOpenURL(url) {
	  UIApplication.shared.open(url)
	  decisionHandler(.cancel)
	} else {
	  decisionHandler(.allow)
	}
  }
  
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
	let upbitChartSymbol = self.toUpbitSymbol(symbol: self.symbol)
	let script = "updateSymbol('\(upbitChartSymbol)');"
	webView.evaluateJavaScript(script) { [weak self] (_, error) in
	  guard let self = self else { return }
	  if let error = error {
		print("JavaScript 실행 오류: \(error)")
	  }
	}
  }
}

// MARK: - WKUIDelegate
extension TradeChartView: WKUIDelegate {
  func webView(
	_ webView: WKWebView,
	createWebViewWith configuration: WKWebViewConfiguration,
	for navigationAction: WKNavigationAction,
	windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
	if let url = navigationAction.request.url {
	  webView.load(URLRequest(url: url))
	}
	return nil
  }
}

extension TradeChartView: UIScrollViewDelegate {
  func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
	scrollView.pinchGestureRecognizer?.isEnabled = false
  }
}
