#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Merge a certified CP-SAT review shortlist into Sanmill's built-in pack.

The shortlist must already have been proved by Rust/TGF and Perfect DB and
selected by ``select_mill_puzzles_cp_sat.py``. This script adds the
application-facing curriculum tags, preserves the complete selected
positions and solution lines, records the pending expert-review batch, and
keeps all embedded pending-review puzzles in deterministic curriculum order
without reordering the established application curriculum.

Re-running the same batch is idempotent: puzzles carrying its
``review-batch:`` tag are replaced before the new shortlist is merged.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from mill_puzzle_similarity import (
    DEFAULT_MINIMUM_POSITION_DISTANCE,
    find_position_conflicts,
)


TOPIC_ORDER = (
    "capture-choice",
    "quiet-move",
    "mill-block",
    "allow-mill",
    "greedy-mill-trap",
    "wrong-mill-trap",
    "double-mill",
    "dual-threat",
    "right-angle-threat",
    "mill-recovery",
    "mill-abandonment",
    "junction-release",
    "ring-transfer",
    "sacrifice",
    "mobility-squeeze",
    "immobilization",
    "flying-defence",
    "zugzwang",
    "calculation",
)
DIFFICULTY_RANK = {
    "beginner": 1,
    "easy": 2,
    "medium": 3,
    "hard": 4,
    "expert": 5,
}
TOPIC_MAP = {
    "capture-choice": "capture-choice",
    "dual-threat": "dual-threat",
    "mill-abandonment": "mill-abandonment",
    "mill-block": "mill-block",
    "zugzwang": "zugzwang",
    "double-mill": "double-mill",
    "immobilization": "immobilization",
    "sacrifice": "sacrifice",
    "quiet-move": "quiet-move",
    "allow-mill": "allow-mill",
    "mobility-squeeze": "mobility-squeeze",
    "junction-release": "junction-release",
    "mill-recovery": "mill-recovery",
    "right-angle-threat": "right-angle-threat",
    "ring-transfer": "ring-transfer",
    "vs-flying": "flying-defence",
    "trap:greedy-mill": "greedy-mill-trap",
    "trap:wrong-mill": "wrong-mill-trap",
    "forced-win": "calculation",
}
ENDGAME_PROFILES = {
    "against-flying",
    "material-odds-6v4",
    "material-odds-7v4",
}


def _load_package(path: Path) -> dict:
    package = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(package, dict) or not isinstance(package.get("puzzles"), list):
        raise ValueError(f"{path} is not a puzzle package")
    if package.get("puzzleCount") != len(package["puzzles"]):
        raise ValueError(f"{path} has a mismatched puzzleCount")
    return package


def _one_tag(tags: list[str], prefix: str, puzzle_id: str) -> str:
    matches = [tag for tag in tags if tag.startswith(prefix)]
    if len(matches) != 1:
        raise ValueError(
            f"{puzzle_id} must have exactly one {prefix!r} tag, found {matches}"
        )
    return matches[0]


def _replace_classification(tags: list[str], prefix: str, value: str) -> None:
    tags[:] = [tag for tag in tags if not tag.startswith(prefix)]
    tags.append(f"{prefix}{value}")


def _curriculum(topic: str, profile: str) -> str:
    if profile in ENDGAME_PROFILES or topic in {
        "immobilization",
        "flying-defence",
        "zugzwang",
    }:
        return "04-endgames"
    if profile == "late-placement" or topic in {
        "capture-choice",
        "double-mill",
        "dual-threat",
        "right-angle-threat",
        "allow-mill",
        "mill-recovery",
        "mill-abandonment",
        "mill-block",
        "sacrifice",
    }:
        return "02-mill-tactics"
    return "03-positional-play"


def _append_unique(tags: list[str], value: str) -> None:
    if value not in tags:
        tags.append(value)


def _selection_records(review: dict) -> tuple[str, dict[str, dict]]:
    provenance = review.get("selectionProvenance")
    if not isinstance(provenance, dict):
        raise ValueError("review package lacks selectionProvenance")
    source = provenance.get("source")
    if source not in {"engine-blunder", "certified"}:
        raise ValueError(
            "review package must be an engine-blunder or certified shortlist"
        )
    selected = provenance.get("selectedCandidates")
    if not isinstance(selected, list):
        raise ValueError("review package lacks selectedCandidates")
    records: dict[str, dict] = {}
    for record in selected:
        if not isinstance(record, dict) or not isinstance(record.get("id"), str):
            raise ValueError("invalid selectedCandidates record")
        puzzle_id = record["id"]
        if puzzle_id in records:
            raise ValueError(f"duplicate selection record {puzzle_id}")
        records[puzzle_id] = record
    return source, records


def _decorate_review_puzzle(
    puzzle: dict,
    record: dict,
    batch_id: str,
    max_solution_lines: int,
    selection_source: str,
) -> dict:
    puzzle_id = puzzle.get("id")
    if not isinstance(puzzle_id, str) or not puzzle_id:
        raise ValueError("review puzzle lacks an id")
    tags = puzzle.get("tags")
    if not isinstance(tags, list) or not all(isinstance(tag, str) for tag in tags):
        raise ValueError(f"{puzzle_id} has invalid tags")
    tags = list(tags)

    source_topic = record.get("topic")
    profile = record.get("profile")
    if source_topic not in TOPIC_MAP:
        raise ValueError(f"{puzzle_id} has unsupported source topic {source_topic!r}")
    if not isinstance(profile, str) or not profile:
        raise ValueError(f"{puzzle_id} has no selection profile")
    topic = TOPIC_MAP[source_topic]

    difficulty = puzzle.get("difficulty")
    if difficulty not in DIFFICULTY_RANK:
        raise ValueError(f"{puzzle_id} has unsupported difficulty {difficulty!r}")
    solutions = puzzle.get("solutions")
    if not isinstance(solutions, list) or not solutions:
        raise ValueError(f"{puzzle_id} has no solutions")
    if len(solutions) > max_solution_lines:
        raise ValueError(
            f"{puzzle_id} has {len(solutions)} solution lines; "
            f"review limit is {max_solution_lines}"
        )
    if "source:composed" not in tags or "source:replay-backed" in tags:
        raise ValueError(f"{puzzle_id} must be disclosed as a composition")
    if selection_source == "engine-blunder":
        if "discovery:engine-blunder-corpus" not in tags:
            raise ValueError(
                f"{puzzle_id} lacks engine-blunder discovery provenance"
            )
    elif not any(tag.startswith("discovery:") for tag in tags):
        _append_unique(tags, "discovery:broad-perfect-db-sampling")

    _replace_classification(tags, "topic:", topic)
    _replace_classification(tags, "curriculum:", _curriculum(topic, profile))
    _replace_classification(
        tags,
        "progression:",
        f"{DIFFICULTY_RANK[difficulty]}-{difficulty}",
    )
    _append_unique(tags, "review-status:expert-pending")
    _append_unique(tags, f"review-batch:{batch_id}")
    _append_unique(tags, f"selection-profile:{profile}")
    puzzle["tags"] = tags
    puzzle["isCustom"] = False
    return puzzle


def _curriculum_key(puzzle: dict) -> tuple[int, int, int, int, str]:
    puzzle_id = puzzle.get("id", "<unknown>")
    tags = puzzle.get("tags")
    if not isinstance(tags, list):
        raise ValueError(f"{puzzle_id} has invalid tags")
    topic = _one_tag(tags, "topic:", puzzle_id).removeprefix("topic:")
    if topic not in TOPIC_ORDER:
        raise ValueError(f"{puzzle_id} has unsupported topic {topic!r}")
    difficulty = puzzle.get("difficulty")
    if difficulty not in DIFFICULTY_RANK:
        raise ValueError(f"{puzzle_id} has unsupported difficulty {difficulty!r}")
    _one_tag(tags, "curriculum:", puzzle_id)
    expected_progression = (
        f"progression:{DIFFICULTY_RANK[difficulty]}-{difficulty}"
    )
    if _one_tag(tags, "progression:", puzzle_id) != expected_progression:
        raise ValueError(f"{puzzle_id} has inconsistent progression")
    _one_tag(tags, "distance-band:", puzzle_id)
    win_tags = [
        tag.removeprefix("win-in-")
        for tag in tags
        if tag.startswith("win-in-")
    ]
    if len(win_tags) != 1 or not win_tags[0].isdigit():
        raise ValueError(f"{puzzle_id} must have exactly one numeric win-in tag")
    rating = puzzle.get("rating")
    if not isinstance(rating, int):
        raise ValueError(f"{puzzle_id} has no numeric rating")
    return (
        TOPIC_ORDER.index(topic),
        DIFFICULTY_RANK[difficulty],
        int(win_tags[0]),
        rating,
        puzzle_id,
    )


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True, help="current built-in pack")
    parser.add_argument("--review", required=True, help="selected review pack")
    parser.add_argument("--out", required=True, help="combined output pack")
    parser.add_argument("--version", default="1.5.0-review.1")
    parser.add_argument("--expected-review-count", type=int, default=30)
    parser.add_argument("--max-review-solution-lines", type=int, default=32)
    parser.add_argument(
        "--min-position-distance",
        type=int,
        default=DEFAULT_MINIMUM_POSITION_DISTANCE,
        help=(
            "minimum whole-pack coloured-point distance after ring-16 "
            "symmetry and solver-side normalisation"
        ),
    )
    args = parser.parse_args()
    if args.expected_review_count < 1:
        parser.error("--expected-review-count must be positive")
    if args.max_review_solution_lines < 1:
        parser.error("--max-review-solution-lines must be positive")
    if args.min_position_distance < 0:
        parser.error("--min-position-distance must not be negative")
    return args


def main() -> None:
    args = _parse_args()
    base_path = Path(args.base).resolve()
    review_path = Path(args.review).resolve()
    output_path = Path(args.out).resolve()
    base = _load_package(base_path)
    review = _load_package(review_path)
    metadata = review.get("metadata")
    if not isinstance(metadata, dict) or metadata.get("isOfficial") is not False:
        raise ValueError("review shortlist must be explicitly unofficial")
    batch_id = metadata.get("id")
    if not isinstance(batch_id, str) or not batch_id:
        raise ValueError("review shortlist metadata lacks an id")
    if len(review["puzzles"]) != args.expected_review_count:
        raise ValueError(
            f"expected {args.expected_review_count} review puzzles, "
            f"found {len(review['puzzles'])}"
        )

    selection_source, records = _selection_records(review)
    review_ids = {puzzle.get("id") for puzzle in review["puzzles"]}
    if review_ids != set(records):
        raise ValueError("review puzzles and CP-SAT selection records differ")

    batch_tag = f"review-batch:{batch_id}"
    retained = [
        puzzle
        for puzzle in base["puzzles"]
        if batch_tag not in puzzle.get("tags", [])
    ]
    retained_ids = {puzzle.get("id") for puzzle in retained}
    overlap = sorted(retained_ids & review_ids)
    if overlap:
        raise ValueError(f"review ids already exist outside this batch: {overlap}")

    decorated = [
        _decorate_review_puzzle(
            puzzle,
            records[puzzle["id"]],
            batch_id,
            args.max_review_solution_lines,
            selection_source,
        )
        for puzzle in review["puzzles"]
    ]
    for puzzle in retained:
        _curriculum_key(puzzle)
    established = []
    pending_review = []
    for puzzle in retained:
        if "review-status:expert-pending" in puzzle.get("tags", []):
            pending_review.append(puzzle)
        else:
            established.append(puzzle)
    pending_review.extend(decorated)
    pending_review.sort(key=_curriculum_key)
    combined = established + pending_review
    if len({puzzle.get("id") for puzzle in combined}) != len(combined):
        raise ValueError("combined pack contains duplicate puzzle ids")
    conflicts = find_position_conflicts(
        combined,
        minimum_distance=args.min_position_distance,
    )
    if conflicts:
        details = "\n".join(
            f"  distance {conflict.distance}: "
            f"{conflict.left_id} <> {conflict.right_id}"
            for conflict in conflicts
        )
        raise ValueError(
            "combined pack contains recognisably similar positions below "
            f"distance {args.min_position_distance}:\n{details}"
        )

    output_metadata = base.get("metadata")
    if not isinstance(output_metadata, dict):
        raise ValueError("base pack lacks metadata")
    output_metadata["version"] = args.version
    output_metadata["isOfficial"] = False
    output_metadata["name"] = "Malom Perfect DB Puzzles — Expert Review"
    output_metadata["description"] = (
        "Perfect DB-certified composed and replay-backed puzzles organised "
        "as a progressive curriculum. This review build includes certified "
        "shortlists pending Mill specialist assessment."
    )
    metadata_tags = output_metadata.get("tags")
    if not isinstance(metadata_tags, list):
        raise ValueError("base metadata tags must be a list")
    if selection_source == "engine-blunder":
        _append_unique(metadata_tags, "engine-blunder-corpus")
    else:
        _append_unique(metadata_tags, "perfect-db-certified")
    _append_unique(metadata_tags, "expert-review")

    review_batches = base.get("reviewBatches", [])
    if not isinstance(review_batches, list):
        raise ValueError("base reviewBatches must be a list when present")
    review_batches = [
        batch
        for batch in review_batches
        if not isinstance(batch, dict) or batch.get("id") != batch_id
    ]
    review_batches.append(
        {
            "id": batch_id,
            "status": "expert-pending",
            "puzzleCount": len(decorated),
            "selectionProvenance": review["selectionProvenance"],
        }
    )

    base["exportDate"] = review.get("exportDate", base.get("exportDate"))
    base["puzzleCount"] = len(combined)
    base["puzzles"] = combined
    base["reviewBatches"] = review_batches
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(
        (json.dumps(base, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    )
    print(
        f"[mill-review-merge] base={len(retained)} review={len(decorated)} "
        f"combined={len(combined)} batch={batch_id} out={output_path}"
    )


if __name__ == "__main__":
    main()
