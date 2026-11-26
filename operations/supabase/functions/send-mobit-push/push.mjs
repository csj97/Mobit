import { createSign } from "node:crypto";
import { Buffer } from "node:buffer";
import campaign from "./campaign.json" with { type: "json" };

import { priceMessage } from "./price-message.mjs";
import { holdingNotification } from "./holding-message.mjs";

const tokenUrl = "https://oauth2.googleapis.com/token";

function signedAssertion(account) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = { iss: account.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: tokenUrl, iat: now, exp: now + 3600 };
  const unsigned = [header, claims].map(value => Buffer.from(JSON.stringify(value)).toString("base64url")).join(".");
  return unsigned + "." + createSign("RSA-SHA256").update(unsigned).sign(account.private_key, "base64url");
}

async function claimHoldingMessage(eventID, env, send) {
  const key = env.get("SUPABASE_SERVICE_ROLE_KEY");
  const claimed = await send(new URL("/rest/v1/rpc/mobit_claim_holding_event", env.get("SUPABASE_URL")), {
    method: "POST", redirect: "error", signal: AbortSignal.timeout(8000),
    headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json" },
    body: JSON.stringify({ p_event: eventID }),
  });
  if (!claimed.ok) throw Object.assign(new Error(), { stage: "holding-claim", remoteStatus: claimed.status });
  if (claimed.status === 204) return null;
  const event = await claimed.json();
  if (!event) return null;
  return {
    token: event.token,
    notification: await holdingNotification(event, send),
    data: { type: "route", destination: "investment", campaign_id: "holding_return", holding: event.holding,
      exchange: event.exchange, market: event.market, side: event.side },
    apns: { headers: { "apns-expiration": String(Math.floor(Date.now()/1000)+300) }, payload: { aps: { sound: "default" } } },
  };
}

export async function sendPush(request, env, send = fetch) {
  if (request.method !== "POST") return new Response(null, { status: 405, headers: { Allow: "POST" } });
  const cronToken = env.get("MOBIT_PUSH_CRON_TOKEN");
  if (!cronToken || request.headers.get("Authorization") !== "Bearer " + cronToken) {
    return new Response(null, { status: 401 });
  }
  const body = await request.json().catch(() => null);
  if (!["validate", "send", "price-alert", "holding-alert"].includes(body?.mode)) return new Response(null, { status: 400 });
  const validateOnly = body.mode === "validate";
  try {
    let message = campaign;
    if (body.mode === "holding-alert") {
      if (typeof body.event !== "string" || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(body.event)) {
        return new Response(null, { status: 400 });
      }
      message = await claimHoldingMessage(body.event, env, send);
      if (!message) return new Response(null, { status: 204 });
    } else if (body.mode === "price-alert") {
      message = priceMessage(body);
      if (!message) return new Response(null, { status: 400 });
    }
    const account = JSON.parse(env.get("MOBIT_FCM_SERVICE_ACCOUNT"));
    await deliverFcmMessage(account, message, validateOnly, send);
    console.info(validateOnly ? "FCM 예약 푸시 검증 성공" : "FCM 예약 푸시 발송 요청 접수");
    return Response.json({ validated: validateOnly });
  } catch (error) {
    const stage = error.stage ?? "configuration";
    const remoteStatus = error.remoteStatus;
    console.error("예약 푸시 실패", { stage, remoteStatus });
    return Response.json({ stage, remoteStatus }, { status: 502 });
  }
}

export async function deliverFcmMessage(account, message, validateOnly, send = fetch) {
  let stage = "configuration";
  let remoteStatus;
  try {
    const assertion = signedAssertion(account);
    stage = "google-oauth";
    const auth = await send(tokenUrl, {
      method: "POST", redirect: "error", signal: AbortSignal.timeout(12000),
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
    });
    if (!auth.ok) { remoteStatus = auth.status; throw new Error(); }
    const { access_token: token } = await auth.json();
    if (typeof token !== "string" || !token) throw new Error();

    stage = "fcm";
    const response = await send("https://fcm.googleapis.com/v1/projects/" +
      encodeURIComponent(account.project_id) + "/messages:send", {
      method: "POST", redirect: "error", signal: AbortSignal.timeout(15000),
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body: JSON.stringify({ validate_only: validateOnly, message }),
    });
    if (!response.ok) { remoteStatus = response.status; throw new Error(); }
    return response;
  } catch {
    throw Object.assign(new Error("FCM 전송 요청 실패"), { stage, remoteStatus });
  }
}
