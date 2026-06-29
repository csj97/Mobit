# MOBIT Start Preparation

이 문서는 MOBIT에서 새로운 기능, 리디자인, 구조 개선을 시작하기 전에 현재 상태를 빠르게 파악하기 위한 준비 문서다.

## 1. 프로젝트 한 줄 요약

MOBIT은 UIKit 기반 Swift iOS 앱이며, 암호화폐 시세 조회와 모의 투자를 중심으로 구성되어 있다. Upbit REST/WebSocket으로 시세와 호가를 받고, Firebase로 코인 정보와 광고/분석 데이터를 보조하며, ReactorKit/RxSwift로 주요 화면 상태를 관리한다.

## 2. 현재 구성

```text
Mobit/
  Application/        AppDelegate, SceneDelegate, CustomWindow
  Presentation/       화면, XIB, Reactor, Coordinator
  Domain/             UseCase, 도메인 모델
  Data/               Moya Target, DTO, Repository, WebSocket
  Common/             공통 뷰, 확장, 유틸, 사용자 데이터
  Resource/           Assets, Colors, Fonts, Localizable, Lotties
MobitTests/           기본 템플릿 수준
MobitUITests/         기본 템플릿 수준
fastlane/             배포 자동화
```

프로젝트는 `Mobit.xcodeproj` 기반이고 주요 스킴은 `Mobit`, `Mobit-Dev`, `Mobit-Release`다. 앱 타깃의 iOS deployment target은 16.0, 테스트 타깃은 15.0으로 설정되어 있다.

## 3. 주요 의존성

- ReactorKit, RxSwift, RxCocoa, RxRelay
- Moya, RxMoya
- Starscream
- Firebase Analytics, Database, Crashlytics
- GoogleMobileAds
- SnapKit, PinLayout, FlexLayout, Then
- SkeletonView
- Lottie
- SwiftJWT

UI 레이아웃 방식은 한 가지로 통일되어 있지 않다. XIB, Auto Layout, SnapKit, PinLayout/FlexLayout이 함께 쓰이고, 거래 상세의 mini chart에는 SwiftUI hosting이 들어간다.

## 4. 앱 시작 흐름

1. `AppDelegate`에서 네트워크 모니터링, Firebase, GoogleMobileAds, ATT 요청, 첫 실행 기본 자금 세팅을 수행한다.
2. `SceneDelegate`에서 `MobitLaunchScreen`을 먼저 보여준다.
3. Firebase에서 `cryptoInformations`, `btc_cryptoInformations`를 미리 다운로드한다.
4. 1.5초 후 `AppCoordinator`를 시작한다.
5. `AppTabBarCoordinator`가 4개 탭을 구성한다.

탭 구성:

- 거래소: `MainCoordinator -> MainViewController`
- 투자내역: `InvestmentCoordinator -> InvestmentViewController`
- 뉴스: `NewsCoordinator -> NewsViewController`
- 더보기: `MoreCoordinator -> MoreViewController`

## 5. 주요 기능 흐름

### 거래소

- `MainViewController`가 코인 목록, 검색, 마켓 탭, 정렬, 즐겨찾기, 네이티브 광고를 담당한다.
- `MainReactor`가 Upbit market list 조회, ticker REST 초기 조회, ticker WebSocket 업데이트를 관리한다.
- 목록은 `UITableViewDiffableDataSource`를 사용한다.
- 마켓 표기는 내부 UI에서 `BTC/KRW` 형태로 바꾸고, Upbit API/WebSocket 구독 시 `KRW-BTC` 형태로 되돌린다.

주의할 점:

- WebSocket 실시간 업데이트와 정렬 포지션 유지 로직이 엮여 있다.
- `hold` 탭 구독 로직은 현재 보유 코인만이 아니라 KRW 전체 마켓을 구독하는 형태로 보인다. 실제 의도 확인이 필요하다.
- 검색/정렬/탭 전환 시 소켓 구독 대상과 UI snapshot 갱신 범위를 같이 봐야 한다.

### 거래 상세

- `TradeViewController`가 상단 시세, 즐겨찾기, 주문/차트/정보 segmented 영역, 광고 배너, mini chart를 담당한다.
- `TradeReactor`가 ticker WebSocket, orderbook WebSocket, CMC 정보, candle API, 사용자 거래 데이터를 관리한다.
- 주문 화면은 `TradeOrderView` 안에 `TradeBidView`, `TradeAskView`, `TradeHistoryView`를 넣는 구조다.
- 체결 성공 시 Lottie 피드백을 보여준다.

주의할 점:

- ticker socket과 orderbook socket이 동시에 동작한다.
- 앱 foreground/background 전환 시 `CustomWindow`가 현재 보이는 컨트롤러의 socket pause/resume을 호출한다.
- 거래 상세에서 탭바 hide/show가 Coordinator delegate로 처리된다.
- Coupang 광고는 TODO로 남아 있고 현재 Google 배너 중심으로 배포된 상태다.

### 투자내역

- `InvestmentViewController`가 보유 자산, 평가손익, 수익률, 정렬, 충전, P&L 진입을 담당한다.
- `InvestReactor`는 `UserDataManager`의 보유 코인/잔고 observable을 구독한다.
- 충전은 보상형 광고 시청 후 10,000,000원을 추가하는 흐름이다.

주의할 점:

- 계산 로직이 ViewController에 많이 남아 있다.
- 정렬 후 diffable snapshot과 내부 `cryptos` 배열의 관계를 조심해야 한다.
- 테스트가 없으므로 손익률/평가금액 계산 변경 시 단위 테스트부터 만드는 것이 좋다.

### 뉴스

- `NewsViewController`는 `https://coinness.com/news`를 WKWebView로 보여준다.
- Pull to refresh만 있다.

주의할 점:

- 외부 웹뷰 의존 화면이라 로딩 실패, 네트워크 실패, 빈 화면 처리가 약할 가능성이 있다.

### 더보기

- 충전, 사용자 안내사항, 투자내역 초기화, 커뮤니티 이동, 버전 표시를 담당한다.
- 커뮤니티 화면은 WebKit/Firebase와 연결되는 흐름이 있다.

주의할 점:

- 초기화는 `UserDataManager`의 여러 저장 값을 직접 비운다.
- 안내 문구와 알럿 문구가 하드코딩되어 있다.

## 6. 데이터와 저장소

### 외부 데이터

- Upbit REST: 마켓 목록, ticker, candle
- Upbit WebSocket: ticker, orderbook
- CoinMarketCap API: 상세 코인 정보
- Firebase Realtime Database: CMC 캐시성 정보, 광고 슬롯, 커뮤니티성 데이터

### 로컬 데이터

`UserDataManager`가 `UserDefaults`에 다음 데이터를 저장한다.

- 첫 실행 여부
- 즐겨찾기 마켓
- 거래 내역
- 유효 거래 내역
- 현재 보유 코인
- P&L 히스토리
- 사용자 보유 현금

보유 코인 모델은 legacy migration 코드가 있다. 저장 모델 변경 시 기존 사용자 데이터 보존을 먼저 확인해야 한다.

## 7. UI/UX 현황

### 강점

- 탭 구조가 명확하다.
- 거래소, 투자내역, 뉴스, 더보기의 정보 구조가 직관적이다.
- 상승/하락 색상, 시세 변화 border animation, Lottie 체결 피드백처럼 금융 앱에서 기대되는 즉각적 피드백이 있다.
- 커스텀 탭바와 neumorphic 계열 컴포넌트로 브랜드 톤을 만들려는 시도가 있다.
- 보유 자산과 주문 화면을 연결해 현재 평가손익을 바로 보여주는 흐름이 좋다.

### 약점

- UI 문자열이 로컬라이즈 파일에 일부 준비되어 있지만 실제 화면 코드는 하드코딩이 많다.
- 색상 사용이 `UIColor.red`, `.blue`, hex, asset color로 섞여 있어 디자인 토큰 일관성이 약하다.
- 레이아웃 기술이 XIB, SnapKit, FlexLayout, PinLayout로 분산되어 있어 수정 시 예측 비용이 크다.
- iOS 접근성 관점에서 아이콘 버튼 라벨, Dynamic Type, VoiceOver 검증 흔적이 부족하다.
- 뉴스/커뮤니티 같은 WebView 화면은 로딩, 실패, skeleton/empty 상태가 약하다.
- 광고가 메인/거래/충전 흐름에 섞여 있어 UX 피로도와 정책 검토가 필요하다.

## 8. 기술 리스크

우선순위 높은 리스크:

1. 테스트가 거의 없다. 계산, 정렬, 거래 처리, 모델 migration 같은 핵심 로직 변경이 위험하다.
2. WebSocket 생명주기가 화면 전환, 탭 전환, foreground/background 전환에 걸쳐 있어 중복 연결이나 구독 누락 가능성이 있다.
3. 사용자 자산/거래 데이터가 `UserDefaults`에 저장되고 View 쪽 계산도 많아 데이터 정합성 검증이 필요하다.
4. CMC API key 접근에 강제 캐스팅이 있고, 설정 누락 시 크래시가 날 수 있다.
5. 네트워크 실패 처리와 사용자 안내가 화면마다 균일하지 않다.
6. 로컬라이즈 리소스와 실제 코드 사용이 분리되어 있다.
7. Debug logging에 IDFA, 네트워크 상태, deinit print 등이 남아 있다.

## 9. 새 작업 시작 전 권장 순서

1. 목표를 기능 추가, 리디자인, 안정화, 수익화 개선 중 하나로 분류한다.
2. 영향 화면을 탭 단위로 좁힌다.
3. 관련 Reactor와 UserDataManager 저장 흐름을 먼저 확인한다.
4. 계산/정렬/거래 데이터가 포함되면 단위 테스트부터 만든다.
5. WebSocket이 포함되면 pause/resume, 화면 이탈, 탭 전환 시나리오를 검증 항목에 넣는다.
6. UI 변경이면 XIB와 코드 레이아웃 충돌 여부를 먼저 확인한다.
7. 사용자 문구 변경이면 로컬라이즈 사용 여부를 먼저 정한다.
8. 광고/추적/외부 SDK 변경이면 정책 영향과 fallback을 같이 본다.

## 10. 추천 첫 개선 후보

### 안정화

- `UserDataManager` 저장/계산 로직 테스트 추가
- 손익률, 평가금액, 매수/매도 계산 테스트 추가
- Upbit market format 변환 테스트 추가
- WebSocket 구독 대상 로직 정리

### UI/UX

- 거래소 메인 목록의 empty/loading/error 상태 정리
- 뉴스 WebView 실패 화면 추가
- 탭바 접근성 라벨 추가
- 색상 토큰 정리 후 상승/하락/브랜드 색상 사용 통일
- 로컬라이즈 리소스 실제 적용

### 구조

- ViewController에 있는 계산 로직을 UseCase 또는 별도 pure function으로 분리
- 광고 노출 정책을 화면 코드에서 분리
- Repository의 Observable wrapping 패턴 정리
- API key 강제 캐스팅 제거와 설정 누락 fallback 추가

## 11. 현재 작업 시 주의할 파일

- `Mobit/Presentation/MainScene/Reactors/MainReactor.swift`
- `Mobit/Presentation/MainScene/Views/Main/MainViewController.swift`
- `Mobit/Presentation/MainScene/Reactors/TradeReactor.swift`
- `Mobit/Presentation/MainScene/Views/Trade/TradeViewController.swift`
- `Mobit/Presentation/MainScene/Views/Trade/TradeOrderView.swift`
- `Mobit/Presentation/InvestmentScene/Views/InvestmentViewController.swift`
- `Mobit/Common/UserDataManager.swift`
- `Mobit/Data/Network/SoketManager/SocketManager.swift`
- `Mobit/Data/Repository/Main/MainRepository.swift`
- `Mobit/Data/Repository/Trade/CryptoDetailRepository.swift`

## 12. 결론

MOBIT은 기능 단위는 이미 분리되어 있고, ReactorKit/Coordinator/UseCase/Repository 골격도 있다. 다만 실제 핵심 계산과 UI 상태 처리 일부가 ViewController에 남아 있고, 테스트가 거의 없어 큰 변경 전에 안전망을 먼저 깔아야 한다.

새로운 시작의 첫 단계는 리디자인이나 대규모 기능 추가보다 `거래소 메인`, `거래 상세`, `투자내역` 중 하나를 고르고, 그 화면의 상태/계산/에러/빈 상태를 정리하는 것이 가장 현실적이다.
