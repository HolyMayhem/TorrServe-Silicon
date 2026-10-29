import { DAY, dayOf, Env, HTTPError, secondsOf } from "./types";
import { versionPattern } from "./validation";
function dateValue(value: string): number {
  const s = secondsOf(value);
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(value) ||
    !Number.isFinite(s) ||
    dayOf(s) !== value
  )
    throw new HTTPError(400, "Invalid date");
  return s;
}
export async function statistics(env: Env, url: URL, now: number) {
  const today = secondsOf(dayOf(now)),
    end = dateValue(url.searchParams.get("end") ?? dayOf(now));
  const start = dateValue(
    url.searchParams.get("start") ?? dayOf(end - 29 * DAY),
  );
  if (start > end || end > today || start < today - 89 * DAY)
    throw new HTTPError(
      400,
      "Select up to 90 retained UTC days, ending no later than today",
    );
  const startDay = dayOf(start),
    endDay = dayOf(end);
  const latest =
    env.LATEST_APP_VERSION && versionPattern.test(env.LATEST_APP_VERSION)
      ? env.LATEST_APP_VERSION
      : null;
  // Latest observed snapshot PER installation in the interval, not event counts.
  const current = end === today;
  const populationArgs = current ? [start, end + DAY] : [startDay, endDay];
  const population = current
    ? `WITH population AS (SELECT app_version, macos_version, cpu_model, country FROM telemetry_installations WHERE last_seen >= ? AND last_seen < ?)`
    : `WITH population AS (SELECT a.* FROM telemetry_activity a JOIN (
 SELECT installation_id,MAX(day) day FROM telemetry_activity WHERE day BETWEEN ? AND ? GROUP BY installation_id
 ) b ON a.installation_id=b.installation_id AND a.day=b.day)`;
  const dimensions = [
    "app_version",
    "macos_version",
    "cpu_model",
    "country",
  ] as const;
  const batch = await env.DB.batch<Record<string, string | number | null>>([
    env.DB.prepare(
      "SELECT installations FROM telemetry_totals WHERE singleton=1",
    ),
    current
      ? env.DB.prepare(
          `SELECT COUNT(CASE WHEN last_seen >= ? THEN 1 END) dau,
 COUNT(CASE WHEN last_seen >= ? THEN 1 END) wau, COUNT(*) mau
 FROM telemetry_installations WHERE last_seen >= ? AND last_seen < ?`,
        ).bind(end, end - 6 * DAY, end - 29 * DAY, end + DAY)
      : env.DB.prepare(
          `SELECT COUNT(DISTINCT CASE WHEN day=? THEN installation_id END) dau,
 COUNT(DISTINCT CASE WHEN day>=? THEN installation_id END) wau, COUNT(DISTINCT installation_id) mau
 FROM telemetry_activity WHERE day BETWEEN ? AND ?`,
        ).bind(endDay, dayOf(end - 6 * DAY), dayOf(end - 29 * DAY), endDay),
    env.DB.prepare(
      "SELECT day,active,new_installations FROM telemetry_daily WHERE day BETWEEN ? AND ? ORDER BY day",
    ).bind(startDay, endDay),
    ...dimensions.map((column) =>
      env.DB.prepare(
        `${population} SELECT ${column} label,COUNT(*) count FROM population GROUP BY ${column} ORDER BY count DESC,label LIMIT ${column === "country" ? 250 : 100}`,
      ).bind(...populationArgs),
    ),
    env.DB.prepare(
      `${population} SELECT COUNT(*) active,COALESCE(SUM(app_version=?),0) current FROM population`,
    ).bind(...populationArgs, latest ?? ""),
    env.DB.prepare(
      "SELECT MAX(last_seen) last_received_at FROM telemetry_installations",
    ),
  ]);
  const daily = new Map(batch[2].results.map((row) => [row.day, row]));
  const activity = [];
  for (let day = start; day <= end; day += DAY)
    activity.push(
      daily.get(dayOf(day)) ?? {
        day: dayOf(day),
        active: 0,
        new_installations: 0,
      },
    );
  const adoption = batch[7].results[0] as { active: number; current: number };
  return {
    generatedAt: new Date(now * 1000).toISOString(),
    timezone: "UTC",
    range: { start: startDay, end: endDay },
    metrics: {
      installations: batch[0].results[0].installations,
      ...batch[1].results[0],
    },
    activity,
    versions: batch[3].results,
    macOS: batch[4].results,
    processors: batch[5].results,
    countries: batch[6].results,
    adoption: {
      latestVersion: latest,
      active: adoption.active,
      current: adoption.current,
      fraction:
        latest && adoption.active ? adoption.current / adoption.active : null,
    },
    system: {
      status: "operational",
      lastReceivedAt: batch[8].results[0].last_received_at,
      environment: env.ENVIRONMENT,
      authMode:
        env.ENVIRONMENT === "local"
          ? "local"
          : (env.ADMIN_AUTH_MODE ?? "access"),
      retentionDays: 120,
    },
  };
}
