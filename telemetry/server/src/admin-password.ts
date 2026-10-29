import { Env, HTTPError } from "./types";

export interface AdminCredential {
  salt: string;
  verifier: string;
  version: number;
}
export const passwordIterations = 600_000;
export const derivedKeyPattern = /^[A-Za-z0-9_-]{43}$/;
export const saltPattern = /^[A-Za-z0-9_-]{22}$/;
export async function readCredential(
  env: Env,
): Promise<AdminCredential | null> {
  return env.DB.withSession("first-primary")
    .prepare(
      "SELECT salt, verifier, version FROM telemetry_admin_auth WHERE singleton=1",
    )
    .first<AdminCredential>();
}
export async function publicAuthConfiguration(env: Env) {
  const credential = await readCredential(env);
  return {
    mode: credential ? "password" : "key",
    algorithm: "PBKDF2-SHA256",
    iterations: passwordIterations,
    salt: credential?.salt ?? null,
  };
}
export async function passwordVerifier(
  derivedKey: string,
  env: Env,
): Promise<string> {
  if (
    !env.ADMIN_PASSWORD_PEPPER ||
    !derivedKeyPattern.test(env.ADMIN_PASSWORD_PEPPER)
  )
    throw new HTTPError(503, "Password changes are not configured");
  const pepper = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(env.ADMIN_PASSWORD_PEPPER),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const result = await crypto.subtle.sign(
    "HMAC",
    pepper,
    new TextEncoder().encode("torrserve-admin-password-v1:" + derivedKey),
  );
  return [...new Uint8Array(result)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
export function constantEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let mismatch = 0;
  for (let i = 0; i < left.length; i++)
    mismatch |= left.charCodeAt(i) ^ right.charCodeAt(i);
  return mismatch === 0;
}
export async function checkCredential(
  presented: string,
  credential: AdminCredential | null,
  env: Env,
): Promise<boolean> {
  if (credential)
    return constantEqual(
      await passwordVerifier(presented, env),
      credential.verifier,
    );
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(presented),
  );
  const hash = [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return (
    typeof env.ADMIN_KEY_SHA256 === "string" &&
    constantEqual(hash, env.ADMIN_KEY_SHA256)
  );
}
export async function storePassword(
  env: Env,
  expected: AdminCredential | null,
  salt: string,
  verifier: string,
): Promise<void> {
  const now = Math.floor(Date.now() / 1000);
  const result = expected
    ? await env.DB.prepare(
        `UPDATE telemetry_admin_auth SET salt=?,verifier=?,version=version+1,updated_at=?
  WHERE singleton=1 AND version=?`,
      )
        .bind(salt, verifier, now, expected.version)
        .run()
    : await env.DB.prepare(
        `INSERT INTO telemetry_admin_auth(singleton,salt,verifier,version,updated_at)
  VALUES(1,?,?,1,?) ON CONFLICT(singleton) DO NOTHING`,
      )
        .bind(salt, verifier, now)
        .run();
  if (result.meta.changes !== 1)
    throw new HTTPError(409, "Credentials changed; sign in again");
}
