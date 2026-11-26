import { readFile } from "node:fs/promises";
import { createInterface } from "node:readline/promises";
import { Writable } from "node:stream";
import { priceMessage } from "./supabase/functions/send-mobit-push/price-message.mjs";
import { deliverFcmMessage } from "./supabase/functions/send-mobit-push/push.mjs";

async function main() {
  if (process.argv.length !== 3 || !process.stdin.isTTY) {
    throw new Error("터미널에서 node operations/test-device-push.mjs '서비스 계정 JSON 경로'를 실행하세요.");
  }
  let account;
  try {
    account = JSON.parse(await readFile(process.argv[2], "utf8"));
  } catch {
    throw new Error("서비스 계정 JSON을 읽을 수 없습니다.");
  }
  if (account.type !== "service_account" || account.project_id !== "mobit-68833") {
    throw new Error("모의비트 Firebase 서비스 계정을 지정하세요.");
  }

  const input = createInterface({ input: process.stdin, terminal: true, historySize: 0,
    output: new Writable({ write(_chunk, _encoding, done) { done(); } }) });
  let token;
  try {
    process.stderr.write("테스트 기기 FCM 토큰 (숨김 입력): ");
    token = (await input.question("")).trim();
  } finally {
    input.close();
    process.stderr.write("\n");
  }
  const response = await deliverFcmMessage(account, testDeviceMessage(token), false);
  const receipt = await response.json();
  if (!receipt.name?.startsWith("projects/mobit-68833/messages/")) throw new Error("FCM 접수 번호를 확인하지 못했습니다.");
  console.log("FCM이 단일 기기 테스트 푸시 1건을 접수했습니다.");
}

export function testDeviceMessage(token) {
  if (!/^[A-Za-z0-9_-]+:[A-Za-z0-9_-]+$/.test(token)) throw new Error("단일 기기의 FCM 등록 토큰을 입력하세요.");
  const example = priceMessage({ exchange: "bithumb", market: "KRW-BTC", hourLevel: 5, exchangeLevel: -10, endHourKst: 10 });
  return {
    token,
    notification: { ...example.notification, title: "[테스트] " + example.notification.title },
    data: { ...example.data, campaign_id: "device_test_price_alert" },
    apns: example.apns,
  };
}

if (import.meta.main) main().catch(error => {
  console.error(error.stage ? `FCM 발송 실패 (${error.stage}, HTTP ${error.remoteStatus ?? "응답 없음"})` : error.message);
  process.exitCode = 1;
});
