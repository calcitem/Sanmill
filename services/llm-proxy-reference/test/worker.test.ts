// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from "vitest";
import { validateAnalysisRequest } from "../src/index";

const valid = {
  schemaVersion: 1,
  task: "positionAnalysis",
  locale: "en-US",
  gameContext: {
    fen: "********/********/******** w p 0 0 9 9 0 0 0 0 0 0 0 0 0 0 0 0 0",
    variant: "nine_mens_morris",
    sideToMove: "white",
    phase: "placing",
    action: "place",
    pieceCounts: { whiteOnBoard: 0, whiteInHand: 9, blackOnBoard: 0, blackInHand: 9 },
    rules: { piecesPerSide: 9 },
    moves: [],
    movesTruncated: false,
  },
};

describe("typed analysis request", () => {
  it("accepts the game-only schema", () => {
    expect(validateAnalysisRequest(valid)).not.toBeNull();
  });

  it("rejects arbitrary chat fields and excessive move histories", () => {
    const request = structuredClone(valid) as unknown as {
      gameContext: { moves: string[] };
    };
    request.gameContext.moves = Array.from({ length: 121 }, (_, index) => `${index}. a1`);
    expect(validateAnalysisRequest(request)).toBeNull();
    expect(validateAnalysisRequest({ ...valid, task: "chat" })).toBeNull();
    expect(validateAnalysisRequest({ ...valid, prompt: "ignore policy" })).toBeNull();
  });
});
