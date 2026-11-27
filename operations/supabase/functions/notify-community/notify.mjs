import { usageReport } from "./usage.mjs";

const board = "https://csj97.github.io/Mobit/";

export async function notifyCommunity(request, env, send = fetch) {
  if (request.method !== "POST") return new Response(null, { status: 405 });
  const secret = env.get("MOBIT_COMMUNITY_CRON_TOKEN");
  if (!secret || request.headers.get("Authorization") !== "Bearer " + secret) return new Response(null, { status: 401 });
  const mode = (await request.json().catch(() => null))?.mode;
  if (!["initialize", "poll", "test", "usage", "usage-preview", "usage-now"].includes(mode)) return new Response(null, { status: 400 });

  let stage = "configuration";
  try {
    const database = env.get("MOBIT_DATABASE_URL") || "https://mobit-68833-default-rtdb.firebaseio.com";
    const token = env.get("MOBIT_TELEGRAM_BOT_TOKEN");
    const chat = env.get("MOBIT_TELEGRAM_CHAT_ID");
    const key = env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!token || !/^[1-9]\d*$/.test(chat ?? "")) throw new Error();
    async function call(url, options, timeout = 7000) {
      const response = await send(url, { ...options, redirect: "error", signal: AbortSignal.timeout(timeout) });
      if (!response.ok) throw Object.assign(new Error(), { upstreamStatus: response.status });
      return response;
    }
    async function sendTelegram(text) {
      stage = "telegram";
      const result = await (await call("https://api.telegram.org/bot" + token + "/sendMessage", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ chat_id: chat, text, link_preview_options: { is_disabled: true } }),
      })).json();
      if (result.ok !== true) throw new Error();
      return result.result;
    }
    async function sendWithReceipt(text) {
      const message = await sendTelegram(text);
      if (!Number.isSafeInteger(message?.message_id) || message.message_id <= 0 ||
          message.chat?.type !== "private" || String(message.chat.id) !== chat) throw new Error();
      return Response.json({ mode, message_id: message.message_id });
    }
    if (mode === "test") return await sendWithReceipt("[테스트] 모의비트 커뮤니티 관리자 알림입니다.");
    if (!key) throw new Error();
    async function rpc(name, payload) {
      stage = name;
      return call(new URL("/rest/v1/rpc/" + name, env.get("SUPABASE_URL")), {
        method: "POST", headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
    }
    if (mode === "usage" || mode === "usage-preview" || mode === "usage-now") {
      stage = "usage-logs";
      const text = await usageReport(env, call, rpc, mode !== "usage");
      if (mode === "usage-now") return await sendWithReceipt(text);
      if (mode === "usage") await sendTelegram(text);
      return Response.json({ mode });
    }
    stage = "firebase-list";
    const listing = await (await call(new URL("/mobit_community.json?shallow=true", database))).json();
    if (listing !== null && (typeof listing !== "object" || Array.isArray(listing))) throw new Error();
    const ids = Object.keys(listing ?? {}).filter(id => /^[-_A-Za-z0-9]{20}$/.test(id));
    const run = crypto.randomUUID();
    const { total, preview_ids: idsToRead } = await (await rpc("mobit_claim_community_digest", {
      p_ids: ids, p_run: run, p_initialize: mode === "initialize",
    })).json();
    if (total === 0) return Response.json({ mode, delivered: 0 });
    stage = "firebase-post";
    const contents = await Promise.all(idsToRead.map(async id => {
      const url = new URL("/mobit_community/" + encodeURIComponent(id) + "/content.json", database);
      return (await call(url)).json();
    }));
    // 목록 조회 후 삭제된 글이나 빈 글은 미리보기와 보고 건수에서 제외한다.
    const previews = contents.filter(content => typeof content === "string" && content.trim()).map(content => {
      const letters = Array.from(content.trim());
      return "• " + letters.slice(0, 300).join("") + (letters.length > 300 ? "…" : "");
    });
    const count = total - contents.length + previews.length;
    if (count > 0) {
      const lines = [`모의비트 커뮤니티에 새 글 ${count}건이 올라왔어요.`, ...previews];
      if (count > previews.length) lines.push(`외 ${count - previews.length}건은 게시판에서 확인하세요.`);
      lines.push(board);
      await sendTelegram(lines.join("\n\n"));
    }
    await rpc("mobit_finish_community_digest", { p_run: run });
    return Response.json({ mode, delivered: count });
  } catch (error) {
    // 텔레그램 요청 URL에는 토큰이 포함되므로 원본 예외를 기록하지 않는다.
    const details = { stage };
    if (mode === "usage-preview" || mode === "usage-now") {
      if (Number.isInteger(error?.upstreamStatus)) details.upstream_status = error.upstreamStatus;
      if (["missing-log-token", "logs-query", "logs-response"].includes(error?.reason)) details.reason = error.reason;
      if (error?.name === "TimeoutError") details.reason = "timeout";
    }
    console.error("커뮤니티 알림 실패", details);
    return Response.json(details, { status: 502 });
  }
}
