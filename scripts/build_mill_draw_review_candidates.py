#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Select unique Perfect DB draw saves into an application review package."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import ortools
from ortools.sat.python import cp_model

from mill_puzzle_objectives import validate_public_objectives
from mill_puzzle_similarity import (
    DEFAULT_MINIMUM_POSITION_DISTANCE,
    minimum_position_distance,
    parse_fen_position,
)


ADJACENCY = (
    (1, 7),
    (0, 2, 9),
    (1, 3),
    (2, 4, 11),
    (3, 5),
    (4, 6, 13),
    (5, 7),
    (6, 0, 15),
    (9, 15),
    (8, 10, 1, 17),
    (9, 11),
    (10, 12, 3, 19),
    (11, 13),
    (12, 14, 5, 21),
    (13, 15),
    (14, 8, 7, 23),
    (17, 23),
    (16, 18, 9),
    (17, 19),
    (18, 20, 11),
    (19, 21),
    (20, 22, 13),
    (21, 23),
    (22, 16, 15),
)


def _load_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} is not a JSON object")
    return value


def _fnv1a(text: str) -> str:
    value = 0xCBF29CE484222325
    for byte in text.encode("utf-8"):
        value ^= byte
        value = (value * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return f"{value:016x}"[:8]


def _primary_move_count(fen: str) -> int:
    position = parse_fen_position(fen)
    solver, _, _, _ = position.solver_normalised()
    occupied = position.white_bits | position.black_bits
    empty_count = 24 - occupied.bit_count()
    if solver.bit_count() == 3:
        return solver.bit_count() * empty_count
    return sum(
        1
        for source, neighbours in enumerate(ADJACENCY)
        if solver & (1 << source)
        for target in neighbours
        if not occupied & (1 << target)
    )


def _difficulty(legal_moves: int) -> tuple[str, int]:
    if legal_moves <= 5:
        return "easy", 1100 + legal_moves * 20
    if legal_moves <= 9:
        return "medium", 1250 + legal_moves * 20
    return "hard", 1450 + legal_moves * 20


def _draw_position(record: dict) -> dict:
    positions = [
        position
        for position in (record.get("positionA"), record.get("positionB"))
        if isinstance(position, dict) and position.get("outcome") == "draw"
    ]
    if len(positions) != 1:
        raise ValueError(f"{record.get('id')} must contain one draw position")
    draw = positions[0]
    if draw.get("bestTurnCount") != 1:
        raise ValueError(f"{record.get('id')} is not a unique draw save")
    best_turns = draw.get("bestTurns")
    if (
        not isinstance(best_turns, list)
        or len(best_turns) != 1
        or not isinstance(best_turns[0], list)
        or not best_turns[0]
        or not all(isinstance(action, str) for action in best_turns[0])
    ):
        raise ValueError(f"{record.get('id')} has invalid best turns")
    return draw


def _candidate(record: dict, source_file: str) -> dict:
    draw = _draw_position(record)
    fen = draw["fen"]
    side = fen.split()[1]
    side_name = "White" if side == "w" else "Black"
    legal_moves = _primary_move_count(fen)
    difficulty, rating = _difficulty(legal_moves)
    suffix = _fnv1a(fen)
    puzzle_id = f"malom_draw_{side_name.lower()}_1_{suffix}"
    moves = [
        {"notation": action, "side": side_name.lower()}
        for action in draw["bestTurns"][0]
    ]
    puzzle = {
        "id": puzzle_id,
        "title": f"{side_name} · Hold the draw: find the only defence",
        "description": (
            f"{side_name} to move. Find the only move that preserves "
            "the draw; every other legal move loses."
        ),
        "category": "defend",
        "difficulty": difficulty,
        "initialPosition": fen,
        "solutions": [
            {
                "moves": moves,
                "description": "Unique drawing move",
                "isOptimal": True,
            }
        ],
        "hint": (
            "Do not chase a quick threat. Preserve the defensive resource "
            "that keeps the position balanced."
        ),
        "completionMessage": (
            "You found the only move that keeps the position drawn."
        ),
        "tags": [
            "generated",
            "malom-db",
            "perfect-db-certified",
            "hold-draw-in-1",
            "objective:hold-draw",
            "unique-draw-save",
            "phase:movement",
            f"side:{side_name.lower()}",
            "source:composed",
            "topic:draw-save",
            "curriculum:04-endgames",
            f"progression:{ {'easy': 2, 'medium': 3, 'hard': 4}[difficulty] }-{difficulty}",
            "distance-band:short",
            "review-status:expert-pending",
            "discovery:outcome-contrast",
            "selection-profile:unique-draw-save-4v3",
        ],
        "isCustom": False,
        "author": "Sanmill Perfect DB Generator",
        "createdDate": datetime.now(timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z"),
        "version": 1,
        "rating": rating,
        "ruleVariantId": "standard_9mm",
    }
    return {
        "puzzle": puzzle,
        "record": {
            "id": puzzle_id,
            "topic": "draw-save",
            "profile": "unique-draw-save-4v3",
            "sourceCandidate": record.get("id"),
            "sourceFile": source_file,
            "sideToMove": side_name.lower(),
            "legalPrimaryMoves": legal_moves,
            "drawingTurn": list(draw["bestTurns"][0]),
            "rootOutcome": "draw",
            "drawingTurnCount": 1,
        },
    }


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+")
    parser.add_argument("--reference-pack", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--count", type=int, default=10)
    parser.add_argument(
        "--min-position-distance",
        type=int,
        default=DEFAULT_MINIMUM_POSITION_DISTANCE,
    )
    parser.add_argument("--seed", type=int, default=20260730)
    args = parser.parse_args()
    if args.count < 2 or args.count % 2:
        parser.error("--count must be a positive even number")
    if args.min_position_distance < 0:
        parser.error("--min-position-distance must not be negative")
    return args


def main() -> None:
    args = _parse_args()
    reference = _load_json(Path(args.reference_pack).resolve())
    reference_puzzles = reference.get("puzzles")
    if not isinstance(reference_puzzles, list):
        raise ValueError("reference pack has no puzzles array")
    reference_positions = [
        parse_fen_position(puzzle["initialPosition"])
        for puzzle in reference_puzzles
    ]

    candidates = []
    seen_fens: set[str] = set()
    for raw_input in args.inputs:
        input_path = Path(raw_input).resolve()
        package = _load_json(input_path)
        records = package.get("candidates")
        if not isinstance(records, list):
            raise ValueError(f"{input_path} has no candidates array")
        for record in records:
            built = _candidate(record, input_path.name)
            fen = built["puzzle"]["initialPosition"]
            if fen in seen_fens:
                continue
            seen_fens.add(fen)
            position = parse_fen_position(fen)
            reference_distance = min(
                minimum_position_distance(position, other)
                for other in reference_positions
            )
            if reference_distance < args.min_position_distance:
                continue
            built["position"] = position
            built["record"]["minimumReferenceDistance"] = reference_distance
            candidates.append(built)

    model = cp_model.CpModel()
    selected = [model.new_bool_var(f"select_{index}") for index in range(len(candidates))]
    model.add(sum(selected) == args.count)
    per_side = args.count // 2
    for side in ("white", "black"):
        model.add(
            sum(
                selected[index]
                for index, candidate in enumerate(candidates)
                if candidate["record"]["sideToMove"] == side
            )
            == per_side
        )
    for left in range(len(candidates)):
        for right in range(left + 1, len(candidates)):
            if (
                minimum_position_distance(
                    candidates[left]["position"],
                    candidates[right]["position"],
                )
                < args.min_position_distance
            ):
                model.add(selected[left] + selected[right] <= 1)
    scores = []
    for index, candidate in enumerate(candidates):
        record = candidate["record"]
        score = (
            (30 - min(record["legalPrimaryMoves"], 30)) * 100
            + min(record["minimumReferenceDistance"], 12) * 10
            + ((args.seed ^ (index * 0x9E3779B1)) & 31)
        )
        scores.append(score)
    model.maximize(
        sum(selected[index] * scores[index] for index in range(len(candidates)))
    )
    solver = cp_model.CpSolver()
    status = solver.solve(model)
    if status != cp_model.OPTIMAL:
        raise ValueError(
            f"draw selection was not proven optimal: {solver.status_name(status)}"
        )
    chosen = [
        candidate
        for index, candidate in enumerate(candidates)
        if solver.value(selected[index])
    ]
    chosen.sort(
        key=lambda candidate: (
            {"easy": 2, "medium": 3, "hard": 4}[
                candidate["puzzle"]["difficulty"]
            ],
            candidate["record"]["sideToMove"],
            candidate["puzzle"]["id"],
        )
    )
    puzzles = [candidate["puzzle"] for candidate in chosen]
    batch_id = f"draw-defence-review-selected-{args.count}"
    for puzzle in puzzles:
        puzzle["tags"].append(f"review-batch:{batch_id}")
    errors = validate_public_objectives(puzzles)
    if errors:
        raise ValueError("\n".join(errors))

    now = (
        datetime.now(timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z")
    )
    output = {
        "formatVersion": "1.0",
        "exportedBy": {
            "appName": "Sanmill",
            "platform": "draw-defence-selector",
        },
        "exportDate": now,
        "puzzleCount": len(puzzles),
        "metadata": {
            "id": batch_id,
            "name": "Unique Draw Defence — Expert Review",
            "description": (
                "Perfect DB-certified positions with exactly one drawing "
                "logical turn."
            ),
            "author": "Sanmill Perfect DB Generator",
            "version": "1.0.0-review.1",
            "tags": [
                "perfect-db-certified",
                "hold-draw",
                "expert-review",
            ],
            "isOfficial": False,
            "ruleVariantId": "standard_9mm",
        },
        "selectionProvenance": {
            "solver": "OR-Tools CP-SAT",
            "version": ortools.__version__,
            "source": "perfect-db-draw-save",
            "status": "OPTIMAL",
            "seed": args.seed,
            "objectiveValue": int(round(solver.objective_value)),
            "minimumPositionDistance": args.min_position_distance,
            "referencePuzzleCount": len(reference_puzzles),
            "candidateCount": len(candidates),
            "sideCounts": {"white": per_side, "black": per_side},
            "selectedCandidates": [
                candidate["record"] for candidate in chosen
            ],
        },
        "puzzles": puzzles,
    }
    output_path = Path(args.out).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(output, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"[mill-draw-selector] candidates={len(candidates)} "
        f"selected={len(puzzles)} status=OPTIMAL out={output_path}"
    )


if __name__ == "__main__":
    main()
