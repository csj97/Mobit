//
//  MainRepository.swift
//  Mobit
//
//  Created by openobject on 2024/07/18.
//

import Foundation
import Moya
import RxMoya
import RxSwift

protocol MainRepositoryProtocol {
  func loadCryptoList() -> Observable<CryptoList>
  func loadCryptoTicker(markets: [String]) -> Observable<CryptoTickerList>
  func loadFearGreedIndex() -> Observable<FearGreedIndex>
}

class MainRepository: MainRepositoryProtocol {
  private struct TickerBatchPolicy {
    let batchSize: Int
    let interBatchDelayMilliseconds: Int
    let maxRetryCount: Int

    static let upbit = TickerBatchPolicy(
      batchSize: 100,
      interBatchDelayMilliseconds: 180,
      maxRetryCount: 2
    )

    static let bithumb = TickerBatchPolicy(
      batchSize: 150,
      interBatchDelayMilliseconds: 180,
      maxRetryCount: 3
    )
  }

  let provider: MoyaProvider<MultiTarget>
  private var disposeBag = DisposeBag()
  private let exchangeProvider: ExchangeMarketDataProviding
  private let tickerRequestScheduler = SerialDispatchQueueScheduler(qos: .utility)

  init(
    exchangeProvider: ExchangeMarketDataProviding = ExchangeAdapterRegistry.default,
    provider: MoyaProvider<MultiTarget> = MoyaProvider<MultiTarget>()
  ) {
    self.exchangeProvider = exchangeProvider
    self.provider = provider
  }

  private func tickerBatchPolicy(for exchange: Exchange) -> TickerBatchPolicy {
    switch exchange {
    case .upbit, .binance, .okx:
      return .upbit
    case .bithumb:
      return .bithumb
    }
  }

  private func retryDelayMilliseconds(for attempt: Int) -> Int {
    switch attempt {
    case 0: return 700
    case 1: return 1400
    default: return 2200
    }
  }

  private func requestTickerBatch(
    markets: [String],
    batchNumber: Int,
    totalBatches: Int,
    retryAttempt: Int,
    policy: TickerBatchPolicy
  ) -> Observable<[CryptoTicker]> {
	// repository는 target이 upbit인지 bithumb인지 몰라도 된다.
    self.provider.rx.request(
      self.exchangeProvider.makeCryptoTickerTarget(markets: markets)
    )
    .asObservable()
    .flatMap { [weak self] response -> Observable<[CryptoTicker]> in
      guard let self = self else { return .empty() }

      switch response.statusCode {
      case 200..<300:
        do {
          let cryptoTickerList = try self.exchangeProvider.decodeCryptoTickerList(
            from: response.data
          )
          Log.info("✅ ticker batch success [\(batchNumber)/\(totalBatches)] status=\(response.statusCode) items=\(cryptoTickerList.count)")
          return .just(cryptoTickerList)
        } catch {
          Log.error("❌ 디코딩 실패: \(error)")
          return .error(ErrorType.dataMappingError)
        }

      case 429:
        let body = String(data: response.data, encoding: .utf8) ?? "N/A"
        guard retryAttempt < policy.maxRetryCount else {
          Log.error("❌ ticker 429 exhausted [\(batchNumber)/\(totalBatches)] retryCount=\(policy.maxRetryCount) batchCount=\(markets.count) sample=\(markets.prefix(5)) body: \(body)")
          return .error(ErrorType.rateLimited)
        }

        let nextAttempt = retryAttempt + 1
        let delayMilliseconds = self.retryDelayMilliseconds(for: retryAttempt)
        Log.error("⏳ ticker 429 retry [\(batchNumber)/\(totalBatches)] attempt=\(nextAttempt)/\(policy.maxRetryCount) delay=\(delayMilliseconds)ms batchCount=\(markets.count) sample=\(markets.prefix(5)) body: \(body)")

        return Observable<Int>
          .timer(.milliseconds(delayMilliseconds), scheduler: self.tickerRequestScheduler)
          .flatMap { _ in
            self.requestTickerBatch(
              markets: markets,
              batchNumber: batchNumber,
              totalBatches: totalBatches,
              retryAttempt: nextAttempt,
              policy: policy
            )
          }

      case 400..<500:
        let body = String(data: response.data, encoding: .utf8) ?? "N/A"
        Log.error("❌ ticker 4xx [\(batchNumber)/\(totalBatches)] status: \(response.statusCode), batchCount: \(markets.count), sample: \(markets.prefix(5)), body: \(body)")
        return .error(ErrorType.badRequest)

      default:
        let body = String(data: response.data, encoding: .utf8) ?? "N/A"
        Log.error("❌ ticker error [\(batchNumber)/\(totalBatches)] status: \(response.statusCode), body: \(body)")
        return .error(ErrorType.unknownError)
      }
    }
    .catch { error in
      Log.error(error.localizedDescription)
      return .error(error)
    }
  }
  
  func loadCryptoList() -> Observable<CryptoList> {
    return Observable.create { observer in
      let disposable = self.provider.rx.request(
        self.exchangeProvider.makeCryptoListTarget()
      )
        .subscribe { event in
          switch event {
          case .success(let response):
            switch response.statusCode {
            case 200..<300:
              guard let cryptoList = try? self.exchangeProvider.decodeCryptoList(
                from: response.data
              ) else {
                observer.onError(ErrorType.dataMappingError)
                return
              }
              observer.onNext(cryptoList)
              observer.onCompleted()
            case 400..<500:
              observer.onError(ErrorType.badRequest)
            default:
              observer.onError(ErrorType.unknownError)
            }
          case .failure(let error):
			Log.error(error.localizedDescription)
            observer.onError(error)
          }
        }
      return Disposables.create {
        disposable.disposed(by: self.disposeBag)
      }
    }
  }
  
    // ticker 리스트 조회
  func loadCryptoTicker(markets: [String]) -> Observable<CryptoTickerList> {
	// 공백, 빈문자열, 중복 제거, 정렬 > 항상 같은 순서로 정리
    let normalizedMarkets = Array(
      Set(
        markets
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
      )
    ).sorted()
    
	// normalizedMarkets emptye > Observable.just([]) 반환
	// 불필요한 네트워크 호출 방지.
    guard !normalizedMarkets.isEmpty else { return .just([]) }

    let policy = self.tickerBatchPolicy(for: self.exchangeProvider.exchange)

	// batchSize 단위 분할
	// 예: 713개면 [100,100,100,100,100,100,100,13] 8개 배치.
    let batchedMarkets = stride(from: 0, to: normalizedMarkets.count, by: policy.batchSize).map {
      Array(normalizedMarkets[$0..<min($0 + policy.batchSize, normalizedMarkets.count)])
    }
    Log.info("📊 ticker batch plan exchange=\(self.exchangeProvider.exchange.rawValue) totalMarkets=\(normalizedMarkets.count) batchSize=\(policy.batchSize) totalBatches=\(batchedMarkets.count) interBatchDelay=\(policy.interBatchDelayMilliseconds)ms maxRetryCount=\(policy.maxRetryCount)")
    
	// concatMap으로 순차 실행(병렬 아님)합니다.
	// 배치 순차 호출
    return Observable.from(Array(batchedMarkets.enumerated()))
      .concatMap { [weak self] batchItem -> Observable<[CryptoTicker]> in
        guard let self = self else { return .empty() }
        let (batchIndex, batchMarkets) = batchItem
        let batchNumber = batchIndex + 1
        let totalBatches = batchedMarkets.count
        let batchPreview = batchMarkets.prefix(5).joined(separator: ",")
        let batchDelay = batchIndex == 0 ? 0 : policy.interBatchDelayMilliseconds
        
        Log.info("📡 ticker batch request [\(batchNumber)/\(totalBatches)] count=\(batchMarkets.count) delay=\(batchDelay)ms preview=\(batchPreview)")

        return Observable<Int>
          .timer(.milliseconds(batchDelay), scheduler: self.tickerRequestScheduler)
          .flatMap { _ in
            self.requestTickerBatch(
              markets: batchMarkets,
              batchNumber: batchNumber,
              totalBatches: totalBatches,
              retryAttempt: 0,
              policy: policy
            )
          }
      }
      .reduce([CryptoTicker]()) { result, partial in
		// 각 배치 결과를 하나로 합쳐 Observable<CryptoTickerList> 반환
        result + partial
      }
  }

  // 시장 공포·탐욕 지수 (CMC). 하루 단위 갱신이라 화면 진입 시 1회만 조회한다.
  func loadFearGreedIndex() -> Observable<FearGreedIndex> {
    let decodeTarget = FearGreedIndexResponseDTO.self

    return Observable.create { observer in
      let disposable = self.provider.rx.request(
        self.exchangeProvider.makeFearAndGreedIndexTarget()
      )
        .subscribe { event in
          switch event {
          case .success(let response):
            switch response.statusCode {
            case 200..<300:
              guard let dto = try? JSONDecoder().decode(decodeTarget, from: response.data) else {
                observer.onError(ErrorType.dataMappingError)
                return
              }
              observer.onNext(dto.toDomain())
              observer.onCompleted()
            case 400..<500:
              observer.onError(ErrorType.badRequest)
            default:
              observer.onError(ErrorType.unknownError)
            }
          case .failure(let error):
            Log.error(error.localizedDescription)
            observer.onError(error)
          }
        }
      return Disposables.create {
        disposable.disposed(by: self.disposeBag)
      }
    }
  }
}
