function hourRange(end) {
  const start = (end + 23) % 24;
  const period = hour => hour < 12 ? "오전 " : "오후 ";
  const clock = hour => (hour % 12 || 12) + "시";
  const endPeriod = period(start) === period(end) ? "" : period(end);
  return period(start) + clock(start) + "부터 " + endPeriod + clock(end) + "까지";
}

function percentText(level) {
  return Math.abs(level).toLocaleString("ko-KR", { maximumFractionDigits: 8 }) + "% 이상 ";
}

export function priceMessage({ exchange, market, basis, percent, hourLevel, exchangeLevel, endHourKst }) {
  if (!["upbit", "bithumb"].includes(exchange) || typeof market !== "string" || !/^KRW-[A-Z0-9]+$/.test(market)) return null;

  // 함수가 먼저 배포되므로 이전 SQL이 큐에 넣은 단일 기준 요청도 처리한다.
  const legacy = hourLevel === undefined && exchangeLevel === undefined;
  if (legacy && basis === "hour") hourLevel = percent;
  if (legacy && basis === "exchange") exchangeLevel = percent;
  const levels = [hourLevel, exchangeLevel].filter(level => level !== undefined);
  if (!levels.length || levels.some(level => !Number.isFinite(level) || level === 0)) return null;

  const combined = levels.length === 2;
  const comparison = combined ? "combined" : hourLevel !== undefined ? "hour" : "exchange";
  const mixed = combined && Math.sign(hourLevel) !== Math.sign(exchangeLevel);
  const direction = mixed ? "가격 변동" : levels[0] > 0 ? "상승" : "하락";
  const sentences = [];
  if (hourLevel !== undefined) {
    if (!legacy && (!Number.isInteger(endHourKst) || endHourKst < 0 || endHourKst > 23)) return null;
    const range = legacy ? "1시간 전보다" : hourRange(endHourKst);
    sentences.push(range + " " + percentText(hourLevel) + (hourLevel > 0 ? "올랐어요." : "내렸어요."));
  }
  if (exchangeLevel !== undefined) {
    if (combined) {
      sentences.push((mixed ? "전일 종가보다는 " : "전일 종가보다도 ") + percentText(exchangeLevel)
        + (exchangeLevel > 0 ? "높아요." : "낮아요."));
    } else {
      sentences.push("전일 종가보다 " + percentText(exchangeLevel) + (exchangeLevel > 0 ? "올랐어요." : "내렸어요."));
    }
  }
  const venue = exchange === "upbit" ? "업비트" : "빗썸";
  return {
    topic: "mobit_price_alerts",
    notification: { title: venue + " " + market.slice(4) + " " + direction, body: sentences.join(" ") },
    data: { type: "route", destination: "exchange", exchange, market, basis: comparison, campaign_id: "price_alert_" + comparison },
    apns: { payload: { aps: { sound: "default" } } },
  };
}
