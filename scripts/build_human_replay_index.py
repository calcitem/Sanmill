#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Reference builder for the anonymised HumanDB SQLite replay index.

The production full-corpus path is the versioned Rust command
``tgf mill replay-index``.  This independent Python implementation is kept
for small parity builds and schema/canonicalisation cross-checks.  The
existing HumanDB remains the aggregate position/move index; this sidecar
stores only the information needed to recover a legal game prefix for a
selected position.  Player names and other account data are never copied.

JSONL files are parsed by a small worker pool.  A single writer batches the
results into SQLite because SQLite deliberately serialises writes.  The
database is assembled under a ``.building`` suffix and is published only
after its integrity and row counts have been checked.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3
import time
from concurrent.futures import (
    FIRST_COMPLETED,
    ProcessPoolExecutor,
    wait,
)
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from extract_human_game_puzzle_candidates import (
    _state_key,
    _transform_notation,
)


SCHEMA_VERSION = "1"


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _chunks(values: list[Path], size: int) -> Iterable[list[Path]]:
    for start in range(0, len(values), size):
        yield values[start : start + size]


def _parse_batch(
    job: tuple[Path, list[Path]],
) -> tuple[int, list[tuple], list[tuple], int]:
    root, paths = job
    games: list[tuple] = []
    turns: list[tuple] = []
    skipped_non_human_records = 0
    for path in paths:
        relative_path = path.relative_to(root).as_posix()
        for source_line, raw_record in enumerate(
            path.read_bytes().splitlines(),
            start=1,
        ):
            if not raw_record.strip():
                continue
            game = json.loads(raw_record)
            if (
                not isinstance(game, dict)
                or game.get("source_type") != "human_vs_human"
            ):
                skipped_non_human_records += 1
                continue
            move_records = game.get("moves")
            if not isinstance(move_records, list):
                continue
            source_sha256 = hashlib.sha256(raw_record).hexdigest()
            parsed_turns: list[tuple] = []
            valid = True
            for logical_ply, move in enumerate(move_records, start=1):
                if not isinstance(move, dict):
                    valid = False
                    break
                notation = move.get("notation")
                board_fen = move.get("board_fen_before")
                move_type = move.get("type")
                if (
                    not isinstance(notation, str)
                    or not isinstance(board_fen, str)
                    or not isinstance(move_type, str)
                ):
                    valid = False
                    break
                try:
                    fields = board_fen.split("|")
                    if len(fields) != 4:
                        raise ValueError("board FEN must have four fields")
                    board = fields[0]
                    if (
                        len(board) != 24
                        or any(piece not in ".WB" for piece in board)
                        or fields[1] not in ("W", "B")
                    ):
                        raise ValueError("board FEN has invalid board fields")
                    placed_white = int(fields[2])
                    placed_black = int(fields[3])
                    side_to_move = 0 if fields[1] == "W" else 1
                    if (
                        move_type == "move"
                        and placed_white == 9
                        and placed_black == 9
                    ):
                        state_key, d4_operation = _state_key(board_fen)
                        canonical_notation = _transform_notation(
                            notation,
                            d4_operation,
                        )
                    else:
                        state_key = None
                        canonical_notation = None
                except (KeyError, TypeError, ValueError):
                    valid = False
                    break
                parsed_turns.append(
                    (
                        source_sha256,
                        logical_ply,
                        notation,
                        canonical_notation,
                        board_fen,
                        state_key,
                        move_type,
                        side_to_move,
                        placed_white,
                        placed_black,
                        board.count("W"),
                        board.count("B"),
                    )
                )
            if not valid:
                continue
            games.append(
                (
                    source_sha256,
                    relative_path,
                    source_line,
                    len(parsed_turns),
                )
            )
            turns.extend(parsed_turns)
    return len(paths), games, turns, skipped_non_human_records


def _create_schema(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        CREATE TABLE meta (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        ) WITHOUT ROWID;

        CREATE TABLE games (
            source_sha256      TEXT PRIMARY KEY,
            source_file        TEXT NOT NULL,
            source_line        INTEGER NOT NULL,
            logical_turn_count INTEGER NOT NULL
        ) WITHOUT ROWID;

        CREATE TABLE turns (
            source_sha256       TEXT NOT NULL,
            logical_ply         INTEGER NOT NULL,
            notation            TEXT NOT NULL,
            canonical_notation  TEXT,
            board_fen            TEXT NOT NULL,
            state_key           TEXT,
            move_type           TEXT NOT NULL,
            side_to_move        INTEGER NOT NULL
                                CHECK (side_to_move IN (0, 1)),
            placed_white        INTEGER NOT NULL,
            placed_black        INTEGER NOT NULL,
            white_on_board      INTEGER NOT NULL,
            black_on_board      INTEGER NOT NULL,
            PRIMARY KEY (source_sha256, logical_ply),
            FOREIGN KEY (source_sha256)
                REFERENCES games(source_sha256)
        ) WITHOUT ROWID;
        """
    )


def _insert_batch(
    connection: sqlite3.Connection,
    games: list[tuple],
    turns: list[tuple],
) -> None:
    connection.executemany(
        """
        INSERT OR IGNORE INTO games (
            source_sha256,
            source_file,
            source_line,
            logical_turn_count
        ) VALUES (?, ?, ?, ?)
        """,
        games,
    )
    connection.executemany(
        """
        INSERT OR IGNORE INTO turns (
            source_sha256,
            logical_ply,
            notation,
            canonical_notation,
            board_fen,
            state_key,
            move_type,
            side_to_move,
            placed_white,
            placed_black,
            white_on_board,
            black_on_board
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        turns,
    )


def _write_documentation(
    path: Path,
    *,
    database_name: str,
    database_path: Path,
    database_sha256: str,
    source_root: Path,
    built_at: str,
    source_file_count: int,
    game_count: int,
    turn_count: int,
    indexed_root_count: int,
    duplicate_game_records: int,
    skipped_non_human_records: int,
    workers: int,
    files_per_batch: int,
) -> None:
    path.write_bytes(
        f"""# Human Replay Index

## Purpose

`{database_name}` is an anonymised, reproducible replay sidecar for the
HumanDB source corpus. It allows a selected aggregate HumanDB position and
recorded move to be traced back to a complete legal game prefix without
rescanning the original JSONL files.

This database is a **candidate index**, not a game-theoretic oracle. Every
published puzzle must still be replayed by the production Rust/TGF rules and
certified independently against the configured Perfect DB.

## Provenance

- Built at (UTC): `{built_at}`
- Source root: `{source_root}`
- Source JSONL files: `{source_file_count}`
- Anonymised games: `{game_count}`
- Logical turns: `{turn_count}`
- Searchable movement roots: `{indexed_root_count}`
- Duplicate game records ignored: `{duplicate_game_records}`
- Invalid game records skipped: `0`
- Non-human records skipped: `{skipped_non_human_records}`
- Database SHA-256: `{database_sha256}`
- Schema version: `{SCHEMA_VERSION}`
- HumanDB state-key model: `sector-corrected-v1`

Player names and account identifiers are deliberately not copied. A source
game is identified only by the SHA-256 of its exact JSONL record, together
with its relative source file and line number for maintainer-side auditing.

## Relationship to Other Databases

- **HumanDB** aggregates positions, recorded moves and Malom annotations. It
  cheaply identifies possible human mistakes.
- **Human Replay Index** recovers the actual game and preceding turns for a
  selected HumanDB row.
- **Perfect DB** supplies the final exact W/D/L and distance proof used by the
  Rust puzzle generator.

The databases are intentionally separate so that aggregate annotations can
be refreshed without changing immutable replay evidence.

## Schema

### `meta`

| Column | Type | Meaning |
| --- | --- | --- |
| `key` | `TEXT` | Metadata key; primary key |
| `value` | `TEXT` | Metadata value |

Recorded keys are `schema_version`, `build_date`, `source_root`,
`source_file_count`, `game_count`, `turn_count`,
`indexed_root_count`, `duplicate_game_records`, `invalid_game_records`,
`skipped_non_human_records`, `anonymised` and `state_key_model`.

### `games`

| Column | Type | Meaning |
| --- | --- | --- |
| `source_sha256` | `TEXT` | SHA-256 of the exact source JSON row; primary key |
| `source_file` | `TEXT` | Source path relative to the corpus root |
| `source_line` | `INTEGER` | One-based JSONL line number |
| `logical_turn_count` | `INTEGER` | Number of complete logical turns |

### `turns`

| Column | Type | Meaning |
| --- | --- | --- |
| `source_sha256` | `TEXT` | Parent game; foreign key to `games` |
| `logical_ply` | `INTEGER` | One-based complete-turn number |
| `notation` | `TEXT` | Recorded Sanmill turn notation |
| `canonical_notation` | `TEXT` | Notation after HumanDB's D4 canonicalisation; `NULL` before movement |
| `board_fen` | `TEXT` | Position immediately before the turn |
| `state_key` | `TEXT` | HumanDB-compatible key; `NULL` until both sides have placed nine pieces |
| `move_type` | `TEXT` | Source move type |
| `side_to_move` | `INTEGER` | `0` for White, `1` for Black |
| `placed_white` | `INTEGER` | White pieces placed so far |
| `placed_black` | `INTEGER` | Black pieces placed so far |
| `white_on_board` | `INTEGER` | White pieces currently on the board |
| `black_on_board` | `INTEGER` | Black pieces currently on the board |

The primary key is (`source_sha256`, `logical_ply`). The following secondary
indexes are present:

- `turns_by_state_and_move` on (`state_key`, `canonical_notation`) for joining
  HumanDB candidates to replay evidence.
- `turns_by_material_and_ply` for movement-root material and ply filters.

## Symmetry Convention

HumanDB matching uses its eight D4 board symmetries. The additional
outer/inner-ring swap is applied only when a puzzle is exported, giving
Sanmill's deterministic 16 presentation transforms. Transformed copies are
never duplicated in this database, and final puzzle deduplication uses the
canonical ring-16 position key.

## Example Query

After attaching HumanDB as schema `human`, candidate missed wins can be found
with:

```sql
SELECT r.source_sha256, r.logical_ply, r.notation, p.malom_dtw
FROM turns AS r
JOIN human.positions AS p
  ON p.state_key = r.state_key
JOIN human.moves AS m
  ON m.state_key = r.state_key
 AND m.notation = r.canonical_notation
WHERE p.malom_wdl = 'W'
  AND p.canonical_winning_move IS NOT NULL
  AND r.canonical_notation <> p.canonical_winning_move
  AND m.malom_wdl_after IN ('D', 'W');
```

`malom_wdl_after` is only a mining prior. Rust/TGF replays the prefix and
recorded turn, then re-queries Perfect DB before accepting a puzzle.

## Rebuild

The index was built with:

```powershell
python scripts/build_human_replay_index.py `
  --games-dir "{source_root}" `
  --out "{database_path}" `
  --workers {workers} `
  --files-per-batch {files_per_batch}
```

The builder creates the database under a `.building` suffix, checks its row
counts and `PRAGMA integrity_check`, and only then publishes the database and
this document. Existing outputs are never overwritten automatically.
""".encode("utf-8")
    )


def build_index(args: argparse.Namespace) -> None:
    source_root = Path(args.games_dir).resolve()
    output = Path(args.out).resolve()
    building = output.with_name(f"{output.name}.building")
    documentation = output.with_name(f"{output.stem}.README.md")
    documentation_building = documentation.with_name(
        f"{documentation.name}.building"
    )
    if output.exists():
        raise SystemExit(
            f"{output} already exists; choose a new path or remove it explicitly"
        )
    if documentation.exists():
        raise SystemExit(
            f"{documentation} already exists; choose a new output name"
        )
    if building.exists():
        raise SystemExit(
            f"{building} already exists from an earlier build; "
            "inspect or remove it explicitly"
        )
    if documentation_building.exists():
        raise SystemExit(
            f"{documentation_building} already exists from an earlier build; "
            "inspect or remove it explicitly"
        )

    files = sorted(source_root.rglob("*.jsonl"))
    if args.max_files > 0:
        files = files[: args.max_files]
    if not files:
        raise SystemExit("no JSONL source files were found")
    output.parent.mkdir(parents=True, exist_ok=True)

    connection = sqlite3.connect(building)
    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute("PRAGMA journal_mode = OFF")
    connection.execute("PRAGMA synchronous = OFF")
    connection.execute("PRAGMA temp_store = MEMORY")
    connection.execute(f"PRAGMA cache_size = {-args.cache_mib * 1024}")
    _create_schema(connection)
    connection.execute("BEGIN")

    started = time.monotonic()
    processed_files = 0
    parsed_game_count = 0
    parsed_turn_count = 0
    skipped_non_human_records = 0
    jobs = iter(
        (source_root, batch)
        for batch in _chunks(files, args.files_per_batch)
    )
    with ProcessPoolExecutor(max_workers=args.workers) as executor:
        pending = set()
        for _ in range(args.workers * 2):
            try:
                pending.add(executor.submit(_parse_batch, next(jobs)))
            except StopIteration:
                break
        while pending:
            completed, pending = wait(
                pending,
                return_when=FIRST_COMPLETED,
            )
            for future in completed:
                (
                    batch_file_count,
                    games,
                    turns,
                    batch_skipped_non_human,
                ) = future.result()
                try:
                    pending.add(executor.submit(_parse_batch, next(jobs)))
                except StopIteration:
                    pass
                _insert_batch(connection, games, turns)
                processed_files += batch_file_count
                parsed_game_count += len(games)
                parsed_turn_count += len(turns)
                skipped_non_human_records += batch_skipped_non_human
                if (
                    processed_files == len(files)
                    or processed_files % args.progress_every
                    < args.files_per_batch
                ):
                    elapsed = max(time.monotonic() - started, 0.001)
                    print(
                        "[human-replay-index] "
                        f"files={processed_files}/{len(files)} "
                        f"parsed-games={parsed_game_count} "
                        f"parsed-turns={parsed_turn_count} "
                        f"rate={processed_files / elapsed:.0f} files/s",
                        flush=True,
                    )

    connection.commit()
    game_count = connection.execute(
        "SELECT COUNT(*) FROM games"
    ).fetchone()[0]
    turn_count = connection.execute(
        "SELECT COUNT(*) FROM turns"
    ).fetchone()[0]
    indexed_root_count = connection.execute(
        "SELECT COUNT(*) FROM turns WHERE state_key IS NOT NULL"
    ).fetchone()[0]
    duplicate_games = parsed_game_count - game_count

    built_at = datetime.now(timezone.utc).isoformat()
    connection.executemany(
        "INSERT INTO meta (key, value) VALUES (?, ?)",
        (
            ("schema_version", SCHEMA_VERSION),
            ("build_date", built_at),
            ("source_root", str(source_root)),
            ("source_file_count", str(len(files))),
            ("game_count", str(game_count)),
            ("turn_count", str(turn_count)),
            ("indexed_root_count", str(indexed_root_count)),
            ("duplicate_game_records", str(duplicate_games)),
            ("invalid_game_records", "0"),
            (
                "skipped_non_human_records",
                str(skipped_non_human_records),
            ),
            ("anonymised", "true"),
            ("state_key_model", "sector-corrected-v1"),
        ),
    )
    connection.commit()

    print("[human-replay-index] creating lookup index", flush=True)
    connection.execute(
        """
        CREATE INDEX turns_by_state_and_move
        ON turns(state_key, canonical_notation)
        WHERE state_key IS NOT NULL
        """
    )
    connection.execute(
        """
        CREATE INDEX turns_by_material_and_ply
        ON turns(logical_ply, white_on_board, black_on_board)
        WHERE state_key IS NOT NULL
        """
    )
    connection.execute("ANALYZE")
    connection.commit()

    actual_games = connection.execute(
        "SELECT COUNT(*) FROM games"
    ).fetchone()[0]
    actual_turns = connection.execute(
        "SELECT COUNT(*) FROM turns"
    ).fetchone()[0]
    integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
    connection.close()
    if (
        actual_games != game_count
        or actual_turns != turn_count
        or integrity != "ok"
    ):
        raise RuntimeError(
            "replay index validation failed: "
            f"games={actual_games}/{game_count}, "
            f"turns={actual_turns}/{turn_count}, integrity={integrity}"
        )

    database_sha256 = _sha256_file(building)
    _write_documentation(
        documentation_building,
        database_name=output.name,
        database_path=output,
        database_sha256=database_sha256,
        source_root=source_root,
        built_at=built_at,
        source_file_count=len(files),
        game_count=game_count,
        turn_count=turn_count,
        indexed_root_count=indexed_root_count,
        duplicate_game_records=duplicate_games,
        skipped_non_human_records=skipped_non_human_records,
        workers=args.workers,
        files_per_batch=args.files_per_batch,
    )
    os.replace(building, output)
    os.replace(documentation_building, documentation)
    elapsed = time.monotonic() - started
    print(
        "[human-replay-index] "
        f"done files={len(files)} games={game_count} turns={turn_count} "
        f"indexed-roots={indexed_root_count} "
        f"seconds={elapsed:.1f} out={output} docs={documentation}",
        flush=True,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--games-dir", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--files-per-batch", type=int, default=64)
    parser.add_argument("--progress-every", type=int, default=5000)
    parser.add_argument("--cache-mib", type=int, default=256)
    parser.add_argument("--max-files", type=int, default=0)
    args = parser.parse_args()
    if args.workers < 1:
        parser.error("--workers must be positive")
    if args.files_per_batch < 1:
        parser.error("--files-per-batch must be positive")
    if args.progress_every < args.files_per_batch:
        parser.error("--progress-every must be at least --files-per-batch")
    if args.cache_mib < 16:
        parser.error("--cache-mib must be at least 16")
    if args.max_files < 0:
        parser.error("--max-files must not be negative")
    return args


def main() -> None:
    build_index(parse_args())


if __name__ == "__main__":
    main()
