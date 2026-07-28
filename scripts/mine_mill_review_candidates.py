#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Run reproducible Perfect DB mining profiles for editorial review.

The profiles deliberately produce review candidates, not automatic additions
to the built-in pack. Rust/TGF still checks every complete logical first turn
and Perfect DB remains the W/D/L and distance authority. The caller supplies
one run-specific exclusion file containing the current pack and all editorial
reference roots.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


@dataclass(frozen=True)
class Profile:
    solver_pieces: tuple[int, int]
    defender_pieces: tuple[int, int]
    depth: tuple[int, int]
    max_solutions: int
    min_mistakes: int
    max_piece_diff: int
    min_solve_depth: int
    require_trap: bool = False


PROFILES = {
    # Material-odds profiles for six- or seven-piece attacking
    # constructions against four mobile defenders.
    "material-odds-6v4": Profile((6, 6), (4, 4), (3, 15), 2, 4, 2, 4),
    "material-odds-7v4": Profile((7, 7), (4, 4), (3, 15), 2, 4, 3, 4),
    # The defending side already flies. These roots favour nets whose
    # official line exercises the rule-sensitive flying phase.
    "against-flying": Profile((4, 6), (3, 3), (4, 24), 2, 4, 3, 4),
    # A sharp first decision with exactly one shortest solution and a
    # tempting mill-closing mistake.
    "precision-trap": Profile((3, 7), (3, 7), (3, 20), 1, 4, 1, 4, True),
    # Longer plans, including blockade candidates, which a short-distance
    # filter would systematically miss.
    "long-endgame": Profile((4, 7), (4, 7), (16, 31), 2, 4, 1, 6),
}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _profile_command(
    args: argparse.Namespace,
    name: str,
    profile: Profile,
    output: Path,
    seed: int,
) -> list[str]:
    command = [
        str(Path(args.tgf).resolve()),
        "mill",
        "puzzle-gen",
        "--db",
        str(Path(args.db).resolve()),
        "--out",
        str(output),
        "--exclude-fens",
        str(Path(args.exclusions).resolve()),
        "--phase",
        "moving",
        "--side",
        "random",
        "--min-solver-pieces",
        str(profile.solver_pieces[0]),
        "--max-solver-pieces",
        str(profile.solver_pieces[1]),
        "--min-defender-pieces",
        str(profile.defender_pieces[0]),
        "--max-defender-pieces",
        str(profile.defender_pieces[1]),
        "--min-depth",
        str(profile.depth[0]),
        "--max-depth",
        str(profile.depth[1]),
        "--max-solutions",
        str(profile.max_solutions),
        "--min-mistakes",
        str(profile.min_mistakes),
        "--max-piece-diff",
        str(profile.max_piece_diff),
        "--min-solve-depth",
        str(profile.min_solve_depth),
        "--count",
        str(args.count_per_profile),
        "--max-attempts",
        str(args.max_attempts),
        "--cache",
        str(args.cache),
        "--seed",
        f"0x{seed:016x}",
        "--author",
        "Sanmill offline review miner",
        "--pack-id",
        f"editorial-review-{name}",
        "--pack-name",
        f"Expert review: {name}",
        "--pack-description",
        "Offline review candidates; not approved for the built-in pack.",
        "--review-pack",
    ]
    if profile.require_trap:
        command.append("--require-trap")
    return command


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tgf", required=True, help="path to tgf or tgf.exe")
    parser.add_argument("--db", required=True, help="full Perfect DB directory")
    parser.add_argument(
        "--exclusions",
        required=True,
        help="combined current-pack and editorial-reference exclusion FENs",
    )
    parser.add_argument("--out-dir", required=True)
    parser.add_argument(
        "--profiles",
        default=",".join(PROFILES),
        help=f"comma-separated subset of: {', '.join(PROFILES)}",
    )
    parser.add_argument("--count-per-profile", type=int, default=12)
    parser.add_argument("--max-attempts", type=int, default=120_000)
    parser.add_argument("--cache", type=int, default=64)
    parser.add_argument(
        "--seed",
        type=lambda value: int(value, 0),
        default=0x4558_5045_5254_2026,
    )
    args = parser.parse_args()
    selected = [value.strip() for value in args.profiles.split(",") if value.strip()]
    unknown = sorted(set(selected) - PROFILES.keys())
    if unknown:
        parser.error(f"unknown profiles: {', '.join(unknown)}")
    if not selected:
        parser.error("--profiles must select at least one profile")
    if args.count_per_profile < 1:
        parser.error("--count-per-profile must be positive")
    if args.max_attempts < 1:
        parser.error("--max-attempts must be positive")
    if args.cache < 1:
        parser.error("--cache must be positive")
    args.selected_profiles = selected
    return args


def main() -> None:
    args = parse_args()
    tgf_path = Path(args.tgf).resolve()
    database_path = Path(args.db).resolve()
    exclusions_path = Path(args.exclusions).resolve()
    for path, label in [
        (tgf_path, "tgf executable"),
        (database_path, "Perfect DB"),
        (exclusions_path, "exclusion record"),
    ]:
        if not path.exists():
            raise FileNotFoundError(f"{label} does not exist: {path}")

    output_dir = Path(args.out_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    runs = []
    for index, name in enumerate(args.selected_profiles):
        profile = PROFILES[name]
        output = output_dir / f"{name}.sanmill_puzzles"
        seed = (args.seed + index * 0x9E37_79B9_7F4A_7C15) & 0xFFFF_FFFF_FFFF_FFFF
        command = _profile_command(args, name, profile, output, seed)
        print(f"[review-miner] profile={name} out={output}", flush=True)
        completed = subprocess.run(command, check=False)
        if completed.returncode != 0:
            raise SystemExit(
                f"profile {name} failed with exit code {completed.returncode}"
            )
        package = json.loads(output.read_text(encoding="utf-8-sig"))
        runs.append(
            {
                "profile": name,
                "seed": seed,
                "configuration": {
                    "solverPieces": profile.solver_pieces,
                    "defenderPieces": profile.defender_pieces,
                    "winIn": profile.depth,
                    "maxSolutions": profile.max_solutions,
                    "minimumMistakes": profile.min_mistakes,
                    "maximumSolverMaterialAdvantage": profile.max_piece_diff,
                    "minimumProbeDepth": profile.min_solve_depth,
                    "requiresTemptingMillTrap": profile.require_trap,
                },
                "candidateCount": package["puzzleCount"],
                "output": output.name,
                "outputSha256": _sha256(output),
            }
        )

    manifest = {
        "formatVersion": "1.0",
        "purpose": "editorial-review-candidates",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "perfectDbPath": str(database_path),
        "exclusionsSha256": _sha256(exclusions_path),
        "runs": runs,
    }
    manifest_path = output_dir / "manifest.json"
    manifest_path.write_bytes(
        (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    )
    print(f"[review-miner] manifest={manifest_path}")


if __name__ == "__main__":
    main()
