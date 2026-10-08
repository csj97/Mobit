//
//  CryptoDetailRepository.swift
//  Mobit
//
//  Created by 조성재 on 8/19/24.
//

import Foundation
import Moya
import RxMoya
import RxSwift

protocol CryptoDetailRepositoryProtocol {
  // 종목의 시세·시가총액 정보를 조회한다.
  func fetchCryptoInformation(market: String) -> Observable<CryptoQuoteResponse>
}

class CryptoDetailRepository: CryptoDetailRepositoryProtocol {
  let provider: MoyaProvider<MultiTarget>
  private var disposeBag = DisposeBag()
  private let exchangeProvider: ExchangeMarketDataProviding

  init(
    exchangeProvider: ExchangeMarketDataProviding = ExchangeAdapterRegistry.default,
    provider: MoyaProvider<MultiTarget> = MoyaProvider<MultiTarget>()
  ) {
    self.exchangeProvider = exchangeProvider
    self.provider = provider
  }
  
  // 종목의 시세·시가총액 정보를 조회한다.
  func fetchCryptoInformation(market: String) -> Observable<CryptoQuoteResponse> {
	return Observable.create { observer in
	  let disposable = self.provider.rx.request(
        self.exchangeProvider.makeCryptoInformationTarget(
          market: market,
          currency: "KRW"
        )
      )
		.subscribe { event in
		  switch event {
		  case .success(let response):
			do {
			  try NetworkResponseValidator.validate(response: response)
			  guard let quote = try? self.exchangeProvider.decodeCryptoInformation(
                from: response.data,
                symbol: market
              ) else {
				observer.onError(ErrorType.decodingFailed)
				return
			  }
			  observer.onNext(quote)
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
  
  /// 종목·봉 간격·종료 시각·개수를 지정해 거래소의 분봉 데이터를 조회한다.
  func fetchCandleListMinutes(market: String, unit: Int32, to: String?, count: Int?) -> Observable<[MinuteResponseModel]> {
	return Observable.create { observer in
	  let disposable = self.provider.rx.request(
        self.exchangeProvider.makeCandleMinutesTarget(
          market: market,
          unit: unit,
          to: to,
          count: count
        )
      ).subscribe { event in
		switch event {
		case .success(let response):
		  do {
			try NetworkResponseValidator.validate(response: response)
			let candles = try self.exchangeProvider.decodeMinuteCandles(from: response.data)
			observer.onNext(candles)
			observer.onCompleted()
		  } catch let error as ErrorType {
			let body = NetworkResponseValidator.bodyPreview(from: response.data)
			Log.error("분봉 조회 실패 status=\(response.statusCode) market=\(market) unit=\(unit) to=\(to ?? "nil") url=\(response.request?.url?.absoluteString ?? "") body=\(body)")
			observer.onError(error)
		  } catch {
			let body = NetworkResponseValidator.bodyPreview(from: response.data)
			Log.error("분봉 디코딩 실패 market=\(market) unit=\(unit) to=\(to ?? "nil") url=\(response.request?.url?.absoluteString ?? "") error=\(error) body=\(body)")
			observer.onError(ErrorType.decodingFailed)
		  }
		case .failure(let error):
		  Log.error("분봉 요청 전송 실패 market=\(market) unit=\(unit) to=\(to ?? "nil") error=\(error.localizedDescription)")
		  observer.onError(NetworkResponseValidator.mapRequestError(error))
		}
	  }
	  return Disposables.create {
		disposable.disposed(by: self.disposeBag)
	  }
	}
  }
  
  // 지정한 종목의 일봉 데이터를 조회한다.
  func fetchCandleListDays(
  market: String,
  to: String?,
  count: Int?,
  convertingPriceUnit: String?
  ) -> Observable<[DayResponseModel]> {
	return Observable.create { observer in
	  let disposable = self.provider.rx.request(
        self.exchangeProvider.makeCandleDaysTarget(
          market: market,
          to: to,
          count: count,
          convertingPriceUnit: convertingPriceUnit
        )
      ).subscribe { event in
		switch event {
		case .success(let response):
		  do {
			try NetworkResponseValidator.validate(response: response)
			guard let candles = try? self.exchangeProvider.decodeDayCandles(
              from: response.data
            ) else {
			  observer.onError(ErrorType.decodingFailed)
			  return
			}
			observer.onNext(candles)
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
