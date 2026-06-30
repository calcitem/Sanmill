#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Convert legacy Mill FEN square ids to node-id FENs.

The node-id FEN dialect is identified by the `ids:nodes` extension token.
Legacy FENs without that marker encode square-like numeric fields as
legacy Square ids (`8..31`, `0` for none).  Node-id FENs encode them as
direct engine node ids (`0..23`, `-1` for none).
"""

from __future__ import annotations

import argparse
import os
import re
from pathlib import Path


NODE_ID_MARKER = "ids:nodes"
BOARD_RE = r"[O@X*]{8}/[O@X*]{8}/[O@X*]{8}"
TOKEN_RE = r"[^\s\"'`,;\]\}\)]+"
FEN_RE = re.compile(rf"{BOARD_RE}(?:\s+{TOKEN_RE}){{16}}(?:\s+{TOKEN_RE})*")
TEXT_SUFFIXES = {
    ".arb",
    ".dart",
    ".json",
    ".md",
    ".py",
    ".rs",
    ".sh",
    ".toml",
    ".txt",
    ".yaml",
    ".yml",
}
SKIP_DIR_NAMES = {
    ".dart_tool",
    ".git",
    ".idea",
    ".vscode",
    "build",
    # These snapshots intentionally preserve the C++ reference engine's
    # historical FEN dialect.  Pass a concrete JSON file if conversion is
    # explicitly needed for a separate experiment.
    "legacy_oracle",
    "target",
}


def legacy_square_to_node(value: int) -> int:
    if value == 0:
        return -1
    if 8 <= value < 32:
        return value - 8
    raise ValueError(f"legacy square id must be 0 or 8..31, got {value}")


def legacy_square_bb_to_node_bb(value: int) -> int:
    return (value >> 8) & 0x00FF_FFFF


def convert_square_token(token: str) -> str:
    return str(legacy_square_to_node(int(token)))


def convert_formed_mills_field(token: str) -> str:
    raw = int(token)
    white_legacy = (raw >> 32) & 0xFFFF_FFFF
    black_legacy = raw & 0xFFFF_FFFF
    white_nodes = legacy_square_bb_to_node_bb(white_legacy)
    black_nodes = legacy_square_bb_to_node_bb(black_legacy)
    return str((white_nodes << 32) | black_nodes)


def convert_capture_segment(segment: str) -> str:
    first_dash = segment.find("-")
    second_dash = segment.find("-", first_dash + 1)
    if first_dash == -1 or second_dash == -1:
        raise ValueError(f"invalid capture segment: {segment}")

    prefix = segment[: second_dash + 1]
    targets = segment[second_dash + 1 :]
    if not targets:
        return segment

    converted = [
        str(legacy_square_to_node(int(target)))
        for target in targets.split(".")
        if target
    ]
    return prefix + ".".join(converted)


def convert_capture_token(token: str) -> str:
    label, value = token.split(":", 1)
    converted = [convert_capture_segment(segment) for segment in value.split("|")]
    return f"{label}:{'|'.join(converted)}"


def convert_extension_token(token: str) -> str:
    if len(token) < 2 or token[1] != ":":
        return token
    label = token[0]
    if label in ("c", "i", "l"):
        return convert_capture_token(token)
    if label == "p":
        return f"p:{convert_square_token(token[2:])}"
    return token


def convert_fen(fen: str) -> str:
    fields = fen.split()
    if len(fields) < 17:
        raise ValueError(f"FEN needs at least 17 fields: {fen}")
    if NODE_ID_MARKER in fields[17:]:
        return fen

    fields = fields[:]
    for idx in range(10, 14):
        fields[idx] = convert_square_token(fields[idx])
    fields[14] = convert_formed_mills_field(fields[14])

    converted_extensions = [convert_extension_token(token) for token in fields[17:]]
    return " ".join(fields[:17] + [NODE_ID_MARKER] + converted_extensions)


def convert_text(text: str) -> tuple[str, int]:
    count = 0

    def replace(match: re.Match[str]) -> str:
        nonlocal count
        original = match.group(0)
        converted = convert_fen(original)
        if converted != original:
            count += 1
        return converted

    return FEN_RE.sub(replace, text), count


def is_text_candidate(path: Path) -> bool:
    return path.suffix in TEXT_SUFFIXES


def iter_input_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    seen: set[Path] = set()
    for path in paths:
        if path.is_file():
            candidates = [path]
        elif path.is_dir():
            candidates = []
            for dirpath, dirnames, filenames in os.walk(path):
                dirnames[:] = [
                    dirname for dirname in dirnames if dirname not in SKIP_DIR_NAMES
                ]
                root = Path(dirpath)
                candidates.extend(root / filename for filename in filenames)
        else:
            raise FileNotFoundError(path)

        for candidate in candidates:
            if not is_text_candidate(candidate):
                continue
            resolved = candidate.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            files.append(candidate)
    return files


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Convert legacy Mill FEN strings to node-id FEN strings in files "
            "or directories."
        )
    )
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument(
        "--write",
        action="store_true",
        help="Rewrite files in place. Without this flag, only report changes.",
    )
    args = parser.parse_args()

    files = iter_input_files(args.paths)
    total = 0
    changed_files = 0
    for path in files:
        text = path.read_text(encoding="utf-8")
        converted, count = convert_text(text)
        total += count
        if not count:
            continue
        changed_files += 1
        if args.write:
            path.write_text(converted, encoding="utf-8")
        print(f"{path}: {count} FEN(s)")

    print(f"Scanned {len(files)} file(s); found {total} legacy FEN(s).")
    if total and not args.write:
        print("Dry run only; pass --write to update files.")
    if args.write:
        print(f"Updated {changed_files} file(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
