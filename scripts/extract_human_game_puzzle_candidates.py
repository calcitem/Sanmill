#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Extract replay-backed Mill puzzle roots from HumanDB source games.

The HumanDB SQLite file is used only as a cheap candidate prior: annotated
winning roots whose recorded human turn differs from its canonical winning
turn are retained. Rust/TGF subsequently replays every transformed history,
checks the recorded turn, and asks Perfect DB whether the turn really threw
away a forced win.

Each retained game prefix is transformed by one deterministic pseudo-random
member of Sanmill's 16 board automorphisms. Canonical ring-16 keys are still
used for deduplication, so transforms change presentation without multiplying
one puzzle into several apparent candidates. When a replay reference record
is supplied, the deterministic choice advances through the ring-16 orbit
until the raw board differs from every recorded presentation. Other editorial
reference roots are rejected before export.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
from pathlib import Path
from typing import Iterable


NMM_POSITIONS = (
    "a7",
    "d7",
    "g7",
    "g4",
    "g1",
    "d1",
    "a1",
    "a4",
    "b6",
    "d6",
    "f6",
    "f4",
    "f2",
    "d2",
    "b2",
    "b4",
    "c5",
    "d5",
    "e5",
    "e4",
    "e3",
    "d3",
    "c3",
    "c4",
)
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
NMM_INDEX = {label: index for index, label in enumerate(NMM_POSITIONS)}
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
    if not 0 <= operation < 16:
        raise ValueError(f"invalid ring-16 operation {operation}")
    x, y = COORDINATES[label]
    if operation >= 8:
        x, y = _ring_swap(x, y)
    return LABEL_BY_COORDINATE[_dihedral(x, y, operation % 8)]


def _transform_notation(notation: str, operation: int) -> str:
    base, separator, capture = notation.partition("x")
    capture_suffix = (
        f"x{_transform_label(capture, operation)}" if separator else ""
    )
    if not base:
        return capture_suffix
    if "-" in base:
        source, target = base.split("-", maxsplit=1)
        return (
            f"{_transform_label(source, operation)}-"
            f"{_transform_label(target, operation)}{capture_suffix}"
        )
    return f"{_transform_label(base, operation)}{capture_suffix}"


def _transform_board(board: str, operation: int) -> str:
    transformed = ["."] * 24
    for index, piece in enumerate(board):
        target = _transform_label(NMM_POSITIONS[index], operation)
        transformed[NMM_INDEX[target]] = piece
    return "".join(transformed)


def _canonical_d4(board: str) -> tuple[str, int]:
    images = [(_transform_board(board, operation), operation) for operation in range(8)]
    return min(images)


def _state_key(board_fen: str) -> tuple[str, int]:
    fields = board_fen.split("|")
    if len(fields) != 4:
        raise ValueError("board_fen_before must contain four pipe fields")
    board, turn, placed_white_text, placed_black_text = fields
    if len(board) != 24 or any(piece not in ".WB" for piece in board):
        raise ValueError("board_fen_before has an invalid board")
    if turn not in ("W", "B"):
        raise ValueError("board_fen_before has an invalid side")
    placed_white = int(placed_white_text)
    placed_black = int(placed_black_text)
    on_white = board.count("W")
    on_black = board.count("B")
    side_on_board = on_white if turn == "W" else on_black
    side_placed = placed_white if turn == "W" else placed_black
    phase = (
        "place"
        if side_placed < 9
        else ("fly" if side_on_board <= 3 else "move")
    )
    canonical, d4_operation = _canonical_d4(board)
    return (
        f"{canonical}|{turn}|{phase}|{placed_white}|{placed_black}|"
        f"{on_white}|{on_black}",
        d4_operation,
    )


def _bitboards(board: str, operation: int) -> tuple[int, int]:
    white_bits = 0
    black_bits = 0
    for piece, label in zip(board, NMM_POSITIONS, strict=True):
        transformed = _transform_label(label, operation)
        bit = 1 << PERFECT_INDEX[transformed]
        if piece == "W":
            white_bits |= bit
        elif piece == "B":
            black_bits |= bit
    return white_bits, black_bits


def _transform_bits(bits: int, operation: int) -> int:
    transformed = 0
    for source, label in enumerate(PERFECT_LABELS):
        if bits & (1 << source):
            transformed |= 1 << PERFECT_INDEX[
                _transform_label(label, operation)
            ]
    return transformed


def _canonical_ring16(
    white_bits: int, black_bits: int, side_to_move: int
) -> int:
    return min(
        _transform_bits(white_bits, operation)
        | (_transform_bits(black_bits, operation) << 24)
        | (side_to_move << 56)
        for operation in range(16)
    )


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _file_order(path: Path, seed: int) -> bytes:
    return hashlib.sha256(f"{seed}:{path.name}".encode()).digest()


def _load_reference_presentations(
    raw_path: str,
) -> tuple[dict[int, set[tuple[int, int, int]]], str | None, int]:
    if not raw_path:
        return {}, None, 0
    path = Path(raw_path).resolve()
    references: dict[int, set[tuple[int, int, int]]] = {}
    raw_count = 0
    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8-sig").splitlines(),
        start=1,
    ):
        line = " ".join(raw_line.split())
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        board = "".join(fields[0].split("/")) if fields else ""
        if (
            len(fields) < 2
            or len(board) != 24
            or any(piece not in "*O@" for piece in board)
            or fields[1] not in ("w", "b")
        ):
            raise ValueError(
                f"{path}:{line_number} is not a supported reference FEN"
            )
        white_bits = 0
        black_bits = 0
        for piece, label in zip(board, FEN_LABELS, strict=True):
            bit = 1 << PERFECT_INDEX[label]
            if piece == "O":
                white_bits |= bit
            elif piece == "@":
                black_bits |= bit
        side_to_move = 0 if fields[1] == "w" else 1
        canonical = _canonical_ring16(
            white_bits,
            black_bits,
            side_to_move,
        )
        references.setdefault(canonical, set()).add(
            (white_bits, black_bits, side_to_move)
        )
        raw_count += 1
    if raw_count == 0:
        raise ValueError(f"{path} contains no reference FENs")
    return references, _sha256_file(path), raw_count


def _load_excluded_roots(
    raw_paths: list[str],
) -> tuple[set[int], list[str], int]:
    excluded = set()
    digests = []
    raw_count = 0
    for raw_path in raw_paths:
        roots, digest, count = _load_reference_presentations(raw_path)
        excluded.update(roots)
        assert digest is not None
        digests.append(digest)
        raw_count += count
    return excluded, digests, raw_count


def _hashed_presentation_operation(
    source_game_sha256: str, logical_ply: int, seed: int
) -> int:
    digest = hashlib.sha256(
        f"{seed}:{source_game_sha256}:{logical_ply}".encode()
    ).digest()
    return int.from_bytes(digest[:2], "big") % 16


def _presentation_operation(
    source_game_sha256: str,
    logical_ply: int,
    seed: int,
    board: str,
    side_to_move: int,
    reference_presentations: dict[int, set[tuple[int, int, int]]],
) -> int | None:
    first = _hashed_presentation_operation(
        source_game_sha256,
        logical_ply,
        seed,
    )
    if not reference_presentations:
        return first
    for offset in range(16):
        operation = (first + offset) % 16
        white_bits, black_bits = _bitboards(board, operation)
        canonical = _canonical_ring16(
            white_bits,
            black_bits,
            side_to_move,
        )
        raw = (white_bits, black_bits, side_to_move)
        if raw not in reference_presentations.get(canonical, set()):
            return operation
    return None


def _database_connection(path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(
        f"{path.resolve().as_uri()}?mode=ro&immutable=1",
        uri=True,
    )
    connection.execute("PRAGMA query_only = ON")
    meta = dict(connection.execute("SELECT key, value FROM meta"))
    if meta.get("schema_version") != "2":
        raise ValueError("HumanDB schema_version must be 2")
    if meta.get("malom_label_version") != "sector-corrected-v1":
        raise ValueError(
            "HumanDB must declare malom_label_version sector-corrected-v1"
        )
    return connection


def _human_miss_targets(
    connection: sqlite3.Connection,
    minimum_games: int,
    minimum_dtw: int,
    maximum_dtw: int,
) -> dict[tuple[str, str], tuple[int, int, int, str]]:
    rows = connection.execute(
        "SELECT p.state_key, m.notation, p.total_games, m.total, "
        "p.malom_dtw, m.malom_wdl_after "
        "FROM positions p JOIN moves m USING(state_key) "
        "WHERE p.total_games >= ?1 "
        "AND p.malom_wdl = 'W' "
        "AND p.canonical_winning_move IS NOT NULL "
        "AND m.notation <> p.canonical_winning_move "
        "AND m.malom_wdl_after IN ('D', 'W') "
        "AND p.malom_dtw >= ?2 "
        "AND (?3 = 0 OR p.malom_dtw <= ?3)",
        (minimum_games, minimum_dtw, maximum_dtw),
    )
    return {
        (state_key, notation): (
            position_games,
            recorded_games,
            annotated_dtw,
            annotated_after_wdl,
        )
        for (
            state_key,
            notation,
            position_games,
            recorded_games,
            annotated_dtw,
            annotated_after_wdl,
        ) in rows
    }


def _replay_index_connection(
    replay_index_path: Path,
) -> tuple[sqlite3.Connection, dict[str, str]]:
    connection = sqlite3.connect(
        f"{replay_index_path.resolve().as_uri()}?mode=ro&immutable=1",
        uri=True,
    )
    connection.execute("PRAGMA query_only = ON")
    replay_meta = dict(connection.execute("SELECT key, value FROM meta"))
    if replay_meta.get("schema_version") != "1":
        raise ValueError("replay-index schema_version must be 1")
    if replay_meta.get("anonymised") != "true":
        raise ValueError("replay index must declare anonymised=true")
    if replay_meta.get("state_key_model") != "sector-corrected-v1":
        raise ValueError(
            "replay index must use state_key_model sector-corrected-v1"
        )
    return connection, replay_meta


def _indexed_candidate_rows(
    connection: sqlite3.Connection,
    human_miss_targets: dict[
        tuple[str, str], tuple[int, int, int, str]
    ],
    args: argparse.Namespace,
) -> list[tuple]:
    rows = []
    query = """
            SELECT
                r.source_sha256,
                r.logical_ply,
                r.notation,
                r.board_fen
            FROM turns AS r
            WHERE r.state_key = ?1
              AND r.canonical_notation = ?2
              AND r.move_type = 'move'
              AND r.logical_ply BETWEEN ?3 AND ?4
              AND r.placed_white = 9
              AND r.placed_black = 9
              AND r.white_on_board BETWEEN ?5 AND ?6
              AND r.black_on_board BETWEEN ?5 AND ?6
            """
    for (state_key, canonical_notation), annotation in (
        human_miss_targets.items()
    ):
        for replay_row in connection.execute(
            query,
            (
                state_key,
                canonical_notation,
                args.min_logical_ply,
                args.max_logical_ply,
                args.min_pieces,
                args.max_pieces,
            ),
        ):
            rows.append((*replay_row, *annotation))
    return rows


def _candidate_order(row: tuple, seed: int) -> bytes:
    source_sha256, logical_ply = row[:2]
    return hashlib.sha256(
        f"{seed}:{source_sha256}:{logical_ply}".encode()
    ).digest()


def extract_from_index(args: argparse.Namespace) -> dict:
    replay_index_path = Path(args.replay_index).resolve()
    database_path = Path(args.human_db).resolve()
    (
        reference_presentations,
        reference_presentations_sha256,
        reference_presentation_count,
    ) = _load_reference_presentations(args.reference_presentation_fens)
    (
        excluded_roots,
        excluded_root_digests,
        excluded_root_count,
    ) = _load_excluded_roots(args.exclude_root_fens)
    human_connection = _database_connection(database_path)
    human_meta = dict(
        human_connection.execute("SELECT key, value FROM meta")
    )
    human_miss_targets = _human_miss_targets(
        human_connection,
        args.min_games,
        args.min_annotated_dtw,
        args.max_annotated_dtw,
    )
    human_connection.close()

    connection, replay_meta = _replay_index_connection(replay_index_path)
    rows = _indexed_candidate_rows(connection, human_miss_targets, args)
    rows.sort(key=lambda row: _candidate_order(row, args.seed))

    candidates = []
    seen_roots = set()
    presentation_reorientations = 0
    unpresentable_roots = 0
    reference_roots_rejected = 0
    for (
        source_game_sha256,
        logical_ply,
        notation,
        board_fen,
        position_games,
        recorded_games,
        annotated_dtw,
        annotated_after_wdl,
    ) in rows:
        fields = board_fen.split("|")
        board = fields[0]
        side_to_move = 0 if fields[1] == "W" else 1
        presentation = _presentation_operation(
            source_game_sha256,
            logical_ply,
            args.seed,
            board,
            side_to_move,
            reference_presentations,
        )
        if presentation is None:
            unpresentable_roots += 1
            continue
        if presentation != _hashed_presentation_operation(
            source_game_sha256,
            logical_ply,
            args.seed,
        ):
            presentation_reorientations += 1
        white_bits, black_bits = _bitboards(board, presentation)
        canonical_root = _canonical_ring16(
            white_bits,
            black_bits,
            side_to_move,
        )
        if canonical_root in excluded_roots:
            reference_roots_rejected += 1
            continue
        if canonical_root in seen_roots:
            continue
        seen_roots.add(canonical_root)
        history = [
            turn[0]
            for turn in connection.execute(
                """
                SELECT notation
                FROM turns
                WHERE source_sha256 = ?1
                  AND logical_ply < ?2
                ORDER BY logical_ply
                """,
                (source_game_sha256, logical_ply),
            )
        ]
        candidates.append(
            {
                "whiteBits": white_bits,
                "blackBits": black_bits,
                "whiteInHand": 0,
                "blackInHand": 0,
                "sideToMove": side_to_move,
                "replay": {
                    "history": [
                        _transform_notation(turn, presentation)
                        for turn in history
                    ],
                    "recordedTurn": _transform_notation(
                        notation,
                        presentation,
                    ),
                    "sourceGameSha256": source_game_sha256,
                    "sourceLogicalPly": logical_ply,
                    "presentationTransform": presentation,
                    "positionGames": position_games,
                    "recordedTurnGames": recorded_games,
                    "annotatedDtw": annotated_dtw,
                    "annotatedAfterWdl": annotated_after_wdl,
                },
            }
        )
        if len(candidates) >= args.count:
            break

    connection.close()
    if not candidates:
        raise SystemExit("no indexed replay candidates satisfied the filters")
    database_sha256 = _sha256_file(database_path)
    return {
        "formatVersion": "1.0",
        "ruleVariantId": "standard_9mm",
        "source": {
            "kind": "human-game-replay",
            "corpus": args.corpus,
            "databaseSha256": database_sha256,
            "databaseBuildDate": human_meta.get("build_date"),
            "transformModel": "sanmill-ring16-v1",
            "referencePresentationRootsSha256": (
                reference_presentations_sha256
            ),
            "excludedRootSetSha256": excluded_root_digests,
        },
        "seed": args.seed,
        "filters": {
            "minimumGames": args.min_games,
            "minimumAnnotatedDtw": args.min_annotated_dtw,
            "maximumAnnotatedDtw": args.max_annotated_dtw,
            "logicalPly": [args.min_logical_ply, args.max_logical_ply],
            "piecesPerSide": [args.min_pieces, args.max_pieces],
            "referenceRawPresentationRoots": reference_presentation_count,
            "excludedRawRoots": excluded_root_count,
        },
        "audit": {
            "indexedGames": int(replay_meta["game_count"]),
            "indexedTurns": int(replay_meta["turn_count"]),
            "matchedReplayTurns": len(rows),
            "symmetryUniqueRoots": len(seen_roots),
            "humanTargetRows": len(human_miss_targets),
            "presentationReorientations": presentation_reorientations,
            "unpresentableReferenceRoots": unpresentable_roots,
            "referenceRootsRejected": reference_roots_rejected,
        },
        "candidateCount": len(candidates),
        "candidates": candidates,
    }


def _game_records(path: Path) -> Iterable[tuple[bytes, dict]]:
    for line in path.read_bytes().splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        if not isinstance(record, dict):
            raise ValueError(f"{path} contains a non-object JSON row")
        yield line, record


def extract(args: argparse.Namespace) -> dict:
    games_dir = Path(args.games_dir).resolve()
    database_path = Path(args.human_db).resolve()
    (
        reference_presentations,
        reference_presentations_sha256,
        reference_presentation_count,
    ) = _load_reference_presentations(args.reference_presentation_fens)
    (
        excluded_roots,
        excluded_root_digests,
        excluded_root_count,
    ) = _load_excluded_roots(args.exclude_root_fens)
    files = sorted(
        games_dir.rglob("*.jsonl"),
        key=lambda path: _file_order(path, args.seed),
    )
    if args.max_files > 0:
        files = files[: args.max_files]
    connection = _database_connection(database_path)
    meta = dict(connection.execute("SELECT key, value FROM meta"))
    human_miss_targets = _human_miss_targets(
        connection,
        args.min_games,
        args.min_annotated_dtw,
        args.max_annotated_dtw,
    )

    candidates = []
    seen_roots = set()
    inspected_games = 0
    inspected_positions = 0
    annotated_wins = 0
    noncanonical_human_turns = 0
    presentation_reorientations = 0
    unpresentable_roots = 0
    reference_roots_rejected = 0

    for path in files:
        for raw_record, game in _game_records(path):
            inspected_games += 1
            if game.get("source_type") != "human_vs_human":
                continue
            moves = game.get("moves")
            if not isinstance(moves, list):
                continue
            source_game_sha256 = hashlib.sha256(raw_record).hexdigest()
            history: list[str] = []
            for index, move in enumerate(moves):
                if not isinstance(move, dict):
                    break
                notation = move.get("notation")
                board_fen = move.get("board_fen_before")
                move_type = move.get("type")
                if not isinstance(notation, str) or not isinstance(board_fen, str):
                    break
                logical_ply = index + 1
                fields = board_fen.split("|")
                if (
                    move_type != "move"
                    or logical_ply < args.min_logical_ply
                    or logical_ply > args.max_logical_ply
                    or len(fields) != 4
                    or fields[2] != "9"
                    or fields[3] != "9"
                ):
                    history.append(notation)
                    continue
                board = fields[0]
                on_white = board.count("W")
                on_black = board.count("B")
                if not (
                    args.min_pieces <= on_white <= args.max_pieces
                    and args.min_pieces <= on_black <= args.max_pieces
                ):
                    history.append(notation)
                    continue

                inspected_positions += 1
                try:
                    state_key, d4_operation = _state_key(board_fen)
                except (TypeError, ValueError):
                    history.append(notation)
                    continue
                canonical_recorded = _transform_notation(
                    notation, d4_operation
                )
                target = human_miss_targets.get(
                    (state_key, canonical_recorded)
                )
                if target is None:
                    history.append(notation)
                    continue
                annotated_wins += 1
                noncanonical_human_turns += 1

                side_to_move = 0 if fields[1] == "W" else 1
                presentation = _presentation_operation(
                    source_game_sha256,
                    logical_ply,
                    args.seed,
                    board,
                    side_to_move,
                    reference_presentations,
                )
                if presentation is None:
                    unpresentable_roots += 1
                    history.append(notation)
                    continue
                if presentation != _hashed_presentation_operation(
                    source_game_sha256,
                    logical_ply,
                    args.seed,
                ):
                    presentation_reorientations += 1
                white_bits, black_bits = _bitboards(board, presentation)
                canonical_root = _canonical_ring16(
                    white_bits, black_bits, side_to_move
                )
                if canonical_root in excluded_roots:
                    reference_roots_rejected += 1
                    history.append(notation)
                    continue
                if canonical_root in seen_roots:
                    history.append(notation)
                    continue
                seen_roots.add(canonical_root)
                candidates.append(
                    {
                        "whiteBits": white_bits,
                        "blackBits": black_bits,
                        "whiteInHand": 0,
                        "blackInHand": 0,
                        "sideToMove": side_to_move,
                        "replay": {
                            "history": [
                                _transform_notation(turn, presentation)
                                for turn in history
                            ],
                            "recordedTurn": _transform_notation(
                                notation, presentation
                            ),
                            "sourceGameSha256": source_game_sha256,
                            "sourceLogicalPly": logical_ply,
                            "presentationTransform": presentation,
                            "positionGames": target[0],
                            "recordedTurnGames": target[1],
                            "annotatedDtw": target[2],
                            "annotatedAfterWdl": target[3],
                        },
                    }
                )
                history.append(notation)
                if len(candidates) >= args.count:
                    break
            if len(candidates) >= args.count:
                break
        if len(candidates) >= args.count:
            break

    connection.close()
    if not candidates:
        raise SystemExit("no HumanDB replay candidates satisfied the filters")
    database_sha256 = _sha256_file(database_path)
    return {
        "formatVersion": "1.0",
        "ruleVariantId": "standard_9mm",
        "source": {
            "kind": "human-game-replay",
            "corpus": args.corpus,
            "databaseSha256": database_sha256,
            "databaseBuildDate": meta.get("build_date"),
            "transformModel": "sanmill-ring16-v1",
            "referencePresentationRootsSha256": (
                reference_presentations_sha256
            ),
            "excludedRootSetSha256": excluded_root_digests,
        },
        "seed": args.seed,
        "filters": {
            "minimumGames": args.min_games,
            "minimumAnnotatedDtw": args.min_annotated_dtw,
            "maximumAnnotatedDtw": args.max_annotated_dtw,
            "logicalPly": [args.min_logical_ply, args.max_logical_ply],
            "piecesPerSide": [args.min_pieces, args.max_pieces],
            "referenceRawPresentationRoots": reference_presentation_count,
            "excludedRawRoots": excluded_root_count,
        },
        "audit": {
            "inspectedGames": inspected_games,
            "inspectedPositions": inspected_positions,
            "annotatedWinningRoots": annotated_wins,
            "noncanonicalHumanTurns": noncanonical_human_turns,
            "targetRows": len(human_miss_targets),
            "presentationReorientations": presentation_reorientations,
            "unpresentableReferenceRoots": unpresentable_roots,
            "referenceRootsRejected": reference_roots_rejected,
        },
        "candidateCount": len(candidates),
        "candidates": candidates,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--games-dir")
    source.add_argument("--replay-index")
    parser.add_argument("--human-db", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--count", type=int, default=5000)
    parser.add_argument("--max-files", type=int, default=0)
    parser.add_argument("--min-games", type=int, default=1)
    parser.add_argument("--min-annotated-dtw", type=int, default=1)
    parser.add_argument(
        "--max-annotated-dtw",
        type=int,
        default=31,
        help="0 disables the HumanDB distance prior",
    )
    parser.add_argument("--min-logical-ply", type=int, default=19)
    parser.add_argument("--max-logical-ply", type=int, default=120)
    parser.add_argument("--min-pieces", type=int, default=4)
    parser.add_argument("--max-pieces", type=int, default=7)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=1)
    parser.add_argument(
        "--reference-presentation-fens",
        default=str(
            Path(__file__).resolve().parents[1]
            / "crates"
            / "tgf-cli"
            / "testdata"
            / "puzzle_exclusions"
            / "mill_editorial_replay.fen"
        ),
        help=(
            "recorded replay presentations; matching candidates are "
            "deterministically transformed to a different presentation"
        ),
    )
    parser.add_argument(
        "--exclude-root-fens",
        action="append",
        default=[
            str(
                Path(__file__).resolve().parents[1]
                / "crates"
                / "tgf-cli"
                / "testdata"
                / "puzzle_exclusions"
                / "mill_editorial_non_replay.fen"
            )
        ],
        help=(
            "reject these roots under ring-16 symmetry before exporting "
            "(repeatable; the default editorial record is always applied)"
        ),
    )
    parser.add_argument(
        "--corpus",
        default="HumanDB raw human games (anonymised PlayOK sample)",
    )
    args = parser.parse_args()
    if args.count < 1:
        parser.error("--count must be positive")
    if args.max_files < 0:
        parser.error("--max-files must not be negative")
    if args.min_games < 1:
        parser.error("--min-games must be positive")
    if args.min_annotated_dtw < 1:
        parser.error("--min-annotated-dtw must be positive")
    if args.max_annotated_dtw < 0:
        parser.error("--max-annotated-dtw must not be negative")
    if (
        args.max_annotated_dtw > 0
        and args.min_annotated_dtw > args.max_annotated_dtw
    ):
        parser.error(
            "--min-annotated-dtw must not exceed --max-annotated-dtw"
        )
    if args.replay_index and args.max_files:
        parser.error("--max-files applies only to --games-dir")
    if not 1 <= args.min_logical_ply <= args.max_logical_ply:
        parser.error("logical-ply bounds are invalid")
    if not 3 <= args.min_pieces <= args.max_pieces <= 9:
        parser.error("piece bounds must satisfy 3 <= min <= max <= 9")
    return args


def main() -> None:
    args = parse_args()
    package = extract_from_index(args) if args.replay_index else extract(args)
    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(
        (json.dumps(package, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    )
    audit = package["audit"]
    inspected_games = audit.get("inspectedGames", audit.get("indexedGames"))
    inspected_positions = audit.get(
        "inspectedPositions",
        audit.get("indexedTurns"),
    )
    print(
        "[human-puzzle-extract] "
        f"games={inspected_games} "
        f"positions={inspected_positions} "
        f"candidates={package['candidateCount']} out={output}"
    )


if __name__ == "__main__":
    main()
