import {
  beforeAll,
  afterAll,
  beforeEach,
  describe,
  it,
  expect,
  vi,
} from "vitest";
import { Miniflare, convertV4MiniflareOptions } from "miniflare";
import { applyAllMigrations } from "./migrations";
import { countryFromRequest, normalizeCountry } from "../src/country";
import { generateKeyPair, exportJWK, SignJWT } from "jose";
import { pbkdf2Sync } from "node:crypto";
import { handleRequest } from "../src/index";
import { cleanup, installationHash, storeHeartbeat } from "../src/storage";
import { statistics } from "../src/stats";
import { DAY, dayOf, type Env, type Heartbeat } from "../src/types";
import {
  derivePassword,
  newSalt,
  credentialForInput,
  validateNewPassword,
} from "../public/password-crypto.js";
const now = Date.parse("2026-10-30T12:00:00Z") / 1000;
const payload: Heartbeat = {
  schemaVersion: 1,
  installationID: "e30710ba-3e87-48c1-a0f0-3d7c1685c301",
  appVersion: "2.8.0",
  macOSVersion: "15.7.0",
  cpuArchitecture: "arm64",
  cpuModel: "Apple M4 Pro",
};
let mf: Miniflare, env: Env;
const post = (body: unknown = payload, headers = {}) =>
  new Request("http://localhost/v1/heartbeat", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
const stats = (start = dayOf(now - 29 * DAY), end = dayOf(now)) =>
  statistics(
    env,
    new URL(`http://localhost/admin/api/stats?start=${start}&end=${end}`),
    now,
  );
const heartbeat = (body = payload, time = now) =>
  handleRequest(post(body), env, time);
beforeAll(async () => {
  mf = new Miniflare(
    convertV4MiniflareOptions({
      modules: true,
      script: 'export default {fetch() {return new Response("test")}}',
      compatibilityDate: "2026-10-23",
      d1Databases: { DB: "telemetry-tests" },
    }),
  );
  const DB = await mf.getD1Database("DB");
  await applyAllMigrations(DB);
  env = {
    DB,
    ENVIRONMENT: "local",
    LATEST_APP_VERSION: "2.8.0",
    MAX_DAILY_HEARTBEATS: "5000",
    ASSETS: { fetch: vi.fn(async () => new Response("private")) },
    INGRESS_LIMITER: { limit: vi.fn(async () => ({ success: true })) },
    INSTALLATION_LIMITER: { limit: vi.fn(async () => ({ success: true })) },
  } as unknown as Env;
});
afterAll(async () => {
  await mf?.dispose();
});
beforeEach(async () => {
  await env.DB.batch(
    [
      "DELETE FROM telemetry_admin_auth",
      "DELETE FROM telemetry_activity",
      "DELETE FROM telemetry_installations",
      "DELETE FROM telemetry_daily",
      "UPDATE telemetry_totals SET installations=0",
    ].map((s) => env.DB.prepare(s)),
  );
  env.ADMIN_AUTH_MODE = undefined;
  env.ENVIRONMENT = "local";
  env.MAX_DAILY_HEARTBEATS = "5000";
  vi.mocked(env.INGRESS_LIMITER.limit).mockResolvedValue({ success: true });
  vi.mocked(env.INSTALLATION_LIMITER.limit).mockResolvedValue({
    success: true,
  });
});
describe("D1 ingestion and aggregation", () => {
  it("deduplicates concurrent replays and stores only a hash of the UUID", async () => {
    const responses = await Promise.all(
      Array.from({ length: 16 }, () => heartbeat()),
    );
    expect(responses.every((r) => r.status === 204)).toBe(true);
    const data = await stats();
    expect(data.metrics).toEqual({ installations: 1, dau: 1, wau: 1, mau: 1 });
    expect(data.activity.at(-1)).toEqual({
      day: "2026-10-30",
      active: 1,
      new_installations: 1,
    });
    const row = await env.DB.prepare(
      "SELECT * FROM telemetry_installations",
    ).first();
    expect(row?.id).toBe(await installationHash(payload.installationID));
    expect(JSON.stringify(row)).not.toContain(payload.installationID);
    expect(Object.keys(row!).sort()).toEqual(
      [
        "id",
        "first_seen",
        "last_seen",
        "app_version",
        "macos_version",
        "cpu_architecture",
        "cpu_model",
        "country",
      ].sort(),
    );
  });
  it("normalizes UUID casing", async () => {
    await heartbeat();
    await heartbeat({
      ...payload,
      installationID: payload.installationID.toUpperCase(),
    });
    expect((await stats()).metrics.installations).toBe(1);
  });
  it("enforces 24 hours across UTC midnight and refreshes versions on next heartbeat", async () => {
    await heartbeat({ ...payload, appVersion: "2.7.0" }, now - DAY);
    await heartbeat(payload, now - DAY + 13 * 3600);
    expect((await stats()).versions).toEqual([{ label: "2.7.0", count: 1 }]);
    await heartbeat();
    const data = await stats();
    expect(data.metrics.installations).toBe(1);
    expect(data.adoption.fraction).toBe(1);
    expect(data.versions).toEqual([{ label: "2.8.0", count: 1 }]);
    expect(data.activity.slice(-2).map((r) => r.active)).toEqual([1, 1]);
  });
  it("counts unique IDs in rolling UTC DAU/WAU/MAU windows and historical windows", async () => {
    for (const ago of [0, 6, 7, 29, 30])
      await storeHeartbeat(
        env,
        { ...payload, installationID: crypto.randomUUID() },
        now - ago * DAY,
      );
    expect((await stats()).metrics).toEqual({
      installations: 5,
      dau: 1,
      wau: 2,
      mau: 4,
    });
    const old = await stats(dayOf(now - 29 * DAY), dayOf(now - DAY));
    expect(old.metrics.dau).toBe(0);
    expect(old.metrics.wau).toBe(2);
    expect(old.metrics.mau).toBe(4);
  });
  it("uses last snapshot inside selected range", async () => {
    await heartbeat({ ...payload, appVersion: "2.7.0" }, now - 2 * DAY);
    await heartbeat();
    expect(
      (await stats(dayOf(now - 7 * DAY), dayOf(now - DAY))).versions,
    ).toEqual([{ label: "2.7.0", count: 1 }]);
  });
  it("supports Intel CPU families", async () => {
    expect(
      (
        await heartbeat({
          ...payload,
          cpuArchitecture: "x86_64",
          cpuModel: "Intel Core i7",
        })
      ).status,
    ).toBe(204);
    expect((await stats()).processors).toEqual([
      { label: "Intel Core i7", count: 1 },
    ]);
  });
  it("returns honest zero-filled empty state", async () => {
    const data = await stats();
    expect(data.metrics).toEqual({ installations: 0, dau: 0, wau: 0, mau: 0 });
    expect(data.activity).toHaveLength(30);
    expect(data.adoption.fraction).toBeNull();
    expect(data.system.lastReceivedAt).toBeNull();
  });
  it("caps daily ingestion but acknowledges duplicates", async () => {
    env.MAX_DAILY_HEARTBEATS = "1";
    expect((await heartbeat()).status).toBe(204);
    expect(
      (await heartbeat({ ...payload, installationID: crypto.randomUUID() }))
        .status,
    ).toBe(503);
    expect((await heartbeat()).status).toBe(204);
    expect((await stats()).metrics.installations).toBe(1);
  });
  it("retains lifetime counters after expiration of linkable data", async () => {
    await heartbeat(payload, now - 401 * DAY);
    await heartbeat(
      { ...payload, installationID: crypto.randomUUID() },
      now - 121 * DAY,
    );
    await heartbeat(
      { ...payload, installationID: crypto.randomUUID() },
      now - DAY,
    );
    await cleanup(env, now);
    expect(
      await env.DB.prepare("SELECT COUNT(*) n FROM telemetry_activity").first(
        "n",
      ),
    ).toBe(1);
    expect(
      await env.DB.prepare(
        "SELECT COUNT(*) n FROM telemetry_installations",
      ).first("n"),
    ).toBe(2);
    expect((await stats()).metrics.installations).toBe(3);
  });
  it("indexes date-bounded activity queries", async () => {
    const plan = await env.DB.prepare(
      "EXPLAIN QUERY PLAN SELECT installation_id FROM telemetry_activity WHERE day BETWEEN ? AND ?",
    )
      .bind("2026-10-01", "2026-10-30")
      .all();
    expect(JSON.stringify(plan.results)).toContain("telemetry_activity_day");
  });
});
describe("validation and abuse controls", () => {
  it.each([
    { ...payload, torrentName: "private" },
    { ...payload, installationID: "serial" },
    { ...payload, schemaVersion: 2 },
    { ...payload, appVersion: "latest" },
    { ...payload, macOSVersion: "user@host" },
    { ...payload, cpuModel: "Apple M4 serial123" },
    { ...payload, cpuArchitecture: "arm64", cpuModel: "Intel Core i7" },
    [],
    null,
  ])("rejects invalid schema %j", async (value) => {
    expect((await handleRequest(post(value), env, now)).status).toBe(400);
    expect((await stats()).metrics.installations).toBe(0);
  });
  it("limits actual bytes and declared length", async () => {
    expect(
      (await handleRequest(post({ value: "x".repeat(2048) }), env, now)).status,
    ).toBe(413);
    expect(
      (
        await handleRequest(
          post(payload, { "Content-Length": "9999999" }),
          env,
          now,
        )
      ).status,
    ).toBe(413);
  });
  it("requires JSON, rejects compression, malformed JSON and non-POST", async () => {
    expect(
      (
        await handleRequest(
          post(payload, { "Content-Type": "text/plain" }),
          env,
          now,
        )
      ).status,
    ).toBe(415);
    expect(
      (
        await handleRequest(
          post(payload, { "Content-Encoding": "gzip" }),
          env,
          now,
        )
      ).status,
    ).toBe(415);
    expect(
      (
        await handleRequest(
          new Request("http://localhost/v1/heartbeat", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: "{",
          }),
          env,
          now,
        )
      ).status,
    ).toBe(400);
    expect(
      (
        await handleRequest(
          new Request("http://localhost/v1/heartbeat"),
          env,
          now,
        )
      ).status,
    ).toBe(405);
  });
  it("rate limits before D1", async () => {
    vi.mocked(env.INGRESS_LIMITER.limit).mockResolvedValue({ success: false });
    const response = await heartbeat();
    expect(response.status).toBe(429);
    expect(response.headers.get("Retry-After")).toBe("60");
    expect((await stats()).metrics.installations).toBe(0);
  });
  it("redacts internal exceptions", async () => {
    const broken = {
      ...env,
      DB: {
        batch: async () => {
          throw new Error("secret query");
        },
      },
    } as unknown as Env;
    const response = await handleRequest(post(), broken, now);
    expect(response.status).toBe(503);
    expect(await response.text()).not.toContain("secret");
  });
  it("rejects invalid/out-of-retention dates", async () => {
    for (const [start, end] of [
      ["2026-02-30", "2026-10-30"],
      ["2026-11-01", "2026-11-02"],
      ["2026-10-30", "2026-10-01"],
      ["2025-01-01", "2026-10-30"],
    ])
      await expect(stats(start, end)).rejects.toMatchObject({ status: 400 });
  });
});
describe("private dashboard", () => {
  it("authenticates assets too, including direct unprefixed paths", async () => {
    const response = await handleRequest(
      new Request("http://localhost/admin/"),
      env,
      now,
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(response.headers.get("Content-Security-Policy")).toContain(
      "frame-ancestors 'none'",
    );
    env.ENVIRONMENT = "production";
    for (const path of [
      "/admin/",
      "/admin/app.js",
      "/admin/styles.css",
      "/admin/api/stats",
      "/index.html",
      "/app.js",
      "/styles.css",
      "/",
    ])
      expect(
        (
          await handleRequest(
            new Request("https://private.example" + path),
            env,
            now,
          )
        ).status,
      ).toBe(503);
  });
  it("does not bypass auth on a public host in local mode", async () => {
    expect(
      (
        await handleRequest(
          new Request("https://public.example/admin/api/stats"),
          env,
          now,
        )
      ).status,
    ).toBe(503);
  });
  it("verifies JWT signature, issuer, audience, expiry and administrator email", async () => {
    env.ENVIRONMENT = "production";
    env.ACCESS_TEAM_DOMAIN = "telemetry-test.cloudflareaccess.com";
    env.ACCESS_AUD = "test-audience";
    env.ACCESS_ADMIN_EMAILS = "admin@example.com";
    const { publicKey, privateKey } = await generateKeyPair("RS256");
    const jwk = {
      ...(await exportJWK(publicKey)),
      kid: "test-key",
      alg: "RS256",
      use: "sig",
    };
    const fetchMock = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ keys: [jwk] }), {
        headers: { "Content-Type": "application/json" },
      }),
    );
    const issue = (email = "admin@example.com") =>
      new SignJWT({ email })
        .setProtectedHeader({ alg: "RS256", kid: "test-key" })
        .setSubject("admin")
        .setIssuedAt()
        .setIssuer("https://telemetry-test.cloudflareaccess.com")
        .setAudience("test-audience")
        .setExpirationTime("1h");
    const request = (token?: string) =>
      new Request("https://private.example/admin/api/stats", {
        headers: token ? { "Cf-Access-Jwt-Assertion": token } : {},
      });
    try {
      expect((await handleRequest(request(), env, now)).status).toBe(401);
      expect((await handleRequest(request("forged"), env, now)).status).toBe(
        403,
      );
      expect(
        (await handleRequest(request(await issue().sign(privateKey)), env, now))
          .status,
      ).toBe(200);
      for (const jwt of [
        issue("outsider@example.com"),
        issue().setAudience("wrong"),
        issue().setIssuer("https://wrong.example"),
        issue().setExpirationTime(1),
      ])
        expect(
          (await handleRequest(request(await jwt.sign(privateKey)), env, now))
            .status,
        ).toBe(403);
      const other = await generateKeyPair("RS256");
      expect(
        (
          await handleRequest(
            request(await issue().sign(other.privateKey)),
            env,
            now,
          )
        ).status,
      ).toBe(403);
    } finally {
      fetchMock.mockRestore();
    }
  });
});

describe("connection country", () => {
  const withCountry = (
    country: unknown,
    body: unknown = payload,
    headers = {},
  ) => {
    const request = post(body, headers);
    Object.defineProperty(request, "cf", { value: { country } });
    return request;
  };
  it.each([
    undefined,
    null,
    "",
    "XX",
    "T1",
    "ZZ",
    "AA",
    "ru",
    "user@host",
    123,
  ])(
    "groups unavailable and unsupported country %j as Unknown",
    async (country) => {
      expect(normalizeCountry(country)).toBe("ZZ");
      expect((await handleRequest(withCountry(country), env, now)).status).toBe(
        204,
      );
      expect((await stats()).countries).toEqual([{ label: "ZZ", count: 1 }]);
    },
  );
  it("trusts only edge metadata and never a client country field or header", async () => {
    const request = withCountry("DE", payload, {
      "CF-IPCountry": "RU",
      "CF-Connecting-IP": "203.0.113.7",
      "User-Agent": "private user agent",
    });
    expect(countryFromRequest(request)).toBe("DE");
    expect((await handleRequest(request, env, now)).status).toBe(204);
    expect((await stats()).countries).toEqual([{ label: "DE", count: 1 }]);
    const rows = await env.DB.prepare("SELECT * FROM telemetry_activity").all();
    expect(JSON.stringify(rows.results)).not.toContain("203.0.113.7");
    expect(JSON.stringify(rows.results)).not.toContain("private user agent");
    expect(
      (
        await handleRequest(
          withCountry("US", { ...payload, country: "RU" }),
          env,
          now,
        )
      ).status,
    ).toBe(400);
    expect(countryFromRequest(post(payload, { "CF-IPCountry": "RU" }))).toBe(
      "ZZ",
    );
  });
  it("deduplicates country changes and preserves historical country snapshots", async () => {
    await handleRequest(withCountry("RU"), env, now - 2 * DAY);
    await handleRequest(withCountry("DE"), env, now - 2 * DAY + 60);
    expect((await stats()).countries).toEqual([{ label: "RU", count: 1 }]);
    await handleRequest(withCountry("DE"), env, now);
    const data = await stats();
    expect(data.metrics.installations).toBe(1);
    expect(data.countries).toEqual([{ label: "DE", count: 1 }]);
    expect(
      (await stats(dayOf(now - 7 * DAY), dayOf(now - DAY))).countries,
    ).toEqual([{ label: "RU", count: 1 }]);
  });
  it("counts installations rather than heartbeat events in country shares", async () => {
    await handleRequest(withCountry("US"), env, now - DAY);
    await handleRequest(withCountry("US"), env, now);
    await handleRequest(
      withCountry("US", { ...payload, installationID: crypto.randomUUID() }),
      env,
      now,
    );
    await handleRequest(
      withCountry("DE", { ...payload, installationID: crypto.randomUUID() }),
      env,
      now,
    );
    const data = await stats();
    expect(data.countries).toEqual([
      { label: "US", count: 2 },
      { label: "DE", count: 1 },
    ]);
    expect(data.adoption.active).toBe(3);
  });
});

describe("administrator key sessions", () => {
  let loginKey: string;
  const origin = "https://private.example";
  const loginRequest = (body: unknown, headers: Record<string, string> = {}) =>
    new Request(origin + "/admin/login", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Origin: origin,
        ...headers,
      },
      body: JSON.stringify(body),
    });
  const authenticated = (
    path: string,
    cookie: string,
    method = "GET",
    site = origin,
  ) =>
    new Request(site + path, {
      method,
      headers: { Cookie: cookie, Origin: site },
    });
  const session = async () => {
    const response = await handleRequest(
      loginRequest({ key: loginKey }),
      env,
      now,
    );
    expect(response.status).toBe(204);
    return response.headers.get("Set-Cookie")!.split(";")[0];
  };
  beforeEach(async () => {
    env.ENVIRONMENT = "production";
    env.ADMIN_AUTH_MODE = "key";
    loginKey = Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString(
      "base64url",
    );
    env.ADMIN_KEY_SHA256 = Buffer.from(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(loginKey)),
    ).toString("hex");
    env.ADMIN_SESSION_SECRET = Buffer.from(
      crypto.getRandomValues(new Uint8Array(32)),
    ).toString("base64url");
    env.ADMIN_LIMITER = {
      limit: vi.fn(async () => ({ success: true })),
    } as unknown as RateLimit;
  });
  beforeEach(() => {
    env.ADMIN_PASSWORD_PEPPER = Buffer.from(
      crypto.getRandomValues(new Uint8Array(32)),
    ).toString("base64url");
  });
  it("issues a private secure session only for the correct key", async () => {
    const response = await handleRequest(
      loginRequest({ key: loginKey }),
      env,
      now,
    );
    expect(response.status).toBe(204);
    const cookie = response.headers.get("Set-Cookie")!;
    for (const attribute of [
      "__Host-TorrServeAdmin=",
      "Path=/",
      "Secure",
      "HttpOnly",
      "SameSite=Strict",
      "Max-Age=28800",
    ])
      expect(cookie).toContain(attribute);
    expect(cookie).not.toContain(loginKey);
    expect(await response.text()).toBe("");
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    const data = await handleRequest(
      authenticated("/admin/api/stats", cookie.split(";")[0]),
      env,
      now,
    );
    expect(data.status).toBe(200);
    expect((await data.json()).system.authMode).toBe("key");
  });
  it("protects every private asset and redirects only the dashboard document to login", async () => {
    const main = await handleRequest(new Request(origin + "/admin/"), env, now);
    expect(main.status).toBe(303);
    expect(main.headers.get("Location")).toBe("/admin/login");
    for (const path of [
      "/admin/api/stats",
      "/admin/app.js",
      "/admin/styles.css",
      "/index.html",
      "/app.js",
      "/styles.css",
      "/login.html",
    ])
      expect(
        (await handleRequest(new Request(origin + path), env, now)).status,
      ).toBe(401);
    for (const path of ["/admin/login", "/admin/login.js", "/admin/login.css"])
      expect(
        (await handleRequest(new Request(origin + path), env, now)).status,
      ).toBe(200);
  });
  it("rejects malformed, wrong, oversized and extra-field credentials", async () => {
    for (const body of [
      { key: "a".repeat(43) },
      { key: loginKey, extra: true },
      { key: 123 },
      [],
      null,
    ]) {
      const result = await handleRequest(loginRequest(body), env, now);
      expect(result.status).toBe(
        body === null || Array.isArray(body) ? 400 : 401,
      );
      expect(result.headers.has("Set-Cookie")).toBe(false);
      expect(await result.text()).not.toContain(loginKey);
    }
    expect(
      (await handleRequest(loginRequest({ key: "x".repeat(512) }), env, now))
        .status,
    ).toBe(413);
  });
  it("blocks cross-origin login and logout and insecure credentials", async () => {
    expect(
      (
        await handleRequest(
          loginRequest(
            { key: loginKey },
            { Origin: "https://attacker.example" },
          ),
          env,
          now,
        )
      ).status,
    ).toBe(403);
    const cookie = await session();
    const logout = new Request(origin + "/admin/logout", {
      method: "POST",
      headers: { Cookie: cookie, Origin: "https://attacker.example" },
    });
    expect((await handleRequest(logout, env, now)).status).toBe(403);
    const insecure = new Request("http://private.example/admin/login", {
      method: "POST",
      headers: {
        Origin: "http://private.example",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ key: loginKey }),
    });
    expect((await handleRequest(insecure, env, now)).status).toBe(403);
    expect(
      (
        await handleRequest(
          authenticated(
            "/admin/api/stats",
            cookie,
            "GET",
            "http://private.example",
          ),
          env,
          now,
        )
      ).status,
    ).toBe(401);
  });
  it("rate limits login independently of telemetry and fails closed without server secrets", async () => {
    vi.mocked(env.ADMIN_LIMITER!.limit).mockResolvedValue({ success: false });
    expect(
      (await handleRequest(loginRequest({ key: loginKey }), env, now)).status,
    ).toBe(429);
    expect((await heartbeat()).status).toBe(204);
    delete env.ADMIN_SESSION_SECRET;
    expect(
      (await handleRequest(loginRequest({ key: loginKey }), env, now)).status,
    ).toBe(503);
    expect(
      (await handleRequest(new Request(origin + "/admin/api/stats"), env, now))
        .status,
    ).toBe(503);
  });
  it("rejects forged, expired, cross-host and duplicate cookies", async () => {
    const cookie = await session();
    expect(
      (
        await handleRequest(
          authenticated(
            "/admin/api/stats",
            cookie,
            "GET",
            "https://other.example",
          ),
          env,
          now,
        )
      ).status,
    ).toBe(401);
    expect(
      (
        await handleRequest(
          authenticated("/admin/api/stats", cookie + "; " + cookie),
          env,
          now,
        )
      ).status,
    ).toBe(401);
    const forged = cookie.slice(0, -8) + "forgery_";
    expect(
      (await handleRequest(authenticated("/admin/api/stats", forged), env, now))
        .status,
    ).toBe(401);
    const expired = await new SignJWT({})
      .setProtectedHeader({ alg: "HS256" })
      .setSubject("administrator")
      .setIssuer("torrserve-telemetry")
      .setAudience(origin + "/admin")
      .setIssuedAt(1)
      .setExpirationTime(2)
      .sign(new TextEncoder().encode(env.ADMIN_SESSION_SECRET));
    expect(
      (
        await handleRequest(
          authenticated("/admin/api/stats", "__Host-TorrServeAdmin=" + expired),
          env,
          now,
        )
      ).status,
    ).toBe(401);
  });
  it("expires the browser cookie on logout and rejects GET logout", async () => {
    const cookie = await session();
    const response = await handleRequest(
      authenticated("/admin/logout", cookie, "POST"),
      env,
      now,
    );
    expect(response.status).toBe(204);
    expect(response.headers.get("Set-Cookie")).toContain("Max-Age=0");
    expect(
      (await handleRequest(authenticated("/admin/logout", cookie), env, now))
        .status,
    ).toBe(405);
    expect(
      (await handleRequest(new Request(origin + "/admin/api/stats"), env, now))
        .status,
    ).toBe(401);
  });
  it("invalidates all prior sessions when the signing secret is rotated", async () => {
    const cookie = await session();
    env.ADMIN_SESSION_SECRET = "Z".repeat(43);
    expect(
      (await handleRequest(authenticated("/admin/api/stats", cookie), env, now))
        .status,
    ).toBe(401);
  });
  const update = (cookie: string, body: unknown, headers = {}) =>
    handleRequest(
      new Request(origin + "/admin/api/password", {
        method: "POST",
        headers: {
          Origin: origin,
          "Content-Type": "application/json",
          Cookie: cookie,
          ...headers,
        },
        body: JSON.stringify(body),
      }),
      env,
      now,
    );
  const configuration = async () => {
    const result = await handleRequest(
      new Request(origin + "/admin/auth-config"),
      env,
      now,
    );
    expect(result.status).toBe(200);
    return result.json();
  };
  it("changes from the bootstrap key to a custom password and revokes every prior session", async () => {
    const oldSession = await session();
    const anotherOldSession = await session();
    const before = await configuration();
    expect(before.mode).toBe("key");
    const salt = newSalt();
    const password = "Correct horse battery, индивидуальный пароль";
    const newKey = await derivePassword(password, salt);
    const result = await update(oldSession, {
      currentKey: loginKey,
      newKey,
      salt,
    });
    expect(result.status).toBe(204);
    expect(result.headers.get("Set-Cookie")).toContain("Max-Age=0");
    for (const cookie of [oldSession, anotherOldSession])
      expect(
        (
          await handleRequest(
            authenticated("/admin/api/stats", cookie),
            env,
            now,
          )
        ).status,
      ).toBe(401);
    expect(
      (await handleRequest(loginRequest({ key: loginKey }), env, now)).status,
    ).toBe(401);
    const after = await configuration();
    expect(after.mode).toBe("password");
    expect(after.salt).toBe(salt);
    expect(Object.keys(after).sort()).toEqual(
      ["mode", "algorithm", "iterations", "salt"].sort(),
    );
    const presented = await credentialForInput(password, after);
    expect(presented).toBe(newKey);
    const signedIn = await handleRequest(
      loginRequest({ key: presented }),
      env,
      now,
    );
    expect(signedIn.status).toBe(204);
    const cookie = signedIn.headers.get("Set-Cookie")!.split(";")[0];
    expect(
      (await handleRequest(authenticated("/admin/api/stats", cookie), env, now))
        .status,
    ).toBe(200);
    const stored = JSON.stringify(
      await env.DB.prepare("SELECT * FROM telemetry_admin_auth").first(),
    );
    expect(stored).not.toContain(password);
    expect(stored).not.toContain(newKey);
    expect(stored).not.toContain(loginKey);
    expect((await stats()).metrics.installations).toBe(0);
  });
  it("requires the current password, HTTPS origin and a valid session for changes", async () => {
    const cookie = await session();
    const body = {
      currentKey: loginKey,
      newKey: "A".repeat(43),
      salt: newSalt(),
    };
    expect((await update("", body)).status).toBe(401);
    expect(
      (await update(cookie, body, { Origin: "https://attacker.example" }))
        .status,
    ).toBe(403);
    expect(
      (await update(cookie, { ...body, currentKey: "X".repeat(43) })).status,
    ).toBe(401);
    expect((await update(cookie, { ...body, extra: true })).status).toBe(400);
    expect(
      await env.DB.prepare("SELECT COUNT(*) n FROM telemetry_admin_auth").first(
        "n",
      ),
    ).toBe(0);
    expect(
      (await handleRequest(authenticated("/admin/api/stats", cookie), env, now))
        .status,
    ).toBe(200);
  });
  it("changes a custom password again and disables both the old password and bootstrap key", async () => {
    const cookie = await session();
    const salt = newSalt();
    const firstKey = await derivePassword("A first long unique password", salt);
    expect(
      (await update(cookie, { currentKey: loginKey, newKey: firstKey, salt }))
        .status,
    ).toBe(204);
    const firstLogin = await handleRequest(
      loginRequest({ key: firstKey }),
      env,
      now,
    );
    const firstCookie = firstLogin.headers.get("Set-Cookie")!.split(";")[0];
    const nextSalt = newSalt();
    const nextKey = await derivePassword(
      "A second long unique password",
      nextSalt,
    );
    expect(
      (
        await update(firstCookie, {
          currentKey: firstKey,
          newKey: nextKey,
          salt: nextSalt,
        })
      ).status,
    ).toBe(204);
    expect(
      (await handleRequest(loginRequest({ key: firstKey }), env, now)).status,
    ).toBe(401);
    expect(
      (await handleRequest(loginRequest({ key: loginKey }), env, now)).status,
    ).toBe(401);
    expect(
      (await handleRequest(loginRequest({ key: nextKey }), env, now)).status,
    ).toBe(204);
    expect(
      (
        await handleRequest(
          authenticated("/admin/api/stats", firstCookie),
          env,
          now,
        )
      ).status,
    ).toBe(401);
    expect(
      await env.DB.prepare("SELECT version FROM telemetry_admin_auth").first(
        "version",
      ),
    ).toBe(2);
  });
  it("allows only one of two simultaneous password updates to win", async () => {
    const cookie = await session();
    const replies = await Promise.all([
      update(cookie, {
        currentKey: loginKey,
        newKey: "A".repeat(43),
        salt: newSalt(),
      }),
      update(cookie, {
        currentKey: loginKey,
        newKey: "B".repeat(43),
        salt: newSalt(),
      }),
    ]);
    expect(replies.filter((r) => r.status === 204)).toHaveLength(1);
    expect(replies.filter((r) => [401, 409].includes(r.status))).toHaveLength(
      1,
    );
    expect(
      await env.DB.prepare("SELECT version FROM telemetry_admin_auth").first(
        "version",
      ),
    ).toBe(1);
  });
  it("fails closed without the password pepper and rate limits password mutations", async () => {
    const cookie = await session();
    const body = {
      currentKey: loginKey,
      newKey: "A".repeat(43),
      salt: newSalt(),
    };
    delete env.ADMIN_PASSWORD_PEPPER;
    expect((await update(cookie, body)).status).toBe(503);
    expect(
      await env.DB.prepare("SELECT COUNT(*) n FROM telemetry_admin_auth").first(
        "n",
      ),
    ).toBe(0);
    vi.mocked(env.ADMIN_LIMITER!.limit).mockResolvedValue({ success: false });
    expect((await update(cookie, body)).status).toBe(429);
  });
  it("validates password length in the browser and uses the same Unicode normalization for login", async () => {
    expect(() => validateNewPassword("short")).toThrow();
    expect(() => validateNewPassword("e\u0301".repeat(6))).toThrow();
    expect(() => validateNewPassword(" ".repeat(12))).toThrow();
    expect(() => validateNewPassword("x".repeat(129))).toThrow();
    expect(() =>
      validateNewPassword("A long unique password phrase"),
    ).not.toThrow();
    const salt = newSalt();
    expect(await derivePassword("long cafe\u0301 password", salt)).toBe(
      await derivePassword("long café password", salt),
    );
  });
  it("matches an independent PBKDF2-SHA256 reference at 600000 iterations", async () => {
    const salt = newSalt();
    const password = "An independent test password";
    const reference = pbkdf2Sync(
      password,
      Buffer.from(salt, "base64url"),
      600000,
      32,
      "sha256",
    ).toString("base64url");
    expect(await derivePassword(password, salt)).toBe(reference);
  });
  it("accepts existing pre-upgrade sessions until the first password change", async () => {
    const token = await new SignJWT({})
      .setProtectedHeader({ alg: "HS256" })
      .setSubject("administrator")
      .setIssuer("torrserve-telemetry")
      .setAudience(origin + "/admin")
      .setIssuedAt()
      .setExpirationTime("8h")
      .sign(new TextEncoder().encode(env.ADMIN_SESSION_SECRET));
    const cookie = "__Host-TorrServeAdmin=" + token;
    expect(
      (await handleRequest(authenticated("/admin/api/stats", cookie), env, now))
        .status,
    ).toBe(200);
    expect(
      (
        await update(cookie, {
          currentKey: loginKey,
          newKey: "A".repeat(43),
          salt: newSalt(),
        })
      ).status,
    ).toBe(204);
    expect(
      (await handleRequest(authenticated("/admin/api/stats", cookie), env, now))
        .status,
    ).toBe(401);
  });
});
