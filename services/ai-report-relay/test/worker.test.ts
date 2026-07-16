// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from "vitest";
import { validateReport } from "../src/index";

const valid = {
  schemaVersion: 1,
  category: "incorrect",
  task: "positionAnalysis",
  surface: "gameAnalysis",
  provider: "OpenAI-compatible proxy",
  model: "model",
  appVersion: "8.0.0+1",
  platform: "android",
  locale: "en-US",
};

describe("AI report data minimization", () => {
  it("accepts metadata-only reports", () => {
    expect(validateReport(valid)).not.toBeNull();
  });

  it("rejects game state and device identifiers", () => {
    expect(validateReport({ ...valid, fen: "secret" })).toBeNull();
    expect(validateReport({ ...valid, deviceId: "device" })).toBeNull();
  });

  it("accepts an explicitly supplied bounded answer", () => {
    expect(validateReport({ ...valid, answer: "Incorrect analysis" })).not.toBeNull();
    expect(validateReport({ ...valid, answer: "x".repeat(16_385) })).toBeNull();
  });
});
