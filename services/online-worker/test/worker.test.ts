// SPDX-License-Identifier: AGPL-3.0-or-later

import { env } from "cloudflare:workers";
import {
  SELF,
  evictDurableObject,
  runDurableObjectAlarm,
} from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";

type Json = Record<string, any>;

let openSockets: WebSocket[] = [];

afterEach(() => {
  for (const socket of openSockets) {
    try {
      socket.close(1000, "Test complete");
    } catch {
      // The room alarm may already have closed the socket.
    }
  }
  openSockets = [];
});

const defaultOptions = {
  pieceCount: 9,
  flyPieceCount: 3,
  piecesAtLeastCount: 3,
  mayFly: true,
  hasDiagonalLines: false,
  millFormationActionInPlacingPhase: "removeOpponentsPieceFromBoard",
  mayRemoveFromMillsAlways: false,
  mayRemoveMultiple: false,
  nMoveRule: 100,
  endgameNMoveRule: 100,
  mayMoveInPlacingPhase: false,
  isDefenderMoveFirst: false,
  restrictRepeatedMillsFormation: false,
  oneTimeUseMill: false,
  stopPlacingWhenTwoEmptySquares: false,
  boardFullAction: "firstPlayerLose",
  threefoldRepetitionRule: true,
  custodianCapture: capture(false),
  interventionCapture: capture(false),
  leapCapture: capture(false),
  stalemateAction: "endWithStalemateLoss",
};

describe("online worker", () => {
  it("reports capabilities and protocol support", async () => {
    const response = await SELF.fetch("https://example.test/v1/capabilities");
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      enabled: true,
      protocolVersions: [1],
    });
  });

  it("serves a bilingual invitation landing page with source provenance", async () => {
    const roomId = "A".repeat(22);
    const response = await SELF.fetch(`https://example.test/invite/${roomId}`);
    expect(response.status).toBe(200);
    expect(response.headers.get("referrer-policy")).toBe("no-referrer");
    const html = await response.text();
    expect(html).toContain("Open Sanmill / 打开 Sanmill");
    expect(html).toContain("Source code / 源代码");
    expect(html).toContain("AGPL license / AGPL 许可证");
    expect(html).toContain("Deployment / 部署版本: <code>development</code>");
  });

  it("creates, joins once, and rejects reuse of the invitation", async () => {
    expect(env.ONLINE_ENABLED).toBe("true");
    const createdResponse = await SELF.fetch("https://example.test/v1/rooms", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        protocolVersion: 1,
        appId: "sanmill",
        gameId: "mill",
        rulesetId: "custom-v1",
        ruleOptions: defaultOptions,
        sidePreference: "first",
      }),
    });
    expect(createdResponse.status).toBe(201);
    const created = (await createdResponse.json()) as Record<string, any>;
    expect(created.inviteUrl).toContain(`#${created.inviteToken}`);
    expect(created.snapshot.actions).toEqual([]);

    const roomId = created.room.roomId as string;
    const join = () =>
      SELF.fetch(`https://example.test/v1/rooms/${roomId}/join`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          protocolVersion: 1,
          appId: "sanmill",
          inviteToken: created.inviteToken,
          supportedGames: ["mill"],
          supportedRulesets: ["custom-v1"],
        }),
      });
    expect((await join()).status).toBe(200);
    const reused = await join();
    expect(reused.status).toBe(409);
    expect(await reused.json()).toMatchObject({ error: "invite_already_used" });
  });

  it("does not consume an invite when protocol or rules are incompatible", async () => {
    const created = await createRoom("second");
    expect(created.seat).toBe("second");

    const wrongProtocol = await joinRoom(created, { protocolVersion: 2 });
    expect(wrongProtocol.status).toBe(409);
    expect(await wrongProtocol.json()).toMatchObject({ error: "version_mismatch" });

    const wrongApp = await joinRoom(created, { appId: "another-app" });
    expect(wrongApp.status).toBe(409);
    expect(await wrongApp.json()).toMatchObject({ error: "version_mismatch" });

    const wrongRules = await joinRoom(created, {
      supportedRulesets: ["future-v2"],
    });
    expect(wrongRules.status).toBe(409);
    expect(await wrongRules.json()).toMatchObject({ error: "version_mismatch" });

    expect((await joinRoom(created)).status).toBe(200);
  });

  it("cancels a waiting room only with the creator seat token", async () => {
    const created = await createRoom("random");
    expect(["first", "second"]).toContain(created.seat);
    const roomId = created.room.roomId as string;

    const unauthorized = await SELF.fetch(
      `https://example.test/v1/rooms/${roomId}`,
      { method: "DELETE" },
    );
    expect(unauthorized.status).toBe(401);

    const canceled = await SELF.fetch(
      `https://example.test/v1/rooms/${roomId}`,
      {
        method: "DELETE",
        headers: { authorization: `Bearer ${created.seatToken}` },
      },
    );
    expect(canceled.status).toBe(204);
    expect((await issueTicket(roomId, created.seatToken)).status).toBe(410);
  });

  it("uses one-time WebSocket tickets and restores hibernated sockets", async () => {
    const created = await createRoom("first");
    const joinedResponse = await joinRoom(created);
    const joined = (await joinedResponse.json()) as Json;
    const roomId = created.room.roomId as string;

    const hostTicket = await ticketValue(roomId, created.seatToken);
    const host = await openSocket(roomId, hostTicket);
    expect(host.welcome).toMatchObject({
      type: "welcome",
      seat: "first",
      opponentConnected: false,
    });

    const reused = await SELF.fetch(
      socketUrl(roomId, hostTicket),
      { headers: { upgrade: "websocket" } },
    );
    expect(reused.status).toBe(401);
    await reused.arrayBuffer();

    const hostPeerConnected = nextMessage(host.socket);
    const joinTicket = await ticketValue(roomId, joined.seatToken as string);
    const joiner = await openSocket(roomId, joinTicket);
    expect(joiner.welcome).toMatchObject({
      type: "welcome",
      seat: "second",
      opponentConnected: true,
    });
    await expect(hostPeerConnected).resolves.toMatchObject({
      type: "opponentConnection",
      connected: true,
    });

    const hostState = nextMessage(host.socket);
    const joinState = nextMessage(joiner.socket);
    const firstAction = command("action-0001", 1, "action", { action: "a7" });
    host.socket.send(JSON.stringify(firstAction));
    await expect(hostState).resolves.toMatchObject({
      type: "state",
      seq: 2,
      commandId: "action-0001",
      snapshot: { actions: ["a7"] },
    });
    await expect(joinState).resolves.toMatchObject({
      type: "state",
      seq: 2,
      snapshot: { actions: ["a7"] },
    });

    const duplicate = nextMessage(host.socket);
    host.socket.send(JSON.stringify(firstAction));
    await expect(duplicate).resolves.toMatchObject({
      type: "state",
      seq: 2,
      snapshot: { actions: ["a7"] },
    });

    const stale = nextMessage(host.socket);
    host.socket.send(
      JSON.stringify(command("action-0002", 1, "action", { action: "d7" })),
    );
    await expect(stale).resolves.toMatchObject({
      type: "error",
      error: "stale_revision",
      seq: 2,
    });

    const staleDuplicate = nextMessage(host.socket);
    host.socket.send(
      JSON.stringify(command("action-0002", 2, "action", { action: "d7" })),
    );
    await expect(staleDuplicate).resolves.toMatchObject({
      type: "error",
      error: "stale_revision",
      seq: 2,
    });

    await evictDurableObject(env.ROOMS.getByName(roomId));
    const hostAfterHibernate = nextMessage(host.socket);
    const joinAfterHibernate = nextMessage(joiner.socket);
    joiner.socket.send(
      JSON.stringify(command("action-0003", 2, "action", { action: "d7" })),
    );
    await expect(hostAfterHibernate).resolves.toMatchObject({
      type: "state",
      seq: 3,
      snapshot: { actions: ["a7", "d7"] },
    });
    await expect(joinAfterHibernate).resolves.toMatchObject({
      type: "state",
      seq: 3,
    });
  });

  it("persists control results and terminal state across reconnects", async () => {
    const created = await createRoom("first");
    const joined = (await (await joinRoom(created)).json()) as Json;
    const roomId = created.room.roomId as string;
    const host = await openSocket(
      roomId,
      await ticketValue(roomId, created.seatToken),
    );
    const hostConnected = nextMessage(host.socket);
    const joiner = await openSocket(
      roomId,
      await ticketValue(roomId, joined.seatToken as string),
    );
    await hostConnected;

    const hostAction = nextMessage(host.socket);
    const joinAction = nextMessage(joiner.socket);
    host.socket.send(
      JSON.stringify(command("control-a1", 1, "action", { action: "a7" })),
    );
    await hostAction;
    await joinAction;

    const hostRequestAck = nextMessage(host.socket);
    const joinRequest = nextMessage(joiner.socket);
    host.socket.send(
      JSON.stringify(
        command("takeback-001", 2, "takeBackRequest", { steps: 1 }),
      ),
    );
    await expect(hostRequestAck).resolves.toMatchObject({
      seq: 3,
      pendingControl: {
        kind: "takeBack",
        requestId: "takeback-001",
        requester: "first",
      },
    });
    await expect(joinRequest).resolves.toMatchObject({
      type: "controlRequest",
      kind: "takeBack",
      requestId: "takeback-001",
    });

    const hostResult = nextMessage(host.socket);
    const joinResult = nextMessage(joiner.socket);
    joiner.socket.send(
      JSON.stringify(
        command("takeback-002", 3, "takeBackResponse", {
          requestId: "takeback-001",
          accepted: true,
        }),
      ),
    );
    await expect(hostResult).resolves.toMatchObject({
      type: "controlResult",
      accepted: true,
      seq: 4,
      snapshot: { actions: [] },
    });
    await expect(joinResult).resolves.toMatchObject({
      type: "controlResult",
      seq: 4,
    });

    const hostEnded = nextMessage(host.socket);
    const joinEnded = nextMessage(joiner.socket);
    host.socket.send(JSON.stringify(command("resign-0001", 4, "resign", {})));
    await expect(hostEnded).resolves.toMatchObject({ status: "ended", seq: 5 });
    await expect(joinEnded).resolves.toMatchObject({
      type: "opponentResigned",
      seq: 5,
    });

    const recovered = await openSocket(
      roomId,
      await ticketValue(roomId, joined.seatToken as string),
    );
    expect(recovered.welcome).toMatchObject({
      type: "welcome",
      room: {
        status: "ended",
        endReason: "resign",
        winnerSeat: "second",
      },
    });
  });

  it("automatically rejects an unanswered control request without deleting the room", async () => {
    const created = await createRoom("first");
    const joined = (await (await joinRoom(created)).json()) as Json;
    const roomId = created.room.roomId as string;
    const host = await openSocket(
      roomId,
      await ticketValue(roomId, created.seatToken),
    );
    const hostConnected = nextMessage(host.socket);
    const joiner = await openSocket(
      roomId,
      await ticketValue(roomId, joined.seatToken as string),
    );
    await hostConnected;

    const hostAck = nextMessage(host.socket);
    const joinRequest = nextMessage(joiner.socket);
    host.socket.send(
      JSON.stringify(command("restart-001", 1, "restartRequest", {})),
    );
    await expect(hostAck).resolves.toMatchObject({
      type: "state",
      seq: 2,
    });
    await expect(joinRequest).resolves.toMatchObject({
      type: "controlRequest",
      kind: "restart",
      requestId: "restart-001",
    });

    const hostTimeout = nextMessage(host.socket);
    const joinTimeout = nextMessage(joiner.socket);
    expect(await runDurableObjectAlarm(env.ROOMS.getByName(roomId))).toBe(true);
    await expect(hostTimeout).resolves.toMatchObject({
      type: "controlResult",
      requestId: "restart-001",
      accepted: false,
      seq: 3,
      pendingControl: null,
    });
    await expect(joinTimeout).resolves.toMatchObject({
      type: "controlResult",
      accepted: false,
      seq: 3,
    });
    expect((await issueTicket(roomId, created.seatToken)).status).toBe(200);
  });

  it("deletes room state when its Durable Object alarm runs", async () => {
    const created = await createRoom("first");
    const roomId = created.room.roomId as string;
    expect(await runDurableObjectAlarm(env.ROOMS.getByName(roomId))).toBe(true);
    expect((await issueTicket(roomId, created.seatToken)).status).toBe(410);
  });
});

async function createRoom(sidePreference: "first" | "second" | "random") {
  const response = await SELF.fetch("https://example.test/v1/rooms", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      protocolVersion: 1,
      appId: "sanmill",
      gameId: "mill",
      rulesetId: "custom-v1",
      ruleOptions: defaultOptions,
      sidePreference,
    }),
  });
  expect(response.status).toBe(201);
  return (await response.json()) as Json;
}

function joinRoom(
  created: Json,
  overrides: Partial<{
    protocolVersion: number;
    appId: string;
    inviteToken: string;
    supportedGames: string[];
    supportedRulesets: string[];
  }> = {},
): Promise<Response> {
  const roomId = created.room.roomId as string;
  return SELF.fetch(`https://example.test/v1/rooms/${roomId}/join`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      protocolVersion: 1,
      appId: "sanmill",
      inviteToken: created.inviteToken,
      supportedGames: ["mill"],
      supportedRulesets: ["custom-v1"],
      ...overrides,
    }),
  });
}

function issueTicket(roomId: string, seatToken: string): Promise<Response> {
  return SELF.fetch(`https://example.test/v1/rooms/${roomId}/ticket`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${seatToken}`,
      "content-type": "application/json",
    },
    body: "{}",
  });
}

async function ticketValue(roomId: string, seatToken: string): Promise<string> {
  const response = await issueTicket(roomId, seatToken);
  expect(response.status).toBe(200);
  const body = (await response.json()) as Json;
  return body.ticket as string;
}

async function openSocket(roomId: string, ticket: string) {
  const response = await SELF.fetch(socketUrl(roomId, ticket), {
    headers: { upgrade: "websocket" },
  });
  expect(response.status).toBe(101);
  const socket = response.webSocket;
  if (socket === null) {
    throw new Error("WebSocket upgrade returned no client socket");
  }
  openSockets.push(socket);
  const welcome = nextMessage(socket);
  socket.accept();
  return { socket, welcome: await welcome };
}

function socketUrl(roomId: string, ticket: string): string {
  return `https://example.test/v1/rooms/${roomId}/socket?ticket=${ticket}`;
}

function nextMessage(socket: WebSocket): Promise<Json> {
  return new Promise<Json>((resolve, reject) => {
    const timeout = setTimeout(
      () => reject(new Error("Timed out waiting for WebSocket message")),
      3000,
    );
    socket.addEventListener(
      "message",
      (event) => {
        clearTimeout(timeout);
        try {
          resolve(JSON.parse(event.data as string) as Json);
        } catch (error) {
          reject(error);
        }
      },
      { once: true },
    );
  });
}

function command(
  commandId: string,
  expectedSeq: number,
  type: string,
  payload: Record<string, unknown>,
): Json {
  return { protocolVersion: 1, commandId, expectedSeq, type, payload };
}

function capture(enabled: boolean): Record<string, boolean> {
  return {
    enabled,
    onSquareEdges: true,
    onCrossLines: true,
    onDiagonalLines: true,
    inPlacingPhase: true,
    inMovingPhase: true,
    onlyAvailableWhenOwnPiecesLeq3: false,
  };
}
