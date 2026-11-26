const exchanges = {
  upbit: "https://api.upbit.com/v1/market/all?isDetails=false",
  bithumb: "https://api.bithumb.com/v1/market/all?isDetails=false",
};
const branches = { KRW: "cryptoInformations", BTC: "btc_cryptoInformations" };
const seoulTime = new Intl.DateTimeFormat("sv-SE", {
  timeZone: "Asia/Seoul", year: "numeric", month: "2-digit", day: "2-digit",
  hour: "2-digit", minute: "2-digit", hourCycle: "h23",
});

async function fetchJSON(url, headers, deadline) {
  const response = await fetch(url, { headers, redirect: "error",
    signal: AbortSignal.any([deadline, AbortSignal.timeout(20000)]) });
  if (!response.ok) throw new Error(`${new URL(url).hostname} HTTP ${response.status}`);
  return response.json();
}

function parseMarkets(exchange, rows) {
  if (!Array.isArray(rows)) throw new Error(`${exchange} 마켓 응답 형식 오류`);
  const markets = [];
  for (const row of rows) {
    const match = /^(KRW|BTC)-([A-Z0-9_-]+)$/.exec(row?.market);
    if (match) markets.push({ exchange, branch: branches[match[1]], symbol: match[2], name: row.english_name });
  }
  if (!markets.some(market => market.branch === branches.KRW)) {
    throw new Error(`${exchange} KRW 마켓 목록이 비어 있습니다`);
  }
  return markets;
}

function selectCoin(entries, market) {
  if (!Array.isArray(entries)) return;
  const active = entries.filter(coin => coin?.is_active === 1 && coin.symbol === market.symbol);
  if (active.length === 1) return active[0];
  const matches = active.filter(coin => typeof market.name === "string" &&
    market.name.toLowerCase() === coin.name?.toLowerCase());
  if (matches.length === 1) return matches[0];
}

function toRecord(coin) {
  const quote = coin?.quote?.KRW;
  if (!quote || !Number.isSafeInteger(coin.id) || coin.id <= 0 || !Number.isSafeInteger(coin.cmc_rank) ||
      ![coin.name, coin.slug, coin.date_added].every(value => typeof value === "string" && value.length) ||
      ![quote.price, quote.market_cap, quote.volume_24h].every(Number.isFinite) ||
      !Number.isFinite(Date.parse(quote.last_updated))) return;

  const record = {
    id: coin.id, name: coin.name, symbol: coin.symbol, slug: coin.slug, date_added: coin.date_added,
    iconURL: `https://s2.coinmarketcap.com/static/img/coins/64x64/${coin.id}.png`,
    market_cap_rank: coin.cmc_rank, market_cap: quote.market_cap, price: quote.price,
    volume_24h: quote.volume_24h, last_updated: quote.last_updated,
    updated_at_string: `코인마켓캡 기준: ${seoulTime.format(new Date(quote.last_updated))}`,
  };
  for (const key of ["circulating_supply", "total_supply"]) {
    const value = coin[key] ?? 0;
    if (!Number.isFinite(value)) return;
    record[key] = value;
  }
  for (const key of ["volume_change_24h", "percent_change_1h", "percent_change_24h", "percent_change_7d",
    "percent_change_30d", "percent_change_60d", "percent_change_90d"]) {
    const value = quote[key] ?? 0;
    if (!Number.isFinite(value)) return;
    record[key] = value;
  }
  for (const key of ["max_supply", "self_reported_circulating_supply", "self_reported_market_cap"]) {
    if (Number.isFinite(coin[key])) record[key] = coin[key];
  }
  if (typeof coin.platform?.name === "string") record.platform_name = coin.platform.name;
  if (typeof coin.platform?.token_address === "string") record.token_address = coin.platform.token_address;
  if (Array.isArray(coin.tags)) {
    record.tags = coin.tags.map(tag => typeof tag === "string" ? tag : tag?.slug).filter(tag => typeof tag === "string");
  }
  return record;
}

export async function prepareUpdates(apiKey, read = fetchJSON) {
  // Edge 실행 한도 안에서 Firebase 저장 시간을 확보한다.
  const deadline = AbortSignal.timeout(90000);
  const markets = (await Promise.all(Object.entries(exchanges).map(async ([exchange, url]) =>
    parseMarkets(exchange, await read(url, undefined, deadline))
  ))).flat();
  const symbols = [...new Set(markets.map(market => market.symbol))].sort();
  const quotes = new Map();
  for (let start = 0; start < symbols.length; start += 100) {
    const batch = symbols.slice(start, start + 100);
    const url = new URL("https://pro-api.coinmarketcap.com/v2/cryptocurrency/quotes/latest");
    url.search = new URLSearchParams({ symbol: batch.join(","), convert: "KRW", skip_invalid: "true" });
    const result = await read(url, { "X-CMC_PRO_API_KEY": apiKey }, deadline);
    if (result?.status?.error_code !== 0 || !result.data || typeof result.data !== "object" || Array.isArray(result.data)) {
      throw new Error("CMC 시세 응답 오류");
    }
    for (const symbol of batch) quotes.set(symbol, result.data[symbol]);
  }

  const updates = {};
  const skipped = [];
  const updatedMarkets = new Set();
  for (const market of markets) {
    const path = `exchanges/${market.exchange}/${market.branch}`;
    const record = toRecord(selectCoin(quotes.get(market.symbol), market));
    if (!record) {
      skipped.push(`${path}/${market.symbol}`);
      continue;
    }
    updates[`${path}/${market.symbol}`] = record;
    if (market.exchange === "upbit") updates[`${market.branch}/${market.symbol}`] = record;
    updatedMarkets.add(path);
  }
  for (const market of markets) {
    if (!updatedMarkets.has(`exchanges/${market.exchange}/${market.branch}`)) {
      throw new Error(`${market.exchange}/${market.branch} 전체 종목 매칭 실패`);
    }
  }
  return { updates, skipped };
}
