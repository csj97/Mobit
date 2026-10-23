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
- Firebase Analytics, Database, Crashlytics, Messaging
- GoogleMobileAds
- SkeletonView
- Lottie
- PinLayout, FlexLayout, Then
- Swift-JWT

## FCM 푸시 설정

앱은 기존 ATT 요청이 끝난 뒤 활성 상태에서 알림 권한을 요청한다. 거부한 경우 다시 요청하지 않으며, 설정에서 허용한 뒤 앱으로 돌아오면 APNs 등록을 재시도한다. 앱 사용 중에는 배너·알림센터·소리로 표시하고, 알림을 누르면 커스텀 데이터에 지정한 화면으로 이동한다.

실제 발송 전 다음 외부 설정이 필요하다.

1. Apple Developer → Certificates, Identifiers & Profiles → Identifiers에서 `com.kando.Mobit` App ID를 선택하고 Push Notifications를 활성화한다.
2. 같은 메뉴의 Keys에서 Apple Push Notifications service(APNs) 인증 키(`.p8`)를 준비하고 Key ID와 Team ID를 확인한다. 새 키는 Sandbox 또는 Production 환경에 제한되므로 개발·배포를 모두 지원하려면 각 환경에 맞는 키를 준비한다. Topic Specific 키라면 허용 대상에 `com.kando.Mobit`이 포함되어야 한다. 인증 키는 저장소에 추가하지 않는다.
3. Firebase 프로젝트 설정 → Cloud Messaging → Apple 앱 구성에서 Bundle ID가 `com.kando.Mobit`인 앱에 `.p8`, Key ID, Team ID를 등록한다. Sandbox 키는 development 슬롯, Production 키는 production 슬롯에 맞춘다. 기존 양 환경 공용 키는 계속 사용할 수 있다.
4. Xcode의 Mobit 타깃 → Signing & Capabilities에서 올바른 Team, Automatically manage signing, Push Notifications를 확인한다. 푸시 권한이 포함되도록 프로비저닝 프로파일을 갱신하며, 수동 서명이라면 개발·배포 프로파일을 재생성해 적용한다.
5. 실제 기기에서 앱을 실행해 ATT 요청이 끝난 뒤 알림을 허용한다. ATT 허용 여부는 푸시 수신 조건이 아니다.
6. Xcode에서 `messaging(_:didReceiveRegistrationToken:)`에 중단점을 걸고 `po fcmToken`으로 테스트 대상 토큰을 확인한 뒤 실행을 재개한다. 토큰은 로그·UserDefaults·저장소에 별도로 남기지 않는다.
7. Firebase Messaging에서 알림 제목·내용을 작성하고 해당 FCM 토큰으로 테스트 메시지를 발송한다. 앱 사용 중 배너 표시, 백그라운드·종료 상태의 알림 표시, 알림을 눌렀을 때 앱 실행을 각각 확인한다. 권한 거부 후 재실행 시 재요청하지 않는지, 설정에서 허용하고 복귀한 뒤 수신되는지도 확인한다.
8. TestFlight·App Store 앱은 Production APNs를 사용한다. 배포용 키 등록 후 TestFlight에서 받은 FCM 토큰으로도 수신을 다시 확인한다.

`Mobit/Mobit.entitlements`는 개발용 APNs 환경을 선언한다. 배포 서명 시에는 프로비저닝 프로파일에 따라 `production`이 적용되는지 최종 아카이브에서 확인한다. 일반 표시 알림만 지원하며, 무음 푸시·이미지 알림 확장·개인별 서버 토큰 저장은 별도 구현 범위다.

설정 및 수신 규약은 [Firebase Apple 플랫폼 설정](https://firebase.google.com/docs/cloud-messaging/ios/get-started), [알림 수신 안내](https://firebase.google.com/docs/cloud-messaging/ios/receive-messages), [Apple APNs 인증 키](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns), [APNs 환경](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment)을 참고한다. 현재 프로젝트는 Firebase 11.15.0의 등록 토큰 API를 사용한다.

### 푸시 화면 이동·액션 실행과 유입 분석

Firebase Messaging의 알림 작성 화면에서 추가 옵션 → 커스텀 데이터에 다음 값을 넣는다. 별도의 URL Scheme이나 Universal Link 설정은 필요하지 않다.

| 키 | 예시 값 | 용도 |
| --- | --- | --- |
| `type` | `route` | 화면 이동. 생략하면 기존과 동일하게 화면 이동으로 해석 |
| `destination` | `investment` | `exchange`(거래소), `investment`(투자내역), `news`(뉴스), `more`(더보기) |
| `campaign_id` | `daily_investment_20261023` | 선택 사항. 공지별 유입을 구분하는 식별자 |

현재 선택한 거래소와 현물·선물 모드는 유지한다. 앱 종료 상태에서는 인트로와 화면 준비가 끝난 뒤 이동하고, 이미 실행 중이면 상세·모달을 닫아 지정한 탭의 루트를 보여준다. 강제 업데이트 안내는 화면 이동으로 우회하지 않는다. `destination`을 생략하거나 지원하지 않는 명령이면 별도 화면 전환 없이 앱을 연다. 푸시를 받기만 하거나 알림을 닫는 동작은 유입으로 기록하지 않는다.

화면 이동 없이 기능만 실행하려면 `type=action`, `action=<등록한 이름>`을 사용한다. `AppDelegate`의 `PushNotificationOpenHandler` 생성 시 `actionHandlers`에 이름과 기능 서비스의 처리 함수를 등록한다. 현재 기본 등록 액션은 없으며, 예를 들어 `refresh_content`를 등록한 이후에만 해당 이름의 푸시가 실행된다. 이름은 영문 소문자로 시작하는 40자 이내의 영문 소문자·숫자·밑줄로 정한다. 처리 함수는 제어 키(`type`, `action`, `destination`, `campaign_id`)와 APNs·FCM 메타데이터를 제외한 커스텀 문자열 데이터를 받으며 화면을 이동시키지 않는다. 이는 알림을 눌렀을 때의 처리이며 백그라운드 무음 푸시 실행 기능은 아니다.

새 화면은 `PushNotificationDestination`과 Coordinator의 목적지 처리를 추가하고, 새 독립 기능은 `actionHandlers`에 등록한다. payload 해석은 `PushNotificationCommand`, 중복 방지와 대기·실행은 `PushNotificationOpenHandler`가 담당한다. 앱 준비·Scene 활성화 전에는 실행을 기다리며, 대기 중인 화면 이동은 가장 최근 클릭을 따르고 독립 액션은 클릭 순서대로 각각 실행한다. 뒤에 누른 일반 알림이나 액션은 이전의 대기 화면 이동을 취소하지만 이미 대기 중인 독립 액션을 지우지 않는다. 미등록 목적지·액션이나 잘못된 `type`은 실행하지 않는다.

실제 원격 알림을 누를 때 `push_open` 이벤트를 한 번 기록한다. 파라미터는 `destination`(등록된 화면 이름 또는 `app`), 액션 푸시의 선택적 `action`, 선택적 `campaign_id`다. 신규 목적지도 같은 이벤트로 집계하며 커스텀 데이터 원문은 분석에 전달하지 않는다. `campaign_id`는 영문·숫자·밑줄·하이픈·점만 허용하고 최대 100자로 제한한다. FCM의 기본 캠페인 열기 지표는 SDK 기본 swizzling에 맡기며 `notification_open` 이벤트를 별도로 수동 전송하지 않는다.

개발 검증은 Xcode 실행 인자에 `-FIRDebugEnabled`를 추가하고 Firebase Analytics → DebugView에서 `push_open` 및 파라미터를 확인한다. 일반 보고서에서 목적지·공지별로 분류하려면 연결된 GA4의 관리 → 맞춤 정의에서 이벤트 범위의 `destination`, `campaign_id` 맞춤 측정기준을 등록한다. 검증 후 `-FIRDebugEnabled` 대신 `-FIRDebugDisabled`로 한 번 실행해 디버그 모드를 끄고 개발용 인자를 제거한다. 자세한 동작은 [커스텀 데이터](https://firebase.google.com/docs/cloud-messaging/send/firebase-console), [DebugView](https://firebase.google.com/docs/analytics/debugview), [이벤트 파라미터 보고](https://firebase.google.com/docs/analytics/ios/events)를 참고한다.

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
