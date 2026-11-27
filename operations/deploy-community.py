"""커뮤니티 새 글을 받을 개인 텔레그램 채팅을 연결하고 매일 한국 시간 오전 9시 배치를 배포한다."""
import argparse
import getpass
import json
from pathlib import Path
import re
import secrets
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from supabase_deploy import SupabaseProject

BASE = Path(__file__).resolve().parent
JOB = "mobit-community-alerts"
FUNCTION = "notify-community"


def telegram(token, method, payload=None):
    request = Request(f"https://api.telegram.org/bot{token}/{method}", method="POST",
                      data=json.dumps(payload or {}).encode(), headers={"Content-Type": "application/json"})
    try:
        with urlopen(request, timeout=15) as response:
            result = json.load(response)
    except HTTPError as error:
        raise RuntimeError(f"Telegram {method} HTTP {error.code}. BotFather 토큰과 봇 상태를 확인하세요.") from None
    except (OSError, ValueError):
        raise RuntimeError(f"Telegram {method} 응답을 확인하지 못했습니다.") from None
    if result.get("ok") is not True:
        raise RuntimeError(f"Telegram {method} 요청을 처리하지 못했습니다.")
    return result["result"]


def private_chat(updates, code):
    for update in updates:
        message = update.get("message", {})
        chat = message.get("chat", {})
        if (message.get("text") == "/start " + code and chat.get("type") == "private"
                and isinstance(chat.get("id"), int) and chat["id"] == message.get("from", {}).get("id")):
            return str(chat["id"])
    return None


def connect_bot():
    token = getpass.getpass("BotFather 봇 토큰 (숨김 입력): ").strip()
    if not re.fullmatch(r"[0-9]+:[A-Za-z0-9_-]+", token):
        raise ValueError("BotFather가 발급한 봇 토큰 형식을 확인하세요.")
    bot = telegram(token, "getMe")["username"]
    if telegram(token, "getWebhookInfo").get("url"):
        raise RuntimeError("이 봇은 다른 웹훅을 사용 중입니다. 새로 만든 커뮤니티 알림 봇의 토큰을 입력하세요.")
    code = secrets.token_urlsafe(16)
    print(f"본인 텔레그램에서 이 링크를 열고 시작(Start)을 누르세요.\nhttps://t.me/{bot}?start={code}")
    print(f"이미 대화 중이면 @{bot} 개인 채팅에 /start {code} 를 보내도 됩니다.")
    input("완료한 뒤 Enter: ")
    for _ in range(3):
        chat = private_chat(telegram(token, "getUpdates", {"limit": 100, "timeout": 2}), code)
        if chat:
            return token, chat
        time.sleep(1)
    raise RuntimeError("이번 실행의 연결 코드가 담긴 개인 메시지를 찾지 못했습니다. 다시 실행하고 새 링크를 열어 주세요.")


def initialize(endpoint, token):
    request = Request(endpoint, data=b'{"mode":"initialize"}',
                      headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    for attempt in range(4):
        try:
            with urlopen(request, timeout=30) as response:
                if json.load(response) == {"mode": "initialize", "delivered": 0}:
                    return
            raise RuntimeError("커뮤니티 기준점 초기화 응답을 확인할 수 없습니다.")
        except HTTPError as error:
            if attempt == 3:
                raise RuntimeError(f"커뮤니티 기준점 초기화 실패 (HTTP {error.code}). 함수 로그를 확인하세요.") from None
        time.sleep(3)


def daily_schedule(zone, hour=9, minute=0):
    if zone == "Asia/Seoul":
        return f"{minute} {hour} * * *"
    if zone in ("UTC", "GMT", "Etc/UTC", "Etc/GMT"):
        return f"{minute} {(hour - 9) % 24} * * *"
    raise ValueError(f"지원하지 않는 Cron 시간대 {zone}. 프로젝트 Cron 시간대를 확인하세요.")


def existing_connection(ref):
    project = SupabaseProject(ref)
    rows = project.sql("select decrypted_secret from vault.decrypted_secrets where name=$1", "mobit_community_cron_token")
    if not rows:
        raise RuntimeError("커뮤니티 알림을 먼저 등록하세요. --deploy-and-test로 첫 배포와 테스트를 함께 할 수 있습니다.")
    return f"https://{ref}.supabase.co/functions/v1/{FUNCTION}", rows[0]["decrypted_secret"]


def send_admin_message(endpoint, token, mode="test"):
    request = Request(endpoint, data=json.dumps({"mode": mode}).encode(),
                      headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    # 응답만 유실됐을 수 있으므로 테스트 메시지는 자동 재시도하지 않는다.
    try:
        with urlopen(request, timeout=45) as response:
            receipt = json.load(response)
    except HTTPError as error:
        if mode == "usage-now":
            if error.code in (400, 404):
                raise RuntimeError("즉시 발송 기능을 먼저 --usage-report 옵션으로 배포하세요.") from None
            raise RuntimeError(usage_preview_error(error) + " 재실행 전 관리자 봇 대화방을 확인하세요.") from None
        if error.code in (400, 404):
            raise RuntimeError("테스트 기능을 먼저 배포하세요. --deploy-and-test로 배포 후 한 건을 보낼 수 있습니다.") from None
        raise RuntimeError(f"테스트 메시지 접수 확인 실패 (HTTP {error.code}). 봇 대화방과 함수 로그를 확인하세요.") from None
    except (OSError, ValueError):
        raise RuntimeError("발송 응답을 확인하지 못했습니다. 다시 실행하기 전에 관리자 봇 대화방을 확인하세요.") from None
    message_id = receipt.get("message_id") if isinstance(receipt, dict) and receipt.get("mode") == mode else None
    if type(message_id) is not int or message_id <= 0:
        raise RuntimeError("텔레그램 메시지 번호를 확인하지 못했습니다. 관리자 봇 대화방을 확인하세요.")
    print(f"텔레그램 관리자 개인 채팅 발송 접수 완료 · 메시지 번호 {message_id}")


def register_job(project, job, schedule, command):
    # 재배포할 때 운영자가 중지한 작업은 중지 상태를 유지한다.
    project.sql("""with existing as (select jobid from cron.job where jobname=$1 and username=current_user)
      select cron.alter_job(jobid, schedule := $2::text, command := $3::text)::text from existing
      union all select cron.schedule($1::text,$2::text,$3::text)::text where not exists(select from existing)""",
                job, schedule, command)
    state = project.sql("select active,schedule from cron.job where jobname=$1 and username=current_user", job)
    if len(state) != 1 or state[0]["schedule"] != schedule:
        raise RuntimeError(f"{job} 등록 상태를 확인하지 못했습니다.")
    return "활성" if state[0]["active"] else "일시 중지"


def usage_preview_error(error):
    try:
        details = json.loads(error.read(4096))
    except (ValueError, UnicodeError):
        details = {}
    if not isinstance(details, dict):
        details = {}
    stage = details.get("stage")
    labels = {"usage-logs": "Edge 호출 로그 조회", "mobit_usage_report": "DB 사용량 조회",
              "configuration": "함수 Secrets 확인", "telegram": "텔레그램 발송 접수 확인"}
    upstream = details.get("upstream_status")
    label = labels.get(stage, "사용량 미리보기") if isinstance(stage, str) else "사용량 미리보기"
    status = f"원격 HTTP {upstream}" if type(upstream) is int else f"함수 HTTP {error.code}"
    reason = details.get("reason")
    if reason == "missing-log-token":
        hint = "두 번째 입력란에 Logs 읽기 전용 토큰을 입력하세요."
    elif stage == "usage-logs" and upstream in (401, 403):
        hint = "로그 토큰의 만료 여부와 mobit 프로젝트의 Logs → Read 권한을 확인하세요."
    elif reason == "timeout":
        hint = "원격 요청이 시간 내에 완료되지 않았습니다."
    elif reason == "logs-query" or (stage == "usage-logs" and upstream == 400):
        hint = "Supabase Logs API가 조회 쿼리를 거절했습니다."
    elif reason == "logs-response":
        hint = "Supabase Logs API 응답에서 호출 수를 읽을 수 없습니다."
    else:
        hint = "notify-community 함수 로그를 확인하세요."
    return f"{label} 실패 ({status}). {hint}"


def deploy_usage(ref):
    project = SupabaseProject(ref)
    rows = project.sql("select decrypted_secret from vault.decrypted_secrets where name=$1", "mobit_community_cron_token")
    if not rows:
        raise RuntimeError("관리자 텔레그램 봇을 deploy-community.py로 먼저 연결하세요.")
    zone = project.sql("select coalesce(nullif(current_setting('cron.timezone',true),''),'GMT') as zone")[0]["zone"]
    schedule = daily_schedule(zone, 18, 30)
    log_token = getpass.getpass("모의비트 Logs 읽기 전용 토큰 (숨김 입력, 기존 값 재사용은 Enter): ").strip()
    if log_token:
        project.api("secrets", [{"name": "MOBIT_USAGE_LOG_TOKEN", "value": log_token}])
    project.sql("do $setup$ begin\n" + (BASE / "usage-report.sql").read_text() + "\nend $setup$;")
    project.deploy_function(FUNCTION)
    endpoint = f"https://{ref}.supabase.co/functions/v1/{FUNCTION}"
    request = Request(endpoint, data=b'{"mode":"usage-preview"}',
                      headers={"Authorization": "Bearer " + rows[0]["decrypted_secret"], "Content-Type": "application/json"})
    for attempt in range(4):
        try:
            with urlopen(request, timeout=45) as response:
                if json.load(response) != {"mode": "usage-preview"}:
                    raise RuntimeError("사용량 미리보기 응답을 확인하지 못했습니다.")
            break
        except HTTPError as error:
            if attempt == 3:
                raise RuntimeError(usage_preview_error(error)) from None
            time.sleep(3)
    state = register_job(project, "mobit-usage-report", schedule, f"select mobit_ops.enqueue_usage_report('{endpoint}')")
    project.sql((BASE / "cron-history.sql").read_text())
    print(f"mobit-usage-report 등록 완료 · 매일 오후 6시 30분(한국 시간) · {state}")
    return endpoint, rows[0]["decrypted_secret"]


def deploy(ref, reconnect=False):
    project = SupabaseProject(ref)
    token = project.cron_token("mobit_community_cron_token")
    zone = project.sql("select coalesce(nullif(current_setting('cron.timezone',true),''),'GMT') as zone")[0]["zone"]
    schedule = daily_schedule(zone)
    existing = project.sql("select jobid from cron.job where jobname=$1 and username=current_user", JOB)
    settings = {"MOBIT_COMMUNITY_CRON_TOKEN": token}
    if not existing or reconnect:
        bot, chat = connect_bot()
        settings.update(MOBIT_TELEGRAM_BOT_TOKEN=bot, MOBIT_TELEGRAM_CHAT_ID=chat)
    project.api("secrets", [{"name": name, "value": value} for name, value in settings.items()])
    if existing:
        # 함수 교체 중 기존 5분 일정이 새 요약을 발송하지 않게 먼저 변경한다.
        project.sql("select cron.alter_job($1::bigint, schedule := $2::text)", existing[0]["jobid"], schedule)
    project.sql("do $setup$ begin\n" + (BASE / "community-alerts.sql").read_text() + "\nend $setup$;")
    project.deploy_function(FUNCTION)
    endpoint = f"https://{ref}.supabase.co/functions/v1/{FUNCTION}"
    initialize(endpoint, token)
    state = register_job(project, JOB, schedule, f"select mobit_ops.enqueue_community_alerts('{endpoint}')")
    project.sql((BASE / "cron-history.sql").read_text())
    print(f"{JOB} 등록 완료 · 매일 오전 9시(한국 시간) · {state}")
    return endpoint, token


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-ref", default="bxuirfkxptypevhfnqrx")
    parser.add_argument("--reconnect", action="store_true", help="기존 봇 또는 수신 채팅을 다시 연결")
    parser.add_argument("--usage-now", action="store_true", help="현재 사용량 보고서 한 건을 즉시 발송")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--usage-report", action="store_true", help="기존 관리자 봇으로 매일 18:30 KST에 Supabase 사용량 발송")
    mode.add_argument("--test-only", action="store_true", help="이미 배포한 함수로 관리자 테스트 메시지 1건 발송")
    mode.add_argument("--deploy-and-test", action="store_true", help="배포 성공 후 관리자 테스트 메시지 1건 발송")
    args = parser.parse_args()
    if args.usage_now and (args.reconnect or args.test_only or args.deploy_and_test):
        parser.error("--usage-now는 단독으로 또는 --usage-report와 함께 사용하세요.")
    if args.usage_report and args.reconnect:
        parser.error("--usage-report는 기존 관리자 봇을 사용합니다.")
    if args.test_only and args.reconnect:
        parser.error("--test-only는 기존 수신 채팅을 사용합니다. 재연결은 --deploy-and-test와 함께 실행하세요.")
    try:
        if args.usage_report:
            connection = deploy_usage(args.project_ref)
            if args.usage_now:
                send_admin_message(*connection, mode="usage-now")
        elif args.usage_now:
            send_admin_message(*existing_connection(args.project_ref), mode="usage-now")
        elif args.test_only:
            send_admin_message(*existing_connection(args.project_ref))
        else:
            connection = deploy(args.project_ref, args.reconnect)
            if args.deploy_and_test:
                send_admin_message(*connection)
    except (OSError, ValueError, RuntimeError, URLError, subprocess.CalledProcessError) as exc:
        sys.exit(str(exc))
