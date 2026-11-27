const day = 86_400_000;
const edgeQuota = 500_000;
const dbQuotaMB = 500;
const format = value => value.toLocaleString("ko-KR");
const percent = (value, quota) => (100 * value / quota).toFixed(1);
const isCount = value => Number.isSafeInteger(value) && value >= 0;

export async function usageReport(env, call, rpc, preview, now = Date.now()) {
  // UTC 09:30 = 한국 시간 18:30. 배포 검증 때는 현재 시점까지의 로그를 읽는다.
  const date = new Date(now);
  const slot = Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate(), 9, 30);
  const end = preview ? Math.floor(now / 60000) * 60000 : (slot > now ? slot - day : slot);
  const kstTime = new Date(end + 9 * 3600000).toISOString().slice(0, 16).replace("T", " ");
  const reportDay = kstTime.slice(0, 10);
  let calls = null;
  try {
    const token = env.get("MOBIT_USAGE_LOG_TOKEN");
    if (!token) throw Object.assign(new Error(), { reason: "missing-log-token" });
    const ref = new URL(env.get("SUPABASE_URL")).hostname.split(".")[0];
    const url = new URL(`https://api.supabase.com/v1/projects/${ref}/analytics/endpoints/logs`);
    url.searchParams.set("sql", "SELECT count() AS calls FROM logs WHERE source = 'function_edge_logs' AND log_attributes['request.method'] != 'OPTIONS'");
    url.searchParams.set("iso_timestamp_start", new Date(end - day).toISOString());
    url.searchParams.set("iso_timestamp_end", new Date(end).toISOString());
    const response = await (await call(url, { headers: { Authorization: "Bearer " + token } }, 20000)).json();
    const raw = response.result?.[0]?.calls;
    if (response.error) throw Object.assign(new Error(), { reason: "logs-query" });
    if (!(isCount(raw) || (typeof raw === "string" && /^\d+$/.test(raw) && isCount(Number(raw))))) {
      throw Object.assign(new Error(), { reason: "logs-response" });
    }
    calls = Number(raw);
  } catch (error) {
    if (preview) throw error;
  }

  let snapshot;
  try {
    const result = await (await rpc("mobit_usage_report", { p_day: reportDay, p_calls: calls, p_preview: preview })).json();
    if (!isCount(result.database_bytes) || !isCount(result.calls) || !isCount(result.days) || result.days > 30) throw new Error();
    snapshot = result;
  } catch (error) {
    if (preview) throw error;
  }
  const lines = [`모의비트 · Supabase 사용량 | ${kstTime} KST`];
  if (snapshot) {
    const mb = snapshot.database_bytes / 1_000_000;
    lines.push(`DB 용량  ${mb.toFixed(1)} / ${dbQuotaMB} MB (${percent(mb, dbQuotaMB)}%)`);
    if (mb >= dbQuotaMB * 0.7) lines.push("⚠️ DB 용량이 무료 한도의 70% 이상입니다.");
  } else {
    lines.push("⚠️ DB 용량과 누적 사용량 조회 실패");
  }
  lines.push(calls === null ? "⚠️ 최근 24시간 Edge 호출 조회 실패 · 로그 토큰과 권한을 확인하세요." : `최근 24시간 Edge 호출  ${format(calls)}회`);
  if (snapshot?.days) {
    const projected = Math.round(snapshot.calls * 30 / snapshot.days);
    lines.push(`최근 30일 중 ${snapshot.days}일 관측 합계  ${format(snapshot.calls)}회`,
      `30일 예상  ${format(projected)} / ${format(edgeQuota)}회 (${percent(projected, edgeQuota)}%)`);
    if (snapshot.calls >= edgeQuota * 0.7) lines.push("⚠️ 관측 합계가 월 무료 한도의 70% 이상입니다.");
    else if (projected >= edgeQuota * 0.7) lines.push("⚠️ 현재 속도라면 30일 예상 호출이 월 무료 한도의 70% 이상입니다.");
  }
  lines.push("Edge는 모의비트 프로젝트 로그 기준이며, 월 한도는 조직 전체가 공유합니다.");
  return lines.join("\n");
}
