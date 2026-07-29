#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Shared ring-16 similarity rules for Mill puzzle selection and merging."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Sequence


# Distances below four include exact copies, one-stone changes, and the
# smallest two-stone edits. Those positions are too easy to recognise as the
# same exercise even after colours and the solver side are normalised.
DEFAULT_MINIMUM_POSITION_DISTANCE = 4

PERFECT_LABELS = (
    "a4",
    "a7",
    "d7",
    "g7",
    "g4",
    "g1",
    "d1",
    "a1",
    "b4",
    "b6",
    "d6",
    "f6",
    "f4",
    "f2",
    "d2",
    "b2",
    "c4",
    "c5",
    "d5",
    "e5",
    "e4",
    "e3",
    "d3",
    "c3",
)
LABEL_INDEX = {label: index for index, label in enumerate(PERFECT_LABELS)}
FEN_LABELS = (
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
)
COORDINATES = {
    "a7": (-3, -3),
    "d7": (0, -3),
    "g7": (3, -3),
    "g4": (3, 0),
    "g1": (3, 3),
    "d1": (0, 3),
    "a1": (-3, 3),
    "a4": (-3, 0),
    "b6": (-2, -2),
    "d6": (0, -2),
    "f6": (2, -2),
    "f4": (2, 0),
    "f2": (2, 2),
    "d2": (0, 2),
    "b2": (-2, 2),
    "b4": (-2, 0),
    "c5": (-1, -1),
    "d5": (0, -1),
    "e5": (1, -1),
    "e4": (1, 0),
    "e3": (1, 1),
    "d3": (0, 1),
    "c3": (-1, 1),
    "c4": (-1, 0),
}
INDEX_BY_COORDINATE = {
    coordinate: LABEL_INDEX[label] for label, coordinate in COORDINATES.items()
}


@dataclass(frozen=True)
class PositionFingerprint:
    white_bits: int
    black_bits: int
    white_in_hand: int
    black_in_hand: int
    side_to_move: int

    def solver_normalised(self) -> tuple[int, int, int, int]:
        if self.side_to_move == 0:
            return (
                self.white_bits,
                self.black_bits,
                self.white_in_hand,
                self.black_in_hand,
            )
        return (
            self.black_bits,
            self.white_bits,
            self.black_in_hand,
            self.white_in_hand,
        )


@dataclass(frozen=True)
class PositionConflict:
    left_id: str
    right_id: str
    distance: int


def _dihedral(x: int, y: int, operation: int) -> tuple[int, int]:
    operations = (
        (x, y),
        (-y, x),
        (-x, -y),
        (y, -x),
        (-x, y),
        (x, -y),
        (y, x),
        (-y, -x),
    )
    return operations[operation]


def _ring_swap(x: int, y: int) -> tuple[int, int]:
    radius = max(abs(x), abs(y))
    swapped_radius = 4 - radius
    return (
        0 if x == 0 else (swapped_radius if x > 0 else -swapped_radius),
        0 if y == 0 else (swapped_radius if y > 0 else -swapped_radius),
    )


def _symmetry_permutations() -> tuple[tuple[int, ...], ...]:
    permutations = []
    for swap_rings in (False, True):
        for operation in range(8):
            transformed = []
            for label in PERFECT_LABELS:
                x, y = COORDINATES[label]
                if swap_rings:
                    x, y = _ring_swap(x, y)
                transformed.append(INDEX_BY_COORDINATE[_dihedral(x, y, operation)])
            permutations.append(tuple(transformed))
    assert len(set(permutations)) == 16
    return tuple(permutations)


SYMMETRIES = _symmetry_permutations()


def _transform_bits(bits: int, permutation: Iterable[int]) -> int:
    transformed = 0
    for source, target in enumerate(permutation):
        if bits & (1 << source):
            transformed |= 1 << target
    return transformed


def parse_fen_position(fen: str) -> PositionFingerprint:
    fields = fen.split()
    if len(fields) < 8:
        raise ValueError(f"invalid Mill FEN: {fen}")
    board = fields[0].replace("/", "")
    if len(board) != 24:
        raise ValueError(f"invalid Mill board in FEN: {fen}")
    white_bits = 0
    black_bits = 0
    for symbol, label in zip(board, FEN_LABELS, strict=True):
        bit = 1 << LABEL_INDEX[label]
        if symbol == "O":
            white_bits |= bit
        elif symbol == "@":
            black_bits |= bit
        elif symbol != "*":
            raise ValueError(f"invalid board symbol {symbol!r} in FEN")
    if fields[1] not in ("w", "b"):
        raise ValueError(f"invalid side to move in FEN: {fen}")
    return PositionFingerprint(
        white_bits=white_bits,
        black_bits=black_bits,
        white_in_hand=int(fields[5]),
        black_in_hand=int(fields[7]),
        side_to_move=0 if fields[1] == "w" else 1,
    )


def canonical_position_key(position: PositionFingerprint) -> int:
    return min(
        _transform_bits(position.white_bits, permutation)
        | (_transform_bits(position.black_bits, permutation) << 24)
        | (position.white_in_hand << 48)
        | (position.black_in_hand << 52)
        | (position.side_to_move << 56)
        for permutation in SYMMETRIES
    )


def canonical_solver_position_key(position: PositionFingerprint) -> int:
    solver_bits, defender_bits, solver_hand, defender_hand = (
        position.solver_normalised()
    )
    return min(
        _transform_bits(solver_bits, permutation)
        | (_transform_bits(defender_bits, permutation) << 24)
        | (solver_hand << 48)
        | (defender_hand << 52)
        for permutation in SYMMETRIES
    )


def minimum_position_distance(
    left: PositionFingerprint, right: PositionFingerprint
) -> int:
    left_solver, left_defender, left_solver_hand, left_defender_hand = (
        left.solver_normalised()
    )
    right_solver, right_defender, right_solver_hand, right_defender_hand = (
        right.solver_normalised()
    )
    hand_distance = abs(left_solver_hand - right_solver_hand) + abs(
        left_defender_hand - right_defender_hand
    )
    return hand_distance + min(
        (
            left_solver ^ _transform_bits(right_solver, permutation)
        ).bit_count()
        + (
            left_defender ^ _transform_bits(right_defender, permutation)
        ).bit_count()
        for permutation in SYMMETRIES
    )


def find_position_conflicts(
    puzzles: Sequence[dict],
    minimum_distance: int = DEFAULT_MINIMUM_POSITION_DISTANCE,
) -> list[PositionConflict]:
    if minimum_distance < 0:
        raise ValueError("minimum distance must not be negative")
    positions: list[tuple[str, PositionFingerprint]] = []
    ids: set[str] = set()
    for index, puzzle in enumerate(puzzles):
        if not isinstance(puzzle, dict):
            raise ValueError(f"puzzle {index} is not an object")
        puzzle_id = puzzle.get("id")
        fen = puzzle.get("initialPosition")
        if not isinstance(puzzle_id, str) or not puzzle_id:
            raise ValueError(f"puzzle {index} has no id")
        if puzzle_id in ids:
            raise ValueError(f"duplicate puzzle id {puzzle_id!r}")
        if not isinstance(fen, str):
            raise ValueError(f"puzzle {puzzle_id!r} has no initialPosition")
        ids.add(puzzle_id)
        positions.append((puzzle_id, parse_fen_position(fen)))

    conflicts = []
    for left_index, (left_id, left) in enumerate(positions):
        for right_id, right in positions[left_index + 1 :]:
            distance = minimum_position_distance(left, right)
            if distance < minimum_distance:
                conflicts.append(
                    PositionConflict(
                        left_id=left_id,
                        right_id=right_id,
                        distance=distance,
                    )
                )
    return sorted(
        conflicts,
        key=lambda conflict: (
            conflict.distance,
            conflict.left_id,
            conflict.right_id,
        ),
    )
