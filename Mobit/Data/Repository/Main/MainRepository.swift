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
    let maxConcurrentRequests: Int
    let maxRetryCount: Int

    static let upbit = TickerBatchPolicy(
      batchSize: 100,
      maxConcurrentRequests: 3,
      maxRetryCount: 2
    )

    static let bithumb = TickerBatchPolicy(
      batchSize: 150,
      maxConcurrentRequests: 3,
      maxRetryCount: 3
    )
  }

  private struct IndexedTickerBatch {
    let index: Int
    let tickers: [CryptoTicker]
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

      if response.statusCode == 429 {
        let body = String(data: response.data, encoding: .utf8) ?? "N/A"
        guard retryAttempt < policy.maxRetryCount else {
          Log.error("❌ 티커 요청 제한으로 재시도 종료 [\(batchNumber)/\(totalBatches)] retryCount=\(policy.maxRetryCount) batchCount=\(markets.count) sample=\(markets.prefix(5)) body=\(body)")
          return .error(ErrorType.tooManyRequests)
        }

        let nextAttempt = retryAttempt + 1
        let delayMilliseconds = self.retryDelayMilliseconds(for: retryAttempt)
        Log.error("⏳ 티커 요청 제한으로 재시도 예정 [\(batchNumber)/\(totalBatches)] attempt=\(nextAttempt)/\(policy.maxRetryCount) delay=\(delayMilliseconds)ms batchCount=\(markets.count) sample=\(markets.prefix(5)) body=\(body)")

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
      }

      do {
        try NetworkResponseValidator.validate(response: response)

        let cryptoTickerList = try self.exchangeProvider.decodeCryptoTickerList(
          from: response.data
        )
        Log.info("✅ 티커 배치 요청 성공 [\(batchNumber)/\(totalBatches)] status=\(response.statusCode) itemCount=\(cryptoTickerList.count)")
        return .just(cryptoTickerList)
      } catch let error as ErrorType {
        let body = NetworkResponseValidator.bodyPreview(from: response.data)
        Log.error("❌ 티커 배치 응답 오류 [\(batchNumber)/\(totalBatches)] status=\(response.statusCode) batchCount=\(markets.count) sample=\(markets.prefix(5)) body=\(body)")
        return .error(error)
      } catch {
        Log.error("❌ 디코딩 실패: \(error)")
        return .error(ErrorType.decodingFailed)
      }
    }
    .catch { error in
      Log.error(error.localizedDescription)
      return .error(NetworkResponseValidator.mapRequestError(error))
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
            do {
              try NetworkResponseValidator.validate(response: response)
              guard let cryptoList = try? self.exchangeProvider.decodeCryptoList(
                from: response.data
              ) else {
                observer.onError(ErrorType.decodingFailed)
                return
              }
              observer.onNext(cryptoList)
              observer.onCompleted()
            } catch let error as ErrorType {
              observer.onError(error)
            } catch {
              observer.onError(ErrorType.decodingFailed)
            }
          case .failure(let error):
			Log.error(error.localizedDescription)
            observer.onError(NetworkResponseValidator.mapRequestError(error))
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
    Log.info("📊 티커 배치 요청 계획 exchange=\(self.exchangeProvider.exchange.rawValue) totalMarkets=\(normalizedMarkets.count) batchSize=\(policy.batchSize) totalBatches=\(batchedMarkets.count) maxConcurrentRequests=\(policy.maxConcurrentRequests) maxRetryCount=\(policy.maxRetryCount)")
    
	// 제한 병렬로 호출해 대량 마켓에서도 로딩 지연을 줄인다.
    let indexedBatches = Array(batchedMarkets.enumerated())
    let batchRequests: Observable<IndexedTickerBatch> = Observable.from(indexedBatches)
      .map { [weak self] batchItem -> Observable<IndexedTickerBatch> in
        guard let self = self else { return Observable<IndexedTickerBatch>.empty() }
        let (batchIndex, batchMarkets) = batchItem
        let batchNumber = batchIndex + 1
        let totalBatches = batchedMarkets.count
        let batchPreview = batchMarkets.prefix(5).joined(separator: ",")
        
        Log.info("📡 티커 배치 요청 시작 [\(batchNumber)/\(totalBatches)] batchCount=\(batchMarkets.count) maxConcurrentRequests=\(policy.maxConcurrentRequests) preview=\(batchPreview)")

        return self.requestTickerBatch(
          markets: batchMarkets,
          batchNumber: batchNumber,
          totalBatches: totalBatches,
          retryAttempt: 0,
          policy: policy
        )
        .map { IndexedTickerBatch(index: batchIndex, tickers: $0) }
      }
      .merge(maxConcurrent: policy.maxConcurrentRequests)

    return batchRequests
      .reduce([IndexedTickerBatch]()) { result, partial in
        result + [partial]
      }
      .map { batches in
		// 병렬 응답 완료 순서가 달라도 기존 배치 순서를 유지한다.
        batches
          .sorted { $0.index < $1.index }
          .flatMap { $0.tickers }
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
            do {
              try NetworkResponseValidator.validate(response: response)
              guard let dto = try? JSONDecoder().decode(decodeTarget, from: response.data) else {
                observer.onError(ErrorType.decodingFailed)
                return
              }
              observer.onNext(dto.toDomain())
              observer.onCompleted()
            } catch let error as ErrorType {
              observer.onError(error)
            } catch {
              observer.onError(ErrorType.decodingFailed)
            }
          case .failure(let error):
            Log.error(error.localizedDescription)
            observer.onError(NetworkResponseValidator.mapRequestError(error))
          }
        }
      return Disposables.create {
        disposable.disposed(by: self.disposeBag)
      }
    }
  }
}
