// Never print, persist, or pass credentials in command-line arguments.
import { execFileSync } from "node:child_process";
import { mkdirSync, existsSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
export function adminKey({ create = false } = {}) {
  const directory = new URL("../.test-output/", import.meta.url);
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const binary = fileURLToPath(new URL("admin-keychain", directory));
  const source = fileURLToPath(
    new URL("admin-keychain.swift", import.meta.url),
  );
  if (
    !existsSync(binary) ||
    statSync(binary).mtimeMs < statSync(source).mtimeMs
  )
    execFileSync("swiftc", [source, "-o", binary], {
      stdio: ["ignore", "pipe", "pipe"],
    });
  const key = execFileSync(binary, create ? ["--create-if-missing"] : [], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  }).trim();
  if (!/^[A-Za-z0-9_-]{43}$/.test(key))
    throw new Error("Invalid administrator credential in Keychain");
  return key;
}
