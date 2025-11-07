#!/usr/bin/env python3
"""
Script to check if ARB files have the same entry order as intl_en.arb

This script compares the key order in all ARB files against the reference
file (intl_en.arb) and reports any differences.
"""

import json
import os
from pathlib import Path
from typing import List, Dict, Any


def load_arb_file(file_path: Path) -> Dict[str, Any]:
    """
    Load ARB file and preserve key order

    Args:
        file_path: Path to the ARB file

    Returns:
        Dictionary with preserved key order
    """
    with open(file_path, 'r', encoding='utf-8') as f:
        return json.load(f)


def get_arb_keys(arb_data: Dict[str, Any]) -> List[str]:
    """
    Extract all keys from ARB data

    Args:
        arb_data: ARB file content as dictionary

    Returns:
        List of keys in their original order
    """
    return list(arb_data.keys())


def check_arb_order(l10n_dir: Path, reference_file: str = 'intl_en.arb') -> None:
    """
    Check if all ARB files have the same key order as the reference file

    Args:
        l10n_dir: Directory containing ARB files
        reference_file: Name of the reference ARB file
    """
    # Load reference file
    reference_path = l10n_dir / reference_file
    if not reference_path.exists():
        print(f"❌ Error: Reference file {reference_file} not found!")
        return

    reference_data = load_arb_file(reference_path)
    reference_keys = get_arb_keys(reference_data)

    print(f"📋 Reference file: {reference_file}")
    print(f"📊 Total keys in reference: {len(reference_keys)}\n")

    # Find all ARB files
    arb_files = sorted(l10n_dir.glob('intl_*.arb'))

    files_with_different_order = []
    files_checked = 0

    for arb_file in arb_files:
        if arb_file.name == reference_file:
            continue  # Skip reference file

        files_checked += 1
        arb_data = load_arb_file(arb_file)
        arb_keys = get_arb_keys(arb_data)

        # Get common keys (keys that exist in both files)
        common_keys = [key for key in reference_keys if key in arb_keys]

        # Check if the order of common keys matches
        reference_common_order = [key for key in reference_keys if key in common_keys]
        arb_common_order = [key for key in arb_keys if key in common_keys]

        if reference_common_order != arb_common_order:
            files_with_different_order.append(arb_file.name)
            print(f"❌ {arb_file.name}: Keys are in different order")
            print(f"   - Keys in file: {len(arb_keys)}")
            print(f"   - Keys in reference: {len(reference_keys)}")
            print(f"   - Common keys: {len(common_keys)}")
        else:
            print(f"✅ {arb_file.name}: Keys are in correct order")

    # Summary
    print(f"\n{'='*60}")
    print(f"Summary:")
    print(f"  Total files checked: {files_checked}")
    print(f"  Files with correct order: {files_checked - len(files_with_different_order)}")
    print(f"  Files with different order: {len(files_with_different_order)}")

    if files_with_different_order:
        print(f"\n📝 Files that need reordering:")
        for filename in files_with_different_order:
            print(f"  - {filename}")
    else:
        print(f"\n🎉 All files have the correct key order!")


def main():
    """Main entry point"""
    # Get the l10n directory path
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    l10n_dir = project_root / 'src' / 'ui' / 'flutter_app' / 'lib' / 'l10n'

    if not l10n_dir.exists():
        print(f"❌ Error: l10n directory not found at {l10n_dir}")
        return

    check_arb_order(l10n_dir)


if __name__ == '__main__':
    main()
