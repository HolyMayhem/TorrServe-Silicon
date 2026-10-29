// Read-only Cloudflare inspection; authentication stays in memory, never in output/files.
import { execFileSync } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
const account = "11fb0018827f06abfb9d651295753029";
const worker = "torrserve-telemetry",
  database = "8d44e16c-fa2a-46ed-9032-4c7690a4c30b";
const auth = JSON.parse(
  execFileSync("npx", ["--no-install", "wrangler", "auth", "token", "--json"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  }),
);
const token = auth.token ?? auth.api_token ?? auth.oauth_token;
if (typeof token !== "string")
  throw new Error(
    "Wrangler returned no usable token; update the inspection script for this CLI.",
  );
const root = `https://api.cloudflare.com/client/v4/accounts/${account}`;
const directory = new URL("../remote-inspection/", import.meta.url);
await mkdir(directory, { recursive: true });
const endpoints = {
  workers: "/workers/scripts",
  settings: `/workers/scripts/${worker}/settings`,
  subdomain: "/workers/subdomain",
  workerSubdomain: `/workers/scripts/${worker}/subdomain`,
  schedules: `/workers/scripts/${worker}/schedules`,
  domains: "/workers/domains",
  deployments: `/workers/scripts/${worker}/deployments`,
  database: `/d1/database/${database}`,
  accessOrganization: "/access/organizations",
  accessApplications: "/access/apps",
};
for (const [name, path] of Object.entries(endpoints)) {
  const res = await fetch(root + path, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const body = await res.json();
  await writeFile(
    new URL(name + ".json", directory),
    JSON.stringify(body, null, 2) + "\n",
    { mode: 0o600 },
  );
  console.log(`${name}: HTTP ${res.status}, success=${body.success}`);
}
const scriptsResponse = await fetch(root + "/workers/scripts", {
  headers: { Authorization: `Bearer ${token}` },
});
const scriptsBody = await scriptsResponse.json();
if (!scriptsBody.success)
  throw new Error("Cannot verify existing Worker namespaces");
const namespaces = [];
for (const script of scriptsBody.result) {
  const response = await fetch(
    root + `/workers/scripts/${encodeURIComponent(script.id)}/settings`,
    { headers: { Authorization: `Bearer ${token}` } },
  );
  const body = await response.json();
  if (!body.success)
    throw new Error("Cannot verify Worker rate limit namespaces");
  for (const binding of body.result.bindings ?? [])
    if (binding.type.includes("rate"))
      namespaces.push({ worker: script.id, ...binding });
}
await writeFile(
  new URL("rate-limit-namespaces.json", directory),
  JSON.stringify(namespaces, null, 2) + "\n",
  { mode: 0o600 },
);
console.log(
  `Rate limit namespace audit: ${namespaces.length} existing bindings`,
);
const res = await fetch(root + `/workers/scripts/${worker}`, {
  headers: { Authorization: `Bearer ${token}` },
});
if (!res.ok) throw new Error(`Source download failed: ${res.status}`);
await writeFile(new URL("worker-content.txt", directory), await res.text(), {
  mode: 0o600,
});
console.log("Worker source downloaded into ignored remote-inspection/");
