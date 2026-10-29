import { createRemoteJWKSet, jwtVerify } from "jose";
import { Env, HTTPError } from "./types";
import { requireKeySession } from "./admin-session";
const keySets = new Map<string, ReturnType<typeof createRemoteJWKSet>>();
export async function requireAdmin(request: Request, env: Env): Promise<void> {
  const host = new URL(request.url).hostname;
  if (
    env.ENVIRONMENT === "local" &&
    ["localhost", "127.0.0.1", "[::1]"].includes(host)
  )
    return;
  if (env.ADMIN_AUTH_MODE === "key") return requireKeySession(request, env);
  const team = env.ACCESS_TEAM_DOMAIN;
  const emails = env.ACCESS_ADMIN_EMAILS?.split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
  if (
    !team ||
    !/^[a-z0-9-]+\.cloudflareaccess\.com$/.test(team) ||
    !env.ACCESS_AUD ||
    !emails?.length
  )
    throw new HTTPError(503, "Administrator access is not configured");
  const token = request.headers.get("Cf-Access-Jwt-Assertion");
  if (!token || token.length > 8192)
    throw new HTTPError(401, "Cloudflare Access sign-in required");
  const issuer = `https://${team}`;
  let jwks = keySets.get(issuer);
  if (!jwks) {
    jwks = createRemoteJWKSet(new URL(issuer + "/cdn-cgi/access/certs"), {
      timeoutDuration: 3000,
    });
    keySets.set(issuer, jwks);
  }
  try {
    const { payload } = await jwtVerify(token, jwks, {
      issuer,
      audience: env.ACCESS_AUD,
      algorithms: ["RS256"],
      requiredClaims: ["exp", "iat", "sub", "email"],
    });
    if (
      typeof payload.email !== "string" ||
      !emails.includes(payload.email.toLowerCase())
    )
      throw new Error("Not an administrator");
  } catch {
    throw new HTTPError(403, "Administrator access denied");
  }
}
