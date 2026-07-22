# Exchange Extension Architecture Spec

이 문서는 MOBIT의 단일 거래소(Upbit) 구조를 다중 거래소 확장 구조로 전환하기 위한 아키텍처 기준 문서다.

목표는 단순히 Bithumb을 붙이는 것이 아니라, 추후 Binance, OKX 등 다양한 거래소를 안정적으로 추가할 수 있는 기반을 만드는 것이다.

## 1. 목표

1. 기존 Upbit 기능을 유지한 채 거래소 독립 구조로 전환한다.
2. 거래소별 REST/WebSocket 차이를 Data 계층 안으로 격리한다.
3. Domain, Presentation, 계산 로직은 가능한 한 거래소 비의존적으로 유지한다.
4. 저장 데이터는 거래소 포함 식별자로 재정의해 충돌을 방지한다.
5. 거래소 전환 시 stale data, 중복 socket, 자산 충돌이 발생하지 않게 한다.
6. 현재 구현 기준으로 거래소 전환은 관련 탭 루트를 재생성해 메인/투자 경로의
   Reactor, Repository, Socket을 새 거래소 기준으로 다시 생성한다.

## 2. 비목표

1. 1차 범위에서 실제 거래소 Private 주문 API를 연동하지 않는다.
2. 1차 범위에서 여러 거래소를 동시에 합산한 통합 자산 화면을 만들지 않는다.
3. 1차 범위에서 화면 구조를 대규모 리디자인하지 않는다.
4. 1차 범위에서 기존 Upbit 계산 정책을 임의로 바꾸지 않는다.

## 3. 현재 구조의 문제

### 3.1 식별자 충돌

- 현재는 `BTC/KRW` 같은 `marketName` 문자열을 즐겨찾기, 보유자산, 거래내역, 손익의 핵심 키로 사용한다.
- 동일 페어가 여러 거래소에 존재하면 데이터가 서로 덮이거나 섞인다.

### 3.2 거래소 종속 데이터 파이프라인

- Main 목록, 초기 ticker, 실시간 ticker, orderbook, candle 모두 Upbit 전용 DTO와 포맷을 전제한다.
- `KRW-BTC <-> BTC/KRW` 변환도 Upbit 규칙에 직접 묶여 있다.

### 3.3 상태 전환 리스크

- 거래소 전환이 도입되면 이전 거래소 socket 데이터가 현재 화면에 남을 수 있다.
- 탭 전환, background/foreground, detail 진입/이탈 시 연결 수명 관리가 더 엄격해져야 한다.

## 4. 아키텍처 원칙

1. `Exchange`는 도메인 개념이다. 단순 문자열 상수가 아니다.
2. 거래소 원본 마켓 코드와 앱 표시 문자열을 분리한다.
3. 저장 식별자와 UI 표시는 절대 같은 값을 공유하지 않는다.
4. 공급자별 DTO는 공급자별 파일에 유지하고, 공통 Domain 모델로 변환 후 상위 계층에 전달한다.
5. WebSocket 구독 규칙은 공급자 구현체 안에 숨기고, Reactor는 “무슨 마켓을 구독할지”만 결정한다.
6. 기존 Upbit 구현은 제거하지 않고 어댑터화해 기준 구현으로 삼는다.

## 5. 제안 구조

```text
Mobit/
  Domain/
    Exchange/
      Exchange.swift
      ExchangePairID.swift
      ExchangeMarketPair.swift
      ExchangeTickerSnapshot.swift
      ExchangeOrderBook.swift
      ExchangeCandle.swift
  Data/
    Exchange/
      Common/
        ExchangeMarketRepository.swift
        ExchangeTickerRepository.swift
        ExchangeCandleRepository.swift
        ExchangeSocketService.swift
        ExchangePairFormatter.swift
      Upbit/
        UpbitMarketRepository.swift
        UpbitTickerRepository.swift
        UpbitCandleRepository.swift
        UpbitTickerSocketService.swift
        UpbitOrderBookSocketService.swift
        DTO/
      Bithumb/
        BithumbMarketRepository.swift
        BithumbTickerRepository.swift
        BithumbCandleRepository.swift
        BithumbTickerSocketService.swift
        BithumbOrderBookSocketService.swift
        DTO/
  Common/
    UserData/
      ExchangeSelectionStore.swift
```

## 6. 공통 도메인 모델

### 6.1 Exchange

- 케이스:
  - `upbit`
  - `bithumb`
  - 추후 `binance`
  - 추후 `okx`

### 6.2 ExchangePairID

- 앱 내부 식별자
- 형식:
  - `upbit:KRW-BTC`
  - `bithumb:KRW-BTC`
- 규칙:
  - 저장/비교/정렬/즐겨찾기/보유자산/거래내역은 이 값을 기준으로 한다.

### 6.3 ExchangeMarketPair

- 필드 초안:
  - `id: ExchangePairID`
  - `exchange: Exchange`
  - `rawMarketCode: String`
  - `baseAsset: String`
  - `quoteAsset: String`
  - `displayMarket: String`
  - `koreanName: String?`
  - `englishName: String?`
  - `marketWarning: MarketWarning?`

### 6.4 ExchangeTickerSnapshot

- 초기 REST ticker용 공통 모델
- Main 화면과 Investment 동적 평가 계산의 기준값

### 6.5 ExchangeRealtimeTicker

- WebSocket ticker용 공통 모델
- 공급자별 불완전 필드는 optional로 두고, 상위 계층에서 fallback 정책을 명시한다.

### 6.6 ExchangeOrderBook

- 호가 렌더링 공통 모델
- 정렬은 공급자별 원본이 아니라 공통 모델 변환 후 일관 규칙으로 처리한다.

### 6.7 ExchangeCandle

- 분/일 캔들을 하나의 공통 모델로 수용
- 공급자별 raw field 차이는 DTO 매퍼에서 흡수한다.

## 7. 공급자 인터페이스

### 7.1 Market Repository

- 책임:
  - 거래소 상장 마켓 목록 조회
  - 원본 코드를 공통 `ExchangeMarketPair`로 변환

### 7.2 Ticker Repository

- 책임:
  - 초기 REST ticker 조회
  - 배치 호출 정책, rate limit 대응

### 7.3 Candle Repository

- 책임:
  - minute/day candle 조회
  - 거래소별 시간 파라미터 차이 캡슐화

### 7.4 Socket Service

- 책임:
  - connect / disconnect / reconnect
  - subscribe / resubscribe
  - 공급자별 구독 payload 작성
  - raw data를 공통 realtime/orderbook 모델로 변환

## 8. Presentation 경계

### 8.1 Main Scene

- MainReactor는 더 이상 Upbit 포맷 변환을 직접 알면 안 된다.
- MainReactor 책임:
  - 현재 선택 거래소 상태 조회
  - 현재 탭에 맞는 pair 집합 결정
  - 정렬/검색/즐겨찾기/보유 탭 필터

### 8.2 Trade Scene

- TradeReactor는 선택된 pair ID를 기준으로 ticker/orderbook/candle 공급을 받는다.
- `TradeViewController`, `TradeOrderView`, `TradeAskView`, `TradeBidView`는 거래소 raw market code를 직접 참조하지 않는다.

### 8.3 Investment Scene

- 보유 자산은 `ExchangePairID` 기준으로 관리한다.
- 같은 `BTC/KRW`라도 Upbit 보유와 Bithumb 보유는 별도 자산으로 취급한다.

## 9. 거래소 선택 상태

### 9.1 상태 정의

- 전역 현재 거래소:
  - 앱 세션 기준 단일 선택
- 저장 위치:
  - `UserDefaults` 기반 영속 저장

### 9.2 전환 규칙

1. 이전 거래소 socket 구독 해제
2. 현재 화면의 공급 데이터 초기화
3. 새 거래소 목록/초기 ticker 로드
4. 새 거래소 socket 구독
5. 렌더링

중간 단계에서 이전 거래소 데이터가 보이면 안 된다.

## 10. 성능 원칙

1. 메인 목록은 여전히 초기 REST + 실시간 ticker 병합 구조를 유지한다.
2. ticker/orderbook WebSocket은 화면 생명주기와 탭 상태를 따라 최소 구독만 유지한다.
3. 거래소 전환 시 전체 앱 재구성보다 현재 필요한 Scene만 재구성하는 방향을 우선한다.
4. 대량 상장 목록 조회 시 배치 ticker 정책은 공급자별로 분리한다.

## 11. 금지 사항

1. 저장 모델 마이그레이션 전에 `marketName` 문자열만 바꿔서 대응하지 않는다.
2. DTO를 직접 ViewController로 전달하지 않는다.
3. 거래소별 `if exchange == ...` 분기를 ViewController에 넣지 않는다.
4. 전환 중 socket을 끊지 않은 채 새 거래소 구독을 추가하지 않는다.
5. 기존 Upbit 회귀 검증 없이 Bithumb 구현을 병합하지 않는다.

## 12. 단계별 적용 순서

1. 공통 식별자/도메인 모델 추가
2. 레거시 저장 데이터 마이그레이션 구현
3. Upbit 공급자 어댑터화
4. Main 파이프라인 전환
5. Trade 파이프라인 전환
6. Bithumb 공급자 추가
7. 거래소 전환 상태 도입
8. 회귀/정합성/성능 검증

## 13. 완료 기준

다음 조건을 만족하면 아키텍처 전환이 완료된 것으로 본다.

1. Upbit 기존 기능이 새 공통 인터페이스 경유로 동일 동작한다.
2. 저장 데이터가 `ExchangePairID` 기준으로 무손실 이관된다.
3. Main/Trade/Investment 화면이 거래소 raw format을 직접 알지 않는다.
4. Bithumb 추가 시 기존 Upbit 코드 수정 범위가 최소화된다.
5. Binance, OKX를 추가할 때 Domain/Presentation 변경 없이 Data 공급자 추가만으로 확장 가능한 상태가 된다.
