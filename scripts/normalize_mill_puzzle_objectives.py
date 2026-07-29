#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Normalize Win-in-N public metadata from the exported optimal solutions."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from mill_puzzle_objectives import (
    normalize_package,
    validate_public_objectives,
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package")
    parser.add_argument("--out", required=True)
    parser.add_argument("--version")
    args = parser.parse_args()

    source = Path(args.package).resolve()
    output = Path(args.out).resolve()
    package = json.loads(source.read_text(encoding="utf-8-sig"))
    if not isinstance(package, dict):
        raise ValueError(f"{source} is not a JSON object")
    mapping = normalize_package(package)
    if args.version is not None:
        metadata = package.get("metadata")
        if not isinstance(metadata, dict):
            raise ValueError("puzzle package has no metadata object")
        metadata["version"] = args.version
    errors = validate_public_objectives(package.get("puzzles", []))
    if errors:
        raise ValueError("\n".join(errors))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(package, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"[mill-puzzle-objectives] puzzles={package.get('puzzleCount')} "
        f"renamed_ids={len(mapping)} out={output}"
    )


if __name__ == "__main__":
    main()
