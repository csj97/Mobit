"""투자 현황 정기 푸시, 거래소 급등락, 개인 보유자산 알림을 Supabase Cron에 등록한다."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from supabase_deploy import SupabaseProject

BASE = Path(__file__).resolve().parent
JOBS = {"mobit-weekly-push": "월요일 09:00", "mobit-weekly-push-sat": "토요일 19:00"}
FUNCTION = "send-mobit-push"


def account_secret(path):
    with (BASE.parent / "Mobit/Resource/GoogleService-Info.plist").open("rb") as file:
        project_id = plistlib.load(file)["PROJECT_ID"]
    account = json.loads(path.expanduser().read_text())
    if account.get("type") != "service_account" or account.get("project_id") != project_id:
        raise ValueError(f"{project_id} 프로젝트의 서비스 계정 JSON을 지정하세요.")
    fields = ("project_id", "client_email", "private_key")
    if not all(isinstance(account.get(key), str) and account[key] for key in fields):
        raise ValueError("서비스 계정 JSON에 이메일 또는 비공개 키가 없습니다.")
    return json.dumps({key: account[key] for key in fields})


def validate(endpoint, token):
    request = Request(endpoint, headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
                      data=b'{"mode":"validate"}')
    try:
        with urlopen(request, timeout=50) as response:
            if json.load(response).get("validated") is not True:
                raise RuntimeError("FCM 검증 응답을 확인할 수 없습니다.")
    except HTTPError as error:
        try:
            detail = json.load(error)
        except ValueError:
            detail = {}
        stage = detail.get("stage") if isinstance(detail, dict) else None
        stage = stage if stage in ("configuration", "google-oauth", "fcm") else "edge"
        raise RuntimeError(f"FCM 검증 실패 ({stage}, HTTP {error.code}). 서비스 계정 설정과 함수 로그를 확인하세요.") from None


def deploy(ref, path):
    secrets = {}
    if path:
        secrets["MOBIT_FCM_SERVICE_ACCOUNT"] = account_secret(path)
    project = SupabaseProject(ref)
    token = project.cron_token("mobit_push_cron_token")
    secrets["MOBIT_PUSH_CRON_TOKEN"] = token
    project.api("secrets", [{"name": key, "value": value} for key, value in secrets.items()])
    project.deploy_function(FUNCTION)
    endpoint = f"https://{ref}.supabase.co/functions/v1/{FUNCTION}"
    validate(endpoint, token)
    print("FCM 권한·메시지 검증 완료", flush=True)
    project.sql("do $setup$ begin\n" + (BASE / "push-cron.sql").read_text() + "\nend $setup$;")
    project.sql((BASE / "push-schedule.sql").read_text().replace("__PROJECT_REF__", project.ref))
    project.sql("do $setup$ begin\n" + (BASE / "price-alerts.sql").read_text() + "\nend $setup$;")
    holding_setup = "\n".join((BASE / name).read_text() for name in ("holding-alerts.sql", "holding-cron.sql"))
    project.sql("do $setup$ begin\n" + holding_setup + "\nend $setup$;")
    for job, function in (("mobit-price-alerts", "check_price_alerts"), ("mobit-holding-alerts", "check_holdings")):
        project.sql("""with task as (select format('select mobit_ops.%I(%L)', $2::text, $3::text) as cmd),
            existing as (select jobid from cron.job where jobname=$1 and username=current_user)
          select cron.alter_job(jobid, schedule := '* * * * *', command := cmd)::text from existing, task
          union all select cron.schedule($1,'* * * * *',cmd)::text from task
            where not exists (select 1 from existing)""", job, function, endpoint)
        status = project.sql("select active from cron.job where username=current_user and jobname=$1", job)
        if not status:
            raise RuntimeError(f"{job} 예약을 확인할 수 없습니다.")
        print(f"{job} 등록 완료 · " + ("활성" if status[0]["active"] else "일시 중지"))
    rows = project.sql("select jobname, active from cron.job where username=current_user and jobname in ($1,$2)", *JOBS)
    states = {row["jobname"]: row["active"] for row in rows}
    if states.keys() != JOBS.keys():
        raise RuntimeError("두 푸시 예약의 등록을 확인할 수 없습니다.")
    for name, time in JOBS.items():
        print(f"{name} 등록 완료 · 매주 {time} 한국 시간 · " + ("활성" if states[name] else "일시 중지"))
    project.sql((BASE / "cron-history.sql").read_text())
    cleanup = project.sql("select active from cron.job where jobname='mobit-cleanup-cron-history' and username=current_user")
    if not cleanup:
        raise RuntimeError("Cron 실행 기록 정리 예약을 확인할 수 없습니다.")
    print("mobit-cleanup-cron-history 등록 완료 · 매일 04:00 한국 시간 · " + ("활성" if cleanup[0]["active"] else "일시 중지"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-ref", default="bxuirfkxptypevhfnqrx")
    parser.add_argument("--service-account", type=Path, help="최초 배포 또는 키 교체 시 사용할 서비스 계정 JSON 경로")
    args = parser.parse_args()
    try:
        deploy(args.project_ref, args.service_account)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
