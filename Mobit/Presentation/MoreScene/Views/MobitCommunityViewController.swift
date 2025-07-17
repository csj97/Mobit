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
	if let url = Bundle.main.url(forResource: "mobitCommunity", withExtension: "html") {
//	  mobitWebView.loadFileURL(url, allowingReadAccessTo: url)
	  mobitWebView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
	}
  }
  
  @IBAction func tapOnNavigationBack(_ sender: UIButton) {
	self.navigationController?.popViewController(animated: true)
  }
}

// MARK: - WKScriptMessageHandler 브릿지 처리
extension MobitCommunityViewController: WKScriptMessageHandler {
  func userContentController(
	_ userContentController: WKUserContentController,
	didReceive message: WKScriptMessage
  ) {
	print("🔥 메시지 수신됨!")
	 print("메시지 이름: \(message.name)")
	 print("메시지 내용: \(message.body)")
	 
	 // 콘솔 로그 처리
	 if message.name == "consoleLog" {
		 print("📝 [JS Log]: \(message.body)")
		 return
	 }
	 
	 if message.name == "consoleError" {
		 print("❌ [JS Error]: \(message.body)")
		 return
	 }
	 
	 // 기존 브릿지 처리 코드
	 if message.name == javascriptBridgeInterfaceName {
		 print("✅ 브릿지 이름 매칭 성공")
		 
		 guard let bridge = message.body as? [String: Any] else {
			 print("❌ 메시지 파싱 실패: \(message.body)")
			 return
		 }
		 
		 guard let type = bridge["type"] as? String else {
			 print("❌ type 파싱 실패")
			 return
		 }
		 
		 switch type {
		 case "test":
			 print("🧪 테스트 메시지 수신")
		 case "success":
			 print("✅ 성공 처리")
			 self.show(alertType: .onlyConfirm, title: "안내", content: "개발자에게 성공적으로 전달되었습니다.", callBack: nil)
		 case "failure":
			 print("❌ 실패 처리")
			 self.show(alertType: .onlyConfirm, title: "안내", content: "등록에 실패하였습니다.", callBack: nil)
		 default:
			 print("❓ 알 수 없는 타입: \(type)")
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
	print("🌐 HTML 로딩 완료")
	
	// JavaScript 환경 확인
	webView.evaluateJavaScript("typeof window.webkit !== 'undefined'") { (result, error) in
	  print("webkit 사용 가능: \(result ?? "nil")")
	}
	
	webView.evaluateJavaScript("typeof window.webkit.messageHandlers !== 'undefined'") { (result, error) in
	  print("messageHandlers 사용 가능: \(result ?? "nil")")
	}
	
	webView.evaluateJavaScript("typeof window.webkit.messageHandlers.MobitCommunity !== 'undefined'") { (result, error) in
	  print("MobitCommunity 핸들러 사용 가능: \(result ?? "nil")")
	}
  }
  
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
	  print("❌ 웹뷰 로딩 실패: \(error)")
  }
  
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
	  print("❌ 웹뷰 프로비저널 로딩 실패: \(error)")
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



