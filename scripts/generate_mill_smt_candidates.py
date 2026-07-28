#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Generate constraint-directed Mill roots with Z3.

This tool deliberately stops at board geometry. It does not claim that a
model is reachable, legal under every live rule, winning, or suitable as a
puzzle. `tgf puzzle-gen --candidate-file ...` independently checks all of
those publication gates with Rust/TGF and Perfect DB.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Iterable

try:
    import z3
except ImportError as error:
    raise SystemExit(
        "z3-solver is required; install scripts/requirements-puzzle-math.txt"
    ) from error


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

RINGS = (
    ("a7", "d7", "g7", "g4", "g1", "d1", "a1", "a4"),
    ("b6", "d6", "f6", "f4", "f2", "d2", "b2", "b4"),
    ("c5", "d5", "e5", "e4", "e3", "d3", "c3", "c4"),
)
MILL_LABELS = (
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
    ("a4", "b4", "c4"),
    ("d7", "d6", "d5"),
    ("g4", "f4", "e4"),
    ("d1", "d2", "d3"),
)
MILLS = tuple(tuple(LABEL_INDEX[label] for label in line) for line in MILL_LABELS)


def _standard_edges() -> tuple[tuple[int, int], ...]:
    edges: set[tuple[int, int]] = set()
    for ring in RINGS:
        for offset, label in enumerate(ring):
            other = ring[(offset + 1) % len(ring)]
            a, b = sorted((LABEL_INDEX[label], LABEL_INDEX[other]))
            edges.add((a, b))
    for spoke in (
        ("a4", "b4"),
        ("b4", "c4"),
        ("d7", "d6"),
        ("d6", "d5"),
        ("g4", "f4"),
        ("f4", "e4"),
        ("d1", "d2"),
        ("d2", "d3"),
    ):
        a, b = sorted((LABEL_INDEX[spoke[0]], LABEL_INDEX[spoke[1]]))
        edges.add((a, b))
    return tuple(sorted(edges))


EDGES = _standard_edges()
DIRECTED_EDGES = tuple(
    directed for a, b in EDGES for directed in ((a, b), (b, a))
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


def _dihedral(x: int, y: int, operation: int) -> tuple[int, int]:
    if operation == 0:
        return x, y
    if operation == 1:
        return -y, x
    if operation == 2:
        return -x, -y
    if operation == 3:
        return y, -x
    if operation == 4:
        return -x, y
    if operation == 5:
        return x, -y
    if operation == 6:
        return y, x
    if operation == 7:
        return -y, -x
    raise AssertionError(f"invalid dihedral operation {operation}")


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


def _canonical_key(
    white_bits: int,
    black_bits: int,
    white_in_hand: int,
    black_in_hand: int,
    side_to_move: int,
) -> int:
    return min(
        _transform_bits(white_bits, permutation)
        | (_transform_bits(black_bits, permutation) << 24)
        | (white_in_hand << 48)
        | (black_in_hand << 52)
        | (side_to_move << 56)
        for permutation in SYMMETRIES
    )


def _after(own: list[z3.BoolRef], node: int, source: int, target: int):
    if node == source:
        return z3.BoolVal(False)
    if node == target:
        return z3.BoolVal(True)
    return own[node]


def _complete_line(bits, line: tuple[int, int, int]):
    return z3.And(*(bits[node] for node in line))


def _open_target_expressions(own, occupied):
    expressions = []
    for target in range(24):
        completions = []
        for line in MILLS:
            if target not in line:
                continue
            peers = [node for node in line if node != target]
            completions.append(z3.And(*(own[node] for node in peers)))
        expressions.append(z3.And(z3.Not(occupied[target]), z3.Or(*completions)))
    return expressions


def _count_at_least(expressions, minimum: int):
    return z3.PbGe([(expression, 1) for expression in expressions], minimum)


def _count_at_most(expressions, maximum: int):
    return z3.PbLe([(expression, 1) for expression in expressions], maximum)


def _legal_move_expressions(own, occupied):
    return [
        z3.And(own[source], z3.Not(occupied[target]))
        for source, target in DIRECTED_EDGES
    ]


def _witnesses_for_motif(motif: str, own, opponent):
    occupied = [z3.Or(own[node], opponent[node]) for node in range(24)]
    root_open_targets = _open_target_expressions(own, occupied)
    opponent_open_targets = _open_target_expressions(opponent, occupied)
    root_opponent_moves = _legal_move_expressions(opponent, occupied)
    witnesses = []

    for source, target in DIRECTED_EDGES:
        legal = z3.And(own[source], z3.Not(occupied[target]))
        own_after = [_after(own, node, source, target) for node in range(24)]
        occupied_after = [
            z3.Or(own_after[node], opponent[node]) for node in range(24)
        ]
        forms_mill = z3.Or(
            *(
                _complete_line(own_after, line)
                for line in MILLS
                if target in line
            )
        )
        after_open_targets = _open_target_expressions(own_after, occupied_after)

        if motif == "dual-threat":
            condition = z3.And(
                legal,
                z3.Not(forms_mill),
                _count_at_most(root_open_targets, 1),
                _count_at_least(after_open_targets, 2),
            )
        elif motif == "mill-block":
            accessible = z3.Or(
                *(
                    opponent[other]
                    for edge in EDGES
                    if target in edge
                    for other in edge
                    if other != target
                )
            )
            condition = z3.And(
                legal,
                z3.Not(forms_mill),
                opponent_open_targets[target],
                accessible,
            )
        elif motif == "mill-abandonment":
            source_in_mill = z3.Or(
                *(
                    _complete_line(own, line)
                    for line in MILLS
                    if source in line
                )
            )
            condition = z3.And(
                legal,
                source_in_mill,
                z3.Not(forms_mill),
                _count_at_least(after_open_targets, 1),
            )
        elif motif == "capture-choice":
            opponent_in_mill = [
                z3.Or(
                    *(
                        _complete_line(opponent, line)
                        for line in MILLS
                        if node in line
                    )
                )
                for node in range(24)
            ]
            removable = [
                z3.And(opponent[node], z3.Not(opponent_in_mill[node]))
                for node in range(24)
            ]
            condition = z3.And(
                legal,
                forms_mill,
                _count_at_least(removable, 2),
            )
        elif motif == "zugzwang":
            defender_moves_after = _legal_move_expressions(opponent, occupied_after)
            condition = z3.And(
                legal,
                z3.Not(forms_mill),
                _count_at_least(root_opponent_moves, 3),
                _count_at_least(defender_moves_after, 1),
                _count_at_most(defender_moves_after, 1),
            )
        else:
            raise AssertionError(f"unsupported motif {motif}")
        witnesses.append((source, target, condition))
    return witnesses


def _model_bits(model: z3.ModelRef, variables: list[z3.BoolRef]) -> int:
    return sum(
        1 << node
        for node, variable in enumerate(variables)
        if z3.is_true(model.eval(variable, model_completion=True))
    )


def _build_solver(args: argparse.Namespace, restart: int):
    white = [z3.Bool(f"white_{restart}_{index}") for index in range(24)]
    black = [z3.Bool(f"black_{restart}_{index}") for index in range(24)]
    solver = z3.Solver()
    mixed_seed = (
        args.seed ^ ((restart + 1) * 0x9E37_79B1)
    ) & 0x7FFF_FFFF
    solver.set("random_seed", mixed_seed)
    for node in range(24):
        solver.add(z3.Not(z3.And(white[node], black[node])))
    solver.add(z3.PbEq([(piece, 1) for piece in white], args.white))
    solver.add(z3.PbEq([(piece, 1) for piece in black], args.black))

    own, opponent = (white, black) if args.side == "white" else (black, white)
    if args.max_defender_moves > 0:
        occupied = [
            z3.Or(own[node], opponent[node]) for node in range(24)
        ]
        defender_moves = _legal_move_expressions(opponent, occupied)
        solver.add(_count_at_least(defender_moves, 1))
        solver.add(_count_at_most(defender_moves, args.max_defender_moves))
    witnesses = _witnesses_for_motif(args.motif, own, opponent)
    solver.add(z3.Or(*(condition for _, _, condition in witnesses)))
    return solver, white, black, witnesses


def generate(args: argparse.Namespace) -> dict:
    side_to_move = 0 if args.side == "white" else 1
    candidates = []
    seen_canonical = set()
    inspected_models = 0
    restart = 0
    model_limit = args.max_models or args.count * 30

    while len(candidates) < args.count and inspected_models < model_limit:
        solver, white, black, witnesses = _build_solver(args, restart)
        all_variables = white + black
        local_models = 0
        while (
            len(candidates) < args.count
            and inspected_models < model_limit
            and local_models < args.restart_every
            and solver.check() == z3.sat
        ):
            model = solver.model()
            local_models += 1
            inspected_models += 1
            white_bits = _model_bits(model, white)
            black_bits = _model_bits(model, black)
            key = _canonical_key(white_bits, black_bits, 0, 0, side_to_move)
            if key not in seen_canonical:
                seen_canonical.add(key)
                source, target, _ = next(
                    witness
                    for witness in witnesses
                    if z3.is_true(model.eval(witness[2], model_completion=True))
                )
                candidates.append(
                    {
                        "whiteBits": white_bits,
                        "blackBits": black_bits,
                        "whiteInHand": 0,
                        "blackInHand": 0,
                        "sideToMove": side_to_move,
                        "witness": {
                            "from": PERFECT_LABELS[source],
                            "to": PERFECT_LABELS[target],
                        },
                    }
                )
            solver.add(
                z3.Or(
                    *(
                        variable
                        != z3.is_true(
                            model.eval(variable, model_completion=True)
                        )
                        for variable in all_variables
                    )
                )
            )
        restart += 1
        if local_models == 0:
            break

    if not candidates:
        raise SystemExit("Z3 found no candidate models for the requested constraints")
    return {
        "formatVersion": "1.0",
        "solver": {"name": "Z3", "version": z3.get_version_string()},
        "constraintModel": "sanmill-mill-motifs-v1",
        "motif": args.motif,
        "seed": args.seed,
        "side": args.side,
        "pieceCounts": {"white": args.white, "black": args.black},
        "maxDefenderMoves": args.max_defender_moves,
        "inspectedModels": inspected_models,
        "restarts": restart,
        "candidateCount": len(candidates),
        "candidates": candidates,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--motif",
        required=True,
        choices=(
            "dual-threat",
            "mill-block",
            "mill-abandonment",
            "capture-choice",
            "zugzwang",
        ),
    )
    parser.add_argument("--side", required=True, choices=("white", "black"))
    parser.add_argument("--white", type=int, default=5)
    parser.add_argument("--black", type=int, default=5)
    parser.add_argument("--count", type=int, default=10_000)
    parser.add_argument("--max-models", type=int, default=0)
    parser.add_argument(
        "--max-defender-moves",
        type=int,
        default=0,
        help="optional positive root-mobility cap used to bias tactical models",
    )
    parser.add_argument(
        "--restart-every",
        type=int,
        default=500,
        help="restart Z3 after this many models to diversify enumeration",
    )
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=1)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    if not 4 <= args.white <= 7 or not 4 <= args.black <= 7:
        parser.error("--white and --black must each be in 4..7")
    if args.count < 1:
        parser.error("--count must be positive")
    if args.restart_every < 1:
        parser.error("--restart-every must be positive")
    if args.max_defender_moves < 0:
        parser.error("--max-defender-moves must not be negative")
    return args


def main() -> None:
    args = parse_args()
    package = generate(args)
    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(
        (json.dumps(package, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    )
    print(
        "[mill-smt] "
        f"motif={args.motif} side={args.side} "
        f"candidates={package['candidateCount']} "
        f"models={package['inspectedModels']} "
        f"restarts={package['restarts']} out={output}"
    )


if __name__ == "__main__":
    main()
