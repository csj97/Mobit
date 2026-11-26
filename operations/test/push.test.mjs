import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";
import { Buffer } from "node:buffer";
import { test } from "node:test";
import { sendPush } from "../supabase/functions/send-mobit-push/push.mjs";
import { testDeviceMessage } from "../test-device-push.mjs";

test("실기기 테스트는 단일 토큰만 지정하고 토픽·조건 대상을 제외한다", () => {
  const message = testDeviceMessage("test:device");
  assert.equal(message.token, "test:device");
  assert.ok(!("topic" in message) && !("condition" in message));
  assert.match(message.notification.title, /^\[테스트\]/);
  assert.equal(message.data.campaign_id, "device_test_price_alert");
  for (const invalid of ["", "mobit_price_alerts", "/topics/mobit_price_alerts", "one:device,two:device"]) {
    assert.throws(() => testDeviceMessage(invalid));
  }
});

const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const env = new Map([
  ["MOBIT_PUSH_CRON_TOKEN", "push-only"],
  ["MOBIT_FCM_SERVICE_ACCOUNT", JSON.stringify({ project_id: "fixture", client_email: "test@example.org",
    private_key: privateKey.export({ type: "pkcs8", format: "pem" }) })],
]);
function request(mode, token = "push-only") {
  return new Request("https://example.test", { method: "POST",
    headers: { Authorization: "Bearer " + token }, body: JSON.stringify({ mode }) });
}

test("푸시 전용 인증과 명시적인 실행 모드가 필요하다", async () => {
  for (const [input, status] of [[new Request("https://example.test"), 405],
    [request("send", "coin-only"), 401], [request(null), 400], [request("preview"), 400]]) {
    assert.equal((await sendPush(input, env, () => assert.fail())).status, status);
  }
});

for (const mode of ["validate", "send"]) {
  test(`기존 투자내역 경로로 FCM 토픽 요청 (${mode})`, async () => {
    const urls = [];
    const result = await sendPush(request(mode), env, (url, options) => {
      urls.push(url);
      if (urls.length === 1) {
        const [header, claims, signature] = options.body.get("assertion").split(".");
        assert.ok(verify("RSA-SHA256", Buffer.from(header + "." + claims), publicKey, Buffer.from(signature, "base64url")));
        const payload = JSON.parse(Buffer.from(claims, "base64url").toString());
        assert.equal(payload.aud, url);
        assert.equal(payload.scope, "https://www.googleapis.com/auth/firebase.messaging");
        return Response.json({ access_token: "temporary" });
      }
      const body = JSON.parse(options.body);
      assert.equal(options.headers.Authorization, "Bearer temporary");
      assert.equal(body.validate_only, mode === "validate");
      assert.equal(body.message.topic, "mobit_announcements");
      assert.deepEqual(body.message.data, { type: "route", destination: "investment", campaign_id: "weekly_portfolio" });
      return Response.json({ name: "accepted" });
    });
    assert.deepEqual(urls, ["https://oauth2.googleapis.com/token", "https://fcm.googleapis.com/v1/projects/fixture/messages:send"]);
    assert.equal(result.status, 200);
    assert.deepEqual(await result.json(), { validated: mode === "validate" });
  });
}

test("인증 실패와 FCM 거부는 구분하고 자동으로 재전송하지 않는다", async () => {
  for (const stage of ["google-oauth", "fcm"]) {
    let calls = 0;
    const result = await sendPush(request("send"), env, () => {
      calls++;
      if (stage === "fcm" && calls === 1) return Response.json({ access_token: "temporary" });
      return new Response("private failure", { status: 403 });
    });
    assert.equal(result.status, 502);
    assert.deepEqual(await result.json(), { stage, remoteStatus: 403 });
    assert.equal(calls, stage === "fcm" ? 2 : 1);
  }
});

test("급등락 기준·거래소·부호를 보존해 공지와 별도 토픽으로 보낸다", async () => {
  const cases = [
    [{ hourLevel: 5, endHourKst: 10 }, "hour", "상승", "오전 9시부터 10시까지 5% 이상 올랐어요."],
    [{ hourLevel: -5, endHourKst: 0 }, "hour", "하락", "오후 11시부터 오전 12시까지 5% 이상 내렸어요."],
    [{ exchangeLevel: 10 }, "exchange", "상승", "전일 종가보다 10% 이상 올랐어요."],
    [{ exchangeLevel: -10 }, "exchange", "하락", "전일 종가보다 10% 이상 내렸어요."],
    [{ hourLevel: 5, exchangeLevel: 10, endHourKst: 10 }, "combined", "상승",
      "오전 9시부터 10시까지 5% 이상 올랐어요. 전일 종가보다도 10% 이상 높아요."],
    [{ hourLevel: 5, exchangeLevel: -10, endHourKst: 12 }, "combined", "가격 변동",
      "오전 11시부터 오후 12시까지 5% 이상 올랐어요. 전일 종가보다는 10% 이상 낮아요."],
    [{ basis: "hour", percent: -5 }, "hour", "하락", "1시간 전보다 5% 이상 내렸어요."],
  ];
  for (const [fields, basis, direction, wording] of cases) {
    let message;
    const request = new Request("https://example.test", { method: "POST",
      headers: { Authorization: "Bearer push-only" },
      body: JSON.stringify({ mode: "price-alert", market: "KRW-BTC", exchange: "bithumb", ...fields }) });
    const response = await sendPush(request, env, (url, options) => {
      if (url.includes("oauth2.")) return Response.json({ access_token: "temporary" });
      message = JSON.parse(options.body).message;
      return Response.json({ name: "accepted" });
    });
    assert.equal(response.status, 200);
    assert.equal(message.topic, "mobit_price_alerts");
    assert.equal(message.data.destination, "exchange");
    assert.equal(message.data.exchange, "bithumb");
    assert.equal(message.data.market, "KRW-BTC");
    assert.equal(message.data.basis, basis);
    assert.deepEqual(message.notification, { title: "빗썸 BTC " + direction, body: wording });
  }
});

test("개인 알림은 거래소·종목명·수익 단계를 표시하고 인수한 이벤트만 지정 기기로 보낸다", async () => {
  const settings = new Map([...env, ["SUPABASE_URL", "https://local.example"], ["SUPABASE_SERVICE_ROLE_KEY", "server"]]);
  const holding = "00000000-1111-2222-3333-444444444444";
  const post = event => new Request("https://example.test", { method: "POST", headers: { Authorization: "Bearer push-only" },
    body: JSON.stringify({ mode: "holding-alert", event, token: "ignored", topic: "ignored" }) });
  const cases = [
    ["upbit", "KRW-BTC", "spot", "5", "보유자산 상승", "업비트 비트코인(BTC) +5% 수익"],
    ["bithumb", "KRW-ETH", "short", "-10", "보유자산 하락", "빗썸 이더리움(ETH) -10% 손실"],
    ["upbit", "KRW-ERA", "short", "15.000", "보유자산 상승", "업비트 테스트코인(ERA) +15% 수익"],
    ["upbit", "BTC-XYZ", "long", "-5", "보유자산 하락", "업비트 XYZ -5% 손실"],
  ];
  const eventIDs = cases.map(() => crypto.randomUUID());
  const pending = new Map(eventIDs.map((id, index) => [id, cases[index]]));
  let messages = 0, marketRequests = 0;
  const send = async (url, options) => {
    if (String(url).endsWith("/rpc/mobit_claim_holding_event")) {
      const { p_event } = JSON.parse(options.body);
      assert.ok(eventIDs.includes(p_event));
      assert.equal(options.headers.Authorization, "Bearer server");
      const item = pending.get(p_event);
      if (!pending.delete(p_event)) return Response.json(null);
      const [exchange, market, side, level] = item;
      return Response.json({ token: "fixture:only", holding, side, level, exchange, market });
    }
    if (String(url).endsWith("/v1/market/all")) {
      marketRequests++;
      assert.equal(options.headers, undefined);
      return Response.json(url === "https://api.upbit.com/v1/market/all"
        ? [{ market: "KRW-BTC", korean_name: "비트코인" }, { market: "KRW-ERA", korean_name: "테스트코인" }]
        : [{ market: "KRW-ETH", korean_name: "이더리움" }]);
    }
    if (String(url).includes("oauth2.")) return Response.json({ access_token: "temporary" });
    const { message } = JSON.parse(options.body);
    assert.equal(message.token, "fixture:only");
    assert.ok(!("topic" in message) && !("condition" in message));
    const [exchange, market, side, , title, body] = cases[messages];
    assert.deepEqual(message.data, { type: "route", destination: "investment", campaign_id: "holding_return",
      holding, exchange, market, side });
    assert.deepEqual(message.notification, { title, body });
    messages++;
    return Response.json({ name: "accepted" });
  };
  for (const id of eventIDs) assert.equal((await sendPush(post(id), settings, send)).status, 200);
  assert.equal((await sendPush(post(eventIDs[0]), settings, send)).status, 204);
  assert.equal(messages, cases.length);
  assert.equal(marketRequests, 2);
});
