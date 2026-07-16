// SPDX-License-Identifier: AGPL-3.0-or-later

import { DurableObject } from "cloudflare:workers";

import {
  bearerToken,
  equalTokenHash,
  randomToken,
  tokenHash,
} from "./crypto";
import { HttpError, jsonResponse, protocolError, readJson } from "./http";
import { ruleAdapterFor } from "./rule_engine";
import {
  CONTROL_REQUEST_LIFETIME_MS,
  MAX_RECENT_COMMANDS,
  PROTOCOL_VERSION,
  ROOM_LIFETIME_MS,
  TICKET_LIFETIME_MS,
  type ClientCommand,
  type CreateRoomBody,
  type Env,
  type JoinRoomBody,
  type PendingControl,
  type RoomState,
  type RulePosition,
  type RuleResult,
  type Seat,
  type SocketAttachment,
} from "./types";

export class GameRoom extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS room_state (
        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
        json TEXT NOT NULL
      )
    `);
  }

  async fetch(request: Request): Promise<Response> {
    try {
      const url = new URL(request.url);
      const expired = await this.deleteIfExpired();
      if (expired) {
        return protocolError(
          410,
          url.pathname.endsWith("/join")
            ? "invite_expired"
            : "room_unavailable",
        );
      }

      if (request.method === "POST" && url.pathname === "/v1/rooms") {
        return await this.create(request);
      }
      if (request.method === "POST" && url.pathname.endsWith("/join")) {
        return await this.join(request);
      }
      if (request.method === "POST" && url.pathname.endsWith("/ticket")) {
        return await this.issueTicket(request);
      }
      if (request.method === "DELETE" && /^\/v1\/rooms\/[^/]+$/u.test(url.pathname)) {
        return await this.cancel(request);
      }
      if (request.method === "GET" && url.pathname.endsWith("/socket")) {
        return await this.acceptSocket(request, url);
      }
      return protocolError(404, "not_found");
    } catch (error) {
      if (error instanceof HttpError) {
        return protocolError(error.status, error.code);
      }
      console.error("ROOM_REQUEST_FAILED", safeErrorName(error));
      return protocolError(500, "service_unavailable");
    }
  }

  async webSocketMessage(
    socket: WebSocket,
    message: string | ArrayBuffer,
  ): Promise<void> {
    const attachment = socket.deserializeAttachment() as SocketAttachment | null;
    if (attachment === null || typeof message !== "string" || message.length > 64 * 1024) {
      socket.send(JSON.stringify({ type: "error", error: "protocol_error" }));
      return;
    }
    const state = this.loadState();
    if (state === null || state.expiresAt <= Date.now()) {
      socket.send(JSON.stringify({ type: "error", error: "room_unavailable" }));
      socket.close(4004, "Room unavailable");
      return;
    }

    let command: ClientCommand;
    try {
      command = parseCommand(message);
    } catch {
      this.sendError(socket, state, "protocol_error");
      return;
    }
    if (command.protocolVersion !== PROTOCOL_VERSION) {
      this.rejectCommand(
        socket,
        state,
        attachment.seat,
        command.commandId,
        "version_mismatch",
      );
      return;
    }

    const duplicate = state.recentCommands.find(
      (item) => item.id === command.commandId,
    );
    if (duplicate !== undefined) {
      if (duplicate.seat !== attachment.seat) {
        this.sendError(socket, state, "protocol_error", command.commandId);
      } else if (duplicate.error !== null) {
        this.sendError(socket, state, duplicate.error, command.commandId);
      } else {
        socket.send(JSON.stringify(this.stateEvent(state, command.commandId)));
      }
      return;
    }
    if (command.expectedSeq !== state.seq) {
      this.rejectCommand(
        socket,
        state,
        attachment.seat,
        command.commandId,
        "stale_revision",
      );
      return;
    }

    try {
      await this.handleCommand(socket, attachment.seat, state, command);
    } catch (error) {
      console.error("ROOM_COMMAND_FAILED", safeErrorName(error));
      this.sendError(socket, state, "service_unavailable", command.commandId);
    }
  }

  async webSocketClose(
    socket: WebSocket,
    _code: number,
    _reason: string,
    _wasClean: boolean,
  ): Promise<void> {
    const attachment = socket.deserializeAttachment() as SocketAttachment | null;
    if (attachment === null) {
      return;
    }
    const state = this.loadState();
    if (state === null || state.status === "ended") {
      return;
    }
    const remaining = this.ctx
      .getWebSockets(attachment.seat)
      .some((candidate) => candidate.readyState === WebSocket.OPEN);
    if (!remaining) {
      this.broadcast(
        {
          type: "opponentConnection",
          connected: false,
          seq: state.seq,
        },
        attachment.seat,
      );
    }
  }

  async webSocketError(socket: WebSocket): Promise<void> {
    const attachment = socket.deserializeAttachment() as SocketAttachment | null;
    if (attachment === null) {
      return;
    }
    const state = this.loadState();
    if (state !== null && state.status !== "ended") {
      if (!this.isSeatConnected(attachment.seat)) {
        this.broadcast(
          {
            type: "opponentConnection",
            connected: false,
            seq: state.seq,
          },
          attachment.seat,
        );
      }
    }
  }

  async alarm(): Promise<void> {
    const state = this.loadState();
    if (
      state !== null &&
      state.pendingControl !== null &&
      state.pendingControl.expiresAt < state.expiresAt
    ) {
      const pending = state.pendingControl;
      state.pendingControl = null;
      state.seq += 1;
      this.persistState(state);
      this.broadcast({
        ...this.stateEvent(state),
        type: "controlResult",
        kind: pending.kind,
        requestId: pending.requestId,
        accepted: false,
      });
      await this.ctx.storage.setAlarm(state.expiresAt);
      return;
    }
    for (const socket of this.ctx.getWebSockets()) {
      socket.close(4004, "Room expired");
    }
    this.deleteState();
  }

  private async create(request: Request): Promise<Response> {
    if (this.loadState() !== null) {
      return protocolError(409, "room_unavailable");
    }
    const body = await readJson<CreateRoomBody>(request);
    if (typeof body.protocolVersion !== "number") {
      return protocolError(400, "invalid_request");
    }
    if (body.protocolVersion !== PROTOCOL_VERSION) {
      return protocolError(409, "version_mismatch");
    }
    if (!validCreateBody(body)) {
      return protocolError(400, "invalid_request");
    }
    const ruleAdapter = ruleAdapterFor(body.gameId, body.rulesetId);
    if (ruleAdapter === null) {
      return protocolError(409, "invalid_ruleset");
    }
    const result = ruleAdapter.create(body.ruleOptions);
    if (!completeRuleResult(result)) {
      return protocolError(400, "invalid_ruleset");
    }

    const roomId = request.headers.get("x-sanmill-room-id") ?? "";
    if (!validRoomId(roomId)) {
      return protocolError(400, "invalid_request");
    }
    const creatorToken = randomToken(32);
    const inviteToken = randomToken(32);
    const creatorSeat = chooseSeat(body.sidePreference);
    const now = Date.now();
    const position = toPosition(result);
    const state: RoomState = {
      roomId,
      protocolVersion: PROTOCOL_VERSION,
      appId: body.appId,
      gameId: body.gameId,
      rulesetId: body.rulesetId,
      ruleOptions: body.ruleOptions,
      creatorSeat,
      creatorTokenHash: await tokenHash(creatorToken),
      joinerTokenHash: null,
      inviteTokenHash: await tokenHash(inviteToken),
      inviteUsed: false,
      status: "waiting",
      createdAt: now,
      expiresAt: now + ROOM_LIFETIME_MS,
      seq: 0,
      initialFen: position.fen,
      position,
      actions: [],
      tickets: [],
      recentCommands: [],
      pendingControl: null,
      endReason: null,
      winnerSeat: null,
    };
    this.persistState(state);
    await this.ctx.storage.setAlarm(state.expiresAt);
    return jsonResponse({
      ok: true,
      room: this.roomDescriptor(state),
      seat: creatorSeat,
      seatToken: creatorToken,
      inviteToken,
      snapshot: this.snapshot(state),
    }, 201);
  }

  private async join(request: Request): Promise<Response> {
    const state = this.requireState();
    const body = await readJson<JoinRoomBody>(request);
    if (
      typeof body.protocolVersion !== "number" ||
      typeof body.appId !== "string" ||
      typeof body.inviteToken !== "string" ||
      !validSecretToken(body.inviteToken) ||
      !Array.isArray(body.supportedGames) ||
      !Array.isArray(body.supportedRulesets)
    ) {
      return protocolError(400, "invalid_invite");
    }
    if (body.protocolVersion !== PROTOCOL_VERSION) {
      return protocolError(409, "version_mismatch");
    }
    if (body.appId !== state.appId) {
      return protocolError(409, "version_mismatch");
    }
    if (!body.supportedGames.includes(state.gameId)) {
      return protocolError(409, "version_mismatch");
    }
    if (
      body.supportedRulesets.length > 0 &&
      !body.supportedRulesets.includes(state.rulesetId)
    ) {
      return protocolError(409, "version_mismatch");
    }
    if (
      !equalTokenHash(
        await tokenHash(body.inviteToken),
        state.inviteTokenHash,
      )
    ) {
      return protocolError(404, "invalid_invite");
    }
    if (state.status === "ended") {
      return protocolError(410, "room_unavailable");
    }
    if (state.inviteUsed) {
      return protocolError(409, "invite_already_used");
    }
    if (state.status !== "waiting" || state.joinerTokenHash !== null) {
      return protocolError(409, "room_full");
    }

    const seatToken = randomToken(32);
    const seat = opposite(state.creatorSeat);
    state.joinerTokenHash = await tokenHash(seatToken);
    state.inviteUsed = true;
    state.status = "active";
    state.seq += 1;
    this.persistState(state);
    this.broadcast({
      ...this.stateEvent(state),
      type: "opponentJoined",
      connected: false,
    });
    return jsonResponse({
      ok: true,
      room: this.roomDescriptor(state),
      seat,
      seatToken,
      snapshot: this.snapshot(state),
    });
  }

  private async issueTicket(request: Request): Promise<Response> {
    const state = this.requireState();
    const seat = await this.authorizedSeat(request, state);
    if (seat === null) {
      return protocolError(401, "unauthorized");
    }
    const now = Date.now();
    state.tickets = state.tickets.filter(
      (ticket) =>
        ticket.seat !== seat && !ticket.used && ticket.expiresAt > now,
    );
    const ticket = randomToken(32);
    state.tickets.push({
      hash: await tokenHash(ticket),
      seat,
      expiresAt: now + TICKET_LIFETIME_MS,
      used: false,
    });
    this.persistState(state);
    return jsonResponse({ ok: true, ticket, expiresAt: now + TICKET_LIFETIME_MS });
  }

  private async acceptSocket(request: Request, url: URL): Promise<Response> {
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
      return protocolError(426, "websocket_required");
    }
    const state = this.requireState();
    const rawTicket = url.searchParams.get("ticket") ?? "";
    if (!validSecretToken(rawTicket)) {
      return protocolError(401, "unauthorized");
    }
    const hash = await tokenHash(rawTicket);
    const now = Date.now();
    const record = state.tickets.find(
      (candidate) =>
        equalTokenHash(candidate.hash, hash) &&
        !candidate.used &&
        candidate.expiresAt > now,
    );
    if (record === undefined) {
      return protocolError(401, "unauthorized");
    }
    record.used = true;
    this.persistState(state);

    for (const existing of this.ctx.getWebSockets(record.seat)) {
      existing.close(4001, "Replaced by a newer connection");
    }
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.ctx.acceptWebSocket(server, [record.seat]);
    server.serializeAttachment({
      seat: record.seat,
      connectedAt: now,
    } satisfies SocketAttachment);
    server.send(
      JSON.stringify({
        ...this.stateEvent(state),
        type: "welcome",
        seat: record.seat,
        room: this.roomDescriptor(state),
        opponentConnected: this.isSeatConnected(opposite(record.seat)),
      }),
    );
    this.broadcast(
      { type: "opponentConnection", connected: true, seq: state.seq },
      record.seat,
    );
    return new Response(null, { status: 101, webSocket: client });
  }

  private async cancel(request: Request): Promise<Response> {
    const state = this.requireState();
    const seat = await this.authorizedSeat(request, state);
    if (seat === null) {
      return protocolError(401, "unauthorized");
    }
    if (seat !== state.creatorSeat || state.status !== "waiting") {
      return protocolError(409, "room_unavailable");
    }
    for (const socket of this.ctx.getWebSockets()) {
      socket.close(4000, "Room canceled");
    }
    this.deleteState();
    await this.ctx.storage.deleteAlarm();
    return new Response(null, { status: 204 });
  }

  private async handleCommand(
    socket: WebSocket,
    seat: Seat,
    state: RoomState,
    command: ClientCommand,
  ): Promise<void> {
    switch (command.type) {
      case "action":
        await this.applyAction(socket, seat, state, command);
        return;
      case "takeBackRequest":
        await this.requestControl(socket, seat, state, command, "takeBack");
        return;
      case "restartRequest":
        await this.requestControl(socket, seat, state, command, "restart");
        return;
      case "takeBackResponse":
        await this.respondControl(socket, seat, state, command, "takeBack");
        return;
      case "restartResponse":
        await this.respondControl(socket, seat, state, command, "restart");
        return;
      case "resign":
        if (state.status !== "active") {
          this.rejectCommand(
            socket,
            state,
            seat,
            command.commandId,
            "action_rejected",
          );
          return;
        }
        this.remember(state, seat, command.commandId);
        state.status = "ended";
        state.endReason = "resign";
        state.winnerSeat = opposite(seat);
        state.seq += 1;
        this.persistState(state);
        socket.send(JSON.stringify(this.stateEvent(state, command.commandId)));
        this.broadcast(
          { type: "opponentResigned", seq: state.seq },
          seat,
        );
        return;
      case "leave":
        if (state.status !== "active") {
          this.rejectCommand(
            socket,
            state,
            seat,
            command.commandId,
            "action_rejected",
          );
          return;
        }
        this.remember(state, seat, command.commandId);
        state.status = "ended";
        state.endReason = "left";
        state.winnerSeat = null;
        state.seq += 1;
        this.persistState(state);
        this.broadcast({ type: "opponentLeft", seq: state.seq }, seat);
        socket.send(JSON.stringify(this.stateEvent(state, command.commandId)));
        socket.close(1000, "Left game");
        return;
    }
  }

  private async applyAction(
    socket: WebSocket,
    seat: Seat,
    state: RoomState,
    command: ClientCommand,
  ): Promise<void> {
    const action = command.payload.action;
    if (
      state.status !== "active" ||
      typeof action !== "string" ||
      action.length === 0 ||
      seatForSide(state.position.sideToMove) !== seat ||
      state.pendingControl !== null
    ) {
      this.rejectCommand(
        socket,
        state,
        seat,
        command.commandId,
        "action_rejected",
      );
      return;
    }
    const ruleAdapter = ruleAdapterFor(state.gameId, state.rulesetId);
    if (ruleAdapter === null) {
      throw new Error("Persisted room has no registered rule adapter");
    }
    const result = ruleAdapter.apply(
      state.ruleOptions,
      state.position.snapshot,
      action,
    );
    if (!completeRuleResult(result)) {
      this.rejectCommand(
        socket,
        state,
        seat,
        command.commandId,
        "action_rejected",
      );
      return;
    }
    state.position = toPosition(result);
    state.actions.push(action);
    state.seq += 1;
    this.remember(state, seat, command.commandId);
    if (state.position.outcome.kind !== "ongoing") {
      state.status = "ended";
      state.endReason = "outcome";
      state.winnerSeat = seatForSide(state.position.outcome.winner ?? -1);
    }
    this.persistState(state);
    this.broadcast(this.stateEvent(state, command.commandId));
  }

  private async requestControl(
    socket: WebSocket,
    seat: Seat,
    state: RoomState,
    command: ClientCommand,
    kind: "takeBack" | "restart",
  ): Promise<void> {
    const steps = kind === "takeBack" ? command.payload.steps : undefined;
    if (
      state.status !== "active" ||
      state.pendingControl !== null ||
      (kind === "takeBack" &&
        (typeof steps !== "number" ||
          !Number.isInteger(steps) ||
          steps <= 0 ||
          steps > state.actions.length))
    ) {
      this.rejectCommand(
        socket,
        state,
        seat,
        command.commandId,
        "action_rejected",
      );
      return;
    }
    const expiresAt = Math.min(
      Date.now() + CONTROL_REQUEST_LIFETIME_MS,
      state.expiresAt,
    );
    state.pendingControl = {
      kind,
      requestId: command.commandId,
      requester: seat,
      expiresAt,
      ...(typeof steps === "number" ? { steps } : {}),
    };
    state.seq += 1;
    this.remember(state, seat, command.commandId);
    this.persistState(state);
    await this.ctx.storage.setAlarm(expiresAt);
    socket.send(JSON.stringify(this.stateEvent(state, command.commandId)));
    this.broadcast(
      {
        type: "controlRequest",
        kind,
        requestId: command.commandId,
        steps,
        seq: state.seq,
      },
      seat,
    );
  }

  private async respondControl(
    socket: WebSocket,
    seat: Seat,
    state: RoomState,
    command: ClientCommand,
    kind: "takeBack" | "restart",
  ): Promise<void> {
    const pending: PendingControl | null = state.pendingControl;
    const requestId = command.payload.requestId;
    const accepted = command.payload.accepted;
    if (
      pending === null ||
      pending.kind !== kind ||
      pending.requester === seat ||
      requestId !== pending.requestId ||
      typeof accepted !== "boolean"
    ) {
      this.rejectCommand(
        socket,
        state,
        seat,
        command.commandId,
        "action_rejected",
      );
      return;
    }
    if (accepted && kind === "takeBack") {
      const steps = pending.steps ?? 0;
      state.actions.splice(state.actions.length - steps, steps);
      state.position = this.replayActions(state);
      state.status = "active";
    } else if (accepted && kind === "restart") {
      state.actions = [];
      state.position = this.replayActions(state);
      state.status = "active";
    }
    state.pendingControl = null;
    state.seq += 1;
    this.remember(state, seat, command.commandId);
    this.persistState(state);
    await this.ctx.storage.setAlarm(state.expiresAt);
    this.broadcast({
      ...this.stateEvent(state, command.commandId),
      type: "controlResult",
      kind,
      requestId,
      accepted,
    });
  }

  private requireState(): RoomState {
    const state = this.loadState();
    if (state === null || state.expiresAt <= Date.now()) {
      throw new HttpError(410, "room_unavailable");
    }
    return state;
  }

  private replayActions(state: RoomState): RulePosition {
    const ruleAdapter = ruleAdapterFor(state.gameId, state.rulesetId);
    if (ruleAdapter === null) {
      throw new Error("Persisted room has no registered rule adapter");
    }
    let result = ruleAdapter.create(state.ruleOptions);
    if (!completeRuleResult(result)) {
      throw new Error("Persisted room has invalid rule options");
    }
    let position = toPosition(result);
    for (const action of state.actions) {
      result = ruleAdapter.apply(
        state.ruleOptions,
        position.snapshot,
        action,
      );
      if (!completeRuleResult(result)) {
        throw new Error("Persisted room has an invalid action history");
      }
      position = toPosition(result);
    }
    return position;
  }

  private loadState(): RoomState | null {
    const rows = [
      ...this.ctx.storage.sql.exec<{ json: string }>(
        "SELECT json FROM room_state WHERE singleton = 1",
      ),
    ];
    return rows.length === 0 ? null : (JSON.parse(rows[0].json) as RoomState);
  }

  private persistState(state: RoomState): void {
    this.ctx.storage.sql.exec(
      `INSERT INTO room_state (singleton, json) VALUES (1, ?)
       ON CONFLICT(singleton) DO UPDATE SET json = excluded.json`,
      JSON.stringify(state),
    );
  }

  private async deleteIfExpired(): Promise<boolean> {
    const state = this.loadState();
    if (state === null || state.expiresAt > Date.now()) {
      return false;
    }
    for (const socket of this.ctx.getWebSockets()) {
      socket.close(4004, "Room expired");
    }
    this.deleteState();
    await this.ctx.storage.deleteAlarm();
    return true;
  }

  private deleteState(): void {
    this.ctx.storage.sql.exec(
      "DELETE FROM room_state WHERE singleton = 1",
    );
  }

  private async authorizedSeat(
    request: Request,
    state: RoomState,
  ): Promise<Seat | null> {
    const token = bearerToken(request);
    if (token === null) {
      return null;
    }
    const hash = await tokenHash(token);
    if (equalTokenHash(hash, state.creatorTokenHash)) {
      return state.creatorSeat;
    }
    if (
      state.joinerTokenHash !== null &&
      equalTokenHash(hash, state.joinerTokenHash)
    ) {
      return opposite(state.creatorSeat);
    }
    return null;
  }

  private roomDescriptor(state: RoomState): Record<string, unknown> {
    return {
      roomId: state.roomId,
      protocolVersion: state.protocolVersion,
      appId: state.appId,
      gameId: state.gameId,
      rulesetId: state.rulesetId,
      ruleOptions: state.ruleOptions,
      creatorSeat: state.creatorSeat,
      status: state.status,
      createdAt: state.createdAt,
      expiresAt: state.expiresAt,
      endReason: state.endReason,
      winnerSeat: state.winnerSeat,
    };
  }

  private snapshot(state: RoomState): Record<string, unknown> {
    return {
      revision: state.seq,
      initialFen: state.initialFen,
      actions: state.actions,
      resultFen: state.position.fen,
      outcome: state.position.outcome,
    };
  }

  private stateEvent(
    state: RoomState,
    commandId?: string,
  ): Record<string, unknown> {
    return {
      type: "state",
      seq: state.seq,
      status: state.status,
      ...(commandId === undefined ? {} : { commandId }),
      pendingControl: state.pendingControl,
      snapshot: this.snapshot(state),
    };
  }

  private sendError(
    socket: WebSocket,
    state: RoomState,
    error: string,
    commandId?: string,
  ): void {
    socket.send(
      JSON.stringify({
        type: "error",
        error,
        seq: state.seq,
        ...(commandId === undefined ? {} : { commandId }),
        snapshot: this.snapshot(state),
      }),
    );
  }

  private rejectCommand(
    socket: WebSocket,
    state: RoomState,
    seat: Seat,
    commandId: string,
    error: string,
  ): void {
    this.remember(state, seat, commandId, error);
    this.persistState(state);
    this.sendError(socket, state, error, commandId);
  }

  private broadcast(value: unknown, excludedSeat?: Seat): void {
    const payload = JSON.stringify(value);
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = socket.deserializeAttachment() as SocketAttachment | null;
      if (
        socket.readyState === WebSocket.OPEN &&
        (excludedSeat === undefined || attachment?.seat !== excludedSeat)
      ) {
        socket.send(payload);
      }
    }
  }

  private isSeatConnected(seat: Seat): boolean {
    return this.ctx
      .getWebSockets(seat)
      .some((socket) => socket.readyState === WebSocket.OPEN);
  }

  private remember(
    state: RoomState,
    seat: Seat,
    id: string,
    error: string | null = null,
  ): void {
    state.recentCommands.push({ id, seat, error });
    if (state.recentCommands.length > MAX_RECENT_COMMANDS) {
      state.recentCommands.splice(
        0,
        state.recentCommands.length - MAX_RECENT_COMMANDS,
      );
    }
  }
}

function validCreateBody(value: CreateRoomBody): boolean {
  return (
    value.protocolVersion === PROTOCOL_VERSION &&
    /^[a-z0-9._-]{1,48}$/u.test(value.appId) &&
    /^[a-z0-9._-]{1,48}$/u.test(value.gameId) &&
    /^[a-z0-9._:-]{1,64}$/u.test(value.rulesetId) &&
    value.ruleOptions !== null &&
    typeof value.ruleOptions === "object" &&
    !Array.isArray(value.ruleOptions) &&
    ["first", "second", "random"].includes(value.sidePreference)
  );
}

function validRoomId(value: string): boolean {
  return /^[A-Za-z0-9_-]{22}$/u.test(value);
}

function validSecretToken(value: string): boolean {
  return /^[A-Za-z0-9_-]{43}$/u.test(value);
}

function chooseSeat(preference: "first" | "second" | "random"): Seat {
  if (preference !== "random") {
    return preference;
  }
  const random = new Uint8Array(1);
  crypto.getRandomValues(random);
  return (random[0] & 1) === 0 ? "first" : "second";
}

function opposite(seat: Seat): Seat {
  return seat === "first" ? "second" : "first";
}

function seatForSide(side: number): Seat | null {
  return side === 0 ? "first" : side === 1 ? "second" : null;
}

function completeRuleResult(result: RuleResult): result is RuleResult & RulePosition {
  return (
    result.ok &&
    typeof result.snapshot === "string" &&
    typeof result.fen === "string" &&
    typeof result.sideToMove === "number" &&
    result.outcome !== undefined
  );
}

function toPosition(result: RuleResult & RulePosition): RulePosition {
  return {
    snapshot: result.snapshot,
    fen: result.fen,
    sideToMove: result.sideToMove,
    outcome: result.outcome,
  };
}

function parseCommand(source: string): ClientCommand {
  const decoded: unknown = JSON.parse(source);
  if (decoded === null || typeof decoded !== "object" || Array.isArray(decoded)) {
    throw new Error("Invalid command");
  }
  const value = decoded as Partial<ClientCommand>;
  if (
    typeof value.protocolVersion !== "number" ||
    typeof value.commandId !== "string" ||
    !/^[A-Za-z0-9_-]{8,128}$/u.test(value.commandId) ||
    typeof value.expectedSeq !== "number" ||
    !Number.isInteger(value.expectedSeq) ||
    value.expectedSeq < 0 ||
    typeof value.type !== "string" ||
    ![
      "action",
      "takeBackRequest",
      "takeBackResponse",
      "restartRequest",
      "restartResponse",
      "resign",
      "leave",
    ].includes(value.type) ||
    value.payload === null ||
    typeof value.payload !== "object" ||
    Array.isArray(value.payload)
  ) {
    throw new Error("Invalid command");
  }
  return value as ClientCommand;
}

function safeErrorName(error: unknown): string {
  return error instanceof Error ? error.name : "UnknownError";
}
