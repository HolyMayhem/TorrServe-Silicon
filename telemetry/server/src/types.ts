export interface Env {
  DB: D1Database;
  ASSETS: Fetcher;
  INGRESS_LIMITER: RateLimit;
  INSTALLATION_LIMITER: RateLimit;
  ADMIN_LIMITER?: RateLimit;
  ENVIRONMENT: string;
  LATEST_APP_VERSION?: string;
  MAX_DAILY_HEARTBEATS?: string;
  ACCESS_TEAM_DOMAIN?: string;
  ACCESS_AUD?: string;
  ACCESS_ADMIN_EMAILS?: string;
  ADMIN_AUTH_MODE?: "key" | "access";
  ADMIN_KEY_SHA256?: string;
  ADMIN_SESSION_SECRET?: string;
  ADMIN_PASSWORD_PEPPER?: string;
}
export interface Heartbeat {
  schemaVersion: 1;
  installationID: string;
  appVersion: string;
  macOSVersion: string;
  cpuArchitecture: "arm64" | "x86_64";
  cpuModel: string;
}
export class HTTPError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}
export const DAY = 86400;
export const dayOf = (s: number) =>
  new Date(s * 1000).toISOString().slice(0, 10);
export const secondsOf = (day: string) => Date.parse(day + "T00:00:00Z") / 1000;
