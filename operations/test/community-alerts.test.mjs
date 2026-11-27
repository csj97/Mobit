import assert from "node:assert/strict";
import { test } from "node:test";
import { notifyCommunity } from "../supabase/functions/notify-community/notify.mjs";

const env = new Map(Object.entries({ MOBIT_COMMUNITY_CRON_TOKEN: "cron-fixture", MOBIT_TELEGRAM_BOT_TOKEN: "bot-fixture",
  MOBIT_TELEGRAM_CHAT_ID: "123", MOBIT_USAGE_LOG_TOKEN: "logs-fixture",
  SUPABASE_SERVICE_ROLE_KEY: "service-fixture", SUPABASE_URL: "https://db.example" }));
const request = (mode, token = "cron-fixture") => new Request("https://example.test", {
  method: "POST", headers: { Authorization: "Bearer " + token }, body: JSON.stringify({ mode }),
});

test("개인 채팅으로 지정한 새 글만 전송하고 삭제된 글은 건너뛴다", async () => {
  const ids = ["A".repeat(20), "B".repeat(20)];
  const finished = [];
  const messages = [];
  let run;
  const send = async (url, options) => {
    const address = new URL(url);
    if (address.search === "?shallow=true") return Response.json(Object.fromEntries(ids.map(id => [id, true])));
    if (address.pathname.endsWith("/mobit_claim_community_digest")) {
      const claim = JSON.parse(options.body);
      assert.deepEqual(claim.p_ids, ids);
      run = claim.p_run;
      return Response.json(claim.p_initialize ? { total: 0, preview_ids: [] } : { total: ids.length, preview_ids: ids });
    }
    if (address.pathname.endsWith("/content.json")) return Response.json(address.pathname.includes(ids[0]) ? "💬".repeat(305) : null);
    if (address.pathname.endsWith("/sendMessage")) {
      const payload = JSON.parse(options.body);
      assert.equal(payload.chat_id, "123");
      assert.ok(payload.text.includes("💬".repeat(300) + "…"));
      assert.ok(payload.text.endsWith("https://csj97.github.io/Mobit/"));
      assert.match(payload.text, /새 글 1건/);
      messages.push(payload);
      return Response.json({ ok: true });
    }
    assert.ok(address.pathname.endsWith("/mobit_finish_community_digest"));
    const receipt = JSON.parse(options.body);
    assert.equal(receipt.p_run, run);
    finished.push(receipt.p_run);
    return new Response(null, { status: 204 });
  };
  assert.equal((await notifyCommunity(request("initialize"), env, send)).status, 200);
  assert.deepEqual(messages, []);
  assert.equal((await notifyCommunity(request("poll"), env, send)).status, 200);
  assert.equal(messages.length, 1);
  assert.deepEqual(finished, [run]);
});

test("인증 실패와 텔레그램 거절에 성공 기록을 남기지 않는다", async () => {
  assert.equal((await notifyCommunity(request("poll", "wrong"), env, () => assert.fail())).status, 401);
  const id = "A".repeat(20);
  const calls = [];
  const response = await notifyCommunity(request("poll"), env, async url => {
    const path = new URL(url).pathname;
    calls.push(path);
    if (path.endsWith("/mobit_community.json")) return Response.json({ [id]: true });
    if (path.endsWith("/mobit_claim_community_digest")) return Response.json({ total: 1, preview_ids: [id] });
    if (path.endsWith("/content.json")) return Response.json("새 글");
    assert.ok(path.endsWith("/sendMessage"));
    return new Response(null, { status: 429 });
  });
  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), { stage: "telegram" });
  assert.equal(calls.length, 4);
});

test("새 글이 없으면 발송하지 않고 8건이면 목록을 한 번 조회해 한 건으로 요약한다", async () => {
  for (const count of [0, 8]) {
    const ids = Array.from({ length: count }, (_, i) => String(i).padStart(20, "A"));
    let lists = 0, reads = 0, sends = 0, finishes = 0;
    const response = await notifyCommunity(request("poll"), env, async (url, options) => {
      const path = new URL(url).pathname;
      if (path.endsWith("/mobit_community.json")) {
        lists++;
        return Response.json(Object.fromEntries(ids.map(id => [id, true])));
      }
      if (path.endsWith("/mobit_claim_community_digest")) return Response.json({ total: count, preview_ids: ids.slice(-5).reverse() });
      if (path.endsWith("/content.json")) {
        reads++;
        return Response.json("의견");
      }
      if (path.endsWith("/sendMessage")) {
        sends++;
        assert.match(JSON.parse(options.body).text, /새 글 8건[\s\S]*외 3건/);
        return Response.json({ ok: true });
      }
      assert.ok(path.endsWith("/mobit_finish_community_digest"));
      finishes++;
      return new Response(null, { status: 204 });
    });
    assert.equal(response.status, 200);
    assert.deepEqual([lists, reads, sends, finishes], count ? [1, 5, 1, 1] : [1, 0, 0, 0]);
  }
});

test("관리자 테스트는 저장된 개인 채팅에 한 번만 보내고 텔레그램 메시지 번호를 확인한다", async () => {
  const post = token => new Request("https://example.test", {
    method: "POST", headers: { Authorization: "Bearer " + token },
    body: JSON.stringify({ mode: "test", chat_id: "other", text: "custom" }),
  });
  assert.equal((await notifyCommunity(post("wrong"), env, () => assert.fail())).status, 401);
  const message = { message_id: 37, chat: { id: 123, type: "private" } };
  for (const [reply, status] of [[{ ok: true, result: message }, 200], [{ ok: false }, 502],
    [{ ok: true }, 502], [{ ok: true, result: { ...message, chat: { id: 321, type: "private" } } }, 502]]) {
    let calls = 0;
    const response = await notifyCommunity(post("cron-fixture"), env, async (url, options) => {
      calls++;
      assert.equal(String(url), "https://api.telegram.org/botbot-fixture/sendMessage");
      const payload = JSON.parse(options.body);
      assert.equal(payload.chat_id, "123");
      assert.equal(payload.text, "[테스트] 모의비트 커뮤니티 관리자 알림입니다.");
      return Response.json(reply);
    });
    assert.equal(calls, 1);
    assert.equal(response.status, status);
    if (status === 200) assert.deepEqual(await response.json(), { mode: "test", message_id: 37 });
  }
});

test("사용량 보고는 기존 개인 채팅에만 발송하고 미리보기에서는 기록하거나 발송하지 않는다", async () => {
  for (const preview of [false, true]) {
    const sent = [];
    const mode = preview ? "usage-preview" : "usage";
    const response = await notifyCommunity(request(mode), env, async (url, options) => {
      const address = new URL(url);
      if (address.hostname === "api.supabase.com") {
        assert.match(address.searchParams.get("sql"), /WHERE source = 'function_edge_logs'/);
        assert.equal(Date.parse(address.searchParams.get("iso_timestamp_end")) -
          Date.parse(address.searchParams.get("iso_timestamp_start")), 86400000);
        if (!preview) assert.match(address.searchParams.get("iso_timestamp_end"), /T09:30:00.000Z$/);
        return Response.json({ result: [{ calls: "12000" }] });
      }
      if (address.pathname.endsWith("/mobit_usage_report")) {
        const params = JSON.parse(options.body);
        assert.equal(params.p_calls, 12000);
        assert.equal(params.p_preview, preview);
        return Response.json({ database_bytes: 350000000, days: 2, calls: 24000 });
      }
      assert.match(address.pathname, /sendMessage$/);
      assert.equal(JSON.parse(options.body).chat_id, "123");
      sent.push(JSON.parse(options.body).text);
      return Response.json({ ok: true });
    });
    assert.equal(response.status, 200);
    assert.equal(sent.length, preview ? 0 : 1);
    if (!preview) {
      assert.match(sent[0], /DB 용량이 무료 한도의 70%/);
      assert.match(sent[0], /360,000 \/ 500,000회 \(72.0%\)/);
      assert.match(sent[0], /⚠️ 현재 속도/);
    }
  }
});

test("로그가 없거나 잘못되면 0회와 조회 실패를 구분하고 실제 누적 경고를 보낸다", async () => {
  for (const raw of [0, null, ""]) {
    let text;
    const response = await notifyCommunity(request("usage"), env, async (url, options) => {
      const address = new URL(url);
      if (address.hostname === "api.supabase.com") return Response.json({ result: [{ calls: raw }] });
      if (address.pathname.endsWith("/mobit_usage_report")) {
        assert.equal(JSON.parse(options.body).p_calls, raw === 0 ? 0 : null);
        return Response.json({ database_bytes: 1234, days: 28, calls: 350000 });
      }
      text = JSON.parse(options.body).text;
      return Response.json({ ok: true });
    });
    assert.equal(response.status, 200);
    assert.match(text, raw === 0 ? /Edge 호출  0회/ : /Edge 호출 조회 실패/);
    assert.match(text, /⚠️ 관측 합계/);
  }
});

test("사용량 배포 검증은 토큰·쿼리·DB 실패를 구분하고 응답 원문을 노출하지 않는다", async () => {
  const missingToken = new Map(env);
  missingToken.delete("MOBIT_USAGE_LOG_TOKEN");
  const cases = [
    [missingToken, [], { stage: "usage-logs", reason: "missing-log-token" }],
    [env, [new Response("logs-fixture", { status: 403 })], { stage: "usage-logs", upstream_status: 403 }],
    [env, [Response.json({ error: "logs-fixture" })], { stage: "usage-logs", reason: "logs-query" }],
    [env, [Response.json({ result: [] })], { stage: "usage-logs", reason: "logs-response" }],
    [env, [Response.json({ result: [{ calls: 0 }] }), new Response(null, { status: 404 })],
      { stage: "mobit_usage_report", upstream_status: 404 }],
  ];
  for (const [settings, replies, expected] of cases) {
    const response = await notifyCommunity(request("usage-preview"), settings, async () => {
      assert.ok(replies.length);
      return replies.shift();
    });
    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), expected);
    assert.equal(replies.length, 0);
  }
});

test("즉시 보고는 현재 KST와 직전 24시간을 표시하고 읽기 전용 집계 후 한 건의 접수 번호를 반환한다", async () => {
  const paths = [];
  let time;
  const response = await notifyCommunity(request("usage-now"), env, async (url, options) => {
    const address = new URL(url);
    paths.push(address.pathname.split("/").pop());
    if (address.hostname === "api.supabase.com") {
      const end = Date.parse(address.searchParams.get("iso_timestamp_end"));
      assert.ok(Math.abs(Date.now() - end) < 61000);
      assert.equal(end - Date.parse(address.searchParams.get("iso_timestamp_start")), 86400000);
      time = new Date(end + 9 * 3600000).toISOString().slice(0, 16).replace("T", " ");
      return Response.json({ result: [{ calls: 321 }] });
    }
    const body = JSON.parse(options.body);
    if (address.pathname.endsWith("/mobit_usage_report")) {
      assert.deepEqual(body, { p_calls: 321, p_day: time.slice(0, 10), p_preview: true });
      return Response.json({ database_bytes: 10000000, days: 0, calls: 0 });
    }
    assert.equal(body.chat_id, "123");
    assert.ok(body.text.includes(time + " KST"));
    assert.match(body.text, /최근 24시간 Edge 호출  321회/);
    return Response.json({ ok: true, result: { message_id: 17, chat: { type: "private", id: 123 } } });
  });
  assert.deepEqual(paths, ["logs", "mobit_usage_report", "sendMessage"]);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { mode: "usage-now", message_id: 17 });
});
