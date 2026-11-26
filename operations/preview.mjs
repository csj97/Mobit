import { prepareUpdates } from "./supabase/functions/refresh-mobit-coins/coins.mjs";

async function preview() {
  const apiKey = process.env.MOBIT_CMC_API_KEY;
  if (!apiKey) throw new Error("MOBIT_CMC_API_KEY 설정이 필요합니다");
  const { updates, skipped } = await prepareUpdates(apiKey);
  const counts = {};
  for (const path of Object.keys(updates)) {
    const branch = path.slice(0, path.lastIndexOf("/"));
    counts[branch] = (counts[branch] || 0) + 1;
  }
  console.log(JSON.stringify({ counts, skipped }, null, 2));
}

preview().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});
