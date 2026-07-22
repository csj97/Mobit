# Bithumb API Gap Notes

이 문서는 2026-07-10 기준 Bithumb 공식 문서와 현재 MOBIT 구현을 비교한 결과를 정리한다.

## 1. 문서로 확인된 항목

- 거래 대상 목록 조회
  - `GET /v1/market/all`
  - `market` 포맷은 `KRW-BTC`, `BTC-ETH`
  - `isDetails=true`일 때 `market_warning` 포함
- 현재가(Ticker) 조회
  - `GET /v1/ticker`
  - `markets` 쿼리로 복수 조회 가능
  - 응답 필드는 Upbit REST ticker DTO와 거의 동일한 구조
- 분(Minute) 캔들 조회
  - `GET /v1/candles/minutes/{unit}`
  - `market` 포맷은 `KRW-BTC`
  - 응답 필드는 기존 candle DTO와 호환 가능
- 호가(Orderbook) 조회
  - `GET /v1/orderbook`
  - `markets` 쿼리 사용
  - 응답 필드는 `market`, `timestamp`, `total_ask_size`, `total_bid_size`, `orderbook_units`
- WebSocket Public v1
  - 엔드포인트: `wss://ws-api.bithumb.com/websocket/v1`
  - 요청 포맷: `[{"ticket":"..."},{"type":"ticker|orderbook","codes":[...]}]`
  - `format` 미지정 시 기본값은 `DEFAULT`
  - `is_only_snapshot`, `is_only_realtime`는 선택 파라미터
  - ticker, orderbook 예제 응답은 flat JSON v1 스펙
- 경보제 조회
  - `GET /v1/market/virtual_asset_warning`
  - 거래 페어별 경보 유형/단계 제공
- 공지사항 조회
  - `GET /v1/notices`
  - `count` 기본 5, 최대 20
  - API 호출 제한: IP 기준 초당 1회

## 2. 현재 코드에 반영된 항목

- Bithumb market raw code를 `KRW-BTC` 형식으로 정정
- Bithumb 거래 대상 목록을 전용 DTO로 디코딩
- `market_warning`를 `MarketEvent.warning`에 반영
- Bithumb ticker REST를 기존 `CryptoTickerDTO`로 디코딩
- Bithumb minute/day candle REST를 기존 candle DTO로 디코딩
- Bithumb WebSocket endpoint를 `wss://ws-api.bithumb.com/websocket/v1`로 정정
- Bithumb WebSocket 구독 payload를 문서 예제 형식으로 정정
- ticker WebSocket flat v1 응답을 우선 디코딩
- orderbook WebSocket flat v1 응답을 우선 디코딩
- 상태 메시지(`status`, `status: UP`)와 에러 payload는 무시

## 3. 아직 미연결인 항목

### 3.1 경보제 상세 정보

현재 메인 목록에서는 `warning` boolean만 사용한다.

- 반영 완료:
  - `market/all?isDetails=true`의 `market_warning`
- 미반영:
  - `virtual_asset_warning`의 경보 유형/단계 상세

즉, 현재는 "유의 여부"까지만 반영되고, 경보 사유/레벨은 아직 앱 상태 모델에 연결되지 않았다.

### 3.2 공지사항 조회

공지사항 API는 아직 앱 기능 경로에 연결되어 있지 않다.

- 이유:
  - 현재 More/News/Community 흐름과 별도 설계가 필요
  - IP 기준 초당 1회 제한이 있어 화면 진입 시 무분별한 호출에 주의 필요

### 3.3 호가 REST

Trade 화면은 현재 WebSocket 호가를 사용한다.

- REST orderbook 스펙은 문서로 확인됨
- 하지만 현재 앱에서 REST fallback orderbook 호출은 구현하지 않음

필요 시 다음 순서로 붙인다.

1. `ExchangeMarketDataProviding`에 orderbook REST target/decode 추가
2. Trade 상세 최초 진입 시 REST snapshot 1회 조회
3. 이후 WebSocket 실시간으로 덮어쓰기

### 3.4 Orderbook WebSocket 실응답 최종 대조

현재 orderbook WebSocket은 아래 두 경로를 모두 허용한다.

- flat v1 공통 DTO decode
- legacy content envelope fallback decode

공식 문서의 현재 예제는 flat v1 기준이므로, 실응답 검증이 끝나면 legacy fallback 제거를 검토하는 것이 맞다.

### 3.5 문서상 애매한 timestamp 단위

orderbook WebSocket 문서는 timestamp를 마이크로초라고 설명하지만, 예시 값 자릿수는 밀리초에 가깝다.

- 현재 구현은 원본 정수값을 그대로 사용
- 실제 단위 보정 로직은 실응답 캡처 확보 후 결정하는 것이 안전하다

## 4. 다음 우선순위

1. 거래소 전환 UI/상태 도입 전, Bithumb live path에 남은 Upbit 전용 가정 제거
2. `virtual_asset_warning` 응답 캡처 확보 후 경보 상세 모델 설계
3. 필요 시 공지사항 API를 별도 feature로 연결
4. orderbook WebSocket 실응답 최종 대조 후 fallback 정리
