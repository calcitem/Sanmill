#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Select a balanced puzzle shortlist with OR-Tools CP-SAT.

Inputs must already be certified by Rust/TGF and Perfect DB. CP-SAT has no
role in proving a win: it only enforces editorial quotas and maximises a
deterministic diversity/quality score over the certified pool.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

try:
    from ortools.sat.python import cp_model
    import ortools
except ImportError as error:
    raise SystemExit(
        "OR-Tools is required; install scripts/requirements-puzzle-math.txt"
    ) from error


MOTIFS = (
    "dual-threat",
    "mill-block",
    "mill-abandonment",
    "capture-choice",
    "zugzwang",
)
ENGINE_TOPICS = (
    # Exact requested motifs take precedence over secondary line traits.
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
    "vs-flying",
    "trap:greedy-mill",
    "trap:wrong-mill",
    "forced-win",
)
DIFFICULTIES = ("beginner", "easy", "medium", "hard", "expert")
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
class Candidate:
    puzzle: dict
    motif: str
    profile: str
    side: str
    difficulty: str
    first_move: str
    canonical_position: int
    canonical_solver_position: int
    position: PositionFingerprint
    score: int


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


def _parse_fen_position(fen: str) -> PositionFingerprint:
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
    side_to_move = 0 if fields[1] == "w" else 1
    white_in_hand = int(fields[5])
    black_in_hand = int(fields[7])
    return PositionFingerprint(
        white_bits=white_bits,
        black_bits=black_bits,
        white_in_hand=white_in_hand,
        black_in_hand=black_in_hand,
        side_to_move=side_to_move,
    )


def _canonical_position_key(position: PositionFingerprint) -> int:
    return min(
        _transform_bits(position.white_bits, permutation)
        | (_transform_bits(position.black_bits, permutation) << 24)
        | (position.white_in_hand << 48)
        | (position.black_in_hand << 52)
        | (position.side_to_move << 56)
        for permutation in SYMMETRIES
    )


def _canonical_solver_position_key(position: PositionFingerprint) -> int:
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


def _minimum_position_distance(
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


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _load_reference_positions(
    paths: list[Path],
) -> tuple[list[PositionFingerprint], list[dict[str, object]]]:
    positions = []
    records = []
    for path in paths:
        path_positions = []
        for line_number, raw_line in enumerate(
            path.read_text(encoding="utf-8-sig").splitlines(),
            start=1,
        ):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            try:
                path_positions.append(_parse_fen_position(line))
            except ValueError as error:
                raise ValueError(f"{path}:{line_number}: {error}") from error
        if not path_positions:
            raise ValueError(f"{path} contains no reference positions")
        positions.extend(path_positions)
        records.append(
            {
                "name": path.name,
                "positionCount": len(path_positions),
                "sha256": _sha256(path),
            }
        )
    return positions, records


def _tag_value(tags: list[str], prefix: str) -> int:
    for tag in tags:
        if tag.startswith(prefix):
            try:
                return int(tag.removeprefix(prefix))
            except ValueError:
                return 0
    return 0


def _solve_depth_score(tags: list[str]) -> int:
    for tag in tags:
        if tag == "solve-depth:deep":
            return 10
        if tag.startswith("solve-depth:"):
            try:
                return int(tag.removeprefix("solve-depth:"))
            except ValueError:
                return 0
    return 0


def _candidate_score(
    puzzle: dict, tags: list[str], source: str
) -> int:
    rating = puzzle.get("rating")
    rating_score = 0
    if isinstance(rating, int):
        target_rating = 1450 if source == "smt-z3" else 1900
        rating_score = max(0, 800 - abs(rating - target_rating))
    score = rating_score
    score += min(_tag_value(tags, "non-winning-first-turns:"), 20) * 12
    score += min(_solve_depth_score(tags), 10) * 35
    score += 80 if "precision" in tags else 0
    score += 50 if "sacrifice" in tags else 0
    score += 40 if "immobilization" in tags else 0
    if source == "engine-blunder":
        score += _tag_value(tags, "source-severity:") * 100
        score += min(_tag_value(tags, "source-search-depth:"), 20) * 8
    solutions = puzzle.get("solutions")
    if isinstance(solutions, list):
        score -= max(0, len(solutions) - 1) * 120
    return score


def _load_candidates(
    paths: list[Path], source: str
) -> tuple[list[Candidate], str]:
    candidates = []
    latest_export_date = ""
    for path in paths:
        package = json.loads(path.read_text(encoding="utf-8-sig"))
        export_date = package.get("exportDate", "")
        if isinstance(export_date, str):
            latest_export_date = max(latest_export_date, export_date)
        puzzles = package.get("puzzles")
        if not isinstance(puzzles, list):
            raise ValueError(f"{path} does not contain a puzzles array")
        for puzzle in puzzles:
            if not isinstance(puzzle, dict):
                raise ValueError(f"{path} contains a non-object puzzle")
            tags = puzzle.get("tags")
            if not isinstance(tags, list) or not all(
                isinstance(tag, str) for tag in tags
            ):
                raise ValueError(f"{puzzle.get('id')} has an invalid tags array")
            if source == "smt-z3":
                if "discovery:smt-z3" not in tags:
                    raise ValueError(
                        f"{puzzle.get('id')} lacks discovery:smt-z3 provenance"
                    )
                puzzle_motifs = [motif for motif in MOTIFS if motif in tags]
                if len(puzzle_motifs) != 1:
                    raise ValueError(
                        f"{puzzle.get('id')} must have exactly one recognised motif"
                    )
                motif = puzzle_motifs[0]
            else:
                if "discovery:engine-blunder-corpus" not in tags:
                    raise ValueError(
                        f"{puzzle.get('id')} lacks engine-blunder provenance"
                    )
                motif = next(
                    (tag for tag in tags if tag in ENGINE_TOPICS),
                    "",
                )
                if not motif:
                    raise ValueError(
                        f"{puzzle.get('id')} has no recognised primary topic"
                    )
            sides = [
                side for side in ("white", "black") if f"side:{side}" in tags
            ]
            if len(sides) != 1:
                raise ValueError(f"{puzzle.get('id')} must declare one side tag")
            solutions = puzzle.get("solutions")
            if not isinstance(solutions, list) or not solutions:
                raise ValueError(f"{puzzle.get('id')} has no solutions")
            moves = solutions[0].get("moves")
            if not isinstance(moves, list) or not moves:
                raise ValueError(f"{puzzle.get('id')} has no main-line moves")
            notation = moves[0].get("notation")
            if not isinstance(notation, str) or not notation:
                raise ValueError(f"{puzzle.get('id')} has no first notation")
            fen = puzzle.get("initialPosition")
            if not isinstance(fen, str):
                raise ValueError(f"{puzzle.get('id')} has no initialPosition")
            position = _parse_fen_position(fen)
            difficulty = puzzle.get("difficulty")
            if difficulty not in DIFFICULTIES:
                raise ValueError(
                    f"{puzzle.get('id')} has an unrecognised difficulty"
                )
            candidates.append(
                Candidate(
                    puzzle=puzzle,
                    motif=motif,
                    profile=path.stem,
                    side=sides[0],
                    difficulty=difficulty,
                    first_move=notation,
                    canonical_position=_canonical_position_key(position),
                    canonical_solver_position=(
                        _canonical_solver_position_key(position)
                    ),
                    position=position,
                    score=_candidate_score(puzzle, tags, source),
                )
            )
    return candidates, latest_export_date


def _group_indices(
    candidates: list[Candidate], key
) -> dict[object, list[int]]:
    groups: dict[object, list[int]] = defaultdict(list)
    for index, candidate in enumerate(candidates):
        groups[key(candidate)].append(index)
    return groups


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+")
    parser.add_argument("--out", required=True)
    parser.add_argument("--count", type=int, required=True)
    parser.add_argument(
        "--source",
        choices=("smt-z3", "engine-blunder"),
        default="smt-z3",
        help="candidate provenance and topic model (default smt-z3)",
    )
    parser.add_argument("--min-per-motif", type=int, default=1)
    parser.add_argument("--min-per-difficulty", type=int, default=1)
    parser.add_argument("--min-per-profile", type=int, default=0)
    parser.add_argument(
        "--max-per-profile",
        type=int,
        default=0,
        help="maximum selected from one input profile; 0 disables the cap",
    )
    parser.add_argument(
        "--max-motif-imbalance",
        type=int,
        help=(
            "maximum difference between represented topic counts; defaults "
            "to 1 for smt-z3 and is disabled for engine-blunder"
        ),
    )
    parser.add_argument("--max-per-first-move", type=int, default=2)
    parser.add_argument(
        "--min-position-distance",
        type=int,
        default=0,
        help=(
            "minimum coloured-point difference after symmetry and solver-side "
            "normalisation; 0 disables near-duplicate filtering"
        ),
    )
    parser.add_argument(
        "--reference-fens",
        action="append",
        default=[],
        help=(
            "FEN record whose positions must not be selected; repeatable"
        ),
    )
    parser.add_argument(
        "--min-reference-distance",
        type=int,
        default=1,
        help=(
            "minimum coloured-point distance from --reference-fens after "
            "symmetry and solver-side normalisation; 1 excludes exact copies"
        ),
    )
    parser.add_argument("--side-imbalance", type=int, default=1)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--max-seconds", type=float, default=30.0)
    parser.add_argument("--pack-id", default="malom_constraint_topics_v1")
    parser.add_argument("--pack-name", default="Constraint-Directed Mill Topics")
    parser.add_argument("--author", default="Sanmill Puzzle Toolchain")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.count < 1:
        raise SystemExit("--count must be positive")
    if args.min_per_motif < 0:
        raise SystemExit("--min-per-motif must not be negative")
    if args.min_per_difficulty < 0:
        raise SystemExit("--min-per-difficulty must not be negative")
    if args.min_per_profile < 0:
        raise SystemExit("--min-per-profile must not be negative")
    if args.max_per_profile < 0:
        raise SystemExit("--max-per-profile must not be negative")
    if (
        args.max_per_profile > 0
        and args.min_per_profile > args.max_per_profile
    ):
        raise SystemExit("--min-per-profile exceeds --max-per-profile")
    if args.max_motif_imbalance is not None and args.max_motif_imbalance < 0:
        raise SystemExit("--max-motif-imbalance must not be negative")
    if args.max_per_first_move < 1:
        raise SystemExit("--max-per-first-move must be positive")
    if args.min_position_distance < 0:
        raise SystemExit("--min-position-distance must not be negative")
    if args.min_reference_distance < 0:
        raise SystemExit("--min-reference-distance must not be negative")
    if args.side_imbalance < 0:
        raise SystemExit("--side-imbalance must not be negative")
    if args.max_seconds <= 0:
        raise SystemExit("--max-seconds must be positive")
    if (
        args.source == "smt-z3"
        and args.count < args.min_per_difficulty * len(DIFFICULTIES)
    ):
        raise SystemExit("--count is too small for the requested difficulty minima")
    candidates, export_date = _load_candidates(
        [Path(path).resolve() for path in args.inputs],
        args.source,
    )
    reference_paths = [
        Path(path).resolve() for path in args.reference_fens
    ]
    for path in reference_paths:
        if not path.is_file():
            raise SystemExit(f"reference FEN record does not exist: {path}")
    reference_positions, reference_records = _load_reference_positions(
        reference_paths
    )
    reference_rejected = 0
    if reference_positions and args.min_reference_distance > 0:
        retained = []
        for candidate in candidates:
            if any(
                _minimum_position_distance(candidate.position, reference)
                < args.min_reference_distance
                for reference in reference_positions
            ):
                reference_rejected += 1
            else:
                retained.append(candidate)
        candidates = retained
    if len(candidates) < args.count:
        raise SystemExit(
            f"requested {args.count} puzzles from only {len(candidates)} candidates"
        )

    model = cp_model.CpModel()
    selected = [
        model.new_bool_var(f"selected_{index}") for index in range(len(candidates))
    ]
    model.add(sum(selected) == args.count)

    for indices in _group_indices(
        candidates, lambda candidate: candidate.canonical_position
    ).values():
        if len(indices) > 1:
            model.add(sum(selected[index] for index in indices) <= 1)
    for indices in _group_indices(
        candidates, lambda candidate: candidate.canonical_solver_position
    ).values():
        if len(indices) > 1:
            model.add(sum(selected[index] for index in indices) <= 1)
    near_duplicate_pairs = 0
    if args.min_position_distance > 0:
        for left in range(len(candidates)):
            for right in range(left + 1, len(candidates)):
                if (
                    _minimum_position_distance(
                        candidates[left].position,
                        candidates[right].position,
                    )
                    < args.min_position_distance
                ):
                    model.add(selected[left] + selected[right] <= 1)
                    near_duplicate_pairs += 1
    for indices in _group_indices(
        candidates, lambda candidate: candidate.puzzle.get("id")
    ).values():
        if len(indices) > 1:
            model.add(sum(selected[index] for index in indices) <= 1)
    for indices in _group_indices(
        candidates, lambda candidate: candidate.first_move
    ).values():
        model.add(
            sum(selected[index] for index in indices)
            <= args.max_per_first_move
        )

    motif_order = MOTIFS if args.source == "smt-z3" else ENGINE_TOPICS
    present_motifs = [
        motif
        for motif in motif_order
        if any(candidate.motif == motif for candidate in candidates)
    ]
    missing_motifs = sorted(set(motif_order) - set(present_motifs))
    if (
        args.source == "smt-z3"
        and args.min_per_motif > 0
        and missing_motifs
    ):
        raise SystemExit(
            "candidate pool lacks required motifs: " + ", ".join(missing_motifs)
        )
    if args.count < args.min_per_motif * len(present_motifs):
        raise SystemExit("--count is too small for the requested motif minima")
    motif_counts = {}
    for motif in present_motifs:
        indices = [
            index
            for index, candidate in enumerate(candidates)
            if candidate.motif == motif
        ]
        motif_counts[motif] = sum(selected[index] for index in indices)
        model.add(motif_counts[motif] >= args.min_per_motif)
    max_motif_imbalance = args.max_motif_imbalance
    if max_motif_imbalance is None and args.source == "smt-z3":
        max_motif_imbalance = 1
    if len(motif_counts) > 1 and max_motif_imbalance is not None:
        max_motif_count = model.new_int_var(0, args.count, "max_motif_count")
        min_motif_count = model.new_int_var(0, args.count, "min_motif_count")
        model.add_max_equality(max_motif_count, list(motif_counts.values()))
        model.add_min_equality(min_motif_count, list(motif_counts.values()))
        model.add(
            max_motif_count - min_motif_count <= max_motif_imbalance
        )

    profile_counts = {}
    for profile, indices in _group_indices(
        candidates, lambda candidate: candidate.profile
    ).items():
        profile_counts[str(profile)] = sum(
            selected[index] for index in indices
        )
        model.add(profile_counts[str(profile)] >= args.min_per_profile)
        if args.max_per_profile > 0:
            model.add(
                profile_counts[str(profile)] <= args.max_per_profile
            )
    if args.count < args.min_per_profile * len(profile_counts):
        raise SystemExit("--count is too small for the requested profile minima")
    if (
        args.max_per_profile > 0
        and args.count > args.max_per_profile * len(profile_counts)
    ):
        raise SystemExit("--count is too large for the requested profile caps")

    white_count = sum(
        selected[index]
        for index, candidate in enumerate(candidates)
        if candidate.side == "white"
    )
    black_count = sum(
        selected[index]
        for index, candidate in enumerate(candidates)
        if candidate.side == "black"
    )
    model.add(white_count - black_count <= args.side_imbalance)
    model.add(black_count - white_count <= args.side_imbalance)

    present_difficulties = {
        candidate.difficulty for candidate in candidates
    }
    missing_difficulties = sorted(
        set(DIFFICULTIES) - present_difficulties
    )
    if (
        args.source == "smt-z3"
        and args.min_per_difficulty > 0
        and missing_difficulties
    ):
        raise SystemExit(
            "candidate pool lacks required difficulties: "
            + ", ".join(missing_difficulties)
        )
    if args.count < args.min_per_difficulty * len(present_difficulties):
        raise SystemExit(
            "--count is too small for the requested difficulty minima"
        )
    difficulty_bonus = []
    for difficulty in DIFFICULTIES:
        if difficulty not in present_difficulties:
            continue
        present = model.new_bool_var(f"difficulty_{difficulty}")
        indices = [
            index
            for index, candidate in enumerate(candidates)
            if candidate.difficulty == difficulty
        ]
        model.add(
            sum(selected[index] for index in indices)
            >= args.min_per_difficulty
        )
        model.add(sum(selected[index] for index in indices) >= present)
        model.add(sum(selected[index] for index in indices) <= args.count * present)
        difficulty_bonus.append(present)

    model.maximize(
        sum(
            candidate.score * selected[index]
            for index, candidate in enumerate(candidates)
        )
        + 500 * sum(difficulty_bonus)
    )
    solver = cp_model.CpSolver()
    solver.parameters.num_search_workers = 1
    solver.parameters.random_seed = args.seed
    solver.parameters.max_time_in_seconds = args.max_seconds
    status = solver.solve(model)
    if status not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        raise SystemExit(f"CP-SAT found no shortlist: {solver.status_name(status)}")

    chosen = [
        candidate
        for index, candidate in enumerate(candidates)
        if solver.value(selected[index])
    ]
    chosen.sort(
        key=lambda candidate: (
            motif_order.index(candidate.motif),
            candidate.side,
            -candidate.score,
            candidate.puzzle.get("id", ""),
        )
    )
    motif_summary = Counter(candidate.motif for candidate in chosen)
    profile_summary = Counter(candidate.profile for candidate in chosen)
    side_summary = Counter(candidate.side for candidate in chosen)
    difficulty_summary = Counter(candidate.difficulty for candidate in chosen)
    if args.source == "smt-z3":
        description = (
            "Z3-directed positions independently certified by Rust/TGF "
            "and Perfect DB, then balanced by OR-Tools CP-SAT. CP-SAT "
            "is an editorial selector, not a game-theoretic proof source."
        )
        metadata_tags = [
            "generated",
            "malom-db",
            "smt-z3",
            "cp-sat-selected",
        ]
    else:
        description = (
            "Engine-error-corpus positions independently certified by "
            "Rust/TGF and Perfect DB, then shortlisted by OR-Tools CP-SAT. "
            "CP-SAT balances the review set and does not prove a win."
        )
        metadata_tags = [
            "generated",
            "malom-db",
            "engine-blunder-corpus",
            "cp-sat-selected",
        ]
    package = {
        "formatVersion": "1.0",
        "exportedBy": {
            "appName": "Sanmill",
            "platform": "CP-SAT offline selector",
        },
        "exportDate": export_date,
        "puzzleCount": len(chosen),
        "metadata": {
            "id": args.pack_id,
            "name": args.pack_name,
            "description": description,
            "author": args.author,
            "version": "1.0.0",
            "tags": metadata_tags,
            "isOfficial": args.source == "smt-z3",
            "ruleVariantId": "standard_9mm",
        },
        "selectionProvenance": {
            "solver": "OR-Tools CP-SAT",
            "version": ortools.__version__,
            "status": solver.status_name(status),
            "seed": args.seed,
            "source": args.source,
            "candidateCount": len(candidates),
            "objectiveValue": int(round(solver.objective_value)),
            "constraints": {
                "count": args.count,
                "minPerMotif": args.min_per_motif,
                "minPerDifficulty": args.min_per_difficulty,
                "minPerProfile": args.min_per_profile,
                "maxPerProfile": args.max_per_profile,
                "maxMotifImbalance": max_motif_imbalance,
                "maxPerFirstMove": args.max_per_first_move,
                "minPositionDistance": args.min_position_distance,
                "nearDuplicatePairCount": near_duplicate_pairs,
                "minReferenceDistance": args.min_reference_distance,
                "referenceRejectedCount": reference_rejected,
                "sideImbalance": args.side_imbalance,
            },
            "referenceFens": reference_records,
            "motifs": dict(sorted(motif_summary.items())),
            "profiles": dict(sorted(profile_summary.items())),
            "sides": dict(sorted(side_summary.items())),
            "difficulties": dict(sorted(difficulty_summary.items())),
            "selectedCandidates": [
                {
                    "id": candidate.puzzle.get("id"),
                    "profile": candidate.profile,
                    "topic": candidate.motif,
                    "score": candidate.score,
                }
                for candidate in chosen
            ],
        },
        "puzzles": [candidate.puzzle for candidate in chosen],
    }
    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(
        (json.dumps(package, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    )
    print(
        "[mill-cp-sat] "
        f"status={solver.status_name(status)} candidates={len(candidates)} "
        f"selected={len(chosen)} motifs={dict(motif_summary)} "
        f"profiles={dict(profile_summary)} "
        f"reference_rejected={reference_rejected} "
        f"sides={dict(side_summary)} difficulties={dict(difficulty_summary)} "
        f"out={output}"
    )


if __name__ == "__main__":
    main()
