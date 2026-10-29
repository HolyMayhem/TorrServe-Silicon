import { SignJWT, jwtVerify } from "jose";
import { Env, HTTPError } from "./types";
import {
  checkCredential,
  readCredential,
  passwordVerifier,
  storePassword,
  saltPattern,
} from "./admin-password";

export const sessionCookieName = "__Host-TorrServeAdmin";
const lifetime = 8 * 60 * 60;
const keyPattern = /^[A-Za-z0-9_-]{43}$/;

function signingKey(env: Env): Uint8Array {
  if (
    !env.ADMIN_KEY_SHA256 ||
    !/^[a-f0-9]{64}$/.test(env.ADMIN_KEY_SHA256) ||
    !env.ADMIN_SESSION_SECRET ||
    !keyPattern.test(env.ADMIN_SESSION_SECRET)
  )
    throw new HTTPError(503, "Administrator access is not configured");
  return new TextEncoder().encode(env.ADMIN_SESSION_SECRET);
}
export function requireSameOrigin(request: Request): void {
  if (
    new URL(request.url).protocol !== "https:" ||
    request.headers.get("origin") !== new URL(request.url).origin
  )
    throw new HTTPError(403, "Same-origin HTTPS request required");
}
function cookie(value: string, maxAge: number): string {
  return `${sessionCookieName}=${value}; Path=/; Max-Age=${maxAge}; Secure; HttpOnly; SameSite=Strict`;
}
export const expiredSessionCookie = () => cookie("", 0);

export async function requireKeySession(
  request: Request,
  env: Env,
): Promise<void> {
  if (new URL(request.url).protocol !== "https:")
    throw new HTTPError(401, "HTTPS sign-in required");
  const key = signingKey(env);
  const cookies = request.headers.get("cookie") ?? "";
  if (cookies.length > 8192)
    throw new HTTPError(401, "Administrator sign-in required");
  const values = cookies
    .split(";")
    .map((v) => v.trim())
    .filter((v) => v.startsWith(sessionCookieName + "="));
  if (values.length !== 1)
    throw new HTTPError(401, "Administrator sign-in required");
  const token = values[0].slice(sessionCookieName.length + 1);
  try {
    const { payload } = await jwtVerify(token, key, {
      algorithms: ["HS256"],
      issuer: "torrserve-telemetry",
      audience: new URL(request.url).origin + "/admin",
      requiredClaims: ["exp", "iat", "sub"],
      maxTokenAge: lifetime,
    });
    if (payload.sub !== "administrator") throw new Error("Invalid subject");
    const credential = await readCredential(env);
    if ((payload.credentialVersion ?? 0) !== (credential?.version ?? 0))
      throw new Error("Session revoked");
  } catch {
    throw new HTTPError(401, "Administrator sign-in required");
  }
}

async function readAuthBody(
  request: Request,
): Promise<Record<string, unknown>> {
  if (
    request.headers.get("content-type")?.split(";")[0].trim().toLowerCase() !==
      "application/json" ||
    request.headers.has("content-encoding")
  )
    throw new HTTPError(415, "Expected uncompressed application/json");
  if (Number(request.headers.get("content-length") ?? 0) > 256)
    throw new HTTPError(413, "Payload too large");
  if (!request.body) throw new HTTPError(400, "Missing key");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 256) {
        await reader.cancel();
        throw new HTTPError(413, "Payload too large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  let body: unknown;
  try {
    body = JSON.parse(
      new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes),
    );
  } catch {
    throw new HTTPError(400, "Invalid JSON");
  }
  if (!body || typeof body !== "object" || Array.isArray(body))
    throw new HTTPError(400, "Invalid JSON object");
  return body as Record<string, unknown>;
}
async function readLoginKey(request: Request): Promise<string> {
  const body = await readAuthBody(request);
  if (
    Object.keys(body).length !== 1 ||
    typeof body.key !== "string" ||
    !keyPattern.test(body.key)
  )
    throw new HTTPError(401, "Invalid administrator password");
  return body.key;
}

export async function login(request: Request, env: Env): Promise<string> {
  requireSameOrigin(request);
  const sessionKey = signingKey(env);
  if (
    !env.ADMIN_LIMITER ||
    !(await env.ADMIN_LIMITER.limit({ key: "administrator-login" })).success
  )
    throw new HTTPError(429, "Rate limited");
  const presented = await readLoginKey(request);
  const credential = await readCredential(env);
  if (!(await checkCredential(presented, credential, env)))
    throw new HTTPError(401, "Invalid administrator password");
  const token = await new SignJWT({
    credentialVersion: credential?.version ?? 0,
  })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject("administrator")
    .setIssuer("torrserve-telemetry")
    .setAudience(new URL(request.url).origin + "/admin")
    .setIssuedAt()
    .setExpirationTime("8h")
    .sign(sessionKey);
  return cookie(token, lifetime);
}

export async function changePassword(
  request: Request,
  env: Env,
): Promise<void> {
  requireSameOrigin(request);
  if (
    !env.ADMIN_LIMITER ||
    !(await env.ADMIN_LIMITER.limit({ key: "administrator-login" })).success
  )
    throw new HTTPError(429, "Rate limited");
  // This endpoint never trusts the local-development auth bypass.
  await requireKeySession(request, env);
  const body = await readAuthBody(request);
  if (
    Object.keys(body).length !== 3 ||
    typeof body.currentKey !== "string" ||
    !keyPattern.test(body.currentKey) ||
    typeof body.newKey !== "string" ||
    !keyPattern.test(body.newKey) ||
    typeof body.salt !== "string" ||
    !saltPattern.test(body.salt)
  )
    throw new HTTPError(400, "Invalid password change");
  const credential = await readCredential(env);
  if (!(await checkCredential(body.currentKey, credential, env)))
    throw new HTTPError(401, "Current password is incorrect");
  if (credential && body.salt === credential.salt)
    throw new HTTPError(400, "Use a fresh password salt");
  await storePassword(
    env,
    credential,
    body.salt,
    await passwordVerifier(body.newKey, env),
  );
}
