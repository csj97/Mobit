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
  static let btcKRWPriceMaxAge: TimeInterval = 15

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
        updatedAt.timeIntervalSince($0.updatedAt) > Self.btcKRWPriceMaxAge
      } ?? true
      let changed = previous?.price != price || wasStale
      self.btcKRWPrices[exchange] = TimedPrice(price: price, updatedAt: updatedAt)
      return changed
    }
    if changed {
      DispatchQueue.main.async { self.btcKRWPriceSubject.onNext(exchange) }
    }
  }

  /// 아직 시세를 받지 못했으면 nil이다. 0으로 환산하면 자산이 사라진 것처럼 보이므로 호출 측에서 구분해야 한다.
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
