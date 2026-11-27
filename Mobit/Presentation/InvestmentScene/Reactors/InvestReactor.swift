//
//  InvestReactor.swift
//  Mobit
//
//  Created by 조성재 on 4/8/25.
//

import Foundation
import UIKit
import ReactorKit
import RxSwift

class InvestReactor: Reactor {
  // ReactorKit 외부에서 mutation을 주입하려면 이게 필요
  private let mutationSubject = PublishSubject<InvestMutation>()
  private let disposeBag = DisposeBag()
  private let mainUseCase: MainUseCase
  // 이 Reactor의 저장소가 생성될 때 고정된 거래소다.
  let exchange: Exchange
  let initialState: InvestReactorState = InvestReactorState()

  init(mainUseCase: MainUseCase) {
	self.mainUseCase = mainUseCase
    self.exchange = ExchangeSelectionStore.currentExchange
	UserDataManager.userCryptoListObservable
      .observe(on: MainScheduler.asyncInstance)
	  .map { InvestMutation.setUserCrypto($0) }
	  .bind(to: mutationSubject)
	  .disposed(by: disposeBag)
	
	UserDataManager.userAvailableBalanceObservable
      .observe(on: MainScheduler.asyncInstance)
	  .map { InvestMutation.setUserAvailableBalance($0 ?? 0) }
	  .bind(to: mutationSubject)
	  .disposed(by: disposeBag)
  }
  
}

// 기본 설정
extension InvestReactor {
  enum InvestAction {
	case loadTransactions
	case invalidateSupportedMarkets
//	case updateUserAvailableBalance
  }

  /// 상태 변경 단위, 작업 단위
  enum InvestMutation {
	case setUserCrypto([CryptoTransactionDataModel]?)
	case setUserAvailableBalance(Double)
	case beginSupportedMarketsRequest(UUID, Exchange)
	case setSupportedMarketPairIDs(UUID, Exchange, Set<ExchangePairID>?)
	case invalidateSupportedMarkets
  }

  struct InvestReactorState {
	var cryptos: [CryptoTransactionDataModel] = []
	var userAvailableBalance: Double = UserDataManager.userInformation?.userAvailableBalance ?? 0
	var supportedMarketPairIDs: Set<ExchangePairID>?
    // 늦게 도착한 이전 거래소 목록을 무시할 요청 식별자다.
    var supportedMarketsRequestID: UUID?
    // 조회 오류는 이전 목록이 아닌 재시도 안내에만 사용한다.
    var supportedMarketsFailed = false
  }
}

extension InvestReactor {
  func transform(mutation: Observable<InvestMutation>) -> Observable<InvestMutation> {
	return Observable.merge(
	  mutation,                      // 원래 액션 기반의 내부 스트림
	  mutationSubject.asObservable() // 외부 이벤트 기반의 스트림
	)
  }
  
  // Observable 방출
  func mutate(action: InvestAction) -> Observable<InvestMutation> {
	switch action {
	case .loadTransactions:
	  let currentExchange = ExchangeSelectionStore.currentExchange
      // 이전 조회가 늦게 끝나더라도 마지막 요청만 반영한다.
      let requestID = UUID()
	  let supportedMarkets = self.fetchSupportedMarketPairIDs(for: currentExchange)
        .map { InvestMutation.setSupportedMarketPairIDs(requestID, currentExchange, $0) }
		.catch { error in
		  Log.warning("Failed to refresh supported markets: \(error.localizedDescription)")
		  return .just(.setSupportedMarketPairIDs(requestID, currentExchange, nil))
		}
        .observe(on: MainScheduler.instance)

	  return Observable.concat([
		.just(.setUserCrypto(UserDataManager.userCryptoList)),
        .just(.beginSupportedMarketsRequest(requestID, currentExchange)),
		supportedMarkets
	  ])

    case .invalidateSupportedMarkets:
      return .just(.invalidateSupportedMarkets)

	}
  }
  
  // View 업데이트
  func reduce(state: InvestReactorState, mutation: InvestMutation) -> InvestReactorState {
	var newState = state
	switch mutation {
	case .setUserCrypto(let cryptos):
	  // 거래소별 보유자산 분리: 현재 선택 거래소 보유분만 노출한다.
	  let currentExchange = ExchangeSelectionStore.currentExchange
	  newState.cryptos = (cryptos ?? []).filter { $0.staticData.exchange == currentExchange }
	case .setUserAvailableBalance(let userAvailableBalance):
	  newState.userAvailableBalance = userAvailableBalance
    case let .beginSupportedMarketsRequest(requestID, exchange):
      newState.supportedMarketsRequestID = exchange == self.exchange ? requestID : nil
      newState.supportedMarketPairIDs = nil
      newState.supportedMarketsFailed = false
    case let .setSupportedMarketPairIDs(requestID, exchange, pairIDs):
      guard newState.supportedMarketsRequestID == requestID,
            exchange == self.exchange, exchange == ExchangeSelectionStore.currentExchange else { return state }
      newState.supportedMarketPairIDs = pairIDs
      newState.supportedMarketsRequestID = nil
      newState.supportedMarketsFailed = pairIDs == nil
    case .invalidateSupportedMarkets:
      newState.supportedMarketPairIDs = nil
      newState.supportedMarketsRequestID = nil
      newState.supportedMarketsFailed = false
	}
	return newState
  }
}

extension InvestReactor {
  enum DelistingVerificationError: Error {
    case unavailable
    case supportRestored
    case rateUnavailable

    // 목록 재확인과 환율 재조회의 실패 원인을 구분해서 안내한다.
    var message: String {
      switch self {
      case .unavailable: return FuturesText.text("spot_delisting_market_unavailable")
      case .supportRestored: return FuturesText.text("spot_delisting_support_changed")
      case .rateUnavailable: return TradeOrderValidator.ValidationError.missingSettlementRate.message
      }
    }
  }

  // 유효하지 않은 목록은 거래지원 종료의 근거로 사용할 수 없다.
  func fetchSupportedMarketPairIDs(for exchange: Exchange) -> Observable<Set<ExchangePairID>> {
    guard exchange == self.exchange, exchange == ExchangeSelectionStore.currentExchange else {
      return .error(DelistingVerificationError.unavailable)
    }
    return mainUseCase.fetchCryptoList()
      .take(1)
      .map { cryptoList in
        // 잘못된 코드가 하나라도 있으면 부분 누락을 정상 목록으로 오인하지 않는다.
        let markets = cryptoList.map(\.market)
        guard !markets.isEmpty, markets.allSatisfy({ market in
          let display = ExchangeMarketCodeConverter.displayMarket(fromRawMarketCode: market, exchange: exchange)
          let components = display.split(separator: "/", omittingEmptySubsequences: false)
          return ExchangeMarketCodeConverter.rawMarketCode(fromDisplayMarket: display, exchange: exchange) == market
            && components.count == 2 && components.allSatisfy { component in
            !component.isEmpty && component.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
          }
        }) else { throw DelistingVerificationError.unavailable }
        return MarketFormat.exchangePairIDs(fromAPIMarkets: markets, exchange: exchange)
      }
      .ifEmpty(switchTo: .error(DelistingVerificationError.unavailable))
  }

  func verifiedDelistingSettlementRate(
    for pairID: ExchangePairID,
    currency: SettlementCurrency
  ) -> Observable<Double?> {
    guard pairID.exchange == exchange else { return .error(DelistingVerificationError.unavailable) }
    return fetchSupportedMarketPairIDs(for: exchange)
      .observe(on: MainScheduler.instance)
      .flatMap { [self] markets -> Observable<Double?> in
        guard exchange == ExchangeSelectionStore.currentExchange else { return .error(DelistingVerificationError.unavailable) }
        guard !markets.contains(pairID) else { return .error(DelistingVerificationError.supportRestored) }
        guard let rateMarket = currency.holdingDisplayMarket else { return .just(nil) }
        // 목록 응답을 기다리는 동안 15초를 넘길 수 있어 종료 확인 직후에 검사한다.
        if let price = AppDataManager.shared.freshBTCKRWPrice(for: exchange) { return .just(price) }

        // 해당 거래소에서 원화 환산에 사용할 BTC 시세만 조회한다.
        let market = ExchangeMarketCodeConverter.rawMarketCode(fromDisplayMarket: rateMarket, exchange: exchange)
        return mainUseCase.fetchCryptoTicker(markets: [market])
          .take(1)
          .timeout(.seconds(10), scheduler: MainScheduler.instance)
          .observe(on: MainScheduler.instance)
          .map { [self] tickers -> Double? in
            guard exchange == ExchangeSelectionStore.currentExchange,
                  let price = tickers.first(where: { $0.market == market })?.tradePrice,
                  price.isFinite, price > 0 else { throw DelistingVerificationError.rateUnavailable }
            // 조회 도중 수신한 실시간 시세를 뒤늦은 REST 응답으로 덮어쓰지 않는다.
            if let latest = AppDataManager.shared.freshBTCKRWPrice(for: exchange) { return latest }
            AppDataManager.shared.updateBTCKRWPrice(price, for: exchange)
            return price
          }
          .ifEmpty(switchTo: .error(DelistingVerificationError.rateUnavailable))
          .catch { _ in .error(DelistingVerificationError.rateUnavailable) }
      }
  }
}
