import { Heartbeat, HTTPError } from "./types";
const keys = [
  "schemaVersion",
  "installationID",
  "appVersion",
  "macOSVersion",
  "cpuArchitecture",
  "cpuModel",
];
export const versionPattern =
  /^\d{1,3}\.\d{1,3}\.\d{1,3}(?:-(?:alpha|beta|rc)\.\d{1,3})?$/;
export function validateHeartbeat(value: unknown): Heartbeat {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new HTTPError(400, "Invalid payload");
  const v = value as Record<string, unknown>;
  if (Object.keys(v).length !== keys.length || keys.some((k) => !(k in v)))
    throw new HTTPError(400, "Invalid fields");
  if (
    v.schemaVersion !== 1 ||
    typeof v.installationID !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      v.installationID,
    )
  )
    throw new HTTPError(400, "Invalid schema or ID");
  if (
    typeof v.appVersion !== "string" ||
    !versionPattern.test(v.appVersion) ||
    typeof v.macOSVersion !== "string" ||
    !/^(?:1[0-9]|[2-9][0-9])\.\d{1,3}\.\d{1,3}$/.test(v.macOSVersion)
  )
    throw new HTTPError(400, "Invalid version");
  const valid =
    v.cpuArchitecture === "arm64"
      ? typeof v.cpuModel === "string" &&
        /^(Apple M[1-9][0-9]?( (Pro|Max|Ultra))?|Apple Silicon \(other\))$/.test(
          v.cpuModel,
        )
      : v.cpuArchitecture === "x86_64" &&
        typeof v.cpuModel === "string" &&
        /^Intel (Core i[3579]|Xeon|\(other\))$/.test(v.cpuModel);
  if (!valid) throw new HTTPError(400, "Invalid CPU");
  return { ...v, installationID: v.installationID.toLowerCase() } as Heartbeat;
}
export async function readHeartbeat(request: Request): Promise<Heartbeat> {
  if (
    request.headers.get("content-type")?.split(";")[0].trim().toLowerCase() !==
    "application/json"
  )
    throw new HTTPError(415, "Expected application/json");
  if (request.headers.has("content-encoding"))
    throw new HTTPError(415, "Encoded bodies not supported");
  const length = request.headers.get("content-length");
  if (length !== null && (!/^\d+$/.test(length) || Number(length) > 1024))
    throw new HTTPError(413, "Payload too large");
  if (!request.body) throw new HTTPError(400, "Missing body");
  const reader = request.body.getReader(),
    chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 1024) {
        await reader.cancel();
        throw new HTTPError(413, "Payload too large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const body = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.length;
  }
  let value: unknown;
  try {
    value = JSON.parse(
      new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(body),
    );
  } catch {
    throw new HTTPError(400, "Invalid JSON");
  }
  return validateHeartbeat(value);
}
