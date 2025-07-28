//
//  MobitAnalyticsUtil.swift
//  Mobit
//
//  Created by 조성재 on 7/16/25.
//

import Foundation
import FirebaseAnalytics

/// Event Parameter
protocol MobitAnalyticsEventRule {
	var key: String { get }
	var value: String { get }
}

/// Tracking Screen Event
enum MobitAnalyticsScreenEventType: Int, MobitAnalyticsEventRule {
  case exchange_tab
  case investment_tab
  case investment_charge
  case more_tab
  case trade_screen
  case trade_order
  case trade_chart
  case trade_info
  case trade_order_buy
  case trade_order_sell
  case trade_order_history
  case more_charge
  case more_notice
  case more_init_data

  var key: String {
	switch self {
	case .exchange_tab: return "exchange_tab"
	case .investment_tab: return "investment_tab"
	case .investment_charge: return "investment_charge"
	case .more_tab: return "more_tab"
	case .trade_screen: return "trade_screen"
	case .trade_order: return "trade_order"
	case .trade_chart: return "trade_chart"
	case .trade_info: return "trade_info"
	case .trade_order_buy: return "trade_order_buy"
	case .trade_order_sell: return "trade_order_sell"
	case .trade_order_history: return "trade_order_history"
	case .more_charge: return "more_charge"
	case .more_notice: return "more_notice"
	case .more_init_data: return "more_init_data"
	}
  }

  var value: String {
	switch self {
	case .exchange_tab: return "거래소 화면"
	case .investment_tab: return "투자내역 화면"
	case .investment_charge: return "투자내역 충전 버튼"
	case .more_tab: return "더보기 화면"
	case .trade_screen: return "트레이드 화면"
	case .trade_order: return "코인 주문 탭"
	case .trade_chart: return "코인 차트 탭"
	case .trade_info: return "코인 정보 탭"
	case .trade_order_buy: return "코인 매수 탭"
	case .trade_order_sell: return "코인 매도 탭"
	case .trade_order_history: return "코인 거래내역 탭"
	case .more_charge: return "더보기 충전 버튼"
	case .more_notice: return "더보기 고지사항 버튼"
	case .more_init_data: return "더보기 초기화 버튼"
	}
  }
}

/// Tracking Ad Event
enum MobitAnalyticsRewardEventType: Int, MobitAnalyticsEventRule {
  /// 광고 시청 시작
  case reward_present
  /// 광고 시청 완료
  case reward_finish
  /// 광고 로드 실패
  case reward_failed
  /// 광고 조기 종료
  case reward_close
  
  
  var key: String {
	switch self {
	case .reward_present: return "reward_present"
	case .reward_finish: return "reward_finish"
	case .reward_failed: return "reward_failed"
	case .reward_close: return "reward_close"
	}
  }
  
  var value: String {
	switch self {
	case .reward_present: return "광고 시청 시작"
	case .reward_finish: return "광고 시청 완료"
	case .reward_failed: return "광고 로드 실패"
	case .reward_close: return "광고 조기 종료"
	}
  }
}

/// Tracking Click Event
enum MobitAnalyticsClickEventType: Int, MobitAnalyticsEventRule {
  case ad_click_cancel
  case ad_click_confirm
  
  var key: String {
	switch self {
	case .ad_click_cancel: return "ad_click_cancel"
	case .ad_click_confirm: return "ad_click_confirm"
	}
  }
  
  var value: String {
	switch self {
	case .ad_click_cancel: return "광고 안내 팝업 취소"
	case .ad_click_confirm: return "광고 안내 팝업 확인"
	}
  }
}

class MobitAnalyticsUtil {
  /// 화면 이벤트
  static func sendScreenEvent(event: MobitAnalyticsScreenEventType) {
	self.sendBaseLegacyEvent(eventName: "mobit_screen_event", type: event)
  }
  
  /// 광고 이벤트
  static func sendAdEvent(event: MobitAnalyticsRewardEventType) {
	self.sendBaseLegacyEvent(eventName: "mobit_ad_event", type: event)
  }
  
  static func sendClickEvent(event: MobitAnalyticsClickEventType) {
	self.sendBaseLegacyEvent(eventName: "mobit_click_event", type: event)
  }
  
  static func sendBaseLegacyEvent<T: MobitAnalyticsEventRule>(eventName: String, type: T) {
	let requestParameters: [String: Any] = [
	  "event_type": eventName,
	  "event_name": type.key,
	  "event_info": type.value
	]
	
	Analytics.logEvent(type.key, parameters: requestParameters)
	
	Log.info("MOBIT Analytics [Event Name] - \(eventName)")
	Log.info("MOBIT Analytics [Event Type] - \(type.key)")
	Log.info("MOBIT Analytics [Event Info] - \(type.value)")
  }
}
