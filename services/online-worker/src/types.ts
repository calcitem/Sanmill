// SPDX-License-Identifier: AGPL-3.0-or-later

export const PROTOCOL_VERSION = 1;
export const ROOM_LIFETIME_MS = 24 * 60 * 60 * 1000;
export const TICKET_LIFETIME_MS = 60 * 1000;
export const CONTROL_REQUEST_LIFETIME_MS = 30 * 1000;
export const MAX_BODY_BYTES = 64 * 1024;
export const MAX_RECENT_COMMANDS = 64;

export type Seat = "first" | "second";
export type SidePreference = Seat | "random";
export type RoomStatus = "waiting" | "active" | "ended";
export type EndReason = "outcome" | "resign" | "left";
export type ControlKind = "takeBack" | "restart";

export interface Env {
  ROOMS: DurableObjectNamespace;
  ONLINE_ENABLED: string;
  SOURCE_URL: string;
  INSTALL_URL: string;
  SOURCE_VERSION: string;
  ANDROID_APP_LINK_SHA256_CERT_FINGERPRINTS?: string;
}

export interface RulePosition {
  snapshot: string;
  fen: string;
  sideToMove: number;
  outcome: RuleOutcome;
}

export interface RuleOutcome {
  kind: "ongoing" | "win" | "winTeam" | "draw" | "abandoned";
  winner: number | null;
  reason: string;
}

export interface RuleResult extends Partial<RulePosition> {
  ok: boolean;
  error?: string;
}

export interface PendingControl {
  kind: ControlKind;
  requestId: string;
  requester: Seat;
  expiresAt: number;
  steps?: number;
}

export interface RoomState {
  roomId: string;
  protocolVersion: number;
  appId: string;
  gameId: string;
  rulesetId: string;
  ruleOptions: Record<string, unknown>;
  creatorSeat: Seat;
  creatorTokenHash: string;
  joinerTokenHash: string | null;
  inviteTokenHash: string;
  inviteUsed: boolean;
  status: RoomStatus;
  createdAt: number;
  expiresAt: number;
  seq: number;
  initialFen: string;
  position: RulePosition;
  actions: string[];
  tickets: TicketRecord[];
  recentCommands: RecentCommand[];
  pendingControl: PendingControl | null;
  endReason: EndReason | null;
  winnerSeat: Seat | null;
}

export interface TicketRecord {
  hash: string;
  seat: Seat;
  expiresAt: number;
  used: boolean;
}

export interface RecentCommand {
  id: string;
  seat: Seat;
  error: string | null;
}

export interface SocketAttachment {
  seat: Seat;
  connectedAt: number;
}

export interface ClientCommand {
  protocolVersion: number;
  commandId: string;
  expectedSeq: number;
  type:
    | "action"
    | "takeBackRequest"
    | "takeBackResponse"
    | "restartRequest"
    | "restartResponse"
    | "resign"
    | "leave";
  payload: Record<string, unknown>;
}

export interface CreateRoomBody {
  protocolVersion: number;
  appId: string;
  gameId: string;
  rulesetId: string;
  ruleOptions: Record<string, unknown>;
  sidePreference: SidePreference;
}

export interface JoinRoomBody {
  protocolVersion: number;
  appId: string;
  inviteToken: string;
  supportedGames: string[];
  supportedRulesets: string[];
}
