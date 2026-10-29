import { readFile, readdir } from "node:fs/promises";

export async function applyMigration(
  db: D1Database,
  filename: string,
): Promise<void> {
  const sql = (
    await readFile(
      new URL("../migrations/" + filename, import.meta.url),
      "utf8",
    )
  ).replace(/--[^\n]*/g, "");
  // Only top-level unindented statements; trigger bodies remain a single statement.
  for (const statement of sql
    .split(/(?=^(?:CREATE|ALTER|DROP) |^INSERT INTO telemetry_totals)/m)
    .map((s) => s.trim())
    .filter(Boolean))
    await db.prepare(statement).run();
}

export async function applyAllMigrations(db: D1Database): Promise<void> {
  const files = (await readdir(new URL("../migrations/", import.meta.url)))
    .filter((file) => /^\d+_.+\.sql$/.test(file))
    .sort();
  for (const file of files) await applyMigration(db, file);
}
