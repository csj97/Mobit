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
  let provider = MoyaProvider<MainNetworkService>()
  private var disposeBag = DisposeBag()
  private let tickerBatchSize = 100
  
  func loadCryptoList() -> Observable<CryptoList> {
    let decodeTarget = CryptoListDTO.self
    
    return Observable.create { observer in
      let disposable = self.provider.rx.request(.getCryptoList)
        .subscribe { event in
          switch event {
          case .success(let response):
            switch response.statusCode {
            case 200..<300:
              guard let cryptoListDTO = try? JSONDecoder().decode(decodeTarget, from: response.data) else {
                observer.onError(ErrorType.dataMappingError)
                return
              }
              observer.onNext(cryptoListDTO.toDomain())
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
    let decodeTarget = CryptoTickerListDTO.self
	
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
    
	// batchSize 단위 분할
	// 예: 713개면 [100,100,100,100,100,100,100,13] 8개 배치.
    let batchedMarkets = stride(from: 0, to: normalizedMarkets.count, by: tickerBatchSize).map {
      Array(normalizedMarkets[$0..<min($0 + tickerBatchSize, normalizedMarkets.count)])
    }
    Log.info("📊 ticker batch plan totalMarkets=\(normalizedMarkets.count) batchSize=\(tickerBatchSize) totalBatches=\(batchedMarkets.count)")
    
	// concatMap으로 순차 실행(병렬 아님)합니다.
	// 배치 순차 호출
    return Observable.from(Array(batchedMarkets.enumerated()))
      .concatMap { [weak self] batchItem -> Observable<[CryptoTicker]> in
        guard let self = self else { return .empty() }
        let (batchIndex, batchMarkets) = batchItem
        let batchNumber = batchIndex + 1
        let totalBatches = batchedMarkets.count
        let batchPreview = batchMarkets.prefix(5).joined(separator: ",")
        
        Log.info("📡 ticker batch request [\(batchNumber)/\(totalBatches)] count=\(batchMarkets.count) preview=\(batchPreview)")
        
        return self.provider.rx.request(.getCryptoTicker(markets: batchMarkets))
          .asObservable()
          .flatMap { response -> Observable<[CryptoTicker]> in
            switch response.statusCode {
            case 200..<300:
              do {
                let cryptoTickerList = try JSONDecoder().decode(decodeTarget, from: response.data)
                Log.info("✅ ticker batch success [\(batchNumber)/\(totalBatches)] status=\(response.statusCode) items=\(cryptoTickerList.count)")
                return .just(cryptoTickerList.toDomain())
              } catch {
                Log.error("❌ 디코딩 실패: \(error)")
                return .error(ErrorType.dataMappingError)
              }
              
            case 400..<500:
              let body = String(data: response.data, encoding: .utf8) ?? "N/A"
              Log.error("❌ ticker 4xx [\(batchNumber)/\(totalBatches)] status: \(response.statusCode), batchCount: \(batchMarkets.count), sample: \(batchMarkets.prefix(5)), body: \(body)")
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
      .reduce([CryptoTicker]()) { result, partial in
		// 각 배치 결과를 하나로 합쳐 Observable<CryptoTickerList> 반환
        result + partial
      }
  }

  // 시장 공포·탐욕 지수 (CMC). 하루 단위 갱신이라 화면 진입 시 1회만 조회한다.
  func loadFearGreedIndex() -> Observable<FearGreedIndex> {
    let decodeTarget = FearGreedIndexResponseDTO.self

    return Observable.create { observer in
      let disposable = self.provider.rx.request(.getFearAndGreedIndex)
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
