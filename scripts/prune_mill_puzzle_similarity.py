#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Keep the largest deterministic non-similar subset of a puzzle package."""

from __future__ import annotations

import argparse
import json
from functools import lru_cache
from pathlib import Path

from mill_puzzle_similarity import (
    DEFAULT_MINIMUM_POSITION_DISTANCE,
    find_position_conflicts,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package")
    parser.add_argument("--out", required=True)
    parser.add_argument(
        "--min-position-distance",
        type=int,
        default=DEFAULT_MINIMUM_POSITION_DISTANCE,
    )
    return parser.parse_args()


def _prefer(
    left: frozenset[str],
    right: frozenset[str],
    order: dict[str, int],
) -> frozenset[str]:
    left_key = (
        len(left),
        -sum(order[puzzle_id] for puzzle_id in left),
        tuple(-order[puzzle_id] for puzzle_id in sorted(left, key=order.get)),
    )
    right_key = (
        len(right),
        -sum(order[puzzle_id] for puzzle_id in right),
        tuple(-order[puzzle_id] for puzzle_id in sorted(right, key=order.get)),
    )
    return left if left_key >= right_key else right


def _largest_independent_set(
    nodes: set[str],
    neighbours: dict[str, set[str]],
    order: dict[str, int],
) -> frozenset[str]:
    @lru_cache(maxsize=None)
    def solve(available: frozenset[str]) -> frozenset[str]:
        if not available:
            return frozenset()
        pivot = max(
            available,
            key=lambda node: (
                len(neighbours[node] & available),
                -order[node],
            ),
        )
        without_pivot = solve(available - {pivot})
        with_pivot = frozenset(
            {
                pivot,
                *solve(available - {pivot} - neighbours[pivot]),
            }
        )
        return _prefer(with_pivot, without_pivot, order)

    return solve(frozenset(nodes))


def main() -> None:
    args = parse_args()
    if args.min_position_distance < 0:
        raise ValueError("minimum distance must not be negative")
    package_path = Path(args.package).resolve()
    package = json.loads(package_path.read_text(encoding="utf-8-sig"))
    puzzles = package.get("puzzles")
    if not isinstance(puzzles, list):
        raise ValueError(f"{package_path} has no puzzles array")
    order = {puzzle["id"]: index for index, puzzle in enumerate(puzzles)}
    conflicts = find_position_conflicts(
        puzzles,
        minimum_distance=args.min_position_distance,
    )
    neighbours = {puzzle_id: set() for puzzle_id in order}
    for conflict in conflicts:
        neighbours[conflict.left_id].add(conflict.right_id)
        neighbours[conflict.right_id].add(conflict.left_id)
    kept = _largest_independent_set(set(order), neighbours, order)
    removed = [puzzle_id for puzzle_id in order if puzzle_id not in kept]
    retained_puzzles = [
        puzzle for puzzle in puzzles if puzzle["id"] in kept
    ]
    package["puzzles"] = retained_puzzles
    package["puzzleCount"] = len(retained_puzzles)
    output_path = Path(args.out)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(
        (json.dumps(package, ensure_ascii=False, indent=2) + "\n").encode(
            "utf-8"
        )
    )
    print(
        "[mill-puzzle-prune] "
        f"input={len(puzzles)} retained={len(retained_puzzles)} "
        f"removed={len(removed)} minimum={args.min_position_distance} "
        f"out={output_path}"
    )
    for puzzle_id in removed:
        print(f"removed={puzzle_id}")


if __name__ == "__main__":
    main()
