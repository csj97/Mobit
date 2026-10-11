# MOBIT

MOBIT은 암호화폐 시세 조회와 모의 투자를 중심으로 구성된 UIKit 기반 Swift iOS 앱이다. 실시간 시세, 거래 상세, 모의 보유 자산, 뉴스, 커뮤니티, 더보기 화면을 제공한다.

## 주요 기능

- 암호화폐 마켓 목록과 실시간 티커 조회
- KRW, BTC, 보유, 즐겨찾기 기준 탭 구성
- 거래 상세 화면, 호가, 체결 내역, 차트, 평균 단가 계산
- 모의 투자 자산과 손익률 확인
- 뉴스와 커뮤니티 화면
- Firebase 기반 원격 데이터, 분석, Crashlytics 연동
- GoogleMobileAds 기반 광고와 보상형 광고 처리

## 프로젝트 구조

```text
Mobit/
  Application/        AppDelegate, SceneDelegate, Window
  Presentation/       ViewController, XIB, Reactor, Coordinator
  Domain/             UseCase, 앱 내부 모델
  Data/               NetworkService, DTO, Repository, Socket
  Common/             공통 View, Extension, Util, UserDataManager
  Resource/           Assets, Colors, Fonts, Localizable, Lotties
MobitTests/           단위 테스트
MobitUITests/         UI 테스트
fastlane/             배포 자동화
```

## 화면 구성

- `Presentation/MainScene`: 메인 코인 목록, 거래 상세, 차트, 호가, 주문 관련 화면
- `Presentation/InvestmentScene`: 모의 투자 보유 자산, 손익률, 공유 화면
- `Presentation/NewsScene`: 뉴스 화면
- `Presentation/MoreScene`: 커뮤니티, 리더보드, 더보기 화면
- `Presentation/Common`: 탭바, 알럿, 바텀시트, Coordinator 공통 타입

## 아키텍처

MOBIT은 UIKit, XIB, Coordinator, ReactorKit, RxSwift를 함께 사용한다.

```text
ViewController/XIB
  -> Reactor(Action)
  -> UseCase
  -> Repository
  -> NetworkService / Firebase / WebSocket
  -> DTO
  -> Domain Model
  -> Reactor(State)
  -> ViewController render
```

- ViewController는 사용자 입력 전달과 UI 갱신에 집중한다.
- Reactor는 Action, Mutation, State로 화면 상태와 비동기 이벤트를 관리한다.
- UseCase는 화면 요구사항과 데이터 계층 사이의 사용 사례를 표현한다.
- Repository와 NetworkService는 API, Firebase, WebSocket, DTO 변환을 담당한다.
- Coordinator는 화면 전환과 ViewController 생성 흐름을 담당한다.

## 모의 거래 규약

실행 규칙은 [`TradingRules.swift`](Mobit/Domain/Model/TradingRules.swift)에 정의한다. 실제 거래소 약관이 아니라 **MOBIT 내부 모의거래 정책**이며, 계좌 판정·주문 생성·계산·저장 로직이 이 규칙을 참조한다.

| 거래소·모드 | 마켓·결제 | 가격 기준 | 청산 |
| --- | --- | --- | --- |
| 업비트 현물 | KRW / BTC | 업비트 현물 시세 | 손익률 -100%여도 수량을 자동 제거하지 않음 |
| 빗썸 현물 | KRW / BTC | 빗썸 현물 시세 | 손익률 -100%여도 수량을 자동 제거하지 않음 |
| 업비트 선물 | KRW만 지원 | 업비트 KRW 현물 시세 기반 롱/숏 모의거래 | 증거금 + 실제 손익이 0 이하일 때 |
| 빗썸 선물 | KRW만 지원 | 빗썸 KRW 현물 시세 기반 롱/숏 모의거래 | 증거금 + 실제 손익이 0 이하일 때 |
| Binance / OKX 선물 | USDT 저장 모형만 보존 | 국내 선물 가격 제공자로 사용하지 않음 | 현재 주문 화면은 미지원·준비 상태 |

- 국내 선물은 실제 거래소로 주문을 보내지 않고, 수수료·펀딩·MMR을 적용하지 않는다.
- 레버리지 상한은 BTC·ETH 100배, SOL/XRP/ADA/AVAX/NEAR/SUI/DOGE/SHIB/LINK/UNI/AAVE/RNDR 50배, 나머지 20배다. 유사한 심볼로 대체하지 않는다.
- 같은 거래소·계좌·마켓에서 방향과 레버리지가 같을 때만 추가 진입을 합산한다. 과거 검증을 먼저 완료하고 최초 진입 시각과 개별 체결을 보존한다.
- 거래소와 현물/선물의 자산은 분리한다. 현물 BTC 마켓은 보유 BTC로 결제하며 별도 BTC 현금 계좌를 만들지 않는다. 과거 국내 선물 BTC 저장 데이터는 읽되 신규 주문은 거절한다.
- 인트로는 최소 1.5초, 최대 5초 대기한다. 최대 시간은 화면 대기 한도이며 실제 검증을 취소하지 않는다.
- 앱 복귀·거래소 전환·현물에서 선물 전환 시 과거 청산 검증을 요청한다. 이미 검증 중이면 중복 실행하지 않는다. 검증은 저장된 완료 경계부터 재개한다.
- 검증 완료 전에는 마지막 검증 가격으로 평가하고, 완료 후 최신 수신 시세를 자동 반영한다. 검증 중 받은 청산 가격은 과거 검증 완료 후 처리하며 더 이른 과거 청산을 우선한다.
- 청산 결과·실현 손익·자산·검증 경계를 함께 저장하며 중복 정산하거나 현물 자산을 차감하지 않는다. 청산 안내는 해당 거래소의 선물 모드에서만 표시한다.

`TradingRules`의 정책 정의와 실제 실행 책임은 다음처럼 구분한다.

| 정책 정의 | 참조하는 실행 코드 |
| --- | --- |
| `Funding`: 초기 지급 계좌·금액, 미지급·초기화 잔고, 광고 보상 금액·버전 | `TradingFundingPolicy`, `AdRewardClaim`, `UserDataManager`, 계좌 Repository |
| `Spot`: 최소 주문금액, 결제 자산, 체결·평가 정밀도, 잔량 허용 오차 | `SettlementCurrency`, `TradeOrderValidator`, `TradeOrderService`, `PortfolioCalculator` |
| `Futures`: 신규 계좌·구형 계좌 복원, 추가 진입·부분 종료·펀딩·현재가 청산 허용 조건, 표시 손실 한도 | 계좌 모델, `FuturesCalculator`, `LocalFuturesAccountRepository` |
| `Futures.HistoryCheck`: 주문 검증 경계, 현재가 유효 시간, 정밀 검증 허용 범위, 재검증 진입 조건 | `FuturesOrderCheck`, 검증 서비스·계산기, Reactor, Scene·Coordinator |
| `DomesticFutures`: 국내 가격 출처·계약·레버리지·비용, 인트로 대기 한도 | `FuturesTradingUseCase`, 가격 Repository, 검증 서비스 |
| 마켓 노출·청산 안내 조건 | 메인 화면, `SceneDelegate` |

기존 `TradingFundingPolicy`와 `SettlementCurrency` API는 호환용 참조를 유지하며 정책 값은 `TradingRules`에서만 정의한다. 계좌·마켓 ID 비교, 금액 계산, 검증 순서, 원자적 저장, API 형식·조회 범위는 기존 계층의 책임이다. 규칙 변경 시 [`TradingRulesTests.swift`](MobitTests/TradingRulesTests.swift)와 실제 실행 경로의 `FuturesCalculatorTests`, `LocalFuturesAccountRepositoryTests`, `FuturesHistoryCheckTests`, `FuturesAccountReactorTests`, `UserDataManagerTests`, 현물 주문·평가 테스트를 함께 검증한다.

## 주요 의존성

Swift Package Manager 기반으로 외부 라이브러리를 관리한다.

- ReactorKit, RxSwift, RxRelay
- Moya
- Starscream
- SnapKit
- Firebase Analytics, Database, Crashlytics
- GoogleMobileAds
- SkeletonView
- Lottie
- PinLayout, FlexLayout, Then
- Swift-JWT

## 빌드

Xcode에서 `Mobit.xcodeproj`를 열고 목적에 맞는 스킴을 선택한다.

- `Mobit`: 기본 앱 스킴
- `Mobit-Dev`: 개발 검증용 스킴
- `Mobit-Release`: 릴리즈 검증용 스킴

CLI 빌드 예시:

```bash
xcodebuild -project Mobit.xcodeproj -scheme Mobit-Dev -destination 'platform=iOS Simulator,name=iPhone 16' build
```

사용 가능한 Simulator 이름은 환경마다 다를 수 있다.

```bash
xcrun simctl list devices available
```

## 개발 기준

- 기존 Scene, Reactor, Coordinator, UseCase, Repository 흐름을 먼저 따른다.
- 신규 기능은 `Presentation/<FeatureName>Scene`을 기준으로 추가하고 필요한 경우 `Domain`, `Data` 계층을 함께 구성한다.
- 새 파일을 추가하면 Xcode target membership과 빌드 포함 여부를 확인한다.
- 사용자에게 노출되는 문자열은 로컬라이즈 리소스를 먼저 확인한다.
- 시세, 거래, 자산 계산은 반올림과 포맷 정책을 명확히 확인한다.
- WebSocket, Firebase, 광고 SDK, ATT 흐름은 기존 초기화와 생명주기를 임의로 바꾸지 않는다.
- 변경 후 관련 화면의 정상 흐름, 오류 흐름, 빈 데이터, 화면 이탈 후 비동기 갱신을 확인한다.

## 문서

- `AGENTS.md`: 개발자와 AI 에이전트 작업 지침
- `CLAUDE.md`: Claude 사용 시 동일하게 적용할 작업 지침
- `README.md`: 프로젝트 개요와 빌드/구조 안내
- `docs/exchange-extension-architecture-spec.md`: 다중 거래소 확장 아키텍처 기준
- `docs/data-migration-blueprint.md`: 거래소 확장용 저장 데이터 이관 기준
