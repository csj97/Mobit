# Data Migration Blueprint

이 문서는 기존 Upbit 단일 거래소 저장 데이터를 다중 거래소 구조로 무손실 이관하기 위한 기준 문서다.

핵심 목표는 다음 세 가지다.

1. 기존 사용자의 보유 자산, 거래내역, 손익, 즐겨찾기를 잃지 않는다.
2. Upbit 데이터와 신규 Bithumb 데이터가 절대 충돌하지 않게 한다.
3. 마이그레이션 실패 시 사용자의 기존 데이터가 손상되지 않게 한다.

## 1. 마이그레이션 원칙

1. 모든 레거시 데이터는 기본적으로 `exchange = upbit`로 간주한다.
2. 기존 원본 데이터는 새 포맷 저장이 성공하기 전까지 덮어쓰지 않는다.
3. 읽기 시점 마이그레이션을 우선한다.
4. 부분 성공 상태를 만들지 않는다.
5. 계산 결과가 바뀌지 않으면 성공, 바뀌면 실패로 본다.

## 2. 레거시 데이터 현황

현재 `UserDefaults` 저장 대상:

- `userFavoriteList`
- `userTransactionList`
- `userValidTransactionList`
- `userCryptoList`
- `userPNLHistory`
- 기타 사용자 현금/설정 데이터

문제:

- 거래소 식별자 없음
- `marketName`만 존재
- 예: `BTC/KRW`

이 상태로는 동일 심볼의 다중 거래소 자산을 분리할 수 없다.

## 3. 새 식별자 정책

### 3.1 기본 키

- `ExchangePairID = exchange + rawMarketCode`

예시:

- Upbit BTC/KRW
  - `id = upbit:KRW-BTC`
- Bithumb BTC/KRW
  - `id = bithumb:KRW-BTC`

### 3.2 표시값 분리

- 사용자 표시:
  - `BTC/KRW`
- 내부 저장:
  - `upbit:KRW-BTC`

표시값은 저장 키가 아니다.

## 4. 마이그레이션 대상별 정책

### 4.1 Favorites

기존:

- `[String]`
- 예: `["BTC/KRW", "ETH/KRW"]`

신규:

- `[FavoritePair]`
- 필드:
  - `pairID`
  - `exchange`
  - `rawMarketCode`
  - `displayMarket`

이관 규칙:

1. 기존 문자열을 Upbit display market으로 해석
2. Upbit raw market code로 역변환
3. `pairID = upbit:<rawCode>` 생성

### 4.2 Holdings

기존:

- `CryptoTransactionDataModel`
- `staticData.marketName`
- `dynamicData.marketName`

신규:

- `ExchangeHolding`
- 정적/동적 데이터 모두 `pairID` 포함

이관 규칙:

1. `marketName`을 Upbit 표시 마켓으로 해석
2. raw market code 생성
3. pairID 생성
4. 보유 수량, 평균단가, 매수총액 그대로 보존

### 4.3 Transaction History

기존:

- `TransactionInfo.marketName`

신규:

- `ExchangeTransactionInfo`
- `pairID` 포함

이관 규칙:

1. 기존 `marketName`을 pairID로 승격
2. 체결가, 체결수량, 체결금액, 체결시각 그대로 유지

### 4.4 Valid Transactions

기존:

- `ValidTransactionInfo.marketName`
- 내부 transaction 배열

신규:

- `ExchangeValidTransactionInfo`
- `pairID` 포함

이관 규칙:

1. marketName을 pairID로 승격
2. transaction 배열 순서 유지
3. 평균단가 계산 결과가 기존과 동일해야 함

### 4.5 PNL History

기존:

- `UserPNLHistoryModel.marketName`

신규:

- `ExchangePNLHistory`
- `pairID` 포함

이관 규칙:

1. pairID 승격
2. 진입가/청산가/수량/pnl 그대로 유지

## 5. 마이그레이션 실행 방식

### 5.1 추천 방식

- read-through migration

순서:

1. 기존 키 읽기
2. 레거시 여부 판단
3. 메모리에서 새 모델로 변환
4. 검증 수행
5. 새 키 또는 새 포맷으로 저장
6. 저장 성공 시에만 새 모델 반환
7. 실패 시 기존 모델 유지

### 5.2 쓰기 정책

- 새 구조 저장 성공 전:
  - 기존 데이터 보존
- 새 구조 저장 성공 후:
  - 이후부터는 새 구조만 사용

### 5.3 권장 구현 위치

- `UserDataManager` 내부에 직접 분기만 늘리지 않는다.
- 별도 `Migration` 유틸 또는 `StorageAdapter` 레이어를 둔다.

## 6. 검증 규칙

마이그레이션 성공 전 반드시 아래 검증을 통과해야 한다.

### 6.1 Favorites 검증

- 개수 동일
- 각 표시 마켓이 올바른 Upbit pairID로 매핑

### 6.2 Holdings 검증

- 코인 개수 동일
- 각 코인의:
  - 보유 수량 동일
  - 평균 매수가 동일
  - 매수 총액 동일

### 6.3 Valid Transactions 검증

- 항목 수 동일
- transaction 총 개수 동일
- `averageBuyPrice`, `totalHoldingQuantity` 재계산 결과 동일

### 6.4 PNL 검증

- 항목 수 동일
- 각 항목의:
  - entryPrice 동일
  - exitPrice 동일
  - orderQuantity 동일
  - pnl 동일

### 6.5 종합 검증

- 총 평가금액 동일
- 총 평가손익 동일
- 총 수익률 동일

## 7. 실패 처리

다음 경우 마이그레이션 실패로 간주한다.

1. raw market code 생성 실패
2. 새 모델 encode 실패
3. 저장 실패
4. 평균단가/보유수량/손익 검증 불일치
5. 일부 키만 성공하고 일부 키가 실패

실패 시 정책:

1. 기존 데이터 유지
2. 새 포맷 덮어쓰기 금지
3. 에러 로그 남김
4. 사용자 자산 화면은 기존 포맷 fallback 사용

## 8. 점진 전환 전략

### Phase 1

- 레거시 읽기 + 새 모델 생성 + 검증
- 실제 화면은 아직 기존 모델 사용 가능

### Phase 2

- 화면 내부 계산을 새 모델 기반으로 브릿지

### Phase 3

- 기존 모델 사용 제거
- 신규 거래소 데이터 저장 시작

## 9. 테스트 전략

### 단위 테스트

1. `BTC/KRW -> upbit:KRW-BTC` 변환
2. 즐겨찾기 배열 마이그레이션
3. 거래내역 마이그레이션
4. 보유 자산 마이그레이션
5. 평균단가/보유수량/손익 재계산 검증

### 샘플 데이터 테스트

- 실제 레거시 JSON 샘플을 fixture로 저장
- 마이그레이션 전후 snapshot 비교

### 회귀 테스트

- 기존 사용자 시나리오:
  - 앱 실행
  - 보유 탭 확인
  - 투자내역 정렬
  - 거래 상세 진입
  - 매수/매도 후 수치 확인

## 10. 금지 사항

1. pairID 설계 전 신규 거래소 데이터를 저장하지 않는다.
2. 레거시 데이터를 바로 삭제하지 않는다.
3. UI에서 문자열 치환만으로 마이그레이션을 대체하지 않는다.
4. 손익 계산 불일치 상태로 릴리즈하지 않는다.

## 11. 완료 기준

다음 조건을 모두 만족하면 데이터 마이그레이션 준비가 완료된 것으로 본다.

1. 기존 Upbit 사용자 데이터가 새 식별자로 무손실 승격된다.
2. Favorites/Holdings/Transactions/PNL이 같은 pairID 기준으로 정렬된다.
3. 계산 결과가 이관 전후 동일하다.
4. 이후 Bithumb 데이터를 추가해도 기존 Upbit 데이터와 충돌하지 않는다.
