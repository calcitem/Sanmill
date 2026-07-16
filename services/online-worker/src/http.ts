// SPDX-License-Identifier: AGPL-3.0-or-later

import { MAX_BODY_BYTES } from "./types";

export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
  ) {
    super(code);
  }
}

export function jsonResponse(
  value: unknown,
  status = 200,
  extraHeaders: HeadersInit = {},
): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "access-control-allow-origin": "*",
      ...extraHeaders,
    },
  });
}

export function protocolError(status: number, code: string): Response {
  return jsonResponse({ ok: false, error: code }, status);
}

export async function readJson<T>(request: Request): Promise<T> {
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
    throw new HttpError(413, "request_too_large");
  }
  const source = await request.text();
  if (new TextEncoder().encode(source).byteLength > MAX_BODY_BYTES) {
    throw new HttpError(413, "request_too_large");
  }
  try {
    const decoded: unknown = JSON.parse(source);
    if (decoded === null || typeof decoded !== "object" || Array.isArray(decoded)) {
      throw new Error("JSON root must be an object");
    }
    return decoded as T;
  } catch {
    throw new HttpError(400, "invalid_request");
  }
}

export function withCors(response: Response): Response {
  const decorated = new Response(response.body, response);
  decorated.headers.set("access-control-allow-origin", "*");
  return decorated;
}
