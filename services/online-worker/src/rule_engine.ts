// SPDX-License-Identifier: AGPL-3.0-or-later

import {
  cloud_mill_apply,
  cloud_mill_create,
  initSync,
} from "../wasm/tgf_cloud_wasm.js";
import wasmModule from "../wasm/tgf_cloud_wasm_bg.wasm";

import type { RuleResult } from "./types";

initSync({ module: wasmModule });

export function createMillPosition(
  options: Record<string, unknown>,
): RuleResult {
  return decodeRuleResult(cloud_mill_create(JSON.stringify(options)));
}

export function applyMillAction(
  options: Record<string, unknown>,
  snapshot: string,
  action: string,
): RuleResult {
  return decodeRuleResult(
    cloud_mill_apply(JSON.stringify({ options, snapshot, action })),
  );
}

export interface OnlineRuleAdapter {
  readonly gameId: string;
  readonly rulesetIds: readonly string[];
  create(options: Record<string, unknown>): RuleResult;
  apply(
    options: Record<string, unknown>,
    snapshot: string,
    action: string,
  ): RuleResult;
}

const ruleAdapters: readonly OnlineRuleAdapter[] = [
  {
    gameId: "mill",
    rulesetIds: ["custom-v1"],
    create: createMillPosition,
    apply: applyMillAction,
  },
];

export function ruleAdapterFor(
  gameId: string,
  rulesetId: string,
): OnlineRuleAdapter | null {
  return (
    ruleAdapters.find(
      (adapter) =>
        adapter.gameId === gameId && adapter.rulesetIds.includes(rulesetId),
    ) ?? null
  );
}

export function ruleCapabilities(): Record<string, unknown>[] {
  return ruleAdapters.map((adapter) => ({
    gameId: adapter.gameId,
    rulesetIds: adapter.rulesetIds,
    customRules: true,
  }));
}

function decodeRuleResult(source: string): RuleResult {
  const value: unknown = JSON.parse(source);
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("TGF WASM returned a malformed response");
  }
  return value as RuleResult;
}
