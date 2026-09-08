//
//  HybridAdSlotManager.swift
//  Mobit
//
//  Created by 조성재 on 4/9/26.
//

import Foundation
import FirebaseDatabase
import UIKit
import WebKit

enum HybridAdSlotResult {
  case googleBanner
  case coupangWidget(CoupangWidgetConfig)
}

struct HybridAdSlotConfig {
  let isEnabled: Bool
  let googleRatio: Int
  let coupangRatio: Int
  let dailyCoupangImpressionLimit: Int

  static let `default` = HybridAdSlotConfig(
    isEnabled: true,
    googleRatio: 80,
    coupangRatio: 20,
    dailyCoupangImpressionLimit: 2
  )

  init(
    isEnabled: Bool,
    googleRatio: Int,
    coupangRatio: Int,
    dailyCoupangImpressionLimit: Int
  ) {
    self.isEnabled = isEnabled
    self.googleRatio = max(0, googleRatio)
    self.coupangRatio = max(0, coupangRatio)
    self.dailyCoupangImpressionLimit = max(0, dailyCoupangImpressionLimit)
  }

  init(dictionary: [String: Any]) {
    let isEnabled = dictionary["isEnabled"] as? Bool ?? true
    let googleRatio = dictionary["googleRatio"] as? Int ?? 80
    let coupangRatio = dictionary["coupangRatio"] as? Int ?? 20
    let dailyLimit = dictionary["dailyCoupangImpressionLimit"] as? Int ?? 2
    self.init(
      isEnabled: isEnabled,
      googleRatio: googleRatio,
      coupangRatio: coupangRatio,
      dailyCoupangImpressionLimit: dailyLimit
    )
  }
}

struct CoupangWidgetConfig {
  let id: Int
  let template: String
  let trackingCode: String
  let width: Int
  let height: Int
  let tsource: String
  let isActive: Bool

  init?(_ dictionary: [String: Any]) {
    guard let id = dictionary["id"] as? Int,
          let template = dictionary["template"] as? String,
          let trackingCode = dictionary["trackingCode"] as? String else {
      return nil
    }

    self.id = id
    self.template = template
    self.trackingCode = trackingCode
    self.width = max(1, dictionary["width"] as? Int ?? 350)
    self.height = max(1, dictionary["height"] as? Int ?? 500)
    self.tsource = dictionary["tsource"] as? String ?? ""
    self.isActive = dictionary["isActive"] as? Bool ?? true
  }

  func html() -> String {
    return """
    <!doctype html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no"/>
      <style>
        body { margin:0; padding:0; background: transparent; overflow:hidden; }
        #wrap { width: \(self.width)px; height: \(self.height)px; margin: 0 auto; }
      </style>
    </head>
    <body>
      <div id="wrap"></div>
      <script src="https://ads-partners.coupang.com/g.js"></script>
      <script>
        new PartnersCoupang.G({
          "id": \(self.id),
          "template": "\(self.template)",
          "trackingCode": "\(self.trackingCode)",
          "width": "\(self.width)",
          "height": "\(self.height)",
          "tsource": "\(self.tsource)"
        });
      </script>
    </body>
    </html>
    """
  }
}

final class HybridAdSlotManager {
  static let shared = HybridAdSlotManager()

  private let dbRef = Database.database().reference()
  private let defaults = UserDefaults.standard

  private init() { }

  // 슬롯 설정/노출 한도/비율을 기반으로 이번 노출 광고 타입을 결정한다.
  func resolveAd(slotID: String, completion: @escaping (HybridAdSlotResult) -> Void) {
    self.fetchSlotConfig(slotID: slotID) { [weak self] config in
      guard let self = self else { return }

	  guard config.isEnabled else {
		completion(.googleBanner)
		return
	  }
	  
	  let totalRatio = max(config.googleRatio + config.coupangRatio, 1)
	  let roll = Int.random(in: 0..<totalRatio)
	  let shouldTryCoupang = roll >= config.googleRatio
	  
	  guard shouldTryCoupang else {
		completion(.googleBanner)
		return
	  }
	  
	  guard self.canShowCoupangToday(slotID: slotID, dailyLimit: config.dailyCoupangImpressionLimit) else {
		completion(.googleBanner)
		return
	  }
	  
	  self.fetchCoupangWidget(slotID: slotID) { widget in
		guard let widget = widget, widget.isActive else {
		  completion(.googleBanner)
		  return
		}
		
		self.incrementCoupangImpression(slotID: slotID)
		completion(.coupangWidget(widget))
	  }
	}
  }

  // Firebase에서 슬롯의 하이브리드 광고 설정값을 조회한다.
  private func fetchSlotConfig(slotID: String, completion: @escaping (HybridAdSlotConfig) -> Void) {
    let path = "adSlots/\(slotID)/config"
    self.dbRef.child(path).observeSingleEvent(of: .value) { snapshot in
      guard let dictionary = snapshot.value as? [String: Any] else {
        completion(.default)
        return
      }
      completion(HybridAdSlotConfig(dictionary: dictionary))
    }
  }

  // Firebase에서 슬롯에 연결된 쿠팡 위젯 설정을 조회한다.
  private func fetchCoupangWidget(slotID: String, completion: @escaping (CoupangWidgetConfig?) -> Void) {
    let path = "adSlots/\(slotID)/coupangWidget"
    self.dbRef.child(path).observeSingleEvent(of: .value) { snapshot in
      guard let dictionary = snapshot.value as? [String: Any] else {
        completion(nil)
        return
      }
      completion(CoupangWidgetConfig(dictionary))
    }
  }

  // 오늘 날짜 기준으로 쿠팡 광고를 추가 노출할 수 있는지 확인한다.
  private func canShowCoupangToday(slotID: String, dailyLimit: Int) -> Bool {
    guard dailyLimit > 0 else { return false }
    let key = "ad-slot-\(slotID)-coupang-impression-\(self.currentDateKey())"
    let current = self.defaults.integer(forKey: key)
    return current < dailyLimit
  }

  // 오늘 날짜 키의 쿠팡 노출 카운트를 1 증가시킨다.
  private func incrementCoupangImpression(slotID: String) {
    let key = "ad-slot-\(slotID)-coupang-impression-\(self.currentDateKey())"
    let current = self.defaults.integer(forKey: key)
    self.defaults.set(current + 1, forKey: key)
  }

  // 일일 노출 집계를 위한 서울 기준 날짜 문자열 키를 생성한다.
  private func currentDateKey() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
  }
}

final class CoupangWidgetBannerView: UIView {
  private let webView: WKWebView = {
    let config = WKWebViewConfiguration()
    config.defaultWebpagePreferences.allowsContentJavaScript = true
    let webView = WKWebView(frame: .zero, configuration: config)
    webView.translatesAutoresizingMaskIntoConstraints = false
    webView.scrollView.isScrollEnabled = false
    webView.backgroundColor = .clear
    webView.isOpaque = false
    return webView
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    self.setupUI()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    self.setupUI()
  }

  func configure(widget: CoupangWidgetConfig) {
    self.webView.loadHTMLString(widget.html(), baseURL: nil)
  }

  private func setupUI() {
    self.backgroundColor = .clear
    self.addSubview(self.webView)
    NSLayoutConstraint.activate([
      self.webView.topAnchor.constraint(equalTo: self.topAnchor),
      self.webView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
      self.webView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
      self.webView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
    ])
  }
}
