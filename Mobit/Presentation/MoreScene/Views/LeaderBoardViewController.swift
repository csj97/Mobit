//
//  LeaderBoardViewController.swift
//  Mobit
//
//  Created by 조성재 on 12/2/25.
//

import UIKit
import WebKit

class LeaderBoardViewController: MobitBaseViewController, WKNavigationDelegate {
  
  @IBOutlet weak var webView: WKWebView!
  
  weak var coordinator: LeaderBoardCoordinator?
  weak var delegate: MainCoordinatorDelegate?
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
	// scrollView 배경은 XIB로 지정할 수 없어 코드에서 맞춘다
	webView.scrollView.backgroundColor = .mobitColors(.backgroundPrimary)
  }
  
  func setData() {
	self.webView.navigationDelegate = self
  }
  
  private func setupPullToRefresh() {
	webView.scrollView.refreshControl = refreshControl
	refreshControl.addTarget(self, action: #selector(pulledToRefresh), for: .valueChanged)
  }
  
  private func loadWebView() {
	
	let urlString = "https://www.binance.com/en/futures-activity/leaderboard/"
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
  
  @IBAction func tapOnBackButton(_ sender: UIButton) {
      if self.webView.canGoBack {
          self.webView.goBack()
      } else {
          self.navigationController?.popViewController(animated: true)
      }
  }
    
  // WKNavigationDelegate
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
	if refreshControl.isRefreshing {
	  refreshControl.endRefreshing()
	}
  }
}
