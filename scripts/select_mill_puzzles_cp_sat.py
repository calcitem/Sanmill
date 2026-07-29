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

from mill_puzzle_similarity import (
    DEFAULT_MINIMUM_POSITION_DISTANCE,
    PositionFingerprint,
    canonical_position_key as _canonical_position_key,
    canonical_solver_position_key as _canonical_solver_position_key,
    minimum_position_distance as _minimum_position_distance,
    parse_fen_position as _parse_fen_position,
)

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
CERTIFIED_TOPICS = tuple(dict.fromkeys((*MOTIFS, *ENGINE_TOPICS)))


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
            elif source == "engine-blunder":
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
            else:
                motif = next(
                    (tag for tag in tags if tag in CERTIFIED_TOPICS),
                    "forced-win",
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
        choices=("smt-z3", "engine-blunder", "certified"),
        default="smt-z3",
        help="candidate provenance and topic model (default smt-z3)",
    )
    parser.add_argument("--min-per-motif", type=int, default=1)
    parser.add_argument("--min-per-difficulty", type=int, default=1)
    parser.add_argument(
        "--difficulty-minimum",
        action="append",
        default=[],
        metavar="LEVEL=COUNT",
        help=(
            "override the minimum for one difficulty; repeatable, for "
            "example --difficulty-minimum beginner=3"
        ),
    )
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
        "--max-solution-lines",
        type=int,
        default=32,
        help="maximum exported solution lines per selected puzzle",
    )
    parser.add_argument(
        "--min-position-distance",
        type=int,
        default=DEFAULT_MINIMUM_POSITION_DISTANCE,
        help=(
            "minimum coloured-point difference after symmetry and solver-side "
            f"normalisation; default {DEFAULT_MINIMUM_POSITION_DISTANCE}"
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
        default=DEFAULT_MINIMUM_POSITION_DISTANCE,
        help=(
            "minimum coloured-point distance from --reference-fens after "
            "symmetry and solver-side normalisation; "
            f"default {DEFAULT_MINIMUM_POSITION_DISTANCE}"
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
    difficulty_minima = {
        difficulty: args.min_per_difficulty for difficulty in DIFFICULTIES
    }
    for raw_minimum in args.difficulty_minimum:
        difficulty, separator, raw_count = raw_minimum.partition("=")
        if (
            separator != "="
            or difficulty not in DIFFICULTIES
            or not raw_count.isdigit()
        ):
            raise SystemExit(
                "--difficulty-minimum must use LEVEL=COUNT with a known level"
            )
        difficulty_minima[difficulty] = int(raw_count)
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
    if args.max_solution_lines < 1:
        raise SystemExit("--max-solution-lines must be positive")
    if args.min_position_distance < 0:
        raise SystemExit("--min-position-distance must not be negative")
    if args.min_reference_distance < 0:
        raise SystemExit("--min-reference-distance must not be negative")
    if args.side_imbalance < 0:
        raise SystemExit("--side-imbalance must not be negative")
    if args.max_seconds <= 0:
        raise SystemExit("--max-seconds must be positive")
    candidates, export_date = _load_candidates(
        [Path(path).resolve() for path in args.inputs],
        args.source,
    )
    solution_line_rejected = 0
    retained = []
    for candidate in candidates:
        solutions = candidate.puzzle.get("solutions")
        assert isinstance(solutions, list)
        if len(solutions) > args.max_solution_lines:
            solution_line_rejected += 1
        else:
            retained.append(candidate)
    candidates = retained
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

    motif_order = (
        MOTIFS
        if args.source == "smt-z3"
        else ENGINE_TOPICS
        if args.source == "engine-blunder"
        else CERTIFIED_TOPICS
    )
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
        difficulty
        for difficulty, minimum in difficulty_minima.items()
        if minimum > 0 and difficulty not in present_difficulties
    )
    if missing_difficulties:
        raise SystemExit(
            "candidate pool lacks required difficulties: "
            + ", ".join(missing_difficulties)
        )
    if args.count < sum(
        difficulty_minima[difficulty]
        for difficulty in present_difficulties
    ):
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
            >= difficulty_minima[difficulty]
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
    elif args.source == "engine-blunder":
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
    else:
        description = (
            "Perfect DB-certified positions selected for whole-pack "
            "diversity by OR-Tools CP-SAT. CP-SAT is an editorial selector, "
            "not a game-theoretic proof source."
        )
        metadata_tags = [
            "generated",
            "malom-db",
            "perfect-db-certified",
            "cp-sat-selected",
            "expert-review",
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
                "difficultyMinimums": difficulty_minima,
                "minPerProfile": args.min_per_profile,
                "maxPerProfile": args.max_per_profile,
                "maxMotifImbalance": max_motif_imbalance,
                "maxPerFirstMove": args.max_per_first_move,
                "maxSolutionLines": args.max_solution_lines,
                "solutionLineRejectedCount": solution_line_rejected,
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
