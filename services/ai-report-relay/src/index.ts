// SPDX-License-Identifier: AGPL-3.0-or-later

export interface Env {
  REPORTS_DB: D1Database;
  RATE_LIMIT_SECRET: string;
  ALLOWED_ORIGIN: string;
}

const CATEGORIES = new Set([
  "harmful",
  "hate",
  "sexual",
  "selfHarm",
  "privacy",
  "offTopic",
  "incorrect",
  "other",
]);
const TASKS = new Set([
  "positionAnalysis",
  "explainLastMove",
  "gameReview",
  "explainRules",
]);
const REPORT_ID = /^[0-9a-f-]{36}$/u;
const MAX_REQUEST_BYTES = 24 * 1024;
const MAX_REPORTS_PER_DAY = 20;

type ReportInput = {
  schemaVersion: 1;
  category: string;
  task: string;
  surface: "gameAnalysis";
  provider: string;
  model: string;
  appVersion: string;
  platform: string;
  locale: string;
  answer?: string;
};

export function validateReport(value: unknown): ReportInput | null {
  if (!isRecord(value) || value.schemaVersion !== 1) return null;
  const allowed = new Set([
    "schemaVersion", "category", "task", "surface", "provider", "model",
    "appVersion", "platform", "locale", "answer",
  ]);
  if (Object.keys(value).some((key) => !allowed.has(key))) return null;
  if (typeof value.category !== "string" || !CATEGORIES.has(value.category)) return null;
  if (typeof value.task !== "string" || !TASKS.has(value.task)) return null;
  if (value.surface !== "gameAnalysis") return null;
  for (const key of ["provider", "model", "appVersion", "platform", "locale"] as const) {
    if (!shortString(value[key], 128)) return null;
  }
  if (value.answer !== undefined && (!shortString(value.answer, 16_384) || encodedLength(value.answer) > 16_384)) {
    return null;
  }
  return value as ReportInput;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const origin = request.headers.get("origin");
    if (request.method === "OPTIONS") return preflight(origin, env);
    if (!allowedOrigin(origin, env)) return json({ error: "forbidden" }, 403, origin, env);
    const url = new URL(request.url);
    try {
      if (request.method === "POST" && url.pathname === "/v1/reports") {
        return await createReport(request, env, origin);
      }
      const match = /^\/v1\/reports\/([0-9a-f-]{36})$/u.exec(url.pathname);
      if (request.method === "DELETE" && match !== null) {
        return await deleteReport(request, env, origin, match[1]);
      }
      return json({ error: "not_found" }, 404, origin, env);
    } catch (error) {
      console.error("REPORT_RELAY_FAILED", error instanceof Error ? error.name : "UnknownError");
      return json({ error: "service_unavailable" }, 503, origin, env);
    }
  },

  async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
    const now = new Date();
    const aggregateCutoff = new Date(now);
    aggregateCutoff.setUTCFullYear(aggregateCutoff.getUTCFullYear() - 1);
    const rateCutoff = new Date(now);
    rateCutoff.setUTCDate(rateCutoff.getUTCDate() - 2);
    await env.REPORTS_DB.batch([
      env.REPORTS_DB.prepare("DELETE FROM reports WHERE expires_at <= ?").bind(now.toISOString()),
      env.REPORTS_DB.prepare("DELETE FROM daily_category_totals WHERE report_date < ?").bind(dateOnly(aggregateCutoff)),
      env.REPORTS_DB.prepare("DELETE FROM daily_rate_limits WHERE report_date < ?").bind(dateOnly(rateCutoff)),
    ]);
  },
};

async function createReport(request: Request, env: Env, origin: string | null): Promise<Response> {
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (declared > MAX_REQUEST_BYTES) return json({ error: "request_too_large" }, 413, origin, env);
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength > MAX_REQUEST_BYTES) return json({ error: "request_too_large" }, 413, origin, env);
  const input = validateReport(JSON.parse(new TextDecoder().decode(bytes)) as unknown);
  if (input === null) return json({ error: "invalid_request" }, 400, origin, env);

  const now = new Date();
  const reportDate = dateOnly(now);
  const requesterHash = await rotatingRequesterHash(request, env, reportDate);
  const existing = await env.REPORTS_DB.prepare(
    "SELECT total FROM daily_rate_limits WHERE report_date = ? AND requester_hash = ?",
  ).bind(reportDate, requesterHash).first<{ total: number }>();
  if ((existing?.total ?? 0) >= MAX_REPORTS_PER_DAY) {
    return json({ error: "rate_limited" }, 429, origin, env);
  }

  const reportId = crypto.randomUUID();
  const deleteToken = randomToken();
  const deleteTokenHash = toHex(await sha256(deleteToken));
  const expiresAt = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
  await env.REPORTS_DB.batch([
    env.REPORTS_DB.prepare(`INSERT INTO reports (
      report_id, delete_token_hash, category, task, surface, provider, model,
      app_version, platform, locale, answer, created_at, expires_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).bind(
      reportId, deleteTokenHash, input.category, input.task, input.surface,
      input.provider, input.model, input.appVersion, input.platform, input.locale,
      input.answer ?? null, now.toISOString(), expiresAt.toISOString(),
    ),
    env.REPORTS_DB.prepare(`INSERT INTO daily_category_totals (report_date, category, total)
      VALUES (?, ?, 1) ON CONFLICT(report_date, category) DO UPDATE SET total = total + 1`).bind(
      reportDate, input.category,
    ),
    env.REPORTS_DB.prepare(`INSERT INTO daily_rate_limits (report_date, requester_hash, total)
      VALUES (?, ?, 1) ON CONFLICT(report_date, requester_hash) DO UPDATE SET total = total + 1`).bind(
      reportDate, requesterHash,
    ),
  ]);
  return json({ reportId, deleteToken, expiresAt: expiresAt.toISOString() }, 201, origin, env);
}

async function deleteReport(
  request: Request,
  env: Env,
  origin: string | null,
  reportId: string,
): Promise<Response> {
  if (!REPORT_ID.test(reportId)) return json({ error: "not_found" }, 404, origin, env);
  const supplied = request.headers.get("authorization")?.replace(/^Bearer\s+/iu, "") ?? "";
  if (!supplied) return json({ error: "unauthorized" }, 401, origin, env);
  const row = await env.REPORTS_DB.prepare(
    "SELECT delete_token_hash FROM reports WHERE report_id = ?",
  ).bind(reportId).first<{ delete_token_hash: string }>();
  if (row === null) return new Response(null, { status: 404, headers: corsHeaders(origin, env) });
  const suppliedHash = toHex(await sha256(supplied));
  if (!(await constantTimeEqual(suppliedHash, row.delete_token_hash))) {
    return json({ error: "unauthorized" }, 401, origin, env);
  }
  await env.REPORTS_DB.prepare("DELETE FROM reports WHERE report_id = ?").bind(reportId).run();
  return new Response(null, { status: 204, headers: corsHeaders(origin, env) });
}

async function rotatingRequesterHash(request: Request, env: Env, date: string): Promise<string> {
  const ip = request.headers.get("cf-connecting-ip") ?? "native-no-ip";
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(`${env.RATE_LIMIT_SECRET}:${date}`),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  return toHex(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(ip)));
}

function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/gu, "-").replace(/\//gu, "_").replace(/=+$/gu, "");
}

async function sha256(value: string): Promise<ArrayBuffer> {
  return crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
}

async function constantTimeEqual(a: string, b: string): Promise<boolean> {
  const [left, right] = await Promise.all([sha256(a), sha256(b)]);
  const x = new Uint8Array(left);
  const y = new Uint8Array(right);
  return x.every((value, index) => value === y[index]);
}

function toHex(value: ArrayBuffer): string {
  return [...new Uint8Array(value)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function dateOnly(value: Date): string {
  return value.toISOString().slice(0, 10);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function shortString(value: unknown, max: number): value is string {
  return typeof value === "string" && value.trim().length > 0 && value.length <= max;
}

function encodedLength(value: string): number {
  return new TextEncoder().encode(value).byteLength;
}

function allowedOrigin(origin: string | null, env: Env): boolean {
  return origin === null || origin === env.ALLOWED_ORIGIN;
}

function preflight(origin: string | null, env: Env): Response {
  if (!allowedOrigin(origin, env)) return new Response(null, { status: 403 });
  return new Response(null, { status: 204, headers: corsHeaders(origin, env) });
}

function json(body: unknown, status: number, origin: string | null, env: Env): Response {
  return Response.json(body, { status, headers: corsHeaders(origin, env) });
}

function corsHeaders(origin: string | null, env: Env): Headers {
  const headers = new Headers({
    "cache-control": "no-store",
    "content-type": "application/json; charset=utf-8",
    "x-content-type-options": "nosniff",
    "access-control-allow-methods": "POST,DELETE,OPTIONS",
    "access-control-allow-headers": "authorization,content-type",
    "vary": "origin",
  });
  if (origin === env.ALLOWED_ORIGIN) headers.set("access-control-allow-origin", origin);
  return headers;
}
