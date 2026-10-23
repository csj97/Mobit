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
  #if DEBUG
  // 테스트가 비동기 주문 결과를 관찰할 때 전송 대체 콜백을 안전하게 교체한다.
  private static let eventLock = NSLock()
  // 테스트에서만 Firebase 전송을 대체하고 실제 이벤트 파라미터를 수집한다.
  private static var storedEventCallBack: ((String, [String: Any]) -> Void)?
  // 계측 회귀 검사는 SDK 업로드 없이 실제 호출 경계와 중복 횟수를 확인한다.
  static var eventCallBack: ((String, [String: Any]) -> Void)? {
    get {
      eventLock.lock()
      defer { eventLock.unlock() }
      return storedEventCallBack
    }
    set {
      eventLock.lock()
      defer { eventLock.unlock() }
      storedEventCallBack = newValue
    }
  }
  #endif

  static func sendScreenEvent(
    event: MobitAnalyticsScreenEventType,
    account: TradingAccountID? = nil,
    instrument: TradingInstrumentID? = nil,
    extraParameters: [String: Any] = [:]
  ) {
    sendBaseLegacyEvent(eventName: "mobit_screen_event", type: event, account: account, instrument: instrument, extraParameters: extraParameters)
  }

  static func sendScreenEvent(
    location: String,
    stepDepth01: String,
    stepDepth02: String,
    stepDepth03: String? = nil,
    account: TradingAccountID? = nil,
    instrument: TradingInstrumentID? = nil,
    extraParameters: [String: Any] = [:]
  ) {
    sendLegacyEvent(
      eventName: "mobit_screen_event",
      location: location,
      stepDepth01: stepDepth01,
      stepDepth02: stepDepth02,
      stepDepth03: stepDepth03,
      account: account,
      instrument: instrument,
      extraParameters: extraParameters
    )
  }

  static func sendAdEvent(
    event: MobitAnalyticsRewardEventType,
    account: TradingAccountID? = nil,
    instrument: TradingInstrumentID? = nil,
    extraParameters: [String: Any] = [:]
  ) {
    sendBaseLegacyEvent(eventName: "mobit_ad_event", type: event, account: account, instrument: instrument, extraParameters: extraParameters)
  }

  static func sendClickEvent(
    event: MobitAnalyticsClickEventType,
    account: TradingAccountID? = nil,
    instrument: TradingInstrumentID? = nil,
    extraParameters: [String: Any] = [:]
  ) {
    sendBaseLegacyEvent(eventName: "mobit_click_event", type: event, account: account, instrument: instrument, extraParameters: extraParameters)
  }

  static func sendClickEvent(
    location: String,
    stepDepth01: String,
    stepDepth02: String,
    stepDepth03: String? = nil,
    account: TradingAccountID? = nil,
    instrument: TradingInstrumentID? = nil,
    extraParameters: [String: Any] = [:]
  ) {
    sendLegacyEvent(
      eventName: "mobit_click_event",
      location: location,
      stepDepth01: stepDepth01,
      stepDepth02: stepDepth02,
      stepDepth03: stepDepth03,
      account: account,
      instrument: instrument,
      extraParameters: extraParameters
    )
  }

  static func sendPushOpenEvent(
    destination: String,
    action: String? = nil,
    campaignID: String?
  ) {
    // Firebase 기본 알림 열기 이벤트와 구분해 실제 원격 알림 클릭 유입을 기록한다.
    let eventName = "push_open"
    // 화면·동작의 지원 여부와 별개로 분석에 사용할 식별자 형식만 제한한다.
    let identifierPattern = "^[a-z][a-z0-9_]{0,39}$"
    // 파서가 전달한 화면 식별자를 공백과 대소문자 차이 없이 기록한다.
    let normalizedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    // 푸시 유입 분석에는 이동 대상과 선택적인 동작·캠페인 식별자만 전송한다.
    var parameters: [String: Any] = [
      "destination": normalizedDestination.range(of: identifierPattern, options: .regularExpression) != nil
        ? normalizedDestination : "app"
    ]
    // 동작이 없거나 형식이 잘못됐으면 파라미터를 추가하지 않는다.
    if let normalizedAction = action?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
       normalizedAction.range(of: identifierPattern, options: .regularExpression) != nil {
      parameters["action"] = normalizedAction
    }
    if let campaignID {
      // 식별자에 필요한 문자만 허용하고 Firebase 문자열 길이 제한을 지킨다.
      let normalizedCampaignID = campaignID.trimmingCharacters(in: .whitespacesAndNewlines)
      // 일반 Firebase 문자열 파라미터의 최대 길이를 적용한다.
      let campaignIDLengthLimit = 100
      if !normalizedCampaignID.isEmpty,
         normalizedCampaignID.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil {
        parameters["campaign_id"] = String(normalizedCampaignID.prefix(campaignIDLengthLimit))
      }
    }
    #if DEBUG
    if let eventCallBack {
      eventCallBack(eventName, parameters)
      return
    }
    #endif
    Analytics.logEvent(eventName, parameters: parameters)
    Log.info("MOBIT Analytics [Event Name] - \(eventName)")
  }

  static func sendBaseLegacyEvent<T: MobitAnalyticsEventRule>(
    eventName: String,
    type: T,
    account: TradingAccountID? = nil,
    instrument: TradingInstrumentID? = nil,
    extraParameters: [String: Any] = [:]
  ) {
    sendLegacyEvent(
      eventName: eventName,
      location: type.location,
      stepDepth01: type.stepDepth01,
      stepDepth02: type.stepDepth02,
      account: account,
      instrument: instrument,
      extraParameters: extraParameters
    )
  }

  static func exchangeName(_ exchange: Exchange) -> String {
    switch exchange {
    case .upbit: return "업비트"
    case .bithumb: return "빗썸"
    case .binance: return "바이낸스"
    case .okx: return "오케이엑스"
    }
  }

  static func productName(_ product: TradingProduct) -> String {
    product == .spot ? "현물" : "선물"
  }

  static func accountParameters(
    _ account: TradingAccountID?,
    instrument: TradingInstrumentID? = nil
  ) -> [String: Any] {
    // BTC 마켓도 거래소의 단일 현물 계좌에 속하므로 계좌 통화와 결제 마켓을 구분한다.
    let eventAccount = account ?? instrument.map {
      TradingAccountID(exchange: $0.exchange, product: $0.product, currency: $0.product == .spot ? .krw : $0.settlementCurrency)
    }
    guard let eventAccount else { return [:] }
    // 영문 식별자는 분석 조건으로, 한글 이름은 콘솔에서 계좌를 바로 구분하는 데 쓴다.
    var parameters: [String: Any] = [
      "exchange": eventAccount.exchange.rawValue,
      "exchange_name": exchangeName(eventAccount.exchange),
      "product": eventAccount.product.rawValue,
      "product_name": productName(eventAccount.product),
      "account_name": "\(exchangeName(eventAccount.exchange))_\(productName(eventAccount.product))",
      "currency": eventAccount.currency.rawValue
    ]
    if let instrument, instrument.exchange == eventAccount.exchange, instrument.product == eventAccount.product {
      parameters["market"] = instrument.rawSymbol
      parameters["market_currency"] = instrument.settlementCurrency.rawValue
    }
    return parameters
  }

  static func eventParameters(
    location: String,
    stepDepth01: String,
    stepDepth02: String,
    stepDepth03: String? = nil,
    account: TradingAccountID? = nil,
    instrument: TradingInstrumentID? = nil,
    extraParameters: [String: Any] = [:]
  ) -> [String: Any] {
    // 호출부의 부가 정보가 실제 주문 계좌나 기존 행동 경로를 덮어쓰지 못하게 한다.
    var parameters = extraParameters.merging(accountParameters(account, instrument: instrument), uniquingKeysWith: { _, accountValue in accountValue })
    parameters["location"] = location
    parameters["Step_depth_01"] = stepDepth01
    parameters["Step_depth_02"] = stepDepth02
    if let stepDepth03 { parameters["Step_depth_03"] = stepDepth03 }
    return parameters
  }

  private static func sendLegacyEvent(
    eventName: String,
    location: String,
    stepDepth01: String,
    stepDepth02: String,
    stepDepth03: String? = nil,
    account: TradingAccountID? = nil,
    instrument: TradingInstrumentID? = nil,
    extraParameters: [String: Any] = [:]
  ) {
    // 저장 당시 계좌를 포함한 동일 파라미터를 Firebase와 계측 테스트에 전달한다.
    let requestParameters = eventParameters(
      location: location,
      stepDepth01: stepDepth01,
      stepDepth02: stepDepth02,
      stepDepth03: stepDepth03,
      account: account,
      instrument: instrument,
      extraParameters: extraParameters
    )
    #if DEBUG
    if let eventCallBack {
      eventCallBack(eventName, requestParameters)
      return
    }
    #endif
    Analytics.logEvent(eventName, parameters: requestParameters)
    Log.info("MOBIT Analytics [Event Name] - \(eventName)")
    Log.info("MOBIT Analytics [Parameters] - \(requestParameters)")
  }
}
