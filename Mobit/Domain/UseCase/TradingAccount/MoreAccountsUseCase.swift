import Foundation
import RxSwift

struct MoreAccountBalance: Equatable {
  // 충전 버튼이 화면의 현재 선택과 무관하게 가리킬 계좌다.
  let account: TradingAccountID
  // 저장 실패는 nil이며 미충전 계좌의 실제 잔고 0원과 구분한다.
  let availableBalance: Decimal?
}

final class MoreAccountsUseCase {
  // 더보기에서 지원하는 국내 거래소의 독립된 KRW 모의투자 계좌다.
  static let accounts: [TradingAccountID] = [Exchange.upbit, .bithumb].flatMap { exchange in
    [TradingProduct.spot, .perpetual].map {
      TradingAccountID(exchange: exchange, product: $0, currency: .krw)
    }
  }
  // 기존 현물 저장소를 읽기만 하며 계좌 선택이나 초기 지급을 바꾸지 않는다.
  private let spotBalance: (Exchange) throws -> Decimal
  // 선물 검증·시세 조회 없이 저장 완료된 계좌 잔고만 읽는다.
  private let futuresSnapshot: () throws -> FuturesAccountSnapshot
  // 저장소 읽기가 화면 스크롤을 막지 않게 직렬 큐에서 처리한다.
  private let scheduler: ImmediateSchedulerType

  init(
    spotBalance: @escaping (Exchange) throws -> Decimal = { try Decimal(UserDataManager.getAvailableBalance(for: $0)) },
    futuresSnapshot: @escaping () throws -> FuturesAccountSnapshot = { try LocalFuturesAccountRepository.applicationStore().snapshot() },
    scheduler: ImmediateSchedulerType = SerialDispatchQueueScheduler(qos: .userInitiated)
  ) {
    self.spotBalance = spotBalance
    self.futuresSnapshot = futuresSnapshot
    self.scheduler = scheduler
  }

  func fetchBalances() -> Single<[MoreAccountBalance]> {
    Single.deferred { [self] in
      // 한쪽 저장소가 실패해도 다른 상품의 정상 잔고는 유지한다.
      let futures: FuturesAccountSnapshot?
      do { futures = try futuresSnapshot() }
      catch {
        futures = nil
        Log.info("더보기 선물 잔고 읽기 실패: \(type(of: error))")
      }
      // 모든 버튼과 금액은 동일한 고정 계좌 순서를 사용한다.
      let balances = Self.accounts.map { account -> MoreAccountBalance in
        do {
          // 미생성 선물 계좌는 저장하지 않고 미충전 잔고로 표시한다.
          let balance: Decimal?
          if account.product == .spot {
            balance = try spotBalance(account.exchange)
          } else {
            balance = futures.map { snapshot in
              snapshot.accounts.first { $0.id == account }?.availableBalance ?? Decimal(TradingRules.Funding.unfundedAccountBalance)
            }
          }
          if let balance, balance.isNaN || balance < 0 { throw AdRewardError.invalidStoredData }
          return MoreAccountBalance(account: account, availableBalance: balance)
        } catch {
          Log.info("더보기 \(account.exchange.rawValue) \(account.product.rawValue) 잔고 읽기 실패: \(type(of: error))")
          return MoreAccountBalance(account: account, availableBalance: nil)
        }
      }
      return .just(balances)
    }.subscribe(on: scheduler)
  }
}
