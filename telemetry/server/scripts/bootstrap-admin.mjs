// Uploads server secrets into the EXISTING Worker; use only after deployment approval.
import { execFileSync } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import { adminKey } from "./admin-credentials.mjs";
if (process.argv[2] !== "--upload")
  throw new Error(
    "Usage: node scripts/bootstrap-admin.mjs --upload (updates Worker secrets)",
  );
const key = adminKey({ create: true });
const secrets = {
  ADMIN_KEY_SHA256: createHash("sha256").update(key).digest("hex"),
  ADMIN_SESSION_SECRET: randomBytes(32).toString("base64url"),
};
try {
  const output = execFileSync(
    "npx",
    [
      "--no-install",
      "wrangler",
      "secret",
      "bulk",
      "--name",
      "torrserve-telemetry",
      "-c",
      "wrangler.production.json",
    ],
    {
      input: JSON.stringify(secrets),
      encoding: "utf8",
      stdio: ["pipe", "pipe", "pipe"],
    },
  );
  let safeOutput = output;
  for (const value of [key, ...Object.values(secrets)])
    safeOutput = safeOutput.split(value).join("[redacted]");
  console.log(safeOutput);
  console.log(
    "Administrator key is stored only in macOS Keychain. Existing key was reused if present. Sessions were rotated.",
  );
} catch {
  throw new Error(
    "Secret upload failed; no credentials were printed. Check Wrangler authorization and retry.",
  );
}
