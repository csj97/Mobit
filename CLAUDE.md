# CLAUDE.md

이 문서는 MOBIT 저장소에서 작업하는 개발자와 Claude와 AI 에이전트가 따라야 할 기준이다.
답변, 분석, 구현 계획, 변경 결과는 항상 논리적인 순서로 작성한다.

## 1. 기본 원칙

- 요청한 범위 안에서 가장 작은 변경으로 문제를 해결한다.
- 관련 없는 코드, 파일, 프로젝트 설정을 함께 정리하지 않는다.
- 기존 동작을 보존한다. 동작 변경이 필요한 경우 변경 이유와 영향 범위를 먼저 설명한다.
- 기존 코드 스타일, 아키텍처, 의존성 사용 방식을 우선한다.
- 코드의 짧음보다 가독성, 유지보수성, 실행 효율의 균형을 우선한다.
- 새로운 추상화는 실제 중복을 줄이거나 책임을 분리할 때만 추가한다.
- 프로젝트 전체 구조 변경, 대규모 파일 이동, 의존성 교체는 별도 요청 없이 진행하지 않는다.
- 작업 전후 `git diff`를 확인하고 불필요한 변경을 제거한다.
- 사용자가 작성 중인 변경사항을 임의로 되돌리거나 덮어쓰지 않는다.
- 주석은 최대 2줄, 가급적 1줄을 지향한다. 단순 설명보다 의사결정 이유와 예외 조건을 남긴다.
- 불필요한 프로퍼티, 상태, 플래그를 추가하지 않는다. 이미 가진 데이터와 상태 흐름을 먼저 활용한다.

## 2. 현재 프로젝트 특성

MOBIT은 UIKit 기반 Swift iOS 앱이다. 암호화폐 시세 조회, 모의 투자, 거래 상세, 뉴스, 커뮤니티, 더보기 화면을 제공하며 Clean Architecture에 가까운 계층 구조와 Coordinator, ReactorKit, RxSwift를 함께 사용한다.

- 앱 타깃: `Mobit`
- 테스트 타깃: `MobitTests`, `MobitUITests`
- 주요 스킴: `Mobit`, `Mobit-Dev`, `Mobit-Release`
- 배포 기준: 앱 타깃 iOS 16.0 이상
- 프로젝트 파일: `Mobit.xcodeproj`
- 앱 진입점: `Mobit/Application`
- 화면, Coordinator, Reactor: `Mobit/Presentation`
- UseCase와 도메인 모델: `Mobit/Domain`
- 네트워크, DTO, Repository, Socket: `Mobit/Data`
- 공통 뷰, 유틸리티, 확장, 사용자 데이터: `Mobit/Common`
- 리소스, 색상, 폰트, 로컬라이즈, Lottie: `Mobit/Resource`, `Mobit/Resources`
- 테스트: `MobitTests`, `MobitUITests`
- 배포 자동화: `fastlane`

주요 외부 의존성은 Swift Package Manager 기반으로 관리한다. ReactorKit, RxSwift, Moya, Starscream, SnapKit, Firebase, GoogleMobileAds, SkeletonView, Lottie 등을 사용한다. 새 의존성 추가 전 기존 의존성으로 해결 가능한지 먼저 확인한다.

## 3. 아키텍처와 책임 분리

MOBIT은 화면 계층과 비즈니스 계층을 분리하는 구조를 지향한다.

```text
Mobit/
  Application/        앱 생명주기, Scene/AppDelegate, Window
  Presentation/       ViewController, XIB, Reactor, Coordinator
  Domain/             UseCase, 앱 내부 모델
  Data/               NetworkService, DTO, Repository, Socket
  Common/             공통 View, Extension, Util, UserDataManager
  Resource/           Assets, Colors, Fonts, Localizable, Lotties
```

- 화면 전환은 가능한 한 Coordinator 흐름을 따른다.
- ViewController는 UI 바인딩, 사용자 입력 전달, 화면 갱신에 집중한다.
- Reactor는 Action, Mutation, State를 통해 화면 상태와 비동기 흐름을 관리한다.
- UseCase는 Presentation과 Data 사이의 사용 사례를 표현한다.
- Repository와 NetworkService는 외부 API, Firebase, WebSocket, DTO 변환을 담당한다.
- Domain 모델과 DTO를 혼용하지 않는다. 네트워크 응답은 DTO에서 Domain 모델로 변환한다.
- 공통 유틸리티로 올리기 전에 두 개 이상의 실제 사용처와 명확한 책임이 있는지 확인한다.

## 4. 디렉토리 및 파일 배치

### 기존 코드 수정

- 기존 기능 수정은 해당 Scene 디렉토리 안에서 처리한다.
- Main, Trade, Investment, News, More 등 기능 단위의 기존 배치를 우선한다.
- 단일 화면 전용 타입은 가능한 한 해당 화면 또는 Scene 가까이에 둔다.
- 여러 화면에서 실제로 재사용되는 UI만 `Mobit/Common/CustomViews`로 이동한다.
- 앱 전반에서 사용하는 유틸리티, 확장, 상수, 사용자 데이터는 `Mobit/Common`에 둔다.
- API, Socket, Firebase, DTO, Repository 코드는 `Mobit/Data`에 둔다.
- UseCase와 앱 내부 모델은 `Mobit/Domain`에 둔다.
- 파일 이동이 필요하면 Xcode target membership과 프로젝트 참조를 반드시 확인한다.

### 신규 기능

신규 기능은 `Mobit/Presentation/<FeatureName>Scene`을 기준으로 추가하고, 필요한 경우 `Domain`, `Data` 계층을 함께 구성한다.

```text
Mobit/
  Presentation/
    FeatureNameScene/
      Views/
      Reactors/
      Coordinator/
  Domain/
    UseCase/FeatureName/
    Model/
  Data/
    Network/FeatureName/
    Repository/FeatureName/
```

- 위 하위 폴더는 예시다. 모든 기능에 기계적으로 만들지 않는다.
- `Manager`, `Helper`, `Utils`, `Common` 같은 포괄적인 이름은 피한다.
- 기존 Scene과 밀접한 신규 코드는 해당 Scene 아래에 추가한다.
- 기능 전용 UI와 모델을 `Common`에 미리 섞지 않는다.
- 리소스 이름은 기능과 용도가 드러나게 작성하고 중복 이미지를 추가하지 않는다.

## 5. Swift 코드 작성 기준

- 타입과 함수는 하나의 명확한 책임을 갖도록 작성한다.
- 변수, 타입, 함수 이름은 의도를 드러내는 전체 단어를 우선한다.
- 이미 프로젝트에 정착된 약어가 아니라면 모호한 축약어를 만들지 않는다.
- 함수가 길어지면 의미 있는 작업 단위로 분리하되, 단순 전달만 하는 함수를 과도하게 늘리지 않는다.
- 중복 제거를 위해 복잡한 범용 구조를 먼저 만들지 않는다. 반복되는 요구가 확인된 뒤 추출한다.
- 값 타입이 적합하면 `struct`, 식별성과 수명 관리가 필요하면 `class`를 사용한다.
- 상속보다 조합을 우선하되, 기존 UIKit 상속 구조를 억지로 바꾸지 않는다.
- 접근 수준은 필요한 범위로 제한한다. 가능한 경우 `private`, `fileprivate`, `final`을 사용한다.
- 강제 언래핑(`!`), 강제 캐스팅(`as!`), `try!`은 안전성이 코드상 보장되는 경우가 아니면 사용하지 않는다.
- 매직 넘버와 반복 문자열은 의미 있는 상수로 분리한다.
- 단순한 코드를 설명하는 주석은 추가하지 않는다.
- 복잡한 거래 계산, 시세 정렬, 소켓 재연결, 광고 노출 정책, Firebase fallback처럼 의도가 중요한 부분은 한국어 주석으로 이유를 남긴다.

## 6. ReactorKit, RxSwift 기준

- ViewController는 사용자 입력을 Reactor Action으로 전달하고, State를 구독해 UI만 갱신한다.
- Reactor의 `Action`, `Mutation`, `State`는 화면에서 실제로 필요한 상태만 포함한다.
- `mutate(action:)`에는 비동기 작업과 이벤트 변환을 두고, `reduce(state:mutation:)`는 순수한 상태 변경으로 유지한다.
- 네트워크, Firebase, WebSocket 이벤트는 오류 흐름과 dispose 시점을 명확히 처리한다.
- `DisposeBag`의 소유권은 화면, Reactor, 장기 생존 객체의 수명에 맞춘다.
- `PublishSubject`나 Relay로 Reactor 외부 mutation을 주입할 때는 주입 경로와 생명주기를 명확히 한다.
- 메인 스레드 UI 갱신은 `MainScheduler` 또는 명시적 메인 큐에서 수행한다.
- 중복 구독, 화면 이탈 후 이벤트 반영, 소켓 중복 연결을 반드시 점검한다.

## 7. UIKit, XIB, 레이아웃

UI는 기기 크기, Dynamic Type, 다국어 문자열 길이, 데이터 변경에 자연스럽게 대응해야 한다.

### 우선 사용

- Auto Layout
- Safe Area
- intrinsic content size
- self-sizing `UITableViewCell`, `UICollectionViewCell`
- 콘텐츠 기반 높이 계산
- 데이터 변경에 따른 반응형 레이아웃 갱신
- 기존 XIB와 코드 레이아웃 패턴
- 기존 프로젝트에서 사용 중인 SnapKit 패턴

### 지양

- 디자인 요구사항으로 고정된 값이 아닌 임의의 화면 크기 하드코딩
- 생명주기 시점의 예상값으로 TableView 또는 CollectionView 높이를 고정
- 문자열 길이를 가정한 고정 높이
- Auto Layout으로 해결 가능한 수동 frame 계산
- 레이아웃 갱신을 위해 무분별하게 `layoutIfNeeded()`를 반복 호출
- XIB와 코드 제약이 서로 충돌하는 변경

고정 크기가 디자인상 명확하게 보장되지 않으면 동적 크기로 취급한다.

## 8. 시세, 거래, 데이터 흐름

MOBIT은 암호화폐 시세, 모의 보유 자산, 거래 기록, 호가, 차트 데이터를 다룬다. 데이터 정합성과 사용자 신뢰를 우선한다.

- 코인 심볼, 마켓, 가격, 수량, 평가금액, 손익률 계산은 반올림과 포맷 정책을 명확히 확인한다.
- KRW, BTC 등 마켓 탭별 정렬과 필터링은 기존 상태 흐름을 유지한다.
- WebSocket 실시간 시세와 REST 초기 조회의 병합 순서를 임의로 바꾸지 않는다.
- 빈 데이터, 상장폐지/미지원 심볼, 소켓 끊김, Firebase 응답 누락을 처리한다.
- 사용자 보유 자산과 거래 기록은 `UserDataManager` 흐름과 기존 저장 방식을 확인한다.
- 차트와 거래 화면의 UI 갱신은 과도한 전체 reload보다 필요한 범위 갱신을 우선한다.
- 실제 결제/실거래가 아닌 모의 투자 성격이라도 금액 계산 오류는 사용자 경험에 직접 영향을 준다.

## 9. 네트워크, Firebase, 보안

- API 요청과 응답 모델은 가능한 한 명시적인 타입으로 정의한다.
- 성공 경로뿐 아니라 서버 오류, 네트워크 단절, 타임아웃, 빈 응답, 파싱 실패를 처리한다.
- Moya, Repository, UseCase 경계를 유지한다.
- Firebase Realtime Database, Analytics, Crashlytics 설정은 기존 초기화 흐름을 따른다.
- Firebase 경로, 광고 슬롯, 앱 버전 체크 같은 원격 설정성 데이터는 fallback을 고려한다.
- 인증 토큰, API 키, 광고 식별자, 개인정보, 원본 응답 전체를 로그에 남기지 않는다.
- 민감 정보는 `UserDefaults`에 직접 저장하지 않는다. 저장이 필요하면 기존 저장 방식을 확인한다.
- 사용자에게 표시하는 오류와 디버깅용 오류를 구분한다.
- 분석 이벤트는 기존 `MobitAnalyticsUtil` 패턴을 따른다. 이벤트 이름과 파라미터를 임의로 중복 생성하지 않는다.
- Debug, Dev, Release 설정이 섞이지 않도록 스킴과 빌드 설정을 확인한다.

## 10. 광고, 추적 권한, 외부 SDK

- GoogleMobileAds 초기화와 테스트 디바이스 설정은 `AppDelegate` 흐름을 따른다.
- 광고 노출 위치, 보상형 광고, 하이브리드 광고 슬롯은 기존 `Advertisement` 유틸리티를 먼저 확인한다.
- ATT 요청 시점과 사용자 경험을 임의로 바꾸지 않는다.
- Firebase, GoogleMobileAds, Lottie, SkeletonView 등 SDK 업데이트는 별도 요청 없이 진행하지 않는다.
- 외부 SDK 콜백은 retain cycle, 중복 호출, 화면 이탈 후 UI 갱신을 점검한다.

## 11. 다국어 및 접근성

- 사용자에게 노출되는 문자열을 코드에 직접 하드코딩하지 않는다. 기존 로컬라이즈 리소스를 먼저 검색한다.
- 신규 문자열은 `Mobit/Resource/Localizable` 반영 범위를 확인한다.
- 긴 번역 문자열에서도 잘리지 않도록 레이아웃을 확인한다.
- 아이콘만 있는 버튼은 접근성 라벨을 제공한다.
- 색상만으로 상승/하락, 선택/비선택, 오류/정상 상태를 구분하지 않는다.
- 텍스트 크기 확대와 VoiceOver 영향을 고려한다.

## 12. 의존성 및 프로젝트 설정

- 새 외부 라이브러리는 표준 라이브러리나 기존 의존성으로 해결할 수 없는 경우에만 추가한다.
- 새 의존성을 추가하기 전 유지보수 상태, 라이선스, 앱 크기, 최소 iOS 버전, 기존 구조와의 호환성을 확인한다.
- `Mobit.xcodeproj`, entitlements, plist, SPM 패키지 설정 수정은 영향 범위를 설명하고 꼭 필요한 항목만 변경한다.
- `xcuserdata`, 개인 breakpoint, 사용자별 Xcode 상태 파일을 직접 수정하거나 커밋하지 않는다.
- 새 Swift/XIB/리소스 파일을 추가하면 Xcode target membership과 빌드 포함 여부를 확인한다.
- `fastlane` 파일 수정은 배포 영향이 크므로 요청 범위와 검증 방법을 명확히 한다.

## 13. 테스트 및 검증

변경 위험도에 맞는 검증을 수행한다.

### 공통 확인

- 변경 파일의 컴파일 오류와 경고를 확인한다.
- 관련 화면의 정상 흐름, 오류 흐름, 빈 데이터, 중복 탭을 확인한다.
- 비동기 작업 후 UI 갱신과 화면 이탈 시점을 확인한다.
- 다국어 문자열과 작은 화면에서 레이아웃 깨짐을 확인한다.
- 메모리 누수 가능성과 retain cycle을 확인한다.
- 시세 소켓 연결, 해제, 재연결 흐름을 확인한다.

### 빌드 확인

- 기본 빌드는 `Mobit.xcodeproj`와 요청 범위에 맞는 스킴으로 확인한다.
- 일반 기능 변경은 `Mobit-Dev` 또는 현재 작업 스킴을 우선 검증한다.
- 배포 설정, plist, SDK 초기화, 리소스 변경은 `Mobit`, `Mobit-Release` 영향도까지 확인한다.
- 테스트 추가가 가능한 로직은 UI와 분리하고 단위 테스트를 작성한다.
- 기존 테스트가 부족하다는 이유로 검증을 생략하지 않는다. 수행하지 못한 검증은 결과에 명시한다.

예시 빌드 명령:

```bash
xcodebuild -project Mobit.xcodeproj -scheme Mobit-Dev -destination 'platform=iOS Simulator,name=iPhone 16' build
```

사용 가능한 Simulator 이름은 로컬 환경마다 다를 수 있으므로 `xcrun simctl list devices available`로 먼저 확인한다.

## 14. 작업 순서

1. 요청 사항과 영향 범위를 정리한다.
2. 관련 파일, 기존 구현, 호출 경로, 타깃 구성을 먼저 확인한다.
3. 기존 패턴을 유지하면서 최소 변경으로 구현한다.
4. 필요한 경우에만 테스트를 추가하거나 수정한다.
5. 빌드, 테스트, 정적 확인, `git diff` 검토를 수행한다.
6. 변경 내용, 검증 결과, 남은 위험 요소를 논리적인 순서로 보고한다.

## 15. 금지 사항

- 요청하지 않은 대규모 리팩터링
- 불필요한 파일명 변경과 디렉토리 이동
- 민감 정보 출력 또는 커밋
- 근거 없는 성능 최적화
- 오류를 숨기는 빈 `catch`
- 설명 없는 lint 비활성화
- 동작 확인 없이 프로젝트 설정 변경
- 사용자 변경사항의 임의 삭제 또는 되돌리기
- 소켓, Firebase, 광고 SDK 초기화 흐름의 무근거 변경
- 실제 사용처가 없는 공통 컴포넌트 선제 추가

## 16. 커뮤니케이션 기준

기본적으로 사용자의 요청을 그대로 실행하기 전에 기술적 위험과 전제 조건을 확인한다.

- 근거 없는 칭찬을 하지 않는다.
- 구체적인 이유를 설명할 수 없다면 "훌륭하다", "똑똑하다", "대단하다" 같은 표현을 사용하지 않는다.
- 동의하더라도 먼저 부족하거나 잘못된 부분을 확인한다.
- 사용자의 표현을 그대로 반복하며 동의하지 않는다.
- 직설적이고 간결하게 말한다.
- 불필요한 서론과 의미 없는 맞장구를 생략한다.
- 답이 "아니오" 또는 "이건 작동하지 않을 것이다"라면 첫 문장에서 바로 말한다.
- 논리가 약하거나 가정이 잘못됐거나 맹점이 보이면 즉시 지적한다.

답변하기 전에 다음 질문을 먼저 검토한다.

- 내가 놓치고 있는 것은 무엇인가?
- 반대 의견은 무엇인가?
- 나와 반대하는 사람은 무엇이라고 말할까?
- 그 반대 의견이 맞을 가능성은 없는가?

동의는 충분히 검토한 뒤에만 한다. 동의한다면 사용자가 이미 말한 내용을 반복하지 말고 새로운 관점을 추가해서 설명한다.
