// SPDX-License-Identifier: AGPL-3.0-or-later

import { randomToken } from "./crypto";
import { GameRoom } from "./game_room";
import { HttpError, jsonResponse, protocolError, withCors } from "./http";
import {
  androidAssociation,
  appleAssociation,
  inviteLanding,
} from "./landing";
import { PROTOCOL_VERSION, type Env } from "./types";
import { ruleCapabilities } from "./rule_engine";

export { GameRoom };

const ROOM_ROUTE = /^\/v1\/rooms\/([A-Za-z0-9_-]{22})(?:\/(join|ticket|socket))?$/u;
const INVITE_ROUTE = /^\/invite\/([A-Za-z0-9_-]{22})$/u;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url);
      if (request.method === "OPTIONS") {
        return new Response(null, {
          status: 204,
          headers: {
            "access-control-allow-origin": "*",
            "access-control-allow-methods": "GET,POST,DELETE,OPTIONS",
            "access-control-allow-headers": "authorization,content-type",
            "access-control-max-age": "86400",
          },
        });
      }
      if (request.method === "GET" && url.pathname === "/v1/capabilities") {
        return jsonResponse({
          ok: true,
          enabled: env.ONLINE_ENABLED === "true",
          protocolVersions: [PROTOCOL_VERSION],
          games: ruleCapabilities(),
          roomLifetimeSeconds: 24 * 60 * 60,
          sourceUrl: env.SOURCE_URL,
          sourceVersion: env.SOURCE_VERSION,
        });
      }
      if (
        request.method === "GET" &&
        url.pathname === "/.well-known/apple-app-site-association"
      ) {
        return appleAssociation();
      }
      if (request.method === "GET" && url.pathname === "/.well-known/assetlinks.json") {
        return androidAssociation(env);
      }
      const invitation = INVITE_ROUTE.exec(url.pathname);
      if (request.method === "GET" && invitation !== null) {
        return inviteLanding(invitation[1], env);
      }

      if (request.method === "POST" && url.pathname === "/v1/rooms") {
        if (env.ONLINE_ENABLED !== "true") {
          return protocolError(503, "service_unavailable");
        }
        const roomId = randomToken(16);
        const stub = env.ROOMS.getByName(roomId);
        const headers = new Headers(request.headers);
        headers.set("x-sanmill-room-id", roomId);
        const response = await stub.fetch(new Request(request, { headers }));
        if (!response.ok) {
          return withCors(response);
        }
        const body = (await response.json()) as Record<string, unknown>;
        const inviteToken = body.inviteToken;
        if (typeof inviteToken !== "string") {
          return protocolError(500, "service_unavailable");
        }
        return jsonResponse(
          {
            ...body,
            inviteUrl: `${url.origin}/invite/${roomId}#${inviteToken}`,
          },
          response.status,
        );
      }

      const roomRoute = ROOM_ROUTE.exec(url.pathname);
      if (roomRoute === null) {
        return protocolError(404, "not_found");
      }
      if (
        env.ONLINE_ENABLED !== "true" &&
        request.method === "POST" &&
        roomRoute[2] === "join"
      ) {
        return protocolError(503, "service_unavailable");
      }
      const stub = env.ROOMS.getByName(roomRoute[1]);
      return withCors(await stub.fetch(request));
    } catch (error) {
      if (error instanceof HttpError) {
        return protocolError(error.status, error.code);
      }
      console.error("WORKER_REQUEST_FAILED", error instanceof Error ? error.name : "UnknownError");
      return protocolError(500, "service_unavailable");
    }
  },
} satisfies ExportedHandler<Env>;
