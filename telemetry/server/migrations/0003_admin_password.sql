-- Authentication state is separate from analytics and is never included in retention cleanup.
CREATE TABLE telemetry_admin_auth (
 singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
 salt TEXT NOT NULL CHECK(length(salt) = 22),
 verifier TEXT NOT NULL CHECK(length(verifier) = 64),
 version INTEGER NOT NULL CHECK(version >= 1),
 updated_at INTEGER NOT NULL
);
