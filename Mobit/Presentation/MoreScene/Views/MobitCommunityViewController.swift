//
//  MobitCommunityViewController.swift
//  Mobit
//
//  Created by 조성재 on 7/17/25.
//

import UIKit
import WebKit

class MobitCommunityViewController: UIViewController, UIScrollViewDelegate, MobitAlertDelegate {
  
  @IBOutlet weak var baseView: UIView!
  
  var mobitWebView: WKWebView = WKWebView(frame: .zero)
  
  var html: String? = nil
  var javascriptBridgeInterfaceName = "MobitCommunity"
  weak var coordinator: MobitCommunityCoordinator?
  weak var delegate: MainCoordinatorDelegate?
  
  override func viewDidLoad() {
	super.viewDidLoad()
	
	self.configureWebView()
	self.loadLocalHTML()
  }
  
  override func viewWillDisappear(_ animated: Bool) {
	super.viewWillDisappear(animated)
	self.delegate?.mainCoordinatorDidRequestShowTabBar()
  }
  
  func configureWebView() {
	let config = WKWebViewConfiguration()
	let contentController = WKUserContentController()
	contentController.add(self, name: self.javascriptBridgeInterfaceName)
	config.userContentController = contentController
	config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
	config.defaultWebpagePreferences.allowsContentJavaScript = true
	config.preferences.setValue(true, forKey: "developerExtrasEnabled")

	mobitWebView = WKWebView(frame: self.baseView.bounds, configuration: config)
	mobitWebView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
	mobitWebView.navigationDelegate = self
	mobitWebView.uiDelegate = self
	mobitWebView.scrollView.delegate = self
	mobitWebView.scrollView.isScrollEnabled = false
	
	self.baseView.addSubview(mobitWebView)
  }
  
  private func loadLocalHTML() {
//	if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
//	  mobitWebView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
//	}
	if let url = URL(string: "https://csj97.github.io/Mobit/") {
	  let request = URLRequest(url: url)
	  mobitWebView.load(request)
	}
  }
  
  @IBAction func tapOnNavigationBack(_ sender: UIButton) {
	self.coordinator?.navigationController.popViewController(animated: true)
  }
}

// MARK: - WKScriptMessageHandler 브릿지 처리
extension MobitCommunityViewController: WKScriptMessageHandler {
  func userContentController(
	_ userContentController: WKUserContentController,
	didReceive message: WKScriptMessage
  ) {
	
	// 기존 브릿지 처리 코드
	if message.name == javascriptBridgeInterfaceName {
	  
	  guard let bridge = message.body as? [String: Any] else {
		Log.error("❌ 메시지 파싱 실패: \(message.body)")
		return
	  }
	  
	  guard let type = bridge["type"] as? String else {
		Log.error("❌ type 파싱 실패")
		return
	  }
	  
	  switch type {
	  case "none":
		self.show(alertType: .onlyConfirm, title: "안내", content: "내용을 입력해 주세요.", callBack: nil)
	  case "success":
		self.show(alertType: .onlyConfirm, title: "안내", content: "개발자에게 성공적으로 전달되었습니다.", callBack: nil)
	  case "failure":
		self.show(alertType: .onlyConfirm, title: "안내", content: "등록에 실패하였습니다.", callBack: nil)
	  case "log":
		let content = bridge["content"] as? String
		self.show(alertType: .onlyConfirm, title: "안내", content: content ?? "알 수 없는 에러 발생", callBack: nil)
	  default:
		self.show(alertType: .onlyConfirm, title: "안내", content: "알 수 없는 에러 발생", callBack: nil)
	  }
	}
  }
}

// MARK: - WKNavigationDelegate
extension MobitCommunityViewController: WKNavigationDelegate {
  func webView(
	_ webView: WKWebView,
	decidePolicyFor navigationAction: WKNavigationAction,
	decisionHandler: @escaping (WKNavigationActionPolicy
	) -> Void) {
	
	decisionHandler(.allow)
  }
  
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
	Log.info("🌐 HTML 로딩 완료")
	
	let uuid = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
	let jsCode = "window.setDeviceUUID('\(uuid)');"
	webView.evaluateJavaScript(jsCode, completionHandler: nil)
	
	// JavaScript 환경 확인
	webView.evaluateJavaScript("typeof window.webkit !== 'undefined'") { (result, error) in
	  Log.info("webkit 사용 가능: \(result ?? "nil")")
	}
	
	webView.evaluateJavaScript("typeof window.webkit.messageHandlers !== 'undefined'") { (result, error) in
	  Log.info("messageHandlers 사용 가능: \(result ?? "nil")")
	}
	
	webView.evaluateJavaScript("typeof window.webkit.messageHandlers.MobitCommunity !== 'undefined'") { (result, error) in
	  Log.info("MobitCommunity 핸들러 사용 가능: \(result ?? "nil")")
	}
  }
  
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
	Log.error("❌ 웹뷰 로딩 실패: \(error)")
  }
  
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
	Log.error("❌ 웹뷰 프로비저널 로딩 실패: \(error)")
  }
}

// MARK: - WKUIDelegate
extension MobitCommunityViewController: WKUIDelegate {
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



