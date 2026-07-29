#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Render a blind, Typora-compatible Markdown Mill puzzle review pack.

The input remains the authoritative ``.sanmill_puzzles`` package. This
renderer deliberately shows only the objective and diagram in the question
section, then places one certified line and provisional machine tags in a
separate answer key. It uses no HTML or CSS.
"""

from __future__ import annotations

import argparse
import json
import random
import textwrap
from dataclasses import dataclass
from pathlib import Path

from mill_puzzle_objectives import (
    optimal_solver_move_count,
    validate_public_objectives,
)


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
POINTS = {
    "a7": (0, 0),
    "d7": (12, 0),
    "g7": (24, 0),
    "b6": (2, 2),
    "d6": (12, 2),
    "f6": (22, 2),
    "c5": (4, 4),
    "d5": (12, 4),
    "e5": (20, 4),
    "a4": (0, 6),
    "b4": (2, 6),
    "c4": (4, 6),
    "e4": (20, 6),
    "f4": (22, 6),
    "g4": (24, 6),
    "c3": (4, 8),
    "d3": (12, 8),
    "e3": (20, 8),
    "b2": (2, 10),
    "d2": (12, 10),
    "f2": (22, 10),
    "a1": (0, 12),
    "d1": (12, 12),
    "g1": (24, 12),
}
MILL_LINES = (
    ("a7", "d7", "g7"),
    ("g7", "g4", "g1"),
    ("g1", "d1", "a1"),
    ("a1", "a4", "a7"),
    ("b6", "d6", "f6"),
    ("f6", "f4", "f2"),
    ("f2", "d2", "b2"),
    ("b2", "b4", "b6"),
    ("c5", "d5", "e5"),
    ("e5", "e4", "e3"),
    ("e3", "d3", "c3"),
    ("c3", "c4", "c5"),
    ("d7", "d6", "d5"),
    ("g4", "f4", "e4"),
    ("d1", "d2", "d3"),
    ("a4", "b4", "c4"),
)
THEMES = (
    "allow-mill",
    "mobility-squeeze",
    "junction-release",
    "mill-recovery",
    "right-angle-threat",
    "ring-transfer",
    "double-mill",
    "immobilization",
    "sacrifice",
    "quiet-move",
    "draw-save",
    "vs-flying",
    "trap:greedy-mill",
    "trap:wrong-mill",
    "forced-win",
)
COORDINATE_REFERENCE = """\
a7-----------d7-----------g7
|             |             |
|   b6--------d6--------f6   |
|   |         |         |   |
|   |   c5----d5----e5   |   |
|   |   |           |   |   |
a4--b4--c4          e4--f4--g4
|   |   |           |   |   |
|   |   c3----d3----e3   |   |
|   |         |         |   |
|   b2--------d2--------f2   |
|             |             |
a1-----------d1-----------g1"""


@dataclass(frozen=True)
class ReviewPuzzle:
    number: int
    puzzle: dict


def _draw_segment(canvas: list[list[str]], start: str, end: str) -> None:
    x1, y1 = POINTS[start]
    x2, y2 = POINTS[end]
    if x1 == x2:
        for y in range(min(y1, y2) + 1, max(y1, y2)):
            canvas[y][x1] = "|"
        return
    if y1 == y2:
        for x in range(min(x1, x2) + 1, max(x1, x2)):
            canvas[y1][x] = "-"
        return
    raise AssertionError(f"non-orthogonal board segment: {start}-{end}")


def _parse_board(fen: str) -> dict[str, str]:
    fields = fen.split()
    if len(fields) < 2:
        raise ValueError(f"invalid Mill FEN: {fen}")
    board = fields[0].replace("/", "")
    if len(board) != 24:
        raise ValueError(f"invalid Mill board in FEN: {fen}")
    symbols = {"*": ".", "O": "W", "@": "B"}
    try:
        return {
            label: symbols[symbol]
            for label, symbol in zip(FEN_LABELS, board, strict=True)
        }
    except KeyError as error:
        raise ValueError(f"invalid board symbol in FEN: {fen}") from error


def _board_diagram(fen: str) -> str:
    canvas = [[" " for _ in range(25)] for _ in range(13)]
    for line in MILL_LINES:
        _draw_segment(canvas, line[0], line[1])
        _draw_segment(canvas, line[1], line[2])
    for label, symbol in _parse_board(fen).items():
        x, y = POINTS[label]
        canvas[y][x] = symbol
    return "\n".join("".join(row).rstrip() for row in canvas)


def _side_to_move(fen: str) -> str:
    fields = fen.split()
    if len(fields) < 2 or fields[1] not in ("w", "b"):
        raise ValueError(f"invalid side to move in FEN: {fen}")
    return "White" if fields[1] == "w" else "Black"


def _primary_theme(puzzle: dict) -> str:
    tags = puzzle.get("tags")
    if not isinstance(tags, list):
        raise ValueError(f"{puzzle.get('id')} has no tags")
    topic = next(
        (
            tag.removeprefix("topic:")
            for tag in tags
            if isinstance(tag, str) and tag.startswith("topic:")
        ),
        None,
    )
    if topic is not None:
        return topic
    return next((theme for theme in THEMES if theme in tags), "unclassified")


def _first_line(puzzle: dict) -> str:
    solutions = puzzle.get("solutions")
    if not isinstance(solutions, list) or not solutions:
        raise ValueError(f"{puzzle.get('id')} has no certified line")
    moves = solutions[0].get("moves")
    if not isinstance(moves, list) or not moves:
        raise ValueError(f"{puzzle.get('id')} has an empty certified line")
    notations = []
    for move in moves:
        notation = move.get("notation") if isinstance(move, dict) else None
        if not isinstance(notation, str):
            raise ValueError(f"{puzzle.get('id')} has an invalid move")
        notations.append(notation)
    return " ".join(notations)


def _validate_solution_distances(puzzle: dict) -> None:
    fen = puzzle.get("initialPosition")
    if not isinstance(fen, str):
        raise ValueError(f"{puzzle.get('id')} has no initialPosition")
    solver_side = _side_to_move(fen).lower()
    expected = optimal_solver_move_count(puzzle)
    category = puzzle.get("category")
    solutions = puzzle.get("solutions")
    if not isinstance(solutions, list) or not solutions:
        raise ValueError(f"{puzzle.get('id')} has no certified line")
    for index, solution in enumerate(solutions, start=1):
        moves = solution.get("moves") if isinstance(solution, dict) else None
        if not isinstance(moves, list):
            raise ValueError(
                f"{puzzle.get('id')} solution {index} has no moves"
            )
        solver_moves = sum(
            1
            for move in moves
            if isinstance(move, dict)
            and move.get("side") == solver_side
            and isinstance(move.get("notation"), str)
            and not move["notation"].startswith("x")
        )
        is_optimal = solution.get("isOptimal")
        if is_optimal is True and solver_moves != expected:
            raise ValueError(
                f"{puzzle.get('id')} solution {index} has {solver_moves} "
                f"solver moves, expected {expected}"
            )
        if is_optimal is False and solver_moves <= expected:
            raise ValueError(
                f"{puzzle.get('id')} slower solution {index} is not longer "
                f"than the public distance {expected}"
            )
        if category == "defend" and is_optimal is False:
            raise ValueError(
                f"{puzzle.get('id')} draw-defence solution {index} must be "
                "the certified drawing turn"
            )
        if not isinstance(is_optimal, bool):
            raise ValueError(
                f"{puzzle.get('id')} solution {index} has no isOptimal flag"
            )


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="certified .sanmill_puzzles package")
    parser.add_argument("--out", required=True, help="Markdown review pack")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument(
        "--title",
        default="Mill Puzzle Blind Review Pack",
    )
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    input_path = Path(args.input).resolve()
    package = json.loads(input_path.read_text(encoding="utf-8-sig"))
    puzzles = package.get("puzzles")
    if not isinstance(puzzles, list):
        raise ValueError(f"{input_path} has no puzzles array")
    if package.get("puzzleCount") != len(puzzles):
        raise ValueError(f"{input_path} has a mismatched puzzleCount")
    for puzzle in puzzles:
        if not isinstance(puzzle, dict):
            raise ValueError(f"{input_path} has a non-object puzzle")
        _validate_solution_distances(puzzle)
    objective_errors = validate_public_objectives(puzzles)
    if objective_errors:
        raise ValueError(
            "inconsistent public puzzle objectives:\n"
            + "\n".join(f"  {error}" for error in objective_errors)
        )

    shuffled = list(puzzles)
    random.Random(args.seed).shuffle(shuffled)
    review = [
        ReviewPuzzle(number=index, puzzle=puzzle)
        for index, puzzle in enumerate(shuffled, start=1)
    ]

    lines = [
        f"# {args.title}",
        "",
        "Status: unpublished specialist-review material.",
        "",
        "For each position, solve the stated objective. One turn means one",
        "primary action by one player plus any compulsory removal after",
        "forming a mill. Public `Win in N` counts turns by the solving side;",
        "defensive replies do not add to N. `Hold the draw` asks for the only",
        "move that preserves a draw when every alternative loses. `W` is",
        "White, `B` is Black and `.` is an empty point. Theme labels are",
        "withheld until the answer key.",
        "",
        "Coordinate reference:",
        "",
        "```text",
        COORDINATE_REFERENCE,
        "```",
        "",
    ]
    for item in review:
        puzzle = item.puzzle
        fen = puzzle.get("initialPosition")
        if not isinstance(fen, str):
            raise ValueError(f"{puzzle.get('id')} has no initialPosition")
        if puzzle.get("category") == "defend":
            objective = (
                f"{_side_to_move(fen)} to move. Find the only move that "
                "preserves the draw."
            )
        else:
            objective = (
                f"{_side_to_move(fen)} to move. Win in "
                f"{optimal_solver_move_count(puzzle)} moves by the solving "
                "side."
            )
        lines.extend(
            [
                f"## Puzzle {item.number}",
                "",
                objective,
                "",
                "```text",
                _board_diagram(fen),
                "```",
                "",
            ]
        )

    lines.extend(
        [
            "# Answer key",
            "",
            "Each entry gives one Perfect DB-certified line. Winning studies",
            "may also contain equally short branches or explicitly marked",
            "slower wins in the source package. Draw studies contain the",
            "unique turn that preserves the draw.",
            "",
        ]
    )
    for item in review:
        puzzle = item.puzzle
        wrapped = textwrap.fill(
            _first_line(puzzle),
            width=88,
            subsequent_indent="    ",
        )
        solutions = puzzle.get("solutions")
        assert isinstance(solutions, list)
        lines.extend(
            [
                f"## Puzzle {item.number} — solution",
                "",
                f"- Provisional theme: `{_primary_theme(puzzle)}`",
                f"- Exported solution lines: {len(solutions)}",
                f"- Internal ID: `{puzzle.get('id')}`",
                "",
                "```text",
                wrapped,
                "```",
                "",
            ]
        )

    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes("\n".join(lines).encode("utf-8"))
    print(
        f"[mill-review-render] puzzles={len(review)} seed={args.seed} "
        f"out={output}"
    )


if __name__ == "__main__":
    main()
