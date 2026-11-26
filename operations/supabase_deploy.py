"""운영 배치에서 공유하는 Supabase 배포 연결."""
import getpass
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.error import HTTPError
from urllib.request import Request, urlopen


class SupabaseProject:
    def __init__(self, ref):
        if not re.fullmatch(r"[a-z0-9]{20}", ref):
            raise ValueError("Supabase Project ref는 20자리 영문 소문자·숫자입니다")
        self.ref = ref
        self.access = os.environ.get("SUPABASE_ACCESS_TOKEN") or getpass.getpass("Supabase Access Token (숨김 입력): ")
        if not self.access:
            raise ValueError("Supabase Access Token이 필요합니다")

    def api(self, path, body):
        request = Request(f"https://api.supabase.com/v1/projects/{self.ref}/{path}",
                          headers={"Authorization": f"Bearer {self.access}", "Content-Type": "application/json"},
                          data=json.dumps(body).encode(), method="POST")
        try:
            with urlopen(request, timeout=45) as response:
                raw = response.read()
                return json.loads(raw) if raw.strip() else None
        except HTTPError as error:
            raise RuntimeError(f"Supabase {path} HTTP {error.code}. 대상 프로젝트와 토큰 권한을 확인하세요.") from None

    def sql(self, query, *parameters):
        return self.api("database/query", {"query": query, "parameters": list(parameters)})

    def cron_token(self, name):
        for extension in ("pg_cron", "pg_net", "supabase_vault"):
            self.sql(f"create extension if not exists {extension}")
        # 같은 이름으로 배포를 재시도해도 등록된 호출 토큰을 유지한다.
        if name not in ("mobit_coin_cron_token", "mobit_push_cron_token", "mobit_community_cron_token"):
            raise ValueError("지원하지 않는 예약 토큰입니다")
        self.sql(f"""do $$ begin
            perform pg_advisory_xact_lock(hashtextextended('{name}', 0));
            if not exists (select 1 from vault.secrets where name='{name}') then
              perform vault.create_secret(gen_random_uuid()::text || gen_random_uuid()::text, '{name}');
            end if;
          end $$""")
        return self.sql("select decrypted_secret from vault.decrypted_secrets where name=$1", name)[0]["decrypted_secret"]

    def deploy_function(self, name):
        subprocess.run(["npx", "--yes", "supabase@2.122.1", "functions", "deploy", name,
                        "--project-ref", self.ref, "--use-api", "--no-verify-jwt", "--yes"],
                       cwd=Path(__file__).resolve().parent,
                       env={**os.environ, "SUPABASE_ACCESS_TOKEN": self.access}, check=True)
