# Native Chart Strategy

이 문서는 MOBIT의 Native Chart를 중장기 핵심 기능으로 설계하기 위한 기준 문서다.

현재 TradingView 기반 차트는 빠르게 화면을 구성하기에는 유용하지만, 거래소별 미지원 심볼이 존재하고 데이터 출처를 앱이 직접 통제하기 어렵다. 특히 Bithumb BTC 마켓처럼 `BITHUMB:TRXBTC` 형식의 심볼이 TradingView에서 조회되지 않는 경우가 발생한다.

Native Chart는 이 문제의 단기 fallback이 아니라, MOBIT 전체 거래소 시세 경험을 직접 제어하기 위한 핵심 기능으로 다룬다.

## 1. 목표

1. Upbit, Bithumb, 추후 Binance/OKX 등 거래소별 candle API 응답을 공통 차트 모델로 변환한다.
2. 차트 화면은 거래소별 DTO나 raw market code를 직접 알지 않게 한다.
3. 중앙 차트 데이터 제어 계층에서 거래소 선택, interval, pagination, realtime update를 관리한다.
4. TradingView 지원 여부와 무관하게 현재 선택 거래소의 공식 데이터를 기준으로 차트를 표시한다.
5. 단순 캔들 렌더링이 아니라 실제 거래소 앱 수준의 사용성, 성능, 안정성을 목표로 한다.

## 2. 비목표

1. 현재 Bithumb BTC 마켓 미지원 문제를 급하게 우회하기 위한 임시 차트를 만들지 않는다.
2. 다른 거래소 차트를 무조건 fallback으로 보여주지 않는다.
3. TradingView 심볼이 없다는 이유만으로 `BINANCE`, `UPBIT`, `BITFINEX` 등 임의 거래소 차트를 대신 노출하지 않는다.
4. 기존 TradingView 차트를 즉시 제거하지 않는다.
5. 별도 계획 없이 상세 화면 내부에 차트 렌더링 로직을 직접 넣지 않는다.

## 3. 핵심 원칙

1. 차트 데이터의 출처는 항상 현재 선택된 거래소다.
2. 거래소별 candle 응답 차이는 Data 계층 Adapter에서 흡수한다.
3. 차트 렌더러는 공통 Domain 모델만 입력받는다.
4. Presentation 계층은 차트 데이터 로딩 방식보다 화면 상태와 사용자 입력 처리에 집중한다.
5. TradingView는 장기적으로 필수 의존성이 아니라 보조 Provider 또는 전환기 Provider로 취급한다.
6. Native Chart 작업은 별도 chart branch에서 계획적으로 진행한다.

## 4. 제안 구조

```text
Exchange Candle API
  -> Exchange Adapter
  -> Common Chart Candle Domain Model
  -> Chart Data Controller
  -> Native Chart Renderer
```

예상 파일 배치는 다음 방향을 우선 검토한다.

```text
Mobit/
  Domain/
    Model/
      ChartCandle.swift
      ChartInterval.swift
      ChartViewport.swift
  Data/
    Exchange/
      ExchangeMarketDataProvider.swift
      Upbit/
        DataMapping/
        Network/
      Bithumb/
        DataMapping/
        Network/
  Presentation/
    ChartScene/
      Views/
        NativeCandleChartView.swift
        ChartAxisView.swift
        ChartVolumeView.swift
      Reactors/
        ChartReactor.swift
```

실제 구현 시 현재 프로젝트 구조와 충돌하지 않도록 최종 배치는 다시 검토한다.

## 5. 공통 차트 모델

거래소별 candle DTO는 아래 성격의 공통 모델로 변환한다.

```swift
struct ChartCandle {
  let exchange: Exchange
  let market: String
  let interval: ChartInterval
  let timestamp: Int64
  let openPrice: Decimal
  let highPrice: Decimal
  let lowPrice: Decimal
  let closePrice: Decimal
  let volume: Decimal?
  let tradePrice: Decimal?
}
```

원칙:

- 가격 계산과 축 계산은 가능하면 `Decimal` 기준으로 처리한다.
- 기존 사용자 저장 데이터와 직접 연결되는 모델 변경은 별도 마이그레이션 검토 후 진행한다.
- 서버 응답 DTO의 `Double`, `String`, timestamp 단위 차이는 Adapter에서 정리한다.

## 6. 중앙 제어 계층 책임

Chart Data Controller 또는 Chart Provider는 다음 책임을 가진다.

1. 현재 거래소와 market 기준 candle 조회
2. interval 변경 처리
3. 초기 로딩과 추가 pagination
4. REST candle과 realtime ticker/socket 데이터 병합
5. 마지막 candle 갱신
6. 데이터 누락, 미지원 interval, 네트워크 오류 상태 관리

View나 ViewController가 거래소별 분기를 직접 갖지 않도록 한다.

## 7. 차트 렌더러 요구사항

Native Chart는 다음 기능을 단계적으로 제공하는 것을 목표로 한다.

### 7.1 1차 범위

- 캔들 body/wick 렌더링
- 상승/하락/보합 색상
- 가격축 표시
- 시간축 표시
- 최근 N개 candle 표시
- 빈 데이터/로딩/오류 상태

### 7.2 2차 범위

- 좌우 스크롤
- 캔들 선택
- 선택 candle의 OHLCV 표시
- 거래량 bar
- viewport 기반 부분 렌더링

### 7.3 3차 범위

- pinch zoom
- crosshair
- 실시간 마지막 candle 갱신
- 보조지표 확장 기반
- 고빈도 업데이트 성능 최적화

## 8. 성능 기준

1. 대량 candle을 매번 전체 redraw하지 않는다.
2. 화면에 보이는 candle 범위를 기준으로 렌더링한다.
3. 축, 캔들, 거래량 layer는 책임을 분리한다.
4. 실시간 가격 갱신은 마지막 candle과 현재가 표시 위주로 최소 갱신한다.
5. 스크롤/줌 중 메인 스레드 부하를 측정한다.

## 9. TradingView 처리 정책

TradingView는 다음처럼 취급한다.

- 지원되는 심볼은 계속 사용할 수 있다.
- 지원되지 않는 심볼을 다른 거래소 심볼로 임의 대체하지 않는다.
- Native Chart가 준비되기 전까지 미지원 심볼은 명확한 미지원 상태를 표시한다.
- Native Chart 도입 후에는 현재 거래소 candle API 기반 차트를 우선한다.

## 10. 작업 시작 조건

Native Chart 작업은 별도 branch에서 시작한다.

시작 전 최소 결정해야 할 사항:

1. 1차 지원 interval 범위
2. candle page size와 pagination 정책
3. Decimal 사용 범위
4. realtime 마지막 candle 갱신 방식
5. TradingView와 Native Chart의 전환 정책
6. 성능 검증 기준

## 11. 관련 문서

- `docs/exchange-extension-architecture-spec.md`
- `docs/bithumb-api-gap-notes.md`
