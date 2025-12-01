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
  private let refreshControl = UIRefreshControl()
  
  override func viewWillAppear(_ animated: Bool) {
	super.viewWillAppear(animated)
  }
  
  override func viewDidLoad() {
	super.viewDidLoad()
	setUI()
	setData()
	setupPullToRefresh()
	loadWebView()
  }
  
  func setUI() {
  }
  
  func setData() {
	self.webView.navigationDelegate = self
  }
  
  private func setupPullToRefresh() {
	  webView.scrollView.refreshControl = refreshControl
	  refreshControl.addTarget(self, action: #selector(pulledToRefresh), for: .valueChanged)
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
  
  @objc private func pulledToRefresh() {
	  webView.reload()
  }

  // WKNavigationDelegate
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
	  if refreshControl.isRefreshing {
		  refreshControl.endRefreshing()
	  }
  }
}
