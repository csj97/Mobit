import assert from "node:assert/strict";
import { test } from "node:test";
import { notifyCommunity } from "../supabase/functions/notify-community/notify.mjs";

const env = new Map(Object.entries({ MOBIT_COMMUNITY_CRON_TOKEN: "cron-fixture", MOBIT_TELEGRAM_BOT_TOKEN: "bot-fixture",
  MOBIT_TELEGRAM_CHAT_ID: "123", SUPABASE_SERVICE_ROLE_KEY: "service-fixture", SUPABASE_URL: "https://db.example" }));
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
