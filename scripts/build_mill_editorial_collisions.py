#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Build a run-specific FEN collision list for Mill puzzle mining.

The repository stores normalised collision roots in the version-controlled
``crates/tgf-cli/testdata/puzzle_exclusions/mill_editorial_baseline.fen``
record. This script reconciles newly decoded reference inputs with that record
and can combine it with other editorial records and existing packs.
``tgf puzzle-gen --exclude-fens`` canonicalises every entry under all 16 Mill
board symmetries before accepting new candidates.

An allow record is applied only to editorial reference roots, before base
packs are added. Composed runs retain replay-attributed roots in the collision
set, while replay-backed runs may remove them and separately require a
different raw presentation. Existing Sanmill packs are never allow-listed.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from urllib.parse import unquote_plus

try:
    from PIL import Image
    import zxingcpp
except ImportError:
    Image = None
    zxingcpp = None


IMAGE_PATTERN = re.compile(r"!\[[^\]]*]\(([^)]+)\)")
FEN_PATTERN = re.compile(
    r"(?P<fen>"
    r"[O@*]{8}/[O@*]{8}/[O@*]{8}\s+"
    r"[wb]\s+[pm]\s+[spr]\s+"
    r"(?:-?\d+\s+){12}-?\d+"
    r"(?:\s+ids:nodes)?"
    r")",
    re.IGNORECASE,
)


def _chapter(markdown: str) -> str:
    start_match = re.search(r"(?m)^# 18\.\s+Puzzle Games\s*$", markdown)
    if start_match is None:
        raise ValueError("could not find '# 18. Puzzle Games'")
    end_match = re.search(r"(?m)^# 19\.\s+References\s*$", markdown)
    if end_match is None or end_match.start() <= start_match.end():
        raise ValueError("could not find '# 19. References' after puzzle chapter")
    return markdown[start_match.end() : end_match.start()]


def _extract_fens(text: str) -> set[str]:
    decoded = unquote_plus(text).replace("\\n", "\n")
    return {
        " ".join(match.group("fen").split())
        for match in FEN_PATTERN.finditer(decoded)
    }


def _decode_images(reference_path: Path, chapter: str) -> tuple[set[str], int]:
    if Image is None or zxingcpp is None:
        raise RuntimeError(
            "image decoding requires Pillow and zxing-cpp; install "
            "scripts/requirements-puzzle-math.txt or pass "
            "--skip-image-decode with a reviewed --curated-reference-roots record"
        )
    fens: set[str] = set()
    decoded_count = 0
    for raw_path in IMAGE_PATTERN.findall(chapter):
        image_path = (
            reference_path.parent / unquote_plus(raw_path)
        ).resolve()
        if not image_path.is_file():
            raise FileNotFoundError(f"referenced image does not exist: {image_path}")
        with Image.open(image_path) as image:
            barcodes = zxingcpp.read_barcodes(image)
        if not barcodes:
            continue
        decoded_count += len(barcodes)
        image_fens: set[str] = set()
        for barcode in barcodes:
            image_fens.update(_extract_fens(barcode.text))
        fens.update(image_fens)
        print(
            "[reference-collisions] "
            f"decoded={image_path.name} fens={len(image_fens)}"
        )
    return fens, decoded_count


def _base_pack_fens(path: Path) -> set[str]:
    package = json.loads(path.read_text(encoding="utf-8-sig"))
    puzzles = package.get("puzzles")
    if not isinstance(puzzles, list):
        raise ValueError(f"{path} does not contain a puzzles array")
    fens = set()
    for index, puzzle in enumerate(puzzles):
        if not isinstance(puzzle, dict):
            raise ValueError(f"{path} puzzle {index} is not an object")
        fen = puzzle.get("initialPosition")
        if not isinstance(fen, str) or FEN_PATTERN.fullmatch(fen) is None:
            raise ValueError(f"{path} puzzle {index} has an invalid initialPosition")
        fens.add(" ".join(fen.split()))
    return fens


def _validated_extra_fens(values: list[str]) -> set[str]:
    fens = set()
    for value in values:
        normalised = " ".join(value.split())
        if FEN_PATTERN.fullmatch(normalised) is None:
            raise ValueError(f"invalid --extra-fen value: {value}")
        fens.add(normalised)
    return fens


def _recorded_fens(path: Path) -> set[str]:
    fens = set()
    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8-sig").splitlines(),
        start=1,
    ):
        line = " ".join(raw_line.split())
        if not line or line.startswith("#"):
            continue
        if FEN_PATTERN.fullmatch(line) is None:
            raise ValueError(
                f"{path}:{line_number} is not a valid exclusion FEN"
            )
        fens.add(line)
    if not fens:
        raise ValueError(f"{path} contains no exclusion FENs")
    return fens


def _root_identity(fen: str) -> tuple[str, ...]:
    """Ignore historical counters which do not change the puzzle root."""
    fields = fen.split()
    if len(fields) < 8:
        raise ValueError(f"invalid FEN root identity: {fen}")
    return tuple(fields[:8])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--reference-markdown",
        help=(
            "path to the external reference Markdown; optional when only "
            "existing packs or FEN records are being combined"
        ),
    )
    parser.add_argument(
        "--base-pack",
        action="append",
        default=[],
        help="also exclude every initialPosition in this puzzle package",
    )
    parser.add_argument(
        "--extra-fen",
        action="append",
        default=[],
        help="add a visually recovered puzzle root (repeatable)",
    )
    parser.add_argument(
        "--curated-reference-roots",
        help=(
            "version-controlled reference-root record; decoded roots must be a "
            "subset and the complete recorded set is used"
        ),
    )
    parser.add_argument(
        "--skip-image-decode",
        action="store_true",
        help=(
            "use text plus the curated record without decoding reference media; "
            "requires --curated-reference-roots"
        ),
    )
    parser.add_argument(
        "--additional-exclusions",
        action="append",
        default=[],
        help="add every FEN in another editorial reference record (repeatable)",
    )
    parser.add_argument(
        "--allow-fens",
        action="append",
        default=[],
        help=(
            "remove these FENs from editorial reference roots before base packs "
            "are added (repeatable)"
        ),
    )
    parser.add_argument("--out", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.skip_image_decode and not args.curated_reference_roots:
        raise ValueError(
            "--skip-image-decode requires --curated-reference-roots"
        )
    if args.reference_markdown:
        reference_path = Path(args.reference_markdown).resolve()
        markdown = reference_path.read_text(encoding="utf-8-sig")
        chapter = _chapter(markdown)
        source_fens = _extract_fens(chapter)
        if args.skip_image_decode:
            decoded_fens, decoded_count = set(), 0
        else:
            decoded_fens, decoded_count = _decode_images(
                reference_path,
                chapter,
            )
        source_fens.update(decoded_fens)
    else:
        source_fens = set()
        decoded_count = 0
    source_fens.update(_validated_extra_fens(args.extra_fen))
    if not (
        source_fens
        or args.curated_reference_roots
        or args.additional_exclusions
        or args.base_pack
    ):
        raise ValueError(
            "provide --reference-markdown, a FEN record, or a base pack"
        )
    curated_count = 0
    curated_only_count = 0
    if args.curated_reference_roots:
        curated_fens = _recorded_fens(
            Path(args.curated_reference_roots).resolve()
        )
        unrecorded = source_fens - curated_fens
        if unrecorded:
            details = "\n".join(f"  {fen}" for fen in sorted(unrecorded))
            raise ValueError(
                "the reference now exposes roots absent from the curated record:\n"
                f"{details}"
            )
        curated_count = len(curated_fens)
        curated_only_count = len(curated_fens - source_fens)
        fens = set(curated_fens)
    else:
        fens = set(source_fens)
    additional_count = 0
    for raw_path in args.additional_exclusions:
        additional_fens = _recorded_fens(Path(raw_path).resolve())
        additional_count += len(additional_fens)
        fens.update(additional_fens)

    allow_fens = set()
    for raw_path in args.allow_fens:
        allow_fens.update(_recorded_fens(Path(raw_path).resolve()))
    allow_identities = {_root_identity(fen) for fen in allow_fens}
    retained_fens = {
        fen for fen in fens if _root_identity(fen) not in allow_identities
    }
    allowed_count = len(fens) - len(retained_fens)
    fens = retained_fens

    base_count = 0
    for raw_path in args.base_pack:
        base_fens = _base_pack_fens(Path(raw_path).resolve())
        base_count += len(base_fens)
        fens.update(base_fens)

    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Generated collision roots: editorial references plus base packs.",
        "# This file is a mining input, not puzzle content.",
        *sorted(fens),
    ]
    output.write_bytes(("\n".join(lines) + "\n").encode("utf-8"))
    print(
        "[reference-collisions] "
        f"decoded-payloads={decoded_count} source-roots={len(source_fens)} "
        f"curated-roots={curated_count} curated-only={curated_only_count} "
        f"additional-roots={additional_count} allow-roots={len(allow_fens)} "
        f"allowed-reference-roots={allowed_count} base-roots={base_count} "
        f"unique-fens={len(fens)} out={output}"
    )


if __name__ == "__main__":
    main()
