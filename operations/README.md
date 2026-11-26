# 모의비트 운영 자동화

| 운영 작업 | 실행 조건 | 결과 |
| --- | --- | --- |
| 거래소 코인 정보 | 매일 09:05·18:05 한국 시간 | 업비트·빗썸 KRW/BTC 마켓의 CMC 정보를 Realtime Database에 갱신 |
| 이용자 정기 푸시 | 매주 월요일 09:00·토요일 19:00 한국 시간 | 토픽을 구독한 기기에 투자 현황 안내를 보내고 투자내역 탭으로 이동 |
| 원화 마켓 급등락 푸시 | 5분마다 거래소 시세 조회 | 1시간 전 대비 또는 거래소 전일 종가 대비 기준에 도달하면 급등락 구독 기기에 발송 |
| 개인 보유자산 알림 | 등록 기기의 활성 보유 마켓을 조회 | 평단·포지션 기준 새 5%p 단계에 도달하면 해당 기기에 발송 |

## 1. 코인 갱신 배포 (Firebase Spark)

1. [Supabase 대시보드](https://supabase.com/dashboard)에서 사용할 프로젝트를 선택하거나 만든다. 주소의 `/project/<project-ref>`에서 ref를 확인한다. [Access Tokens](https://supabase.com/dashboard/account/tokens)에서 해당 프로젝트의 Edge Function 배포·시크릿 저장·SQL 실행 권한이 있는 개인 액세스 토큰을 준비한다.
2. 이 Mac의 모의비트 저장소 루트에서 아래 명령을 실행하고 물어볼 때 토큰을 입력한다. 스크립트는 토큰을 파일에 저장하지 않는다. 이 Mac의 npx로 검증된 버전의 공식 Supabase CLI를 실행한다.

```sh
python3 operations/deploy-coins.py --project-ref <project-ref>
```

처음 실행하면 스크립트가 `Firebase 배치 UID`를 출력하고 기다린다. Firebase 콘솔 → Realtime Database → 규칙에서 `CMCResponse` 아래의 `cryptoInformations`, `btc_cryptoInformations`, `exchanges` 세 경로를 찾는다. 각 경로의 기존 `.write` 조건에서 마지막 닫는 괄호 바로 앞에 ` || auth.uid === '출력된 UID'`를 추가한다. 기존 UID를 모두 유지한 채 규칙을 게시하고 터미널에서 Enter를 누른다. 이후 배포에도 같은 UID를 사용한다.

배포 명령은 **첫 운영 DB 갱신을 즉시 실행**한다. Edge Function이 Firebase 쓰기에 성공해 저장 건수를 반환하면 매일 09:05·18:05 한국 시간 예약을 등록한다. 같은 프로젝트에 재실행하면 같은 이름의 함수와 예약을 갱신한다. Free 프로젝트는 비활성 일시정지 정책과 함수당 실행 시간 150초가 적용된다. [Supabase 예약 함수](https://supabase.com/docs/guides/functions/schedule-functions) · [실행 제한](https://supabase.com/docs/guides/functions/limits) · [요금제](https://supabase.com/pricing)

### 자동으로 가져오는 설정

- 인접한 `../CMCToFirebase/CMCToFirebase`에서 기존 CMC 키와 Firebase plist를 읽고 앱 프로젝트 ID가 일치하는지 검사한다. 소스 위치가 바뀌면 `CMC_UPLOADER_DIR`를 지정한다.
- DB 주소는 plist의 `DATABASE_URL` 또는 기존 Firebase iOS SDK의 기본 인스턴스 주소를 사용한다. 인스턴스를 별도로 지정해 운영할 때만 `MOBIT_DATABASE_URL`을 지정한다.
- 배포 스크립트가 Firebase 익명 계정을 한 번 생성하고 UID와 갱신 토큰을 Supabase Vault에 보관한다. Edge Function은 함수 시크릿에 등록된 갱신 토큰으로 같은 계정의 ID 토큰을 발급받는다. 인증·쓰기 권한이 거부되면 첫 배포의 예약 등록을 중단한다. 인증 실패 단계는 함수 로그에서 확인한다.
- CMC 키와 Firebase 연결 값은 Supabase 함수 시크릿에, Cron 호출 전용 토큰은 Vault와 함수 시크릿에 등록한다. Cron 작업과 응답 상태는 전용 스키마 `mobit_ops`에서 관리한다.

### 운영 확인

- 배포 전에 실데이터 조회만 하려면 저장소 루트에서 `python3 operations/deploy-coins.py --preview`를 실행한다. CMC 조회 크레딧을 사용하고 마켓별 건수와 미매칭 경로를 출력한다.
- 업비트·빗썸 KRW/BTC와 구버전 업비트 두 경로를 한 번의 Firebase PATCH로 갱신한다. 미매칭·필수 필드 누락 종목은 기존 값을 보존한다.
- 각 회차의 첫 호출이 실패하거나 응답이 없으면 5분 뒤 재시도하고, 필요하면 10분 뒤 한 번 더 시도한다. 오전 회차 성공 여부와 관계없이 오후 18:05에 다시 갱신한다. Supabase Cron의 실행 성공은 HTTP 요청을 큐에 넣었다는 뜻이다. 실제 반영은 **Edge Functions → refresh-mobit-coins → Logs**의 ‘코인 정보 갱신 완료’와 저장 건수로 확인한다. 예약을 중지하려면 Cron에서 `mobit-refresh-coins`를 비활성화한다.

## 2. Supabase 정기 푸시 배포 (Firebase Spark)

월요일 09:00에는 `mobit-weekly-push`, 토요일 19:00에는 `mobit-weekly-push-sat`가 한국 시간 기준으로 `send-mobit-push`를 호출한다. 메시지는 ‘이번 주 모의투자 현황 / 모의비트에서 보유 자산과 수익률을 확인하세요.’이며, 기존 `type=route`, `destination=investment`, `campaign_id=weekly_portfolio`를 사용한다. [앱의 푸시 수신 규약](../README.md#fcm-푸시-설정)

1. MOBIT Firebase 프로젝트의 [Google Cloud 서비스 계정](https://console.cloud.google.com/iam-admin/serviceaccounts?project=mobit-68833)에서 푸시 발송용 계정을 만들고 **Firebase Cloud Messaging API Admin** 역할을 부여한다. 같은 계정의 **키 → 키 추가 → 새 키 만들기 → JSON**을 선택해 저장소 밖에 보관한다. 프로젝트의 [Firebase Cloud Messaging API](https://console.cloud.google.com/apis/library/fcm.googleapis.com?project=mobit-68833)가 꺼져 있으면 활성화한다. [FCM 서버 인증](https://firebase.google.com/docs/cloud-messaging/send/v1-api)
2. 저장소 루트에서 아래 명령에 실제 JSON 경로를 지정하고 기존 Supabase Access Token을 숨김 입력한다. 다음 배포부터는 키를 교체할 때만 `--service-account`가 필요하다.

   ```sh
   python3 operations/deploy-push.py --service-account "$HOME/Downloads/발급받은파일.json"
   ```

3. 알림 설정이 포함된 iOS 버전을 배포한다. 그 버전을 실행하고 알림을 허용한 기기는 기본적으로 앱 공지(`mobit_announcements`)와 급등락 알림(`mobit_price_alerts`)을 모두 구독한다. 사용자는 **더보기 → 알림**에서 각각 끌 수 있다. 기기 설정에서 권한을 끈 후 앱에 돌아오면 두 구독을 해제한다. 기존 APNs 키와 Firebase 앱 설정을 사용한다.

배포 명령은 푸시 전용 호출 토큰을 Vault와 함수 시크릿에 저장하고, 서비스 계정 인증 정보를 함수 시크릿에 등록한다. [FCM 검증 전용 요청](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages/send) 성공 후에만 Cron 예약을 등록한다. 최초 실제 발송은 다음 예약 시간이다. 같은 이름으로 재배포하면 기존 활성·중지 상태를 유지한다.

- [모의비트 Cron Jobs](https://supabase.com/dashboard/project/bxuirfkxptypevhfnqrx/integrations/cron/jobs)에서 투자 현황은 두 주간 작업, 급등락은 `mobit-price-alerts`의 Active 스위치로 중지·재개한다. 코인 정보 갱신은 `mobit-refresh-coins`에서 별도 관리한다.
- Edge Function 로그의 ‘FCM 예약 푸시 발송 요청 접수’는 FCM이 요청을 수락했다는 뜻이다. 중복 알림 방지를 위해 결과가 불명확한 발송은 자동 재전송하지 않는다. 같은 내용의 Firebase 콘솔 캠페인을 운영 중이라면 두 예약이 겹치는지 확인한다.
- 푸시 문구와 이동 정보는 [campaign.json](supabase/functions/send-mobit-push/campaign.json)에서 수정한 뒤 푸시 배포 명령으로 반영한다.

### 내 iPhone에 급등락 테스트 푸시 보내기

이 명령은 Mac에서 기존 서비스 계정으로 FCM에 직접 요청해, 입력한 기기 한 대에만 예시 알림을 한 건 보낸다.

1. 테스트할 iPhone에서 모의비트의 알림을 허용하고 그 기기의 FCM 등록 토큰을 준비한다. 토큰 확인 방법은 [앱 README의 FCM 푸시 설정](../README.md#fcm-푸시-설정) 6번에 있다.
2. 운영용 Mac의 터미널에 아래 명령을 붙여넣는다. 다른 Mac에서는 저장소와 서비스 계정 JSON 경로를 해당 Mac의 위치로 바꾼다.

   ```bash
   cd "$HOME/Documents/csj_dev/Mobit" && \
     node operations/test-device-push.mjs "$HOME/Documents/csj_dev/Mobit Documents/운영 인증 정보/Firebase/FCM 예약 발송/mobit-68833-6f66d0d1db92.json"
   ```

3. `테스트 기기 FCM 토큰 (숨김 입력)` 안내가 뜨면 토큰을 붙여넣고 Enter를 누른다. 입력 중에는 글자가 표시되지 않는다.
4. 터미널에 `FCM이 단일 기기 테스트 푸시 1건을 접수했습니다.`가 뜨면 FCM 접수가 완료된 것이다. 실제 수신은 iPhone의 배너나 알림 센터에서 **[테스트] 빗썸 BTC 가격 변동**을 확인한다.

### 급등락 감시 기준

- 업비트와 빗썸의 원화 BTC·ETH·SOL·TRX·AVAX·HYPE를 거래소별로 조회한다. 시세 출처는 두 거래소의 공개 API이며 CMC 크레딧 소모는 없다. 거래소에서 404를 반환한 마켓은 한 시간 뒤 다시 확인한다.
- Cron은 매분 실행되며 5분마다 시세를 요청하고 다음 실행부터 응답을 처리한다. 알림의 시간대는 한국 시간의 관측 구간이다.
- **1시간 대비**는 매시 정각에 같은 거래소·마켓의 직전 정각 가격과 비교한다. 09→10시와 10→11시에 각각 5% 올랐다면 두 구간 모두 발송한다. 직전 정각 가격이 없으면 그 회차의 시간 알림을 건너뛴다.
- **전일 종가 대비**는 5분마다 거래소 제공 등락률(`signed_change_rate`)을 확인한다. 거래일 안에서 상승·하락을 따로 기록하며 +5% → +10% → +5% → +10%에서는 처음 두 번만 보낸다. 기록은 한국 시간으로 업비트 오전 9시, 빗썸 자정에 새 거래일로 넘어간다. [업비트 현재가](https://docs.upbit.com/kr/reference/list-quote-tickers) · [빗썸 현재가](https://apidocs.bithumb.com/v2.1.0/reference/현재가-조회)
- 각 기준에서 넘은 가장 높은 5% 단계를 표시한다. +17%라면 ‘15% 이상’으로 안내한다. 같은 정각·거래소·종목에서 둘 다 발송 대상이면 푸시 한 건에 시간 구간과 전일 기준을 함께 적는다. 방향이 엇갈리면 제목은 ‘가격 변동’이다.
- 아래 예시는 두 거래소의 BTC에만 1시간 전 기준을 3%p 간격(3·6·9%), 거래소 기준을 7%p 간격(7·14·21%)으로 적용한다. SQL Editor에서 바꾸면 다음 판정부터 적용되며 재배포해도 값이 유지된다.

```sql
update mobit_ops.price_rule
set hour_percent = 3, exchange_percent = 7
where market = 'KRW-BTC';
```

### 개인 보유자산 알림 서버

개인 알림은 수익 단계에 따라 ‘보유자산 상승 / 업비트 비트코인(BTC) +5% 수익’ 또는 ‘보유자산 하락 / 빗썸 이더리움(ETH) -10% 손실’로 표시한다. 숏도 보유 건의 수익률을 기준으로 표시한다. 종목명은 거래소의 마켓 목록에서 읽으며 이름을 확인할 수 없으면 심볼만 표시한다.

푸시 배포 스크립트는 `mobit-cleanup-cron-history`도 등록한다. 매일 한국 시간 04:00에 현재 등록된 모의비트 작업(코인 갱신, 주간 푸시 2개, 시세·보유자산 알림, 정리 작업)의 Cron 실행 기록 중 종료 후 7일이 지난 행만 삭제한다. 중지·재개는 Supabase Cron에서 이 작업의 Active 스위치로 관리한다.

저장소 루트에서 `python3 operations/deploy-push.py`를 실행하면 기존 서비스 계정으로 Edge Function, 개인 알림 테이블·RPC, 별도 Cron `mobit-holding-alerts`를 배포한다. 최초 등록 시 활성화되고 재배포 시 기존 활성 상태를 유지한다. 실기기에서 테스트하기 전에 프로젝트의 **Authentication → Sign In / Providers → Anonymous Sign-Ins**와 **Data API**를 활성화한다. 앱은 publishable key와 익명 로그인 세션을 사용한다. 개인 테이블은 비공개이며 발송용 RPC는 서비스 역할만 호출할 수 있다. [Supabase 익명 인증](https://supabase.com/docs/guides/auth/auth-anonymous)

**앱이 호출할 RPC**는 `/rest/v1/rpc/` 아래에 있다. 요청의 소유자는 인증된 세션에서 결정한다. 날짜는 시간대가 있는 ISO 8601, 금액과 비율 계수는 정밀도를 보존하는 십진 문자열로 전달한다.

| RPC | 값과 동작 |
| --- | --- |
| `mobit_set_push_device` | `p_revision`, `p_token`. 개인 알림 허용·FCM 토큰 교체 시 등록하고, 해제 시 토큰에 null을 보낸다. 기기 등록용 순번과 보유 건별 순번을 따로 증가시킨다. |
| `mobit_sync_holding` | 공통 필드는 `p_holding`(보유 건 UUID), `p_revision`, `p_closed`, `p_effective_at`(체결 시각). 열려 있는 보유 건은 `p_exchange`(upbit/bithumb), `p_market`, `p_side`(spot/long/short), `p_fill_price`도 보낸다. |
| 현물 추가 필드 | `p_average`는 체결 후 평균 매수가다. 동일 평단의 부분 매도는 생략할 수 있다. 현물은 KRW·BTC 마켓의 호가 통화로 계산한다. |
| 선물 추가 필드 | `p_units : p_cost : p_margin`은 남은 수량·남은 진입원가 합계·잔여 진입증거금의 **정확한 비**다. 세 값을 같은 양수로 스케일해도 된다. 수량÷증거금을 반올림한 소수나 반올림한 평단을 전송하면 경계가 달라진다. 현재 국내 KRW 모의 선물 규칙(수수료·펀딩 0)에 적용한다. |
| 전량 매도·청산 | 공통 필드와 `p_closed=true`를 보낸다. 종료가 최초 요청이어도 기록을 남겨 지연된 매수로 되살아나지 않는다. 재진입은 새 보유 건 UUID를 쓴다. |

예를 들어 빗썸 BTC 현물 평단을 9천만 원으로 갱신할 때의 요청 본문은 다음과 같다.

```json
{"p_holding":"98765432-0000-4000-8000-0123456789ab","p_revision":2,"p_closed":false,
 "p_effective_at":"2026-11-25T10:00:00+09:00","p_exchange":"bithumb","p_market":"KRW-BTC",
 "p_side":"spot","p_fill_price":"80000000","p_average":"90000000"}
```

- 앱의 **더보기 → 알림 → 보유자산 수익률 알림**을 켜면 커밋된 현물·국내 선물 원장에서 감시 조건을 만든다. 앱은 네트워크 요청 전 변경 순번과 전송 대기를 파일에 보관하며, 재실행·연결 복구 시 원장을 다시 비교한다. 익명 세션은 기기 Keychain에 보관한다. 서버는 변경 순번과 거래 시각을 확인하고 체결 가격에서 이미 넘은 단계는 발송 없이 기록한다.
- 기기가 등록한 활성 보유 건이 있을 때만 공개 1분봉을 조회한다. 같은 거래소·마켓은 기기 간 조회를 공유한다. Cron은 매분 실행하며 마켓당 통상 5분 간격으로 조회한다. 거래소당 한 회에 최대 5개 요청을 처리하므로 마켓 수에 따라 간격이 길어질 수 있다. 알림은 최신 완료 분봉의 종가에서 도달한 최고 5%p 단계만 방향별로 보낸다.
- 선물은 직전 검증 시각부터 분봉 고가·저가를 먼저 확인한다. 수집 공백이나 증거금 소진 가능성이 있으면 개인 푸시를 보류한다. 진입한 분의 고가·저가는 체결 이전일 수 있어 서버에서 청산을 확정하지 않는다. 앱에서 과거 이력을 검증한 뒤 종료를 동기화하거나, 생존을 확인한 시각·가격과 새 순번으로 스냅샷을 동기화한다. 오래된 구간은 나눠서 따라잡고 과거 수익 알림은 보내지 않는다.
- 발송 직전까지 보유 건·기기 순번이 유효한지 다시 확인하고, 한 이벤트는 한 번만 인수한다. 인수 전 전달 실패는 유효 시간 안에 재시도한다. FCM 요청 결과가 불명확한 경우 중복 발송을 피하기 위해 인수한 메시지를 다시 보내지 않는다. 오프라인 전량 매도는 서버에 도착한 시점부터 반영된다.
- SQL Editor에서 `select exchange, market, count(*) filter (where paused) as paused, count(*) as holdings from mobit_ops.holding_watch where not closed group by exchange, market;`로 청산 검증 보류 건수를 확인한다. 개인 알림만 중지하려면 Cron에서 `mobit-holding-alerts`를 끈다.

**실기기 확인** — 알림을 허용한 뒤 개인 알림 스위치를 켠다. 등록에 실패하면 스위치가 꺼지고 팝업 하단에 오류가 표시된다. 현물을 매수한 뒤 SQL Editor에서 아래 쿼리로 토큰을 노출하지 않고 최근 변경을 확인할 수 있다. 추가 매수로 평단이 바뀌면 순번이 증가하고 전량 매도하면 `closed`가 true가 된다. 단순 매수만으로는 푸시가 발송되지 않는다.

```sql
select exchange, market, side, revision, closed, paused, effective_at
from mobit_ops.holding_watch
order by revision desc
limit 10;
```
