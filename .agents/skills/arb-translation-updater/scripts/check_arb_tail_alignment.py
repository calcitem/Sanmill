#!/usr/bin/env python3
"""Report the default ARB update scope from the four reference locales."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REFERENCE_LOCALES = ("en", "de", "hu", "zh")


def last_message_key(path: Path) -> str:
    """Return the last top-level ARB key that is not metadata."""
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a JSON object")

    message_keys = [key for key in data if not key.startswith("@")]
    if not message_keys:
        raise ValueError(f"{path} does not contain a message key")

    return message_keys[-1]


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Compare the final message keys in intl_en.arb, intl_de.arb, "
            "intl_hu.arb, and intl_zh.arb."
        )
    )
    parser.add_argument(
        "--l10n-dir",
        type=Path,
        default=Path("src/ui/flutter_app/lib/l10n"),
        help="Directory containing intl_*.arb files",
    )
    args = parser.parse_args()

    try:
        keys = {
            locale: last_message_key(args.l10n_dir / f"intl_{locale}.arb")
            for locale in REFERENCE_LOCALES
        }
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"error={error}", file=sys.stderr)
        return 2

    for locale, key in keys.items():
        print(f"{locale}={key}")

    aligned = len(set(keys.values())) == 1
    print(f"tail_alignment={'aligned' if aligned else 'mismatched'}")
    print(f"default_scope={'all-locales' if aligned else 'en,zh'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
