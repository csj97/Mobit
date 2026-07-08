//
//  MobitAnalyticsUtil.swift
//  Mobit
//
//  Created by 조성재 on 7/16/25.
//

import Foundation
import FirebaseAnalytics

/// Event Parameter
//protocol MobitAnalyticsEventRule {
//	var key: String { get }
//	var value: String { get }
//}

protocol MobitAnalyticsEventRule {
	var location: String { get }
	var stepDepth01: String { get }
	var stepDepth02: String { get }
}

/// Tracking Screen Event
enum MobitAnalyticsScreenEventType: Int, MobitAnalyticsEventRule {
  case trade_order
  case trade_chart
  case trade_info
  case trade_order_buy
  case trade_order_sell
  case trade_order_history
  
  var location: String {
	switch self {
	case .trade_info,
		.trade_chart,
		.trade_order,
		.trade_order_buy,
		.trade_order_sell,
		.trade_order_history:
	  return "트레이딩_화면"
	}
  }
  
  var stepDepth01: String {
	switch self {
	case .trade_info,
		.trade_chart,
		.trade_order,
		.trade_order_buy,
		.trade_order_sell,
		.trade_order_history:
	  return "트레이딩 화면"
	}
  }
  
  var stepDepth02: String {
	switch self {
	case .trade_info:
	  return "트레이딩_탭_정보"
	case .trade_chart:
	  return "트레이딩_탭_차트"
	case .trade_order:
	  return "트레이딩_탭_주문"
	case .trade_order_buy:
	  return "트레이딩_주문_매수"
	case .trade_order_sell:
	  return "트레이딩_주문_매도"
	case .trade_order_history:
	  return "트레이딩_주문_거래내역"
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
  
  var location: String {
	return ""
  }
  
  var stepDepth01: String {
	switch self {
	case .reward_present: return "광고_시청"
	case .reward_finish: return "광고_시청"
	case .reward_failed: return "광고_시청"
	case .reward_close: return "광고_시청"
	}
  }
  
  var stepDepth02: String {
	switch self {
	case .reward_present: return "광고_시청_시작"
	case .reward_finish: return "광고_시청_완료"
	case .reward_failed: return "광고_로드_실패"
	case .reward_close: return "광고_닫기_버튼"
	}
  }
}

/// Tracking Click Event
enum MobitAnalyticsClickEventType: Int, MobitAnalyticsEventRule {
  case exchange_sort
  case ad_click_cancel
  case ad_click_confirm
  case pnl_click_save
  case pnl_click_share
  case trade_order_buy_complete
  case trade_order_buy_fail
  case trade_order_sell_complete
  case trade_order_sell_fail
  case investment_charge
  case investment_pnl
  case more_charge
  case more_notice
  case more_init_data
  case more_community
  case more_leaderboard
  
  var location: String {
	switch self {
	case .exchange_sort:
	  return "거래소_화면"
	case .ad_click_cancel,
		.ad_click_confirm:
	  return "광고_안내_알럿"
	case .pnl_click_save,
		.pnl_click_share:
	  return "실현손익_내역_화면"
	case .trade_order_buy_complete,
		.trade_order_buy_fail,
		.trade_order_sell_complete,
		.trade_order_sell_fail:
	  return "트레이딩_화면"
	case .investment_charge,
		.investment_pnl:
	  return "투자내역_화면"
	case .more_charge,
		.more_notice,
		.more_init_data,
		.more_community,
		.more_leaderboard:
	  return "더보기_화면"
	}
  }
  
  var stepDepth01: String {
	switch self {
	case .exchange_sort:
	  return "거래소_탭"
	case .ad_click_cancel,
		.ad_click_confirm:
	  return "광고_알럿"
	case .pnl_click_save,
		.pnl_click_share:
	  return "실현손익_알럿"
	case .trade_order_buy_complete,
		.trade_order_buy_fail,
		.trade_order_sell_complete,
		.trade_order_sell_fail:
	  return "트레이딩_주문"
	case .investment_charge,
		.investment_pnl:
	  return "투자내역_탭"
	case .more_charge,
		.more_notice,
		.more_init_data,
		.more_community,
		.more_leaderboard:
	  return "더보기_탭"
	}
  }
  
  var stepDepth02: String {
	switch self {
	case .exchange_sort:
	  return "정렬_버튼_클릭"
	case .ad_click_cancel:
	  return "광고_알럿_취소"
	case .ad_click_confirm:
	  return "광고_알럿_확인"
	case .pnl_click_save:
	  return "실현손익_저장"
	case .pnl_click_share:
	  return "실현손익_공유"
	case .trade_order_buy_complete:
	  return "트레이딩_주문_매수_성공"
	case .trade_order_buy_fail:
	  return "트레이딩_주문_매수_실패"
	case  .trade_order_sell_complete:
	  return "트레이딩_주문_매도_성공"
	case .trade_order_sell_fail:
	  return "트레이딩_주문_매도_실패"
	case .investment_charge:
	  return "투자내역_충전_버튼_클릭"
	case .investment_pnl:
	  return "투자내역_pnl_버튼_클릭"
	case .more_charge:
	  return "더보기_충전_버튼_클릭"
	case .more_notice:
	  return "더보기_안내사항_버튼_클릭"
	case .more_init_data:
	  return "더보기_초기화_버튼_클릭"
	case .more_community:
	  return "더보기_커뮤니티_버튼_클릭"
	case .more_leaderboard:
	  return "바이낸스_리더보드_버튼_클릭"
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

  static func sendClickEvent(
	location: String,
	stepDepth01: String,
	stepDepth02: String,
	stepDepth03: String? = nil,
	extraParameters: [String: Any] = [:]
  ) {
	self.sendLegacyEvent(
	  eventName: "mobit_click_event",
	  location: location,
	  stepDepth01: stepDepth01,
	  stepDepth02: stepDepth02,
	  stepDepth03: stepDepth03,
	  extraParameters: extraParameters
	)
  }
  
  static func sendBaseLegacyEvent<T: MobitAnalyticsEventRule>(eventName: String, type: T) {
	self.sendLegacyEvent(
	  eventName: eventName,
	  location: type.location,
	  stepDepth01: type.stepDepth01,
	  stepDepth02: type.stepDepth02
	)
  }

  private static func sendLegacyEvent(
	eventName: String,
	location: String,
	stepDepth01: String,
	stepDepth02: String,
	stepDepth03: String? = nil,
	extraParameters: [String: Any] = [:]
  ) {
	let requestParameters: [String: Any] = [
	  "location": location,
	  "Step_depth_01": stepDepth01,
	  "Step_depth_02": stepDepth02
	].merging(
	  stepDepth03.map { ["Step_depth_03": $0] } ?? [:],
	  uniquingKeysWith: { _, new in new }
	).merging(
	  extraParameters,
	  uniquingKeysWith: { _, new in new }
	)
	
	Analytics.logEvent(eventName, parameters: requestParameters)
	
	Log.info("MOBIT Analytics [Event Name] - \(eventName)")
	Log.info("MOBIT Analytics [Event Location] - \(location)")
	Log.info("MOBIT Analytics [Event Depth 01] - \(stepDepth01)")
	Log.info("MOBIT Analytics [Event Depth 02] - \(stepDepth02)")
	if let stepDepth03 {
	  Log.info("MOBIT Analytics [Event Depth 03] - \(stepDepth03)")
	}
	if !extraParameters.isEmpty {
	  Log.info("MOBIT Analytics [Extra Parameters] - \(extraParameters)")
	}
  }
}
