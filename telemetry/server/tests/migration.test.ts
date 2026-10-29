import { it, expect } from "vitest";
import { Miniflare, convertV4MiniflareOptions } from "miniflare";
import { applyMigration } from "./migrations";
import { storeHeartbeat } from "../src/storage";
import { DAY, type Env } from "../src/types";
it("upgrades existing v1 data without resetting installation or daily counts", async () => {
  const mf = new Miniflare(
    convertV4MiniflareOptions({
      modules: true,
      script: 'export default {fetch(){return new Response("test")}}',
      compatibilityDate: "2026-10-23",
      d1Databases: { DB: "upgrade-test" },
    }),
  );
  try {
    const DB = await mf.getD1Database("DB");
    await applyMigration(DB, "0001_telemetry.sql");
    await DB.prepare(
      `INSERT INTO telemetry_activity VALUES ('legacy-id', '2026-10-29', 1793275200, '2.7.0', '15.7.0', 'arm64', 'Apple M4')`,
    ).run();
    await applyMigration(DB, "0002_country.sql");
    expect(
      await DB.prepare("SELECT country FROM telemetry_installations").first(
        "country",
      ),
    ).toBe("ZZ");
    expect(
      await DB.prepare("SELECT country FROM telemetry_activity").first(
        "country",
      ),
    ).toBe("ZZ");
    expect(
      await DB.prepare("SELECT installations FROM telemetry_totals").first(
        "installations",
      ),
    ).toBe(1);
    expect(
      await DB.prepare("SELECT active FROM telemetry_daily").first("active"),
    ).toBe(1);
    const env = { DB, MAX_DAILY_HEARTBEATS: "5000" } as unknown as Env;
    expect(
      await storeHeartbeat(
        env,
        {
          schemaVersion: 1,
          installationID: crypto.randomUUID(),
          appVersion: "2.8.0",
          macOSVersion: "15.7.0",
          cpuArchitecture: "arm64",
          cpuModel: "Apple M4",
        },
        1793275200 + DAY,
        "DE",
      ),
    ).toBe(true);
    expect(
      await DB.prepare(
        "SELECT COUNT(*) n FROM telemetry_installations WHERE country='DE'",
      ).first("n"),
    ).toBe(1);
    expect(
      await DB.prepare("SELECT installations FROM telemetry_totals").first(
        "installations",
      ),
    ).toBe(2);
  } finally {
    await mf.dispose();
  }
});
