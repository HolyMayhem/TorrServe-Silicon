import { requireAdmin } from "./auth";
import { statistics } from "./stats";
import { cleanup, installationHash, storeHeartbeat } from "./storage";
import { Env, HTTPError } from "./types";
import { readHeartbeat } from "./validation";
import { countryFromRequest } from "./country";
import {
  expiredSessionCookie,
  login,
  requireSameOrigin,
  changePassword,
} from "./admin-session";
import { publicAuthConfiguration } from "./admin-password";
const headers = {
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "X-Frame-Options": "DENY",
  "Content-Security-Policy":
    "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; font-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
};
function response(
  body: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(status === 204 ? null : JSON.stringify(body), {
    status,
    headers: {
      ...headers,
      "Content-Type": "application/json",
      ...(status === 429 ? { "Retry-After": "60" } : {}),
      ...extraHeaders,
    },
  });
}
async function assetResponse(
  request: Request,
  env: Env,
  path: string,
): Promise<Response> {
  const assetURL = new URL(request.url);
  assetURL.pathname = path;
  assetURL.search = "";
  const asset = await env.ASSETS.fetch(
    new Request(assetURL, { method: "GET" }),
  );
  return new Response(asset.body, {
    status: asset.status,
    headers: { ...Object.fromEntries(asset.headers), ...headers },
  });
}
export async function handleRequest(
  request: Request,
  env: Env,
  now = Math.floor(Date.now() / 1000),
): Promise<Response> {
  try {
    const url = new URL(request.url);
    if (url.pathname === "/v1/heartbeat") {
      if (request.method !== "POST") throw new HTTPError(405, "POST required");
      if (url.search)
        throw new HTTPError(400, "Query parameters not supported");
      // Never read or log IP/User-Agent. Global + hashed-ID limits bound database writes.
      if (!(await env.INGRESS_LIMITER.limit({ key: "heartbeat" })).success)
        throw new HTTPError(429, "Rate limited");
      const payload = await readHeartbeat(request),
        key = await installationHash(payload.installationID);
      if (!(await env.INSTALLATION_LIMITER.limit({ key })).success)
        throw new HTTPError(429, "Rate limited");
      if (
        !(await storeHeartbeat(env, payload, now, countryFromRequest(request)))
      )
        throw new HTTPError(503, "Daily ingestion capacity reached");
      return response(null, 204);
    }
    if (url.pathname === "/health" && request.method === "GET")
      return response({ status: "alive" });
    if (env.ADMIN_AUTH_MODE === "key") {
      if (url.pathname === "/admin/auth-config") {
        if (request.method !== "GET") throw new HTTPError(405, "GET required");
        return response(await publicAuthConfiguration(env));
      }
      if (
        [
          "/admin/login",
          "/admin/login.js",
          "/admin/login.css",
          "/admin/password-crypto.js",
        ].includes(url.pathname)
      ) {
        if (request.method === "POST" && url.pathname === "/admin/login")
          return response(null, 204, {
            "Set-Cookie": await login(request, env),
          });
        if (request.method !== "GET") throw new HTTPError(405, "GET required");
        return assetResponse(
          request,
          env,
          url.pathname === "/admin/login"
            ? "/login.html"
            : "/" + url.pathname.split("/").pop(),
        );
      }
    }
    try {
      await requireAdmin(request, env);
    } catch (error) {
      if (
        error instanceof HTTPError &&
        error.status === 401 &&
        env.ADMIN_AUTH_MODE === "key" &&
        request.method === "GET" &&
        ["/admin", "/admin/"].includes(url.pathname)
      )
        return response(null, 303, { Location: "/admin/login" });
      throw error;
    }
    if (url.pathname === "/admin/logout" && env.ADMIN_AUTH_MODE === "key") {
      if (request.method !== "POST") throw new HTTPError(405, "POST required");
      requireSameOrigin(request);
      return response(null, 204, { "Set-Cookie": expiredSessionCookie() });
    }
    if (
      url.pathname === "/admin/api/password" &&
      env.ADMIN_AUTH_MODE === "key"
    ) {
      if (request.method !== "POST") throw new HTTPError(405, "POST required");
      await changePassword(request, env);
      return response(null, 204, { "Set-Cookie": expiredSessionCookie() });
    }
    if (request.method !== "GET") throw new HTTPError(405, "GET required");
    if (url.pathname === "/admin/api/stats")
      return response(await statistics(env, url, now));
    if (
      ![
        "/admin",
        "/admin/",
        "/admin/app.js",
        "/admin/styles.css",
        "/admin/password-crypto.js",
      ].includes(url.pathname)
    )
      throw new HTTPError(404, "Not found");
    const assetPath =
      url.pathname === "/admin" || url.pathname === "/admin/"
        ? "/index.html"
        : "/" + url.pathname.split("/").pop();
    return assetResponse(request, env, assetPath);
  } catch (error) {
    // Do not log requests, bodies, IDs, headers, or raw database exceptions.
    return error instanceof HTTPError
      ? response({ error: error.message }, error.status)
      : response({ error: "Service temporarily unavailable" }, 503);
  }
}
export default {
  fetch(request: Request, env: Env) {
    return handleRequest(request, env);
  },
  async scheduled(_event: ScheduledController, env: Env) {
    await cleanup(env, Math.floor(Date.now() / 1000));
  },
} satisfies ExportedHandler<Env>;
