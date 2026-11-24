import { WorkerEntrypoint } from "cloudflare:workers";
import { statistics } from "./stats";
import type { Env } from "./types";

export { default } from "./http";

// Named service binding only. The default HTTP handler never dispatches these methods.
export class HubAnalytics extends WorkerEntrypoint<Env> {
  health() {
    return { contract: 1, source: "torrserve-silicon" } as const;
  }

  async snapshot(input: { start: string; end: string; section: string }) {
    const { start, end, section } = input;
    if (!["summary", "overview", "audience", "devices", "geography", "versions"].includes(section) ||
        typeof start !== "string" || typeof end !== "string" ||
        !/^\d{4}-\d{2}-\d{2}$/.test(start) || !/^\d{4}-\d{2}-\d{2}$/.test(end)) {
      throw new Error("Invalid analytics request");
    }
    const url = new URL("https://internal.invalid");
    url.searchParams.set("start", start);
    url.searchParams.set("end", end);
    try {
      const { system, ...data } = await statistics(this.env, url, Math.floor(Date.now() / 1000), section);
      return { ...this.health(), data: { ...data, system: { lastReceivedAt: system.lastReceivedAt } } };
    } catch {
      throw new Error("Analytics unavailable");
    }
  }
}
