// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from "vitest";

import {
  BOARD_TRANSFORMATIONS,
  isBoardTransformation,
  transformMillAction,
} from "../src/board_transform";

describe("online board transformations", () => {
  it("matches the Flutter protocol tokens and coordinate mappings", () => {
    const expected = [
      "a7-d5",
      "g7-e4",
      "g1-d3",
      "a1-c4",
      "a1-d3",
      "g7-d5",
      "g1-e4",
      "a7-c4",
      "c5-d7",
      "e5-g4",
      "e3-d1",
      "c3-a4",
      "c3-d1",
      "e5-d7",
      "e3-g4",
      "c5-a4",
    ];

    expect(
      BOARD_TRANSFORMATIONS.map((transformation) =>
        transformMillAction("a7-d5", transformation),
      ),
    ).toEqual(expected);
  });

  it("transforms placements, removals, and moves consistently", () => {
    expect(transformMillAction("a7", "rotate90")).toBe("g7");
    expect(transformMillAction("xa7", "rotate90")).toBe("xg7");
    expect(transformMillAction("a7-d7", "rotate90")).toBe("g7-g4");
    expect(transformMillAction("draw", "rotate90")).toBe("draw");
    expect(transformMillAction("(none)", "rotate90")).toBe("(none)");
  });

  it("rejects transformation tokens outside the stable protocol set", () => {
    expect(isBoardTransformation("swapMirrorSlash")).toBe(true);
    expect(isBoardTransformation("flip")).toBe(false);
    expect(isBoardTransformation(1)).toBe(false);
  });
});
