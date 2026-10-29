-- Namespaced: never touches existing application tables.
CREATE TABLE telemetry_totals (
 singleton INTEGER PRIMARY KEY CHECK(singleton = 1), installations INTEGER NOT NULL DEFAULT 0
);
INSERT INTO telemetry_totals VALUES (1, 0);
CREATE TABLE telemetry_installations (
 id TEXT PRIMARY KEY, first_seen INTEGER NOT NULL, last_seen INTEGER NOT NULL,
 app_version TEXT NOT NULL, macos_version TEXT NOT NULL,
 cpu_architecture TEXT NOT NULL CHECK(cpu_architecture IN ('arm64','x86_64')), cpu_model TEXT NOT NULL
) WITHOUT ROWID;
CREATE INDEX telemetry_installations_last_seen ON telemetry_installations(last_seen);
CREATE TABLE telemetry_daily (
 day TEXT PRIMARY KEY, active INTEGER NOT NULL DEFAULT 0, new_installations INTEGER NOT NULL DEFAULT 0
) WITHOUT ROWID;
CREATE TABLE telemetry_activity (
 installation_id TEXT NOT NULL, day TEXT NOT NULL, received_at INTEGER NOT NULL,
 app_version TEXT NOT NULL, macos_version TEXT NOT NULL,
 cpu_architecture TEXT NOT NULL CHECK(cpu_architecture IN ('arm64','x86_64')), cpu_model TEXT NOT NULL,
 PRIMARY KEY(installation_id, day)
) WITHOUT ROWID;
CREATE INDEX telemetry_activity_day ON telemetry_activity(day, installation_id);
CREATE TRIGGER telemetry_installation_added AFTER INSERT ON telemetry_installations BEGIN
 UPDATE telemetry_totals SET installations = installations + 1 WHERE singleton = 1;
 INSERT INTO telemetry_daily(day, new_installations) VALUES (date(NEW.first_seen, 'unixepoch'), 1)
 ON CONFLICT(day) DO UPDATE SET new_installations = new_installations + 1;
END;
-- Runs only on an inserted heartbeat, atomically with the INSERT.
CREATE TRIGGER telemetry_activity_added AFTER INSERT ON telemetry_activity BEGIN
 INSERT INTO telemetry_installations(id, first_seen, last_seen, app_version, macos_version, cpu_architecture, cpu_model)
 VALUES (NEW.installation_id, NEW.received_at, NEW.received_at, NEW.app_version, NEW.macos_version, NEW.cpu_architecture, NEW.cpu_model)
 ON CONFLICT(id) DO UPDATE SET last_seen = excluded.last_seen, app_version = excluded.app_version,
 macos_version = excluded.macos_version, cpu_architecture = excluded.cpu_architecture, cpu_model = excluded.cpu_model;
 INSERT INTO telemetry_daily(day, active) VALUES (NEW.day, 1)
 ON CONFLICT(day) DO UPDATE SET active = active + 1;
END;
