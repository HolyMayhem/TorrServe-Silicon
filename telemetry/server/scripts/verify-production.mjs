// Checks authentication and reads aggregates. Never submits a production heartbeat.
import assert from "node:assert/strict";
import { adminKey } from "./admin-credentials.mjs";
const origin = "https://torrserve-telemetry.strayuglydog.workers.dev";
const request = (path, options = {}) =>
  fetch(origin + path, {
    redirect: "manual",
    signal: AbortSignal.timeout(15000),
    ...options,
  });
assert.equal((await request("/health")).status, 200, "Worker health");
const page = await request("/admin/");
assert.equal(page.status, 303, "Private dashboard redirect");
assert.equal(page.headers.get("Location"), "/admin/login");
for (const path of [
  "/admin/api/stats",
  "/admin/app.js",
  "/admin/styles.css",
  "/index.html",
  "/app.js",
  "/styles.css",
])
  assert.equal((await request(path)).status, 401, `Unauthenticated ${path}`);
for (const path of ["/admin/login", "/admin/login.css", "/admin/login.js"])
  assert.equal((await request(path)).status, 200, `Public login asset ${path}`);
const configurationResponse = await request("/admin/auth-config");
assert.equal(
  configurationResponse.status,
  200,
  "Public password configuration",
);
const configuration = await configurationResponse.json();
assert.equal(configuration.algorithm, "PBKDF2-SHA256");
assert.equal(configuration.iterations, 600000);
assert.equal(
  (await request("/admin/password-crypto.js")).status,
  200,
  "Browser password derivation",
);
if (configuration.mode === "password") {
  console.log(
    "PASS: private endpoints are protected; custom password is configured. Full authenticated check requires the owner session; bootstrap key was not used.",
  );
  process.exit(0);
}
assert.equal(configuration.mode, "key");
const login = await request("/admin/login", {
  method: "POST",
  headers: { Origin: origin, "Content-Type": "application/json" },
  body: JSON.stringify({ key: adminKey() }),
});
assert.equal(login.status, 204, "Administrator login");
const setCookie = login.headers.get("Set-Cookie");
assert.ok(setCookie);
for (const flag of ["Secure", "HttpOnly", "SameSite=Strict", "Max-Age=28800"])
  assert.ok(setCookie.includes(flag), "Secure cookie flags");
const cookie = setCookie.split(";")[0];
try {
  const response = await request("/admin/api/stats", {
    headers: { Cookie: cookie },
  });
  assert.equal(response.status, 200, "Authenticated statistics");
  assert.equal(response.headers.get("Cache-Control"), "no-store");
  const data = await response.json();
  assert.equal(data.system.authMode, "key");
  assert.ok(Array.isArray(data.countries));
  for (const name of ["installations", "dau", "wau", "mau"])
    assert.ok(Number.isInteger(data.metrics[name]) && data.metrics[name] >= 0);
  for (const path of ["/admin/", "/admin/app.js", "/admin/styles.css"])
    assert.equal(
      (await request(path, { headers: { Cookie: cookie } })).status,
      200,
      `Private asset ${path}`,
    );
  const dashboard = await request("/admin/", { headers: { Cookie: cookie } });
  assert.ok(
    (await dashboard.text()).includes('id="change-password"'),
    "Password change control",
  );
  const deniedChange = await request("/admin/api/password", {
    method: "POST",
    headers: {
      Cookie: cookie,
      Origin: "https://other.example",
      "Content-Type": "application/json",
    },
    body: "{}",
  });
  assert.equal(deniedChange.status, 403, "Cross-origin password change denied");
  console.log(
    "PASS: production authentication, protected assets, private D1 statistics, countries and cookie flags.",
  );
  console.log("Current aggregate counts:", JSON.stringify(data.metrics));
} finally {
  const logout = await request("/admin/logout", {
    method: "POST",
    headers: { Origin: origin, Cookie: cookie },
  });
  assert.equal(logout.status, 204, "Logout");
  assert.ok(logout.headers.get("Set-Cookie").includes("Max-Age=0"));
}
assert.equal(
  (await request("/admin/api/stats")).status,
  401,
  "No access without session",
);
console.log(
  "PASS: logout clears the browser cookie. No production test installation was created.",
);
