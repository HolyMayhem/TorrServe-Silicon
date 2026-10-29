-- Existing records retain Unknown: never infer historical countries from newer requests.
ALTER TABLE telemetry_installations ADD COLUMN country TEXT NOT NULL DEFAULT 'ZZ'
 CHECK (length(country) = 2 AND country GLOB '[A-Z][A-Z]');
ALTER TABLE telemetry_activity ADD COLUMN country TEXT NOT NULL DEFAULT 'ZZ'
 CHECK (length(country) = 2 AND country GLOB '[A-Z][A-Z]');

DROP TRIGGER telemetry_activity_added;
CREATE TRIGGER telemetry_activity_added AFTER INSERT ON telemetry_activity BEGIN
 INSERT INTO telemetry_installations(id, first_seen, last_seen, app_version, macos_version, cpu_architecture, cpu_model, country)
 VALUES (NEW.installation_id, NEW.received_at, NEW.received_at, NEW.app_version, NEW.macos_version, NEW.cpu_architecture, NEW.cpu_model, NEW.country)
 ON CONFLICT(id) DO UPDATE SET last_seen = excluded.last_seen, app_version = excluded.app_version,
 macos_version = excluded.macos_version, cpu_architecture = excluded.cpu_architecture, cpu_model = excluded.cpu_model,
 country = excluded.country;
 INSERT INTO telemetry_daily(day, active) VALUES (NEW.day, 1)
 ON CONFLICT(day) DO UPDATE SET active = active + 1;
END;
