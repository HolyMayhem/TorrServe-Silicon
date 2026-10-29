// Adds the dedicated pepper once. Never rotate it while a custom password is configured.
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
if (process.argv[2] !== "--upload")
  throw new Error("Usage: node scripts/prepare-password-auth.mjs --upload");
const args = ["--no-install", "wrangler", "secret"];
const options = { encoding: "utf8", stdio: ["pipe", "pipe", "pipe"] };
const list = JSON.parse(
  execFileSync(
    "npx",
    [...args, "list", "-c", "wrangler.production.json"],
    options,
  ),
);
if (list.some((secret) => secret.name === "ADMIN_PASSWORD_PEPPER")) {
  console.log("Existing password pepper retained. No secrets changed.");
} else {
  const pepper = randomBytes(32).toString("base64url");
  try {
    const output = execFileSync(
      "npx",
      [...args, "bulk", "-c", "wrangler.production.json"],
      { ...options, input: JSON.stringify({ ADMIN_PASSWORD_PEPPER: pepper }) },
    );
    console.log(output.split(pepper).join("[redacted]"));
    console.log(
      "Dedicated password pepper uploaded. Existing login key and session secret were not changed.",
    );
  } catch {
    throw new Error("Password pepper upload failed; no secret was printed.");
  }
}
