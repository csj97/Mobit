//
//  TradeChartView.swift
//  Mobit
//
//  Created by 조성재 on 2/5/25.
//

import UIKit
import WebKit
import SnapKit

class TradeChartView: UIView, WKScriptMessageHandler {
  
  @IBOutlet weak var settingsContainerView: UIView!
  @IBOutlet weak var chartSettingsTitleLabel: UILabel!
  @IBOutlet weak var intervalSegmentedControl: UISegmentedControl!
  @IBOutlet weak var persistenceGuideLabel: UILabel!
  @IBOutlet weak var webView: WKWebView!
    
  var symbol: String? = nil
  var exchange: Exchange = .upbit
  var html: String? = nil
  var javascriptBridgeInterfaceName = "MobitTradingViewChart"
  private var chartSettings = UserDataManager.tradingViewChartSettings
  
  deinit {
	print("deinit : \(String(describing: type(of: self)))")
  }
  
  static func instanceFromNib(
    symbol: String,
    exchange: Exchange
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
    selfView.exchange = exchange
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
	self.backgroundColor = .mobitColors(.tradeBackground)
	self.webView.backgroundColor = .mobitColors(.chartBackground)
	self.webView.scrollView.backgroundColor = .mobitColors(.chartBackground)
	self.settingsContainerView.backgroundColor = .mobitColors(.tradeSurface)
	self.settingsContainerView.layer.cornerRadius = 0
	self.settingsContainerView.layer.borderWidth = 0.5
	self.updateResolvedColors()
	self.chartSettingsTitleLabel.textColor = .mobitColors(.tradeTextPrimary)
	self.persistenceGuideLabel.textColor = .mobitColors(.tradeTextSecondary)
	self.configureSegmentedControl(self.intervalSegmentedControl)
	// 인라인 안내문은 info 버튼 + 팝업으로 대체한다. 라벨은 숨기고 높이를 접어 레이아웃에서 제거한다.
	self.persistenceGuideLabel.isHidden = true
	self.persistenceGuideLabel.text = nil
	self.persistenceGuideLabel.snp.makeConstraints { $0.height.equalTo(0) }
	self.configureChartInfoButton()
	self.intervalSegmentedControl.selectedSegmentIndex = self.index(for: chartSettings.interval)
  }

  /// 차트 테마는 앱 테마(라이트/다크)를 그대로 따른다
  private func currentChartTheme() -> UserDataManager.TradingViewChartSettings.Theme {
	self.traitCollection.userInterfaceStyle == .dark ? .dark : .light
  }

  private func configureSegmentedControl(_ segmentedControl: UISegmentedControl) {
	segmentedControl.backgroundColor = .mobitColors(.tradeControlSurface)
	segmentedControl.selectedSegmentTintColor = .mobitColors(.segmentSelected)
	segmentedControl.setTitleTextAttributes(
	  [.foregroundColor: UIColor.mobitColors(.tradeTextSecondary)],
	  for: .normal
	)
	segmentedControl.setTitleTextAttributes(
	  [.foregroundColor: UIColor.mobitColors(.tradeTextPrimary)],
	  for: .selected
	)
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
	updateResolvedColors()
	configureSegmentedControl(intervalSegmentedControl)
	// 앱 테마가 바뀌면 차트도 같은 테마로 다시 그린다
	applyCurrentSettings()
  }

  private func updateResolvedColors() {
	self.backgroundColor = .mobitColors(.tradeBackground)
	self.settingsContainerView.backgroundColor = .mobitColors(.tradeSurface)
	self.chartSettingsTitleLabel.textColor = .mobitColors(.tradeTextPrimary)
	self.persistenceGuideLabel.textColor = .mobitColors(.tradeTextSecondary)
	self.chartInfoButton.tintColor = .mobitColors(.tradeTextTertiary)
	self.settingsContainerView.layer.borderColor = UIColor.mobitColors(.tradeSeparator).resolvedColor(with: traitCollection).cgColor
  }

  private lazy var chartInfoButton: UIButton = {
	let button = UIButton(type: .system)
	let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
	button.setImage(UIImage(systemName: "info.circle", withConfiguration: config), for: .normal)
	button.tintColor = .mobitColors(.tradeTextTertiary)
	button.accessibilityLabel = "차트 설정 안내"
	button.addTarget(self, action: #selector(didTapChartInfoButton), for: .touchUpInside)
	return button
  }()

  private func configureChartInfoButton() {
	self.settingsContainerView.addSubview(self.chartInfoButton)
	self.chartInfoButton.snp.makeConstraints { make in
	  make.leading.equalTo(self.chartSettingsTitleLabel.snp.trailing).offset(4)
	  make.centerY.equalTo(self.chartSettingsTitleLabel)
	  make.width.height.equalTo(20)
	}
  }

  @objc private func didTapChartInfoButton() {
	let alert = UIAlertController(
	  title: "차트 설정 안내",
	  message: "기간 설정은 앱을 종료했다가 다시 들어와도 그대로 유지돼요.\n차트 테마는 앱 테마를 따라가요.\n\n차트 안에서 추가한 지표·그림은 저장되지 않아요.",
	  preferredStyle: .alert
	)
	alert.addAction(UIAlertAction(title: "확인", style: .default))
	self.ownerViewController()?.present(alert, animated: true)
  }

  // UIView에서 알럿을 present하기 위해 responder chain으로 소유 뷰컨트롤러를 찾는다.
  private func ownerViewController() -> UIViewController? {
	var responder: UIResponder? = self
	while let current = responder {
	  if let viewController = current as? UIViewController { return viewController }
	  responder = current.next
	}
	return nil
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
  
  private func tradingViewSymbol(symbol: String?) -> String {
	MarketFormat.tradingViewSymbol(
	  fromDisplayMarket: symbol,
	  exchange: self.exchange
	)
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
	case .week1:
	  return 4
	case .month1:
	  return 5
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
	case 4:
	  return .week1
	case 5:
	  return .month1
	default:
	  return .hour1
	}
  }
  
  private func applyCurrentSettings() {
	self.chartSettings = UserDataManager.TradingViewChartSettings(
	  interval: self.selectedInterval(),
	  theme: self.currentChartTheme(),
	  showsToolbar: self.chartSettings.showsToolbar
	)
	UserDataManager.tradingViewChartSettings = self.chartSettings
	self.refreshChart()
  }
  
  private func refreshChart() {
	guard let symbol = self.symbol else { return }
	let tradingViewSymbol = self.tradingViewSymbol(symbol: symbol)
	let themeValue = self.currentChartTheme().rawValue.jsEscaped
	let intervalValue = self.chartSettings.interval.rawValue.jsEscaped
	let symbolValue = tradingViewSymbol.jsEscaped
	// 앱의 상승/하락 색상 테마를 캔들 색에 반영
	let upColorValue = MarketColorPalette.riseColorHex.jsEscaped
	let downColorValue = MarketColorPalette.fallColorHex.jsEscaped
	let script = "updateChart('\(symbolValue)', '\(intervalValue)', '\(themeValue)', '\(upColorValue)', '\(downColorValue)');"
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
