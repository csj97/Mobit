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
