#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Mine one-stone W/D/L contrast pairs for editorial review.

Comparison studies present two near-identical positions and ask whether
moving one stone changes a win into a draw, or a draw into a loss.
This offline tool samples rule-shaped movement roots, relocates one stone,
and queries both positions through the persistent Rust/TGF data-query
protocol. It exports evidence for review; it does not add draw studies to the
forced-win Sanmill puzzle format.
"""

from __future__ import annotations

import argparse
import json
import random
import subprocess
from pathlib import Path
from typing import Iterable


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
PERFECT_INDEX = {
    label: index for index, label in enumerate(PERFECT_LABELS)
}
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
LABEL_BY_COORDINATE = {
    coordinate: label for label, coordinate in COORDINATES.items()
}
ADJACENT_LABELS = (
    ("a7", "d7"),
    ("d7", "g7"),
    ("g7", "g4"),
    ("g4", "g1"),
    ("g1", "d1"),
    ("d1", "a1"),
    ("a1", "a4"),
    ("a4", "a7"),
    ("b6", "d6"),
    ("d6", "f6"),
    ("f6", "f4"),
    ("f4", "f2"),
    ("f2", "d2"),
    ("d2", "b2"),
    ("b2", "b4"),
    ("b4", "b6"),
    ("c5", "d5"),
    ("d5", "e5"),
    ("e5", "e4"),
    ("e4", "e3"),
    ("e3", "d3"),
    ("d3", "c3"),
    ("c3", "c4"),
    ("c4", "c5"),
    ("d7", "d6"),
    ("d6", "d5"),
    ("g4", "f4"),
    ("f4", "e4"),
    ("d1", "d2"),
    ("d2", "d3"),
    ("a4", "b4"),
    ("b4", "c4"),
)
ADJACENCY = tuple(
    tuple(
        PERFECT_INDEX[other]
        for first, second in ADJACENT_LABELS
        for other in (
            (second,) if first == label else (first,) if second == label else ()
        )
    )
    for label in PERFECT_LABELS
)


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


def _transform_label(label: str, operation: int) -> str:
    x, y = COORDINATES[label]
    if operation >= 8:
        x, y = _ring_swap(x, y)
    return LABEL_BY_COORDINATE[_dihedral(x, y, operation % 8)]


def _transform_bits(bits: int, operation: int) -> int:
    transformed = 0
    for source, label in enumerate(PERFECT_LABELS):
        if bits & (1 << source):
            transformed |= 1 << PERFECT_INDEX[
                _transform_label(label, operation)
            ]
    return transformed


def _canonical_key(white_bits: int, black_bits: int, side: int) -> int:
    return min(
        _transform_bits(white_bits, operation)
        | (_transform_bits(black_bits, operation) << 24)
        | (side << 56)
        for operation in range(16)
    )


def _fen(white_bits: int, black_bits: int, side: int) -> str:
    board = "".join(
        (
            "O"
            if white_bits & (1 << PERFECT_INDEX[label])
            else "@" if black_bits & (1 << PERFECT_INDEX[label]) else "*"
        )
        for label in FEN_LABELS
    )
    board_field = "/".join((board[:8], board[8:16], board[16:]))
    return (
        f"{board_field} {'w' if side == 0 else 'b'} m s "
        f"{white_bits.bit_count()} 0 {black_bits.bit_count()} 0 "
        "0 0 -1 -1 -1 -1 0 0 1 ids:nodes"
    )


def _fen_bits(fen: str) -> tuple[int, int, int]:
    fields = fen.split()
    board = "".join(fields[0].split("/"))
    if (
        len(fields) < 2
        or len(board) != 24
        or fields[1] not in ("w", "b")
    ):
        raise ValueError(f"unsupported FEN: {fen}")
    white_bits = 0
    black_bits = 0
    for piece, label in zip(board, FEN_LABELS, strict=True):
        if piece == "O":
            white_bits |= 1 << PERFECT_INDEX[label]
        elif piece == "@":
            black_bits |= 1 << PERFECT_INDEX[label]
        elif piece != "*":
            raise ValueError(f"unsupported FEN board character: {piece}")
    return white_bits, black_bits, 0 if fields[1] == "w" else 1


def _excluded_keys(paths: Iterable[str]) -> set[int]:
    keys = set()
    for raw_path in paths:
        path = Path(raw_path).resolve()
        for line_number, raw_line in enumerate(
            path.read_text(encoding="utf-8-sig").splitlines(),
            start=1,
        ):
            line = " ".join(raw_line.split())
            if not line or line.startswith("#"):
                continue
            try:
                white_bits, black_bits, side = _fen_bits(line)
            except ValueError as error:
                raise ValueError(f"{path}:{line_number}: {error}") from error
            keys.add(_canonical_key(white_bits, black_bits, side))
    return keys


class PerfectQueryProcess:
    def __init__(self, executable: Path, database: Path, cache: int):
        self.database = str(database)
        self.cache = cache
        self.process = subprocess.Popen(
            [str(executable), "mill", "data-query", "--jsonl"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            encoding="utf-8",
        )

    def query(
        self,
        request_id: str,
        white_bits: int,
        black_bits: int,
        side: int,
    ) -> dict | None:
        assert self.process.stdin is not None
        assert self.process.stdout is not None
        request = {
            "operation": "query_perfect_db",
            "protocol_version": 1,
            "request_id": request_id,
            "position": {
                "rule": "nmm",
                "initial": _fen(white_bits, black_bits, side),
                "history_origin": "fresh_setup",
                "actions": [],
            },
            "database_path": self.database,
            "cache_sectors": self.cache,
        }
        self.process.stdin.write(json.dumps(request, separators=(",", ":")) + "\n")
        self.process.stdin.flush()
        response_line = self.process.stdout.readline()
        if not response_line:
            raise RuntimeError("tgf data-query exited without a response")
        response = json.loads(response_line)
        if response.get("status") != "available":
            return None
        candidates = response.get("candidates")
        if not isinstance(candidates, list) or not candidates:
            return None
        return response

    def close(self) -> None:
        if self.process.stdin is not None:
            self.process.stdin.close()
        return_code = self.process.wait()
        if return_code != 0:
            raise RuntimeError(
                f"tgf data-query exited with status {return_code}"
            )


def _summary(response: dict) -> dict:
    candidates = response["candidates"]
    first = candidates[0]["perfect"]
    assert all(
        candidate["perfect"]["category"] == first["category"]
        for candidate in candidates
    )
    return {
        "fen": response["state"]["current_fen"],
        "outcome": first["category"],
        "steps": first["steps"],
        "bestTurnCount": len(candidates),
        "bestTurns": [
            candidate["full_turn_actions"] for candidate in candidates
        ],
    }


def _random_bits(
    rng: random.Random,
    white_count: int,
    black_count: int,
) -> tuple[int, int]:
    occupied = rng.sample(range(24), white_count + black_count)
    white_bits = sum(1 << index for index in occupied[:white_count])
    black_bits = sum(1 << index for index in occupied[white_count:])
    return white_bits, black_bits


def _legal_primary_move_count(
    moving_bits: int,
    occupied_bits: int,
) -> int:
    empty_count = 24 - occupied_bits.bit_count()
    if moving_bits.bit_count() == 3:
        return moving_bits.bit_count() * empty_count
    return sum(
        1
        for source, neighbours in enumerate(ADJACENCY)
        if moving_bits & (1 << source)
        for target in neighbours
        if not occupied_bits & (1 << target)
    )


def _relocate(
    rng: random.Random,
    white_bits: int,
    black_bits: int,
    side: int,
    relocate: str,
) -> tuple[int, int, str, str, str]:
    if relocate == "either":
        moving_side = rng.randrange(2)
    elif relocate == "solver":
        moving_side = side
    else:
        moving_side = 1 - side
    moving_bits = white_bits if moving_side == 0 else black_bits
    source = rng.choice(
        [index for index in range(24) if moving_bits & (1 << index)]
    )
    occupied = white_bits | black_bits
    target = rng.choice(
        [index for index in range(24) if not occupied & (1 << index)]
    )
    moved_bits = (moving_bits & ~(1 << source)) | (1 << target)
    if moving_side == 0:
        white_bits = moved_bits
    else:
        black_bits = moved_bits
    return (
        white_bits,
        black_bits,
        "solver" if moving_side == side else "defender",
        PERFECT_LABELS[source],
        PERFECT_LABELS[target],
    )


def mine(args: argparse.Namespace) -> dict:
    rng = random.Random(args.seed)
    excluded = _excluded_keys(args.exclude_fens)
    seen = set(excluded)
    records = []
    inspected_pairs = 0
    available_pairs = 0
    process = PerfectQueryProcess(
        Path(args.tgf).resolve(),
        Path(args.db).resolve(),
        args.cache,
    )
    source_identity = None
    try:
        for sample in range(args.max_samples):
            if sample > 0 and sample % args.progress_every == 0:
                print(
                    "[outcome-contrast-miner] "
                    f"sampled={sample}/{args.max_samples} "
                    f"pairs={inspected_pairs} selected={len(records)}/{args.count}",
                    flush=True,
                )
            side = rng.randrange(2)
            white_count = (
                args.solver_pieces
                if side == 0
                else args.defender_pieces
            )
            black_count = (
                args.solver_pieces
                if side == 1
                else args.defender_pieces
            )
            white_bits, black_bits = _random_bits(
                rng,
                white_count,
                black_count,
            )
            base_key = _canonical_key(white_bits, black_bits, side)
            if base_key in seen:
                continue
            solver_bits = white_bits if side == 0 else black_bits
            if (
                args.max_root_legal_moves > 0
                and _legal_primary_move_count(
                    solver_bits,
                    white_bits | black_bits,
                )
                > args.max_root_legal_moves
            ):
                continue
            base_response = process.query(
                f"{sample}-base",
                white_bits,
                black_bits,
                side,
            )
            if base_response is None:
                continue
            if source_identity is None:
                source_identity = base_response["source"]["identity"]
            base = _summary(base_response)
            if (
                base["outcome"] == "draw"
                and args.max_draw_best_turns > 0
                and base["bestTurnCount"] > args.max_draw_best_turns
            ):
                continue
            for perturbation in range(args.perturbations):
                (
                    changed_white,
                    changed_black,
                    changed_side,
                    source,
                    target,
                ) = _relocate(
                    rng,
                    white_bits,
                    black_bits,
                    side,
                    args.relocate,
                )
                changed_key = _canonical_key(
                    changed_white,
                    changed_black,
                    side,
                )
                if changed_key in seen or changed_key == base_key:
                    continue
                inspected_pairs += 1
                changed_response = process.query(
                    f"{sample}-{perturbation}",
                    changed_white,
                    changed_black,
                    side,
                )
                if changed_response is None:
                    continue
                available_pairs += 1
                changed = _summary(changed_response)
                categories = {base["outcome"], changed["outcome"]}
                if categories not in ({"win", "draw"}, {"draw", "loss"}):
                    continue
                draw = base if base["outcome"] == "draw" else changed
                if (
                    args.max_draw_best_turns > 0
                    and draw["bestTurnCount"] > args.max_draw_best_turns
                ):
                    continue
                seen.update((base_key, changed_key))
                themes = [
                    "outcome-contrast",
                    f"material:{args.solver_pieces}v{args.defender_pieces}",
                ]
                if draw["bestTurnCount"] == 1:
                    themes.append("unique-draw-save")
                records.append(
                    {
                        "id": f"contrast-{len(records) + 1:04}",
                        "sideToMove": "white" if side == 0 else "black",
                        "relocatedSide": changed_side,
                        "relocation": {"from": source, "to": target},
                        "positionA": base,
                        "positionB": changed,
                        "themes": themes,
                    }
                )
                break
            if len(records) >= args.count:
                break
    finally:
        process.close()

    return {
        "formatVersion": "1.0",
        "kind": "mill-outcome-contrast-review-pool",
        "proofAuthority": "Perfect DB via Rust/TGF data-query",
        "publicationStatus": "unreviewed-offline-candidates",
        "seed": args.seed,
        "filters": {
            "solverPieces": args.solver_pieces,
            "defenderPieces": args.defender_pieces,
            "relocatedSide": args.relocate,
            "perturbationsPerRoot": args.perturbations,
            "maximumDrawingTurns": args.max_draw_best_turns,
            "maximumRootLegalMoves": args.max_root_legal_moves,
            "excludedCanonicalRoots": len(excluded),
        },
        "audit": {
            "maximumSampledRoots": args.max_samples,
            "inspectedPairs": inspected_pairs,
            "availablePairs": available_pairs,
            "selectedPairs": len(records),
        },
        "source": source_identity,
        "candidateCount": len(records),
        "candidates": records,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tgf", required=True)
    parser.add_argument("--db", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument(
        "--exclude-fens",
        action="append",
        default=[],
        help="FEN roots to exclude under all ring-16 symmetries (repeatable)",
    )
    parser.add_argument("--count", type=int, default=20)
    parser.add_argument("--max-samples", type=int, default=20_000)
    parser.add_argument("--perturbations", type=int, default=8)
    parser.add_argument("--solver-pieces", type=int, default=7)
    parser.add_argument("--defender-pieces", type=int, default=4)
    parser.add_argument(
        "--relocate",
        choices=("solver", "defender", "either"),
        default="solver",
    )
    parser.add_argument("--cache", type=int, default=16)
    parser.add_argument("--progress-every", type=int, default=1000)
    parser.add_argument(
        "--max-draw-best-turns",
        type=int,
        default=0,
        help="0 disables the cap; 1 mines unique draw-saving turns",
    )
    parser.add_argument(
        "--max-root-legal-moves",
        type=int,
        default=0,
        help="cheap pre-query mobility cap for the sampled side to move",
    )
    parser.add_argument(
        "--seed",
        type=lambda value: int(value, 0),
        default=0x434F_4E54_5241_5354,
    )
    args = parser.parse_args()
    if args.count < 1:
        parser.error("--count must be positive")
    if args.max_samples < 1:
        parser.error("--max-samples must be positive")
    if args.perturbations < 1:
        parser.error("--perturbations must be positive")
    if not 3 <= args.solver_pieces <= 9:
        parser.error("--solver-pieces must be in 3..9")
    if not 3 <= args.defender_pieces <= 9:
        parser.error("--defender-pieces must be in 3..9")
    if args.solver_pieces + args.defender_pieces > 24:
        parser.error("piece counts exceed the board")
    if args.cache < 1:
        parser.error("--cache must be positive")
    if args.progress_every < 1:
        parser.error("--progress-every must be positive")
    if args.max_draw_best_turns < 0:
        parser.error("--max-draw-best-turns must not be negative")
    if args.max_root_legal_moves < 0:
        parser.error("--max-root-legal-moves must not be negative")
    return args


def main() -> None:
    args = parse_args()
    package = mine(args)
    output = Path(args.out).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(
        (json.dumps(package, indent=2) + "\n").encode("utf-8")
    )
    print(
        "[outcome-contrast-miner] "
        f"selected={package['candidateCount']} "
        f"inspected={package['audit']['inspectedPairs']} out={output}"
    )


if __name__ == "__main__":
    main()
