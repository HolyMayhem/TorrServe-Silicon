import { DAY, dayOf, Env, Heartbeat } from "./types";
export async function installationHash(id: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode("torrserve-telemetry-v1:" + id.toLowerCase()),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
export async function storeHeartbeat(
  env: Env,
  value: Heartbeat,
  now: number,
  country = "ZZ",
): Promise<boolean> {
  const id = await installationHash(value.installationID),
    day = dayOf(now);
  const budget = Math.min(
    5000,
    Math.max(1, Number(env.MAX_DAILY_HEARTBEATS) || 5000),
  );
  const result = await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO telemetry_activity
 (installation_id,day,received_at,app_version,macos_version,cpu_architecture,cpu_model,country)
 SELECT ?,?,?,?,?,?,?,?
 WHERE NOT EXISTS (SELECT 1 FROM telemetry_installations WHERE id = ? AND last_seen > ?)
 AND COALESCE((SELECT active FROM telemetry_daily WHERE day = ?),0) < ?
 ON CONFLICT(installation_id,day) DO NOTHING`,
    ).bind(
      id,
      day,
      now,
      value.appVersion,
      value.macOSVersion,
      value.cpuArchitecture,
      value.cpuModel,
      country,
      id,
      now - DAY,
      day,
      budget,
    ),
    env.DB.prepare(
      "SELECT last_seen FROM telemetry_installations WHERE id = ?",
    ).bind(id),
  ]);
  const row = result[1].results[0] as { last_seen: number } | undefined;
  return !!row && row.last_seen >= now - DAY;
}
export async function cleanup(env: Env, now: number): Promise<void> {
  await env.DB.batch([
    env.DB.prepare(
      `DELETE FROM telemetry_activity WHERE (installation_id,day) IN
 (SELECT installation_id,day FROM telemetry_activity WHERE day < ? LIMIT 5000)`,
    ).bind(dayOf(now - 120 * DAY)),
    env.DB.prepare(
      `DELETE FROM telemetry_installations WHERE id IN
 (SELECT id FROM telemetry_installations WHERE last_seen < ? LIMIT 1000)`,
    ).bind(now - 400 * DAY),
    env.DB.prepare("DELETE FROM telemetry_daily WHERE day < ?").bind(
      dayOf(now - 730 * DAY),
    ),
  ]);
}
