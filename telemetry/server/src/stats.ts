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
export async function statistics(env: Env, url: URL, now: number, hubSection?: string) {
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
    ? `WITH population AS (SELECT app_version, macos_version, cpu_model, cpu_architecture, country FROM telemetry_installations WHERE last_seen >= ? AND last_seen < ?)`
    : `WITH population AS (SELECT a.* FROM telemetry_activity a JOIN (
 SELECT installation_id,MAX(day) day FROM telemetry_activity WHERE day BETWEEN ? AND ? GROUP BY installation_id
 ) b ON a.installation_id=b.installation_id AND a.day=b.day)`;
  const dimensionGroups = {
    admin: ["app_version", "macos_version", "cpu_model", "country"],
    overview: ["app_version", "macos_version", "cpu_model", "country", "cpu_architecture"],
    devices: ["macos_version", "cpu_model", "cpu_architecture"],
    geography: ["country"],
    versions: ["app_version"],
  } as const;
  const dimensions = dimensionGroups[(hubSection ?? "admin") as keyof typeof dimensionGroups] ?? [];
  const dimensionSql = `${population}, grouped AS (
    SELECT labels.key dimension, labels.value label, COUNT(*) count FROM population,
      json_each(json_object(${dimensions.map(column => `'${column}',${column}`).join(",")})) labels
    GROUP BY labels.key, labels.value
  ), ranked AS (
    SELECT *, SUM(count) OVER (PARTITION BY dimension) sample,
      SUM(CASE WHEN label=? THEN count ELSE 0 END) OVER (PARTITION BY dimension) current,
      ROW_NUMBER() OVER (PARTITION BY dimension ORDER BY count DESC,label) rank FROM grouped
  )
  SELECT dimension,label,count,sample,current FROM ranked
  WHERE rank <= CASE dimension WHEN 'country' THEN 250 ELSE 100 END ORDER BY dimension,rank`;
  const withAdoption = hubSection === undefined || ["summary", "overview", "versions"].includes(hubSection);
  const previousEnd = end - (end === today ? DAY : 0);
  const comparisonDays = Math.max(0, 1 + (previousEnd - start) / DAY);
  const previousStart = start - comparisonDays * DAY;
  const compare = ["summary", "overview", "audience"].includes(hubSection ?? "") &&
    comparisonDays > 0 && previousStart >= today - 89 * DAY;
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
    ).bind(compare ? dayOf(previousStart) : startDay, endDay),
    env.DB.prepare(
      "SELECT MAX(last_seen) last_received_at FROM telemetry_installations",
    ),
    ...(dimensions.length ? [env.DB.prepare(dimensionSql).bind(...populationArgs, latest ?? "")] :
      withAdoption ? [env.DB.prepare(
        `${population} SELECT COUNT(*) active,COALESCE(SUM(app_version=?),0) current FROM population`,
      ).bind(...populationArgs, latest ?? "")] : []),
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
  type Bucket = { label: string | number | null; count: string | number | null };
  const grouped = new Map<string, Bucket[]>();
  const rows = batch[4]?.results ?? [];
  if (dimensions.length) for (const row of rows) {
    const key = String(row.dimension);
    const values = grouped.get(key) ?? [];
    values.push({ label: row.label, count: row.count });
    grouped.set(key, values);
  }
  const sample = Number(dimensions.length ? rows[0]?.sample ?? 0 : rows[0]?.active ?? 0);
  const adoption = {
    active: withAdoption ? sample : 0,
    current: withAdoption ? Number((dimensions.length ? rows.find(row => row.dimension === "app_version") : rows[0])?.current ?? 0) : 0,
  };
  const previous = [];
  if (compare) for (let day = previousStart; day < start; day += DAY) {
    const date = dayOf(day);
    previous.push(daily.get(date) ?? { day: date, active: 0, new_installations: 0 });
  }
  return {
    generatedAt: new Date(now * 1000).toISOString(),
    timezone: "UTC",
    range: { start: startDay, end: endDay },
    metrics: {
      installations: batch[0].results[0].installations,
      ...batch[1].results[0],
    },
    activity,
    versions: grouped.get("app_version") ?? [],
    macOS: grouped.get("macos_version") ?? [],
    processors: grouped.get("cpu_model") ?? [],
    countries: grouped.get("country") ?? [],
    ...(hubSection === undefined ? {} : {
      architectures: grouped.get("cpu_architecture") ?? [],
      previous,
      ...(dimensions.length && !withAdoption ? { sample } : {}),
    }),
    adoption: {
      latestVersion: latest,
      active: adoption.active,
      current: adoption.current,
      fraction:
        latest && adoption.active ? adoption.current / adoption.active : null,
    },
    system: {
      status: "operational",
      lastReceivedAt: batch[3].results[0].last_received_at,
      environment: env.ENVIRONMENT,
      authMode:
        env.ENVIRONMENT === "local"
          ? "local"
          : (env.ADMIN_AUTH_MODE ?? "access"),
      retentionDays: 120,
    },
  };
}
