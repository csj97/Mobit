//
//  TradeChartView.swift
//  Mobit
//
//  Created by 조성재 on 2/5/25.
//

import UIKit
import WebKit

class TradeChartView: UIView, WKScriptMessageHandler {
  
  @IBOutlet weak var settingsContainerView: UIView!
  @IBOutlet weak var intervalSegmentedControl: UISegmentedControl!
  @IBOutlet weak var themeSegmentedControl: UISegmentedControl!
  @IBOutlet weak var persistenceGuideLabel: UILabel!
  @IBOutlet weak var webView: WKWebView!
    
  var symbol: String? = nil
  var html: String? = nil
  var javascriptBridgeInterfaceName = "MobitTradingViewChart"
  private var chartSettings = UserDataManager.tradingViewChartSettings
  
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
    selfView.configure()
    
    return selfView
  }
  
  func configure() {
	self.configureSettingsUI()
	
	Task {
	  guard let symbol = self.symbol else {
		self.webView.isHidden = true
		return
	  }
	  
	  await self.configureWebView()
	  await self.loadLocalHTML(symbol: symbol)
	  self.webView.isHidden = false
	}
  }
  
  private func configureSettingsUI() {
	self.settingsContainerView.layer.cornerRadius = 12
	self.settingsContainerView.layer.borderWidth = 0.5
	self.settingsContainerView.layer.borderColor = UIColor.lightGray.withAlphaComponent(0.35).cgColor
	self.persistenceGuideLabel.text = "여기서 선택한 차트 설정은 앱을 종료했다가 다시 들어와도 그대로 유지돼요."
	self.intervalSegmentedControl.selectedSegmentIndex = self.index(for: chartSettings.interval)
	self.themeSegmentedControl.selectedSegmentIndex = self.index(for: chartSettings.theme)
  }
  
  func configureWebView() async {
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
  
  private func loadLocalHTML(symbol: String) async {
	if let url = Bundle.main.url(forResource: "tradingview", withExtension: "html") {
	  webView.loadFileURL(url, allowingReadAccessTo: url)
	}
  }
  
  func toUpbitSymbol(symbol: String?) -> String {
	guard let symbol = symbol else { return "UPBIT:BTCKRW" }
	return "UPBIT:" + symbol.replacingOccurrences(of: "/", with: "")
  }
  
  private func index(for interval: UserDataManager.TradingViewChartSettings.Interval) -> Int {
	switch interval {
	case .minute15:
	  return 0
	case .hour1:
	  return 1
	case .hour4:
	  return 2
	case .day1:
	  return 3
	}
  }
  
  private func index(for theme: UserDataManager.TradingViewChartSettings.Theme) -> Int {
	switch theme {
	case .light:
	  return 0
	case .dark:
	  return 1
	}
  }
  
  private func selectedInterval() -> UserDataManager.TradingViewChartSettings.Interval {
	switch self.intervalSegmentedControl.selectedSegmentIndex {
	case 0:
	  return .minute15
	case 2:
	  return .hour4
	case 3:
	  return .day1
	default:
	  return .hour1
	}
  }
  
  private func selectedTheme() -> UserDataManager.TradingViewChartSettings.Theme {
	self.themeSegmentedControl.selectedSegmentIndex == 1 ? .dark : .light
  }
  
  private func applyCurrentSettings() {
	self.chartSettings = UserDataManager.TradingViewChartSettings(
	  interval: self.selectedInterval(),
	  theme: self.selectedTheme(),
	  showsToolbar: self.chartSettings.showsToolbar
	)
	UserDataManager.tradingViewChartSettings = self.chartSettings
	self.refreshChart()
  }
  
  private func refreshChart() {
	guard let symbol = self.symbol else { return }
	let upbitChartSymbol = self.toUpbitSymbol(symbol: symbol)
	let themeValue = self.chartSettings.theme.rawValue.jsEscaped
	let intervalValue = self.chartSettings.interval.rawValue.jsEscaped
	let symbolValue = upbitChartSymbol.jsEscaped
	let script = "updateChart('\(symbolValue)', '\(intervalValue)', '\(themeValue)');"
	webView.evaluateJavaScript(script) { _, error in
	  if let error = error {
		Log.error("JavaScript 실행 오류: \(error)")
	  }
	}
  }
  
  func userContentController(
	_ userContentController: WKUserContentController,
	didReceive message: WKScriptMessage
	  ) {
		if message.name == javascriptBridgeInterfaceName {
	//		self.webViewBridgeAction?.action(bridge: bridge)
		}
	  }
  
  @IBAction func intervalValueChanged(_ sender: UISegmentedControl) {
	self.applyCurrentSettings()
  }
  
  @IBAction func themeValueChanged(_ sender: UISegmentedControl) {
	self.applyCurrentSettings()
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
		self.refreshChart()
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

private extension String {
  var jsEscaped: String {
	self
	  .replacingOccurrences(of: "\\", with: "\\\\")
	  .replacingOccurrences(of: "'", with: "\\'")
  }
}
