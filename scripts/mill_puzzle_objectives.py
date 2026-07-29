#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Shared public-objective rules for Mill puzzle assets and tooling."""

from __future__ import annotations

import re
from typing import Any, Iterable


WIN_TITLE = re.compile(
    r"^(?:(White|Black) · )?Win in (\d+)(?P<suffix>:.*)?$"
)
WIN_ID = re.compile(
    r"^(malom_(?:movement|placement)_(?:white|black)_)\d+(_[0-9a-f]{8})$"
)
HOLD_DRAW_TITLE = re.compile(
    r"^(White|Black) · Hold the draw(?P<suffix>:.*)?$"
)
HOLD_DRAW_ID = re.compile(
    r"^malom_draw_(white|black)_1_[0-9a-f]{8}$"
)


def side_name_from_fen(fen: str) -> str:
    fields = fen.split()
    if len(fields) < 2 or fields[1] not in {"w", "b"}:
        raise ValueError(f"invalid Mill FEN side to move: {fen}")
    return "White" if fields[1] == "w" else "Black"


def solver_move_count(solution: dict[str, Any], side_name: str) -> int:
    moves = solution.get("moves")
    if not isinstance(moves, list) or not moves:
        raise ValueError("puzzle solution must contain moves")
    side = side_name.lower()
    count = 0
    for move in moves:
        if not isinstance(move, dict):
            raise ValueError("puzzle move must be an object")
        notation = move.get("notation")
        move_side = move.get("side")
        if not isinstance(notation, str) or move_side not in {
            "white",
            "black",
        }:
            raise ValueError(f"invalid puzzle move: {move!r}")
        if move_side == side and not notation.lstrip().lower().startswith("x"):
            count += 1
    return count


def optimal_solver_move_count(puzzle: dict[str, Any]) -> int:
    puzzle_id = puzzle.get("id", "<unknown>")
    fen = puzzle.get("initialPosition")
    solutions = puzzle.get("solutions")
    if not isinstance(fen, str):
        raise ValueError(f"{puzzle_id} has no initialPosition")
    if not isinstance(solutions, list) or not solutions:
        raise ValueError(f"{puzzle_id} has no solutions")
    optimal = [
        solution
        for solution in solutions
        if isinstance(solution, dict) and solution.get("isOptimal", True)
    ]
    if not optimal:
        optimal = [solutions[0]]
    side_name = side_name_from_fen(fen)
    counts = [solver_move_count(solution, side_name) for solution in optimal]
    if len(set(counts)) != 1:
        raise ValueError(
            f"{puzzle_id} has inconsistent optimal solver move counts: "
            f"{counts}"
        )
    if counts[0] < 1:
        raise ValueError(f"{puzzle_id} has an empty solver solution")
    return counts[0]


def distance_band(move_count: int) -> str:
    if move_count <= 7:
        return "short"
    if move_count <= 15:
        return "medium"
    return "long"


def _replace_single_tag(
    tags: Iterable[str],
    prefix: str,
    replacement: str,
) -> list[str]:
    retained = [tag for tag in tags if not tag.startswith(prefix)]
    retained.append(replacement)
    return retained


def normalize_win_puzzle(puzzle: dict[str, Any]) -> tuple[str, str]:
    puzzle_id = puzzle.get("id")
    title = puzzle.get("title")
    fen = puzzle.get("initialPosition")
    tags = puzzle.get("tags")
    if not isinstance(puzzle_id, str) or not puzzle_id:
        raise ValueError("win puzzle has no id")
    if not isinstance(title, str):
        raise ValueError(f"{puzzle_id} has no title")
    if not isinstance(fen, str):
        raise ValueError(f"{puzzle_id} has no initialPosition")
    if not isinstance(tags, list) or not all(
        isinstance(tag, str) for tag in tags
    ):
        raise ValueError(f"{puzzle_id} has invalid tags")
    title_match = WIN_TITLE.fullmatch(title)
    if title_match is None:
        raise ValueError(f"{puzzle_id} has invalid win title: {title!r}")

    move_count = optimal_solver_move_count(puzzle)
    side_name = side_name_from_fen(fen)
    suffix = title_match.group("suffix") or ""
    puzzle["title"] = f"{side_name} · Win in {move_count}{suffix}"
    move_noun = "move" if move_count == 1 else "moves"
    puzzle["description"] = (
        f"{side_name} to move. Find the forced win in "
        f"{move_count} {move_noun}."
    )

    normalized_tags = _replace_single_tag(
        tags,
        "win-in-",
        f"win-in-{move_count}",
    )
    normalized_tags = _replace_single_tag(
        normalized_tags,
        "distance-band:",
        f"distance-band:{distance_band(move_count)}",
    )
    normalized_tags = _replace_single_tag(
        normalized_tags,
        "objective:",
        "objective:win",
    )
    puzzle["tags"] = normalized_tags

    id_match = WIN_ID.fullmatch(puzzle_id)
    if id_match is None:
        raise ValueError(f"{puzzle_id} has invalid generated win id")
    new_id = f"{id_match.group(1)}{move_count}{id_match.group(2)}"
    puzzle["id"] = new_id
    return puzzle_id, new_id


def _replace_id_references(value: Any, mapping: dict[str, str]) -> Any:
    if isinstance(value, str):
        return mapping.get(value, value)
    if isinstance(value, list):
        return [_replace_id_references(item, mapping) for item in value]
    if isinstance(value, dict):
        return {
            key: _replace_id_references(item, mapping)
            for key, item in value.items()
        }
    return value


def normalize_package(package: dict[str, Any]) -> dict[str, str]:
    puzzles = package.get("puzzles")
    if not isinstance(puzzles, list):
        raise ValueError("puzzle package has no puzzles array")
    mapping: dict[str, str] = {}
    for puzzle in puzzles:
        if not isinstance(puzzle, dict):
            raise ValueError("puzzle package contains a non-object")
        if puzzle.get("category") in {"winGame", "opening"}:
            old_id, new_id = normalize_win_puzzle(puzzle)
            if old_id != new_id:
                mapping[old_id] = new_id
    if mapping:
        replaced = _replace_id_references(package, mapping)
        package.clear()
        package.update(replaced)
    return mapping


def validate_public_objectives(
    puzzles: Iterable[dict[str, Any]],
) -> list[str]:
    errors: list[str] = []
    for puzzle in puzzles:
        puzzle_id = puzzle.get("id", "<unknown>")
        try:
            category = puzzle.get("category")
            title = puzzle.get("title")
            fen = puzzle.get("initialPosition")
            tags = puzzle.get("tags")
            if not isinstance(title, str) or not isinstance(fen, str):
                raise ValueError(f"{puzzle_id} has incomplete public metadata")
            if not isinstance(tags, list) or not all(
                isinstance(tag, str) for tag in tags
            ):
                raise ValueError(f"{puzzle_id} has invalid tags")
            side_name = side_name_from_fen(fen)
            move_count = optimal_solver_move_count(puzzle)
            if category in {"winGame", "opening"}:
                match = WIN_TITLE.fullmatch(title)
                if match is None:
                    raise ValueError(
                        f"{puzzle_id} has invalid win title: {title!r}"
                    )
                if match.group(1) != side_name:
                    raise ValueError(
                        f"{puzzle_id} title side does not match its FEN"
                    )
                if int(match.group(2)) != move_count:
                    raise ValueError(
                        f"{puzzle_id} title says Win in {match.group(2)} "
                        f"but optimal solutions take {move_count}"
                    )
                expected_description = (
                    f"{side_name} to move. Find the forced win in "
                    f"{move_count} "
                    f"{'move' if move_count == 1 else 'moves'}."
                )
                if puzzle.get("description") != expected_description:
                    raise ValueError(
                        f"{puzzle_id} has inconsistent win description"
                    )
                if [tag for tag in tags if tag.startswith("win-in-")] != [
                    f"win-in-{move_count}"
                ]:
                    raise ValueError(
                        f"{puzzle_id} has inconsistent win-in tag"
                    )
                if [tag for tag in tags if tag.startswith("objective:")] != [
                    "objective:win"
                ]:
                    raise ValueError(
                        f"{puzzle_id} has inconsistent win objective tag"
                    )
                id_match = WIN_ID.fullmatch(str(puzzle_id))
                if id_match is None or not str(puzzle_id).startswith(
                    f"{id_match.group(1)}{move_count}_"
                ):
                    raise ValueError(
                        f"{puzzle_id} id disagrees with its public move count"
                    )
            elif category == "defend":
                match = HOLD_DRAW_TITLE.fullmatch(title)
                if match is None or match.group(1) != side_name:
                    raise ValueError(
                        f"{puzzle_id} has invalid hold-draw title"
                    )
                if move_count != 1:
                    raise ValueError(
                        f"{puzzle_id} hold-draw solution must take one move"
                    )
                expected_description = (
                    f"{side_name} to move. Find the only move that "
                    "preserves the draw; every other legal move loses."
                )
                if puzzle.get("description") != expected_description:
                    raise ValueError(
                        f"{puzzle_id} has inconsistent hold-draw description"
                    )
                if [tag for tag in tags if tag.startswith("objective:")] != [
                    "objective:hold-draw"
                ]:
                    raise ValueError(
                        f"{puzzle_id} has invalid hold-draw objective tag"
                    )
                if "unique-draw-save" not in tags:
                    raise ValueError(
                        f"{puzzle_id} is not marked as a unique draw save"
                    )
                if [tag for tag in tags if tag.startswith("hold-draw-in-")] != [
                    "hold-draw-in-1"
                ]:
                    raise ValueError(
                        f"{puzzle_id} has invalid hold-draw move tag"
                    )
                id_match = HOLD_DRAW_ID.fullmatch(str(puzzle_id))
                if (
                    id_match is None
                    or id_match.group(1) != side_name.lower()
                ):
                    raise ValueError(
                        f"{puzzle_id} has invalid hold-draw id"
                    )
            else:
                raise ValueError(
                    f"{puzzle_id} has unsupported built-in objective category "
                    f"{category!r}"
                )
        except ValueError as error:
            errors.append(str(error))
    return errors
