//
//  MobitAnalyticsUtil.swift
//  Mobit
//
//  Created by 조성재 on 7/16/25.
//

import Foundation
import FirebaseAnalytics

enum MobitAnalyticsScreenEventType: String {
  case exchange_tab = "거래소 화면"
  case investment_tab = "투자내역 화면"
  case investment_charge = "투자내역 충전 버튼"
  case more_tab = "더보기 화면"
  case trade_screen = "트레이드 화면"
  case trade_order = "코인 주문 탭"
  case trade_chart = "코인 차트 탭"
  case trade_info = "코인 정보 탭"
  case trade_order_buy = "코인 매수 탭"
  case trade_order_sell = "코인 매도 탭"
  case trade_order_history = "코인 거래내역 탭"
  case more_charge = "더보기 충전 버튼"
  case more_notice = "더보기 고지사항 버튼"
  case more_init_data = "더보기 초기화 버튼"
  
  var sendScreenName: String {
	return self.rawValue
  }
}

enum MobitAnalyticsRewardEventType: String {
  case reward_present = "광고 시청 시작"
  case reward_finish = "광고 시청 완료"
  case reward_failed = "광고 로드 실패"
  case reward_close = "광고 조기 종료"
  
  var sendRewardEventName: String {
	return self.rawValue
  }
}

class MobitAnalyticsUtil {
  static func sendScreen(event: MobitAnalyticsScreenEventType) {
	print("MOBIT AnalyticsEvent : \(event.sendScreenName)")
	
	Analytics.logEvent(
	  AnalyticsEventScreenView,
	  parameters: [AnalyticsParameterScreenName: event.sendScreenName]
	)
  }
  
  static func sendAdEvent(event: MobitAnalyticsRewardEventType) {
	Analytics.logEvent(
	  AnalyticsEventAdImpression,
	  parameters: [AnalyticsParameterAdUnitName: event.sendRewardEventName]
	)
	print("MOBIT Analytics [광고] - \(event.sendRewardEventName)")
  }
}
