//
//  AppDataManager.swift
//  Mobit
//
//  Created by 조성재 on 9/3/25.
//

import Foundation
import FirebaseDatabase
import RxSwift

final class AppDataManager {
  static let shared = AppDataManager()
  static let btcKRWPriceRefreshAge: TimeInterval = 15
  static let btcKRWPriceMaxAge: TimeInterval = 60

  private struct TimedPrice {
    let price: Double
    let updatedAt: Date
  }
  
  private(set) var cachedKRWCMCList: [FirebaseCMCResponse] = []
  private(set) var cachedBTCCMCList: [FirebaseCMCResponse] = []
  private let firebaseDB = Database.database().reference()

  /// 거래소별 BTC/KRW 현재가. BTC 마켓 보유분을 원화로 환산할 때 쓴다.
  /// 거래소마다 시세가 다르고 보유자산도 거래소별로 분리되어 있어 하나의 값으로 둘 수 없다.
  private var btcKRWPrices: [Exchange: TimedPrice] = [:]
  private let btcKRWPriceQueue = DispatchQueue(
	label: "com.mobit.appDataManager.btcKRWPrice",
	attributes: .concurrent
  )

  private let btcKRWPriceSubject = PublishSubject<Exchange>()
  var btcKRWPriceUpdates: Observable<Exchange> { btcKRWPriceSubject.asObservable() }

  /// 소켓·REST 어디서 받았든 BTC/KRW 현재가를 갱신한다.
  func updateBTCKRWPrice(
    _ price: Double,
    for exchange: Exchange,
    updatedAt: Date = Date()
  ) {
	guard price.isFinite, price > 0 else { return }
    let changed = self.btcKRWPriceQueue.sync(flags: .barrier) {
      let previous = self.btcKRWPrices[exchange]
      let wasStale = previous.map {
        updatedAt.timeIntervalSince($0.updatedAt) > Self.btcKRWPriceRefreshAge
      } ?? true
      let changed = previous?.price != price || wasStale
      self.btcKRWPrices[exchange] = TimedPrice(price: price, updatedAt: updatedAt)
      return changed
    }
    if changed {
      DispatchQueue.main.async { self.btcKRWPriceSubject.onNext(exchange) }
    }
  }

  /// 15초 동안 새 시세가 없으면 캐시를 바로 버리지 않고 REST 검증 대상으로 표시한다.
  func needsBTCKRWPriceRefresh(
	for exchange: Exchange = ExchangeSelectionStore.currentExchange,
    at date: Date = Date()
  ) -> Bool {
    self.btcKRWPriceQueue.sync {
      guard let quote = self.btcKRWPrices[exchange] else { return true }
      let age = date.timeIntervalSince(quote.updatedAt)
      return age < 0 || age > Self.btcKRWPriceRefreshAge
    }
  }

  /// 검증 요청 중에는 최근 값을 유지하되 장시간 갱신되지 않은 값은 nil로 처리한다.
  func btcKRWPrice(
	for exchange: Exchange = ExchangeSelectionStore.currentExchange,
    at date: Date = Date(),
    maxAge: TimeInterval = AppDataManager.btcKRWPriceMaxAge
  ) -> Double? {
	self.btcKRWPriceQueue.sync {
      guard let quote = self.btcKRWPrices[exchange] else { return nil }
      let age = date.timeIntervalSince(quote.updatedAt)
      guard age >= 0, age <= maxAge else { return nil }
      return quote.price
    }
  }

  /// 평가 화면은 통신 실패 중에도 마지막 정상 가격을 유지한다.
  func lastBTCKRWPrice(
    for exchange: Exchange = ExchangeSelectionStore.currentExchange
  ) -> Double? {
    self.btcKRWPriceQueue.sync {
      self.btcKRWPrices[exchange]?.price
    }
  }

  /// 주문에는 15초 이내에 소켓 또는 REST로 확인한 가격만 사용한다.
  func freshBTCKRWPrice(
    for exchange: Exchange = ExchangeSelectionStore.currentExchange,
    at date: Date = Date()
  ) -> Double? {
    self.btcKRWPrice(
      for: exchange,
      at: date,
      maxAge: Self.btcKRWPriceRefreshAge
    )
  }

  func invalidateBTCKRWPrice(for exchange: Exchange) {
    let removed = self.btcKRWPriceQueue.sync(flags: .barrier) {
      self.btcKRWPrices.removeValue(forKey: exchange) != nil
    }
    if removed {
      DispatchQueue.main.async { self.btcKRWPriceSubject.onNext(exchange) }
    }
  }

  /// 현재(또는 지정) 거래소의 KRW·BTC CMC 정보를 함께 갱신한다.
  func refreshCMCData(for exchange: Exchange = ExchangeSelectionStore.currentExchange) {
	downloadFromFirebase(child_path: "cryptoInformations", exchange: exchange)
	downloadFromFirebase(child_path: "btc_cryptoInformations", exchange: exchange)
  }

  /// 파이어베이스에서 거래소별 CMC 코인 정보 가져오기
  /// 경로: CMCResponse/exchanges/{거래소}/{child_path}
  func downloadFromFirebase(
	child_path: String,
	exchange: Exchange = ExchangeSelectionStore.currentExchange
  ) {
	let path = firebaseDB
	  .child("CMCResponse")
	  .child("exchanges")
	  .child(exchange.rawValue)
	  .child(child_path)

	path.observeSingleEvent(of: .value) { snapshot in
	  guard let value = snapshot.value as? [String: [String: Any]] else {
		Log.error("❌ CMC 데이터 변환 실패 exchange=\(exchange.rawValue) path=\(child_path)")
		return
	  }
	  Log.info("✅ \(value.values.count)개 CMC 데이터 불러오기 성공 exchange=\(exchange.rawValue) path=\(child_path)")

	  if child_path == "cryptoInformations" {
		self.cachedKRWCMCList = value.compactMap { self.parseToCryptoData(dict: $0.value) }
	  } else {
		self.cachedBTCCMCList = value.compactMap { self.parseToCryptoData(dict: $0.value) }
	  }

	}
  }
  
  /// Data Model에 맞게 디코딩
  func parseToCryptoData(dict: [String: Any]) -> FirebaseCMCResponse? {
	do {
	  // Step 1. dict → jsonData
	  let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
	  
	  // Step 2. jsonData → DTO
	  let decoder = JSONDecoder()
	  decoder.dateDecodingStrategy = .iso8601
	  let dto = try decoder.decode(FirebaseCMCResponseDTO.self, from: jsonData)
	  
	  // Step 3. DTO → Domain
	  return dto.toDomain()
	  
	} catch {
	  Log.error("❌ 디코딩 실패: \(error)")
	  return nil
	}
  }
}
