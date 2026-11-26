const exchanges = {
  upbit: { name: "업비트", markets: "https://api.upbit.com/v1/market/all" },
  bithumb: { name: "빗썸", markets: "https://api.bithumb.com/v1/market/all" },
};
const marketCache = new Map();

async function marketNames(exchange, send) {
  let cache = marketCache.get(exchange);
  if (!cache) {
    cache = { names: new Map(), refreshAfter: 0, pending: null };
    marketCache.set(exchange, cache);
  }
  if (Date.now() >= cache.refreshAfter && !cache.pending) {
    cache.pending = (async () => {
      const response = await send(exchanges[exchange].markets, { redirect: "error", signal: AbortSignal.timeout(2000) });
      if (!response.ok) throw new Error("거래소 종목 목록 조회 실패");
      const rows = await response.json();
      const names = new Map();
      for (const row of rows) {
        if (typeof row?.market === "string" && typeof row.korean_name === "string" && row.korean_name.trim()) {
          names.set(row.market, row.korean_name.trim());
        }
      }
      if (!names.size) throw new Error("거래소 종목명 누락");
      cache.names = names;
      cache.refreshAfter = Date.now() + 6 * 60 * 60 * 1000;
    })().catch(() => {
      // 거래소 장애 중에도 기존 이름이나 심볼로 개인 알림을 전달한다.
      cache.refreshAfter = Date.now() + 60 * 1000;
    }).finally(() => { cache.pending = null; });
  }
  await cache.pending;
  return cache.names;
}

export async function holdingNotification(event, send) {
  const symbol = event.market.split("-")[1];
  const name = (await marketNames(event.exchange, send)).get(event.market);
  const coin = name && name !== symbol ? `${name}(${symbol})` : symbol;
  const level = event.level.replace(/\.0+$/, "");
  const loss = level.startsWith("-");
  return {
    title: loss ? "보유자산 하락" : "보유자산 상승",
    body: `[${exchanges[event.exchange].name}] ${coin} ${loss ? level : "+" + level}% ${loss ? "손실" : "수익"}`,
  };
}
