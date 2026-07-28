#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Mine review candidates from the reproducible Mill engine-error corpus.

The JSONL inputs are the FEN-bearing working records used to build the
correction patch. They provide a useful discovery prior: a configured engine
made a measured W/D/L error at a known search depth. They are not solution
proofs. Rust/TGF rebuilds every root, Perfect DB classifies every complete
logical turn, and the publication gates below favour quiet, non-obvious,
manageable studies.

Profiles may run concurrently with ``--jobs``. Each subprocess owns its
database reader and writes a separate candidate pack; no shared mutable
candidate state is used.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path


@dataclass(frozen=True)
class Profile:
    source_group: str
    phase: str
    solver_pieces: tuple[int, int]
    defender_pieces: tuple[int, int]
    depth: tuple[int, int]
    mine_min_severity: int
    mine_min_mass: float
    mine_min_depth_used: int
    mine_min_placements: int
    max_solutions: int
    max_exported_lines: int
    min_mistakes: int
    min_non_winning_turns: int
    max_piece_diff: int
    min_solve_depth: int
    require_quiet_first_move: bool
    require_trap: bool = False
    required_motif: str | None = None


PROFILES = {
    # Balanced-material studies whose source engine lost a full two W/D/L
    # units. "Expert" survives all depth-2/4/6/8 human-difficulty probes.
    "balanced-advanced": Profile(
        "moving", "moving", (4, 7), (4, 7), (4, 15), 2, 0.0, 10, 0,
        1, 32, 6, 4, 1, 5, True,
    ),
    "balanced-expert": Profile(
        "moving", "moving", (4, 7), (4, 7), (4, 15), 2, 0.0, 10, 0,
        1, 32, 6, 4, 1, 9, True,
    ),
    # Material-odds shapes observed repeatedly in specialist review
    # material. A one-unit source error is still a genuine missed win/draw
    # boundary and leaves enough roots for exact quality gates to decide.
    "material-odds-6v4": Profile(
        "moving", "moving", (6, 6), (4, 4), (4, 15), 1, 0.0, 8, 0,
        1, 32, 6, 4, 2, 5, True,
    ),
    "material-odds-7v4": Profile(
        "moving", "moving", (7, 7), (4, 4), (4, 15), 1, 0.0, 8, 0,
        1, 32, 6, 4, 3, 5, True,
    ),
    "against-flying": Profile(
        "moving", "moving", (4, 7), (3, 3), (4, 24), 1, 0.0, 8, 0,
        1, 32, 6, 4, 4, 5, True,
    ),
    # Twelve placements are six complete alternating rounds. Earlier roots
    # remain suitable for a separate foundations curriculum but are not
    # part of this advanced review profile.
    "late-placement": Profile(
        "placing", "placing", (3, 8), (3, 8), (4, 15), 2, 1.0, 8, 12,
        1, 32, 8, 4, 1, 5, True,
    ),
    # Deliberately not part of the default set: the conjunction is rare and
    # often produces a broad later strategy tree. Keep it available for
    # specialist review without weakening its exact or shallow-search gates.
    "hidden-trap-review": Profile(
        "moving", "moving", (4, 7), (4, 7), (4, 15), 2, 1.0, 10, 0,
        1, 128, 6, 4, 1, 9, True, True,
    ),
    # Strategy-led specialist searches. The source corpus supplies positions
    # in which a real engine made a measured error; the named Rust predicate
    # must then hold on every shortest Perfect DB-certified winning turn.
    # These remain opt-in until their review yield is characterised.
    "allow-mill-review": Profile(
        "moving", "moving", (4, 7), (4, 7), (4, 24), 1, 0.0, 8, 0,
        1, 128, 6, 4, 1, 7, True, False, "allow-mill",
    ),
    "mobility-squeeze-review": Profile(
        "moving", "moving", (4, 7), (4, 7), (4, 15), 1, 0.0, 8, 0,
        1, 32, 6, 4, 1, 7, True, False, "mobility-squeeze",
    ),
    "junction-release-review": Profile(
        "moving", "moving", (4, 7), (4, 7), (4, 15), 1, 0.0, 8, 0,
        1, 32, 6, 4, 1, 7, True, False, "junction-release",
    ),
    "mill-recovery-review": Profile(
        "moving", "moving", (4, 7), (4, 7), (4, 15), 1, 0.0, 8, 0,
        1, 32, 6, 4, 1, 7, True, False, "mill-recovery",
    ),
    "right-angle-threat-review": Profile(
        "moving", "moving", (4, 7), (4, 7), (4, 15), 1, 0.0, 8, 0,
        1, 32, 6, 4, 1, 7, True, False, "right-angle-threat",
    ),
    "ring-transfer-review": Profile(
        "moving", "moving", (4, 7), (4, 7), (4, 15), 1, 0.0, 8, 0,
        1, 32, 6, 4, 1, 7, True, False, "ring-transfer",
    ),
}

DEFAULT_PROFILES = (
    "balanced-advanced",
    "balanced-expert",
    "material-odds-6v4",
    "material-odds-7v4",
    "against-flying",
    "late-placement",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _resolved_csv(value: str, label: str) -> tuple[Path, ...]:
    paths = tuple(
        sorted(
            {
                Path(raw.strip()).resolve()
                for raw in value.split(",")
                if raw.strip()
            }
        )
    )
    if not paths:
        raise ValueError(f"{label} did not name any files")
    for path in paths:
        if not path.is_file():
            raise FileNotFoundError(f"{label} does not exist: {path}")
    return paths


def _source_manifest(paths: tuple[Path, ...]) -> str:
    digests = sorted(bytes.fromhex(_sha256(path)) for path in paths)
    manifest = hashlib.sha256()
    manifest.update(b"sanmill.mill-mine-puzzle-source.v1\0")
    for digest in digests:
        manifest.update(len(digest).to_bytes(8, "little"))
        manifest.update(digest)
    return manifest.hexdigest()


def _root_identity(fen: str) -> tuple[str, ...]:
    fields = fen.split()
    if len(fields) < 8:
        raise ValueError(f"invalid Mill FEN: {fen}")
    return tuple(fields[:8])


def _recorded_root_identities(path: Path) -> set[tuple[str, ...]]:
    identities = set()
    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8-sig").splitlines(),
        start=1,
    ):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            identities.add(_root_identity(line))
        except ValueError as error:
            raise ValueError(f"{path}:{line_number}: {error}") from error
    if not identities:
        raise ValueError(f"{path} contains no exclusion roots")
    return identities


def _base_pack_record(
    path: Path, excluded: set[tuple[str, ...]]
) -> dict[str, object]:
    package = json.loads(path.read_text(encoding="utf-8-sig"))
    puzzles = package.get("puzzles")
    if not isinstance(puzzles, list):
        raise ValueError(f"{path} has no puzzles array")
    if package.get("puzzleCount") != len(puzzles):
        raise ValueError(f"{path} has a mismatched puzzleCount")
    roots = []
    for index, puzzle in enumerate(puzzles, start=1):
        fen = puzzle.get("initialPosition") if isinstance(puzzle, dict) else None
        if not isinstance(fen, str):
            raise ValueError(f"{path} puzzle {index} has no initialPosition")
        roots.append(_root_identity(fen))
    missing = [root for root in roots if root not in excluded]
    if missing:
        raise ValueError(
            f"{path} has {len(missing)} roots absent from the exclusion file; "
            "rebuild the collision list against the current built-in pack"
        )
    return {
        "path": str(path),
        "puzzleCount": len(puzzles),
        "sha256": _sha256(path),
    }


def _profile_command(
    args: argparse.Namespace,
    name: str,
    profile: Profile,
    sources: tuple[Path, ...],
    output: Path,
    seed: int,
) -> list[str]:
    command = [
        str(args.tgf_path),
        "mill",
        "puzzle-gen",
        "--db",
        str(args.database_path),
        "--out",
        str(output),
        "--exclude-fens",
        str(args.exclusions_path),
        "--mine-entry-file",
        ",".join(str(path) for path in sources),
        "--mine-candidate-limit",
        str(args.mine_candidate_limit),
        "--mine-per-shape-limit",
        str(args.mine_per_shape_limit),
        "--mine-min-severity",
        str(profile.mine_min_severity),
        "--mine-min-mass",
        str(profile.mine_min_mass),
        "--mine-min-depth-used",
        str(profile.mine_min_depth_used),
        "--mine-min-placements",
        str(profile.mine_min_placements),
        "--phase",
        profile.phase,
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
        "--max-exported-lines",
        str(profile.max_exported_lines),
        "--min-mistakes",
        str(profile.min_mistakes),
        "--min-non-winning-turns",
        str(profile.min_non_winning_turns),
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
        f"engine-blunder-review-{name}",
        "--pack-name",
        f"Engine-blunder review: {name}",
        "--pack-description",
        "Offline review candidates; not approved for the built-in pack.",
        "--review-pack",
    ]
    if profile.require_quiet_first_move:
        command.append("--require-quiet-first-move")
    if profile.require_trap:
        command.append("--require-trap")
    if profile.required_motif is not None:
        command.extend(("--motif", profile.required_motif))
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
    parser.add_argument(
        "--required-base-pack",
        action="append",
        default=[],
        help=(
            "puzzle pack which must already be present in --exclusions; "
            "defaults to Sanmill's current built-in pack"
        ),
    )
    parser.add_argument(
        "--moving-entry-files",
        default="",
        help="comma-separated moving/endgame/closed-loop mine JSONLs",
    )
    parser.add_argument(
        "--placing-entry-files",
        default="",
        help="comma-separated opening/placing mine JSONLs",
    )
    parser.add_argument("--out-dir", required=True)
    parser.add_argument(
        "--profiles",
        default=",".join(DEFAULT_PROFILES),
        help=f"comma-separated subset of: {', '.join(PROFILES)}",
    )
    parser.add_argument("--count-per-profile", type=int, default=20)
    parser.add_argument("--mine-candidate-limit", type=int, default=20_000)
    parser.add_argument("--mine-per-shape-limit", type=int, default=4_096)
    parser.add_argument("--max-attempts", type=int, default=20_000)
    parser.add_argument("--cache", type=int, default=128)
    parser.add_argument(
        "--jobs",
        type=int,
        default=1,
        help="independent profile subprocesses to run concurrently",
    )
    parser.add_argument(
        "--seed",
        type=lambda value: int(value, 0),
        default=0x454E_4749_4E45_2026,
    )
    args = parser.parse_args()

    selected = [value.strip() for value in args.profiles.split(",") if value.strip()]
    unknown = sorted(set(selected) - PROFILES.keys())
    if unknown:
        parser.error(f"unknown profiles: {', '.join(unknown)}")
    if not selected:
        parser.error("--profiles must select at least one profile")
    for name in (
        "count_per_profile",
        "mine_candidate_limit",
        "mine_per_shape_limit",
        "max_attempts",
        "cache",
        "jobs",
    ):
        if getattr(args, name) < 1:
            parser.error(f"--{name.replace('_', '-')} must be positive")

    args.selected_profiles = selected
    args.tgf_path = Path(args.tgf).resolve()
    args.database_path = Path(args.db).resolve()
    args.exclusions_path = Path(args.exclusions).resolve()
    for path, label in (
        (args.tgf_path, "tgf executable"),
        (args.database_path, "Perfect DB"),
        (args.exclusions_path, "exclusion record"),
    ):
        if not path.exists():
            parser.error(f"{label} does not exist: {path}")

    default_base_pack = (
        Path(__file__).resolve().parents[1]
        / "src"
        / "ui"
        / "flutter_app"
        / "assets"
        / "puzzles"
        / "malom_perfect_db_puzzles.sanmill_puzzles"
    )
    raw_base_packs = args.required_base_pack or [str(default_base_pack)]
    args.required_base_pack_paths = tuple(
        Path(raw_path).resolve() for raw_path in raw_base_packs
    )
    for path in args.required_base_pack_paths:
        if not path.is_file():
            parser.error(f"required base pack does not exist: {path}")
    try:
        excluded = _recorded_root_identities(args.exclusions_path)
        args.base_pack_records = [
            _base_pack_record(path, excluded)
            for path in args.required_base_pack_paths
        ]
    except (ValueError, json.JSONDecodeError) as error:
        parser.error(str(error))

    required_groups = {PROFILES[name].source_group for name in selected}
    source_groups: dict[str, tuple[Path, ...]] = {}
    for group, value in (
        ("moving", args.moving_entry_files),
        ("placing", args.placing_entry_files),
    ):
        if group in required_groups:
            try:
                source_groups[group] = _resolved_csv(
                    value, f"--{group}-entry-files"
                )
            except (ValueError, FileNotFoundError) as error:
                parser.error(str(error))
    args.source_groups = source_groups
    return args


def _run_profile(
    args: argparse.Namespace,
    output_dir: Path,
    index: int,
    name: str,
) -> tuple[int, dict[str, object]]:
    profile = PROFILES[name]
    output = output_dir / f"{name}.sanmill_puzzles"
    seed = (args.seed + index * 0x9E37_79B9_7F4A_7C15) & 0xFFFF_FFFF_FFFF_FFFF
    sources = args.source_groups[profile.source_group]
    command = _profile_command(args, name, profile, sources, output, seed)
    print(f"[engine-blunder-miner] profile={name} out={output}", flush=True)
    completed = subprocess.run(command, check=False)
    if completed.returncode != 0:
        raise RuntimeError(
            f"profile {name} failed with exit code {completed.returncode}"
        )
    package = json.loads(output.read_text(encoding="utf-8-sig"))
    return index, {
        "profile": name,
        "seed": seed,
        "configuration": asdict(profile),
        "candidateCount": package["puzzleCount"],
        "output": output.name,
        "outputSha256": _sha256(output),
    }


def main() -> None:
    args = parse_args()
    output_dir = Path(args.out_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    indexed_runs: list[tuple[int, dict[str, object]]] = []
    if args.jobs == 1:
        for index, name in enumerate(args.selected_profiles):
            indexed_runs.append(_run_profile(args, output_dir, index, name))
    else:
        with ThreadPoolExecutor(max_workers=args.jobs) as executor:
            futures = {
                executor.submit(_run_profile, args, output_dir, index, name): name
                for index, name in enumerate(args.selected_profiles)
            }
            for future in as_completed(futures):
                indexed_runs.append(future.result())
    runs = [run for _, run in sorted(indexed_runs)]

    source_manifests = {
        group: {
            "fileCount": len(paths),
            "manifestSha256": _source_manifest(paths),
        }
        for group, paths in args.source_groups.items()
    }
    manifest = {
        "formatVersion": "1.0",
        "purpose": "engine-blunder-review-candidates",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "perfectDbPath": str(args.database_path),
        "exclusionsSha256": _sha256(args.exclusions_path),
        "requiredBasePacks": args.base_pack_records,
        "sourceGroups": source_manifests,
        "parallelProfileJobs": args.jobs,
        "runs": runs,
    }
    manifest_path = output_dir / "manifest.json"
    manifest_path.write_bytes(
        (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    )
    print(f"[engine-blunder-miner] manifest={manifest_path}")


if __name__ == "__main__":
    main()
