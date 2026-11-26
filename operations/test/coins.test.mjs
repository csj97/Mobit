import assert from "node:assert/strict";
import { test } from "node:test";
import { prepareUpdates } from "../supabase/functions/refresh-mobit-coins/coins.mjs";

import { refreshCoins } from "../supabase/functions/refresh-mobit-coins/refresh.mjs";

function coin(id, symbol, name) {
  return {
    id, symbol, name, is_active: 1, cmc_rank: 3, slug: name.toLowerCase(),
    date_added: "2020-01-01T00:00:00Z", tags: [{ slug: "pow" }],
    quote: { KRW: { price: 1400, market_cap: 4200, volume_24h: 300, last_updated: "2026-01-10T16:15:00Z" } },
  };
}

const a = coin(10, "AAA", "Alpha");
const b = coin(20, "AAA", "Beta");
const exchangeRows = {
  upbit: [{ market: "KRW-AAA", english_name: "Alpha" }, { market: "BTC-AAA", english_name: "Alpha" },
    { market: "KRW-MISSING" }, { market: "USDT-OTHER" }],
  bithumb: [{ market: "KRW-AAA", english_name: "Beta" }],
};

function mockRead(data, rows = exchangeRows) {
  return async (url, headers) => {
    const target = new URL(url);
    if (target.host === "api.upbit.com") return rows.upbit;
    if (target.host === "api.bithumb.com") return rows.bithumb;
    assert.equal(target.host, "pro-api.coinmarketcap.com");
    assert.equal(headers["X-CMC_PRO_API_KEY"], "fixture");
    assert.equal(target.searchParams.get("convert"), "KRW");
    return { data, status: { error_code: 0 } };
  };
}

test("거래소별 동일 심볼, KRW 금액, 표시 시간, 구버전 업비트 경로를 보존한다", async () => {
  const { updates, skipped } = await prepareUpdates("fixture", mockRead({ AAA: [a, b] }));
  const upbit = updates["exchanges/upbit/cryptoInformations/AAA"];
  assert.equal(Object.keys(updates).length, 5);
  assert.equal(upbit.id, 10);
  assert.equal(updates["exchanges/bithumb/cryptoInformations/AAA"].id, 20);
  assert.deepEqual(updates["cryptoInformations/AAA"], upbit);
  assert.deepEqual(updates["btc_cryptoInformations/AAA"], updates["exchanges/upbit/btc_cryptoInformations/AAA"]);
  assert.deepEqual(upbit.tags, ["pow"]);
  assert.equal(upbit.price, 1400);
  assert.equal(upbit.updated_at_string, "코인마켓캡 기준: 2026-01-11 01:15");
  assert.equal(upbit.percent_change_90d, 0);
  assert.deepEqual(skipped, ["exchanges/upbit/cryptoInformations/MISSING"]);
});

test("모호한 심볼과 필수 수치가 잘못된 종목에는 쓰기 경로를 생성하지 않는다", async () => {
  const bad = coin(30, "BAD", "Bad");
  bad.quote.KRW.volume_24h = null;
  const data = { AAA: [a, b], BAD: [bad] };
  const rows = { ...exchangeRows, bithumb: [...exchangeRows.bithumb,
    { market: "KRW-BAD" }, { market: "KRW-UNKNOWN" }] };
  data.UNKNOWN = [coin(40, "UNKNOWN", "Name"), coin(50, "UNKNOWN", "Other")];
  const { updates, skipped } = await prepareUpdates("fixture", mockRead(data, rows));
  assert.ok(skipped.includes("exchanges/bithumb/cryptoInformations/BAD"));
  assert.ok(skipped.includes("exchanges/bithumb/cryptoInformations/UNKNOWN"));
  assert.ok(skipped.every(path => !(path in updates)));
});

test("빈 마켓 또는 CMC 전체 미매칭은 쓰기 전에 실패한다", async () => {
  await assert.rejects(prepareUpdates("fixture", mockRead({}, { ...exchangeRows, upbit: [] })), /upbit KRW/);
  await assert.rejects(prepareUpdates("fixture", mockRead({})), /전체 종목 매칭 실패/);
});

test("다음 CMC 묶음이 실패하면 첫 묶음도 게시하지 않는다", async () => {
  const rows = Array.from({ length: 101 }, (_, i) => ({ market: `KRW-A${i}` }));
  let calls = 0;
  await assert.rejects(prepareUpdates("fixture", async url => {
    if (new URL(url).host !== "pro-api.coinmarketcap.com") return rows;
    calls += 1;
    if (calls === 2) throw new Error("HTTP 429");
    assert.equal(new URL(url).searchParams.get("symbol").split(",").length, 100);
    return { status: { error_code: 0 }, data: { A0: [coin(1, "A0", "Alpha")] } };
  }), /429/);
  assert.equal(calls, 2);
});

const config = new Map(Object.entries({
  MOBIT_FIREBASE_REFRESH_TOKEN: "fixture-refresh",
  MOBIT_COIN_CRON_TOKEN: "fixture-token", MOBIT_CMC_API_KEY: "fixture-cmc",
  MOBIT_DATABASE_URL: "https://demo-default-rtdb.firebaseio.com", MOBIT_FIREBASE_API_KEY: "fixture-api",
}));
const post = () => new Request("https://example.test", { method: "POST",
  headers: { Authorization: "Bearer fixture-token" } });

test("Cron 인증 전에는 외부 API를 호출하지 않는다", async () => {
  const unexpected = () => assert.fail("인증 전 호출");
  for (const [request, expected] of [[new Request("https://example.test"), 405],
    [new Request("https://example.test", { method: "POST" }), 401]]) {
    assert.equal((await refreshCoins(request, config, unexpected, unexpected)).status, expected);
  }
});

function refreshSession(url, options) {
  const target = new URL(url);
  assert.equal(target.origin, "https://securetoken.googleapis.com");
  assert.equal(target.pathname, "/v1/token");
  assert.equal(target.searchParams.get("key"), "fixture-api");
  assert.equal(options.method, "POST");
  assert.equal(options.body.get("grant_type"), "refresh_token");
  assert.equal(options.body.get("refresh_token"), "fixture-refresh");
  return Response.json({ id_token: "fixture-firebase" });
}

test("배치 인증 실패 시 CMC 크레딧을 사용하거나 DB에 쓰지 않는다", async () => {
  for (const auth of [new Response(null, { status: 400 }), Response.json({})]) {
    let calls = 0;
    const result = await refreshCoins(post(), config, () => { calls++; return auth; },
      () => assert.fail("인증 실패 후 CMC 조회"));
    assert.equal(calls, 1);
    assert.equal(result.status, 502);
    assert.deepEqual(await result.json(), auth.ok ? { stage: "firebase-token" } :
      { stage: "firebase-token", code: "400" });
  }
});

test("시세 조회가 실패하면 DB에 쓰지 않는다", async () => {
  const result = await refreshCoins(post(), config, refreshSession, () => { throw Error("private"); });
  assert.equal(result.status, 502);
  assert.deepEqual(await result.json(), { stage: "quotes" });
});

for (const status of [204, 401, 403]) {
  test(`동일한 Firebase 계정으로 재실행하고 쓰기 결과를 전달한다 (HTTP ${status})`, async () => {
    const calls = [];
    const updates = { "cryptoInformations/AAA": { id: 1 } };
    const send = async (url, options) => {
      const target = new URL(url);
      calls.push(target.pathname);
      if (target.pathname === "/v1/token") return refreshSession(url, options);
      assert.equal(target.origin, config.get("MOBIT_DATABASE_URL"));
      assert.equal(target.searchParams.get("auth"), "fixture-firebase");
      assert.equal(options.method, "PATCH");
      assert.deepEqual(JSON.parse(options.body), updates);
      return new Response(null, { status });
    };
    for (let run = 0; run < 2; run++) {
      const result = await refreshCoins(post(), config, send, async () => ({ updates, skipped: [] }));
      assert.equal(result.status, status === 204 ? 200 : 502);
      assert.deepEqual(await result.json(), status === 204 ? { updatedPaths: 1, skippedCount: 0 } :
        { stage: "firebase-patch", code: String(status) });
    }
    assert.deepEqual(calls, ["/v1/token", "/CMCResponse.json", "/v1/token", "/CMCResponse.json"]);
  });
}
