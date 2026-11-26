import { prepareUpdates } from "./coins.mjs";

export async function refreshCoins(request, env, send = fetch, prepare = prepareUpdates) {
  if (request.method !== "POST") return new Response(null, { status: 405, headers: { Allow: "POST" } });
  const token = env.get("MOBIT_COIN_CRON_TOKEN");
  if (!token || request.headers.get("Authorization") !== `Bearer ${token}`) {
    return new Response(null, { status: 401 });
  }

  // URL에 인증 값이 포함되므로 응답 본문과 원본 예외는 로그에 전달하지 않는다.
  let stage = "configuration";
  try {
    const db = new URL(env.get("MOBIT_DATABASE_URL"));
    const firebaseKey = env.get("MOBIT_FIREBASE_API_KEY");
    const cmcKey = env.get("MOBIT_CMC_API_KEY");
    const refreshToken = env.get("MOBIT_FIREBASE_REFRESH_TOKEN");
    if (db.protocol !== "https:" || !/\.(firebaseio\.com|firebasedatabase\.app)$/.test(db.hostname) ||
        db.pathname !== "/" || db.search || db.hash || db.username || db.password || db.port ||
        !firebaseKey || !cmcKey || !refreshToken) throw new Error();

    // 배포할 때 등록한 쓰기 전용 UID의 세션을 갱신한다.
    stage = "firebase-token";
    const auth = await send(`https://securetoken.googleapis.com/v1/token?key=${encodeURIComponent(firebaseKey)}`, {
      method: "POST", redirect: "error",
      body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }),
      signal: AbortSignal.timeout(10000),
    });
    if (!auth.ok) throw new Error(String(auth.status));
    const { id_token: idToken } = await auth.json();
    if (typeof idToken !== "string" || !idToken) throw new Error();

    stage = "quotes";
    const { updates, skipped } = await prepare(cmcKey);
    stage = "firebase-patch";
    const url = new URL("/CMCResponse.json", db);
    url.searchParams.set("auth", idToken);
    url.searchParams.set("print", "silent");
    const saved = await send(url, {
      method: "PATCH", redirect: "error", headers: { "Content-Type": "application/json" },
      body: JSON.stringify(updates), signal: AbortSignal.timeout(20000),
    });
    if (!saved.ok) throw new Error(String(saved.status));
    if (skipped.length) console.warn("CMC 갱신 제외", skipped);
    const counts = { updatedPaths: Object.keys(updates).length, skippedCount: skipped.length };
    console.info("코인 정보 갱신 완료", counts);
    return Response.json(counts);
  } catch (error) {
    const code = /^[0-9]{3}$/.test(error?.message) ? error.message : undefined;
    console.error("코인 정보 갱신 실패", { stage, code });
    return Response.json({ stage, code }, { status: 502 });
  }
}
