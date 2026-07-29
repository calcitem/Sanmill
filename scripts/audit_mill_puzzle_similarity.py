#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Audit a puzzle package for recognisably similar ring-16 positions."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

from mill_puzzle_similarity import (
    DEFAULT_MINIMUM_POSITION_DISTANCE,
    find_position_conflicts,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package")
    parser.add_argument(
        "--min-position-distance",
        type=int,
        default=DEFAULT_MINIMUM_POSITION_DISTANCE,
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    package_path = Path(args.package).resolve()
    package = json.loads(package_path.read_text(encoding="utf-8-sig"))
    puzzles = package.get("puzzles")
    if not isinstance(puzzles, list):
        raise ValueError(f"{package_path} has no puzzles array")
    conflicts = find_position_conflicts(
        puzzles,
        minimum_distance=args.min_position_distance,
    )
    counts = Counter(conflict.distance for conflict in conflicts)
    print(
        "[mill-puzzle-similarity] "
        f"puzzles={len(puzzles)} minimum={args.min_position_distance} "
        f"conflicts={len(conflicts)} distances={dict(sorted(counts.items()))}"
    )
    for conflict in conflicts:
        print(
            f"distance={conflict.distance} "
            f"{conflict.left_id} <> {conflict.right_id}"
        )
    if conflicts:
        puzzle_by_id = {puzzle["id"]: puzzle for puzzle in puzzles}
        neighbours: dict[str, set[str]] = {}
        for conflict in conflicts:
            neighbours.setdefault(conflict.left_id, set()).add(conflict.right_id)
            neighbours.setdefault(conflict.right_id, set()).add(conflict.left_id)
        remaining = set(neighbours)
        components = []
        while remaining:
            pending = [min(remaining)]
            component = set()
            while pending:
                puzzle_id = pending.pop()
                if puzzle_id in component:
                    continue
                component.add(puzzle_id)
                pending.extend(neighbours[puzzle_id] - component)
            remaining -= component
            components.append(sorted(component))
        components.sort(key=lambda component: (-len(component), component))
        for index, component in enumerate(components, start=1):
            print(f"component={index} size={len(component)}")
            for puzzle_id in component:
                puzzle = puzzle_by_id[puzzle_id]
                topic = next(
                    (
                        tag.removeprefix("topic:")
                        for tag in puzzle.get("tags", [])
                        if tag.startswith("topic:")
                    ),
                    "unknown",
                )
                print(
                    "  "
                    f"{puzzle_id} difficulty={puzzle.get('difficulty')} "
                    f"rating={puzzle.get('rating')} topic={topic}"
                )
    if conflicts:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
