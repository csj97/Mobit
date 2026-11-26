"""Supabase 코인 배치 초기화. 터미널에는 상태와 집계만 출력한다."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from supabase_deploy import SupabaseProject

BASE = Path(__file__).resolve().parent
JOB = "mobit-refresh-coins"
FUNCTION = "refresh-mobit-coins"


def uploader_settings():
    folder = Path(os.environ.get("CMC_UPLOADER_DIR", BASE.parent.parent / "CMCToFirebase/CMCToFirebase"))
    with (folder / "GoogleService-Info.plist").open("rb") as file:
        settings = plistlib.load(file)
    with (BASE.parent / "Mobit/Resource/GoogleService-Info.plist").open("rb") as file:
        project = plistlib.load(file)["PROJECT_ID"]
    if settings["PROJECT_ID"] != project:
        raise ValueError("업로더와 앱의 Firebase 프로젝트가 다릅니다")
    source = (folder / "NetworkService.swift").read_text()
    match = re.search(r'^\s*private let apiKey\s*=\s*"([^"\n]+)"', source, re.MULTILINE)
    if not match:
        raise ValueError("기존 CMC API 키 선언을 찾지 못했습니다")
    # DATABASE_URL 생략 시 업로더의 Firebase iOS SDK와 같은 기본 인스턴스를 사용한다.
    database = settings.get("DATABASE_URL") or f"https://{project}-default-rtdb.firebaseio.com"
    return {"MOBIT_CMC_API_KEY": match[1], "MOBIT_FIREBASE_API_KEY": settings["API_KEY"],
            "MOBIT_DATABASE_URL": os.environ.get("MOBIT_DATABASE_URL", database)}


def firebase_writer(sql, api_key):
    name = "mobit_coin_firebase_writer"
    lookup = "select decrypted_secret from vault.decrypted_secrets where name=$1"
    existing = sql(lookup, name)
    if existing:
        return json.loads(existing[0]["decrypted_secret"]), False

    request = Request("https://identitytoolkit.googleapis.com/v1/accounts:signUp?" + urlencode({"key": api_key}),
                      headers={"Content-Type": "application/json"}, data=b'{"returnSecureToken":true}')
    try:
        with urlopen(request, timeout=20) as response:
            account = json.load(response)
    except HTTPError as error:
        raise RuntimeError(f"Firebase 배치 계정 생성 실패 (HTTP {error.code})") from None
    writer = {"uid": account["localId"], "refreshToken": account["refreshToken"]}
    try:
        sql("select vault.create_secret($1, $2)", json.dumps(writer), name)
    except RuntimeError:
        # 동시 배포나 응답 유실 시 먼저 저장된 UID를 그대로 사용한다.
        existing = sql(lookup, name)
        if not existing:
            raise
        return json.loads(existing[0]["decrypted_secret"]), False
    return writer, True


def deploy(ref, secrets):
    project = SupabaseProject(ref)
    sql = project.sql
    endpoint = f"https://{ref}.supabase.co/functions/v1/{FUNCTION}"
    print("예약 실행에 필요한 확장과 호출 토큰 확인", flush=True)
    secrets["MOBIT_COIN_CRON_TOKEN"] = project.cron_token("mobit_coin_cron_token")
    writer, created = firebase_writer(sql, secrets["MOBIT_FIREBASE_API_KEY"])
    print(f"Firebase 배치 UID: {writer['uid']}", flush=True)
    if created:
        print("Firebase Realtime Database 규칙에서 CMCResponse 아래 cryptoInformations, "
              "btc_cryptoInformations, exchanges 세 경로의 기존 .write 허용 목록에 이 UID를 추가하세요.")
        if not sys.stdin.isatty():
            raise RuntimeError("규칙 게시 후 같은 배포 명령을 다시 실행하세요. UID는 재사용됩니다.")
        input("규칙을 게시한 후 Enter를 누르세요: ")
    secrets["MOBIT_FIREBASE_REFRESH_TOKEN"] = writer["refreshToken"]
    project.api("secrets", [{"name": key, "value": value} for key, value in secrets.items()])

    print("코인 Edge Function 배포", flush=True)
    project.deploy_function(FUNCTION)
    # 파라미터 없는 DDL 묶음은 단일 트랜잭션으로 반영한다.
    sql("do $setup$ begin\n" + (BASE / "coin-cron.sql").read_text() + "\nend $setup$;")
    request_id = sql("select mobit_ops.enqueue_coin_refresh($1, true) as id", endpoint)[0]["id"]
    print(f"첫 갱신 확인 중 (요청 {request_id})", flush=True)
    deadline = time.monotonic() + 165
    while time.monotonic() < deadline:
        result = sql("select status_code, timed_out, content from net._http_response where id=$1", request_id)
        if not result:
            time.sleep(3)
            continue
        response = result[0]
        if response["status_code"] != 200 or response["timed_out"]:
            try:
                detail = json.loads(response["content"] or "{}")
            except ValueError:
                detail = {}
            stage = detail.get("stage") if isinstance(detail, dict) else None
            code = detail.get("code") if isinstance(detail, dict) else None
            if stage not in ("configuration", "quotes", "firebase-token", "firebase-signup", "firebase-patch"):
                stage = "unknown"
            status = code if isinstance(code, str) and re.fullmatch(r"[0-9]{3}", code) else "unknown"
            raise RuntimeError(f"코인 갱신 실패 (HTTP {response['status_code']}, 단계 {stage}, 원격 HTTP {status}). "
                               "Edge Function 로그를 확인하세요.")
        summary = json.loads(response["content"])
        if not isinstance(summary.get("updatedPaths"), int) or summary["updatedPaths"] <= 0:
            raise RuntimeError("코인 갱신 결과에 저장 경로 수가 없습니다")
        print(f"저장 경로 {summary['updatedPaths']}개, 제외 {summary['skippedCount']}건")
        break
    else:
        raise RuntimeError(f"요청 {request_id} 응답 확인 시간 초과. Edge Function 로그를 확인하세요.")
    # 동일 이름으로 재배포하면 기존 작업을 갱신한다. Cron 기준 시간대도 검사한다.
    zone = sql("select coalesce(nullif(current_setting('cron.timezone', true), ''), 'GMT') as zone")[0]["zone"]
    if zone not in ("UTC", "GMT", "Etc/UTC", "Etc/GMT", "Asia/Seoul"):
        raise ValueError(f"지원하지 않는 Cron 시간대 {zone}. 프로젝트 Cron 시간대를 확인하세요.")
    hours = "9,18" if zone == "Asia/Seoul" else "0,9"
    sql("select cron.schedule($1::text, $2::text, format('select mobit_ops.enqueue_coin_refresh(%L)', $3::text))",
        JOB, f"5,10,15 {hours} * * *", endpoint)
    print(f"{JOB} 등록 완료 · 매일 09:05·18:05 한국 시간, 실패 시 각 회차 5분·10분 뒤 재시도")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--project-ref")
    mode.add_argument("--preview", action="store_true", help="거래소와 CMC 조회만 실행")
    args = parser.parse_args()
    settings = uploader_settings()
    if args.preview:
        subprocess.run(["node", str(BASE / "preview.mjs")], check=True,
                       env={**os.environ, "MOBIT_CMC_API_KEY": settings["MOBIT_CMC_API_KEY"]})
    else:
        deploy(args.project_ref, settings)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, URLError, subprocess.CalledProcessError) as exc:
        sys.exit(str(exc))
