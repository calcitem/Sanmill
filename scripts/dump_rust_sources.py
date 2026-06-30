#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
"""Concatenate the current branch's Rust sources into a single file.

Used to ship the Rust port to an external reviewer alongside
`dump_master_cxx_sources.py` for side-by-side comparison.

Excludes (in order of priority):

  * directories that hold tests / benches / examples (``tests/``,
    ``benches/``, ``examples/``);
  * ``target/`` build artefacts;
  * ``crates/tgf-frb/src/frb_generated.rs`` (auto-generated FRB glue —
    bulky and not authored by hand);
  * inline ``#[cfg(test)] mod tests { ... }`` blocks and ``#[test]`` /
    ``#[bench]`` items inside otherwise-production source files.

The output is written to ``rust_sources_combined.txt`` in the repo
root and is intentionally listed in ``.gitignore``.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import List

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "rust_sources_combined.txt"

# Directories we walk for Rust crates.
CRATE_ROOTS = [ROOT / "crates"]

# Path components anywhere in a path that disqualify a file.
EXCLUDE_DIR_PARTS = {
    "target",
    "tests",
    "benches",
    "examples",
}

# Specific files to drop wholesale.
EXCLUDE_FILES = {
    ROOT / "crates" / "tgf-frb" / "src" / "frb_generated.rs",
}

# Attribute regex.  Matches lines like ``#[cfg(test)]`` (with optional
# inner whitespace), ``#[test]``, ``#[bench]``, and the parametrized
# variants ``#[test(...)]`` / ``#[bench(...)]``.  The final ``\]``
# anchor is essential — using ``\b`` would fail on ``cfg(test)]`` since
# both ``)`` and ``]`` are non-word characters and ``\b`` requires a
# word/non-word transition there.
_TEST_ATTR_RE = re.compile(
    r"^\s*#\[\s*(cfg\s*\(\s*test\s*\)|test(\s|\(|\])|bench(\s|\(|\]))"
)


def collect_files() -> List[Path]:
    """Enumerate every Rust source file we want to ship."""
    files: List[Path] = []
    for root in CRATE_ROOTS:
        for path in root.rglob("*.rs"):
            if any(part in EXCLUDE_DIR_PARTS for part in path.parts):
                continue
            if path in EXCLUDE_FILES:
                continue
            files.append(path)

    # Always include the workspace and per-crate Cargo.toml files for
    # context — they describe the project structure the reviewer needs
    # to interpret module boundaries.
    for root in CRATE_ROOTS:
        for path in root.rglob("Cargo.toml"):
            if any(part in EXCLUDE_DIR_PARTS for part in path.parts):
                continue
            files.append(path)
    workspace_toml = ROOT / "Cargo.toml"
    if workspace_toml.is_file():
        files.append(workspace_toml)

    files.sort()
    return files


def strip_inline_tests(text: str) -> str:
    """Drop ``#[cfg(test)]`` / ``#[test]`` / ``#[bench]``-gated items.

    A run of ``#[...]`` attributes preceding an item is treated as a
    single block: if *any* of the attributes is a test gate, the entire
    attribute run plus the next item is skipped.  The "next item" is
    detected by either a ``{ ... }`` body (brace-counted) or a single
    statement terminated by ``;``.
    """
    lines = text.split("\n")
    out: List[str] = []
    n = len(lines)
    i = 0
    while i < n:
        line = lines[i]
        # If this line opens a run of attributes, scan all consecutive
        # ``#[...]`` lines first and decide as a group.
        if line.lstrip().startswith("#["):
            attr_start = i
            any_test_attr = False
            while i < n and lines[i].lstrip().startswith("#["):
                if _TEST_ATTR_RE.match(lines[i]):
                    any_test_attr = True
                i += 1
            # Skip blank lines between attributes and the item.
            j = i
            while j < n and lines[j].strip() == "":
                j += 1

            if not any_test_attr:
                # Emit the attribute run verbatim and continue from the
                # post-attribute cursor (do not eat the item itself).
                for k in range(attr_start, i):
                    out.append(lines[k])
                # Continue scanning starting at the next line; the item
                # itself is processed by the next loop iteration so any
                # test attributes nested inside it (rare but allowed)
                # still get a chance.
                continue

            # Test-gated.  Skip both the attribute run and the next
            # item.  If the item has a body brace-count past it; else
            # consume up to the first line ending in ``;``.
            if j >= n:
                i = j
                continue
            item_line = lines[j]
            if "{" in item_line:
                depth = 0
                k = j
                while k < n:
                    depth += lines[k].count("{")
                    depth -= lines[k].count("}")
                    k += 1
                    if depth <= 0:
                        break
                i = k
            else:
                k = j
                while k < n and not lines[k].rstrip().endswith(";"):
                    k += 1
                i = k + 1
            continue

        out.append(line)
        i += 1

    return "\n".join(out)


def main() -> int:
    files = collect_files()
    total_bytes = 0
    with OUT.open("w", encoding="utf-8") as fh:
        fh.write("// =====================================================\n")
        fh.write("// Generated by scripts/dump_rust_sources.py\n")
        fh.write(
            "// Concatenated Rust sources for the current branch\n"
            "// (production code only — tests / benches / examples and\n"
            "// the auto-generated FRB bridge are stripped).\n"
        )
        fh.write(f"// Files: {len(files)}\n")
        fh.write("// =====================================================\n\n")
        for path in files:
            rel = path.relative_to(ROOT).as_posix()
            text = path.read_text(encoding="utf-8")
            if path.suffix == ".rs":
                text = strip_inline_tests(text)
            fh.write(f"\n// ===== {rel} =====\n")
            fh.write(text)
            if not text.endswith("\n"):
                fh.write("\n")
            total_bytes += len(text)
    size = OUT.stat().st_size
    print(
        f"Wrote {OUT.relative_to(ROOT)} "
        f"({size:,} bytes on disk; ~{total_bytes:,} bytes of source; "
        f"{len(files)} files)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
