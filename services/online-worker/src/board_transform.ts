// SPDX-License-Identifier: AGPL-3.0-or-later

export const BOARD_TRANSFORMATIONS = [
  "identity",
  "rotate90",
  "rotate180",
  "rotate270",
  "mirrorVertical",
  "mirrorHorizontal",
  "mirrorBackslash",
  "mirrorSlash",
  "swap",
  "swapRotate90",
  "swapRotate180",
  "swapRotate270",
  "swapMirrorVertical",
  "swapMirrorHorizontal",
  "swapMirrorBackslash",
  "swapMirrorSlash",
] as const;

export type BoardTransformation = (typeof BOARD_TRANSFORMATIONS)[number];

type SpatialTransformation =
  | "identity"
  | "rotate90"
  | "rotate180"
  | "rotate270"
  | "mirrorVertical"
  | "mirrorHorizontal"
  | "mirrorBackslash"
  | "mirrorSlash";

interface TransformationDefinition {
  spatial: SpatialTransformation;
  swapRings: boolean;
}

const POINT_MAPS: Record<SpatialTransformation, readonly number[]> = {
  identity: [0, 1, 2, 3, 4, 5, 6, 7],
  rotate90: [2, 3, 4, 5, 6, 7, 0, 1],
  rotate180: [4, 5, 6, 7, 0, 1, 2, 3],
  rotate270: [6, 7, 0, 1, 2, 3, 4, 5],
  mirrorVertical: [4, 3, 2, 1, 0, 7, 6, 5],
  mirrorHorizontal: [0, 7, 6, 5, 4, 3, 2, 1],
  mirrorBackslash: [2, 1, 0, 7, 6, 5, 4, 3],
  mirrorSlash: [6, 5, 4, 3, 2, 1, 0, 7],
};

const TRANSFORMATION_DEFINITIONS: Record<
  BoardTransformation,
  TransformationDefinition
> = {
  identity: { spatial: "identity", swapRings: false },
  rotate90: { spatial: "rotate90", swapRings: false },
  rotate180: { spatial: "rotate180", swapRings: false },
  rotate270: { spatial: "rotate270", swapRings: false },
  mirrorVertical: { spatial: "mirrorVertical", swapRings: false },
  mirrorHorizontal: { spatial: "mirrorHorizontal", swapRings: false },
  mirrorBackslash: { spatial: "mirrorBackslash", swapRings: false },
  mirrorSlash: { spatial: "mirrorSlash", swapRings: false },
  swap: { spatial: "identity", swapRings: true },
  swapRotate90: { spatial: "rotate90", swapRings: true },
  swapRotate180: { spatial: "rotate180", swapRings: true },
  swapRotate270: { spatial: "rotate270", swapRings: true },
  swapMirrorVertical: { spatial: "mirrorVertical", swapRings: true },
  swapMirrorHorizontal: { spatial: "mirrorHorizontal", swapRings: true },
  swapMirrorBackslash: { spatial: "mirrorBackslash", swapRings: true },
  swapMirrorSlash: { spatial: "mirrorSlash", swapRings: true },
};

const BOARD_SQUARES = [
  "d5",
  "e5",
  "e4",
  "e3",
  "d3",
  "c3",
  "c4",
  "c5",
  "d6",
  "f6",
  "f4",
  "f2",
  "d2",
  "b2",
  "b4",
  "b6",
  "d7",
  "g7",
  "g4",
  "g1",
  "d1",
  "a1",
  "a4",
  "a7",
] as const;

const SQUARE_INDICES = new Map<string, number>(
  BOARD_SQUARES.map((square, index) => [square, index]),
);
const BOARD_TRANSFORMATION_SET = new Set<string>(BOARD_TRANSFORMATIONS);

export function isBoardTransformation(
  value: unknown,
): value is BoardTransformation {
  return typeof value === "string" && BOARD_TRANSFORMATION_SET.has(value);
}

export function transformMillAction(
  action: string,
  transformation: BoardTransformation,
): string {
  const trimmed = action.trim();
  if (trimmed === "draw" || trimmed === "(none)" || trimmed === "none") {
    return trimmed;
  }
  if (trimmed.startsWith("x") && trimmed.length === 3) {
    return `x${transformSquare(trimmed.slice(1), transformation)}`;
  }
  if (trimmed.includes("-") && trimmed.length === 5) {
    const parts = trimmed.split("-");
    if (parts.length === 2) {
      return `${transformSquare(parts[0], transformation)}-${transformSquare(
        parts[1],
        transformation,
      )}`;
    }
  }
  if (/^[a-g][1-7]$/u.test(trimmed)) {
    return transformSquare(trimmed, transformation);
  }
  return trimmed;
}

function transformSquare(
  square: string,
  transformation: BoardTransformation,
): string {
  const sourceIndex = SQUARE_INDICES.get(square.toLowerCase());
  if (sourceIndex === undefined) {
    return square;
  }
  const definition = TRANSFORMATION_DEFINITIONS[transformation];
  const sourceRing = Math.floor(sourceIndex / 8);
  const sourcePoint = sourceIndex % 8;
  const targetRing = definition.swapRings ? 2 - sourceRing : sourceRing;
  const targetPoint = POINT_MAPS[definition.spatial][sourcePoint];
  return BOARD_SQUARES[targetRing * 8 + targetPoint];
}
