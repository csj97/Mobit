//
//  CommunityViewController.swift
//  Mobit
//
//  Created by 조성재 on 11/27/25.
//

import UIKit
import WebKit

class NewsViewController: MobitBaseViewController, WKNavigationDelegate {
  
  @IBOutlet weak var webView: WKWebView!
  
  weak var coordinator: NewsCoordinator?
  
  override func viewWillAppear(_ animated: Bool) {
	super.viewWillAppear(animated)
  }
  
  override func viewDidLoad() {
	super.viewDidLoad()
	setUI()
	setData()
	loadWebView()
  }
  
  func setUI() {
  }
  
  func setData() {
	self.webView.navigationDelegate = self
  }
  
  private func loadWebView() {
	
	let urlString = "https://coinness.com/news"
	if let url = URL(string: urlString) {
	  let request = URLRequest(url: url)
	  webView.load(request)
	}
	
	webView.scrollView.isScrollEnabled = true
	webView.scrollView.pinchGestureRecognizer?.isEnabled = false
  }
  
}
