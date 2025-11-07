#!/usr/bin/env python3
"""
Script to normalize the entry order of ARB files to match intl_en.arb

This script reorders all keys in ARB files to match the order in the
reference file (intl_en.arb), while preserving all values and metadata.
Files are saved with 4-space indentation.
"""

import json
import os
from pathlib import Path
from typing import Dict, Any, List
from collections import OrderedDict


def load_arb_file(file_path: Path) -> Dict[str, Any]:
    """
    Load ARB file and preserve key order

    Args:
        file_path: Path to the ARB file

    Returns:
        Dictionary with preserved key order
    """
    with open(file_path, 'r', encoding='utf-8') as f:
        # Use object_pairs_hook to preserve order
        return json.load(f, object_pairs_hook=OrderedDict)


def save_arb_file(file_path: Path, data: Dict[str, Any]) -> None:
    """
    Save ARB file with proper formatting (4-space indentation)

    Args:
        file_path: Path to save the ARB file
        data: ARB data to save
    """
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=4)
        # Add newline at end of file
        f.write('\n')


def normalize_arb_file(
    arb_file_path: Path,
    reference_keys: List[str],
    dry_run: bool = False
) -> bool:
    """
    Normalize the key order of an ARB file to match reference order

    Args:
        arb_file_path: Path to the ARB file to normalize
        reference_keys: List of keys in the desired order
        dry_run: If True, don't write changes to disk

    Returns:
        True if file was modified, False otherwise
    """
    # Load the ARB file
    arb_data = load_arb_file(arb_file_path)
    original_keys = list(arb_data.keys())

    # Create a new ordered dictionary with keys in reference order
    normalized_data = OrderedDict()

    # First, add all keys that exist in both reference and current file
    # in the order they appear in reference
    for key in reference_keys:
        if key in arb_data:
            normalized_data[key] = arb_data[key]

    # Then, add any keys that exist in current file but not in reference
    # (append them at the end to avoid losing data)
    for key in original_keys:
        if key not in normalized_data:
            normalized_data[key] = arb_data[key]

    # Check if order changed
    changed = (list(normalized_data.keys()) != original_keys)

    if changed and not dry_run:
        # Save the normalized file
        save_arb_file(arb_file_path, normalized_data)
        print(f"✅ Normalized: {arb_file_path.name}")
    elif not changed:
        print(f"⏭️  No change needed: {arb_file_path.name}")
    else:
        print(f"🔍 Would normalize: {arb_file_path.name}")

    return changed


def normalize_all_arb_files(
    l10n_dir: Path,
    reference_file: str = 'intl_en.arb',
    dry_run: bool = False
) -> None:
    """
    Normalize all ARB files in the directory to match reference order

    Args:
        l10n_dir: Directory containing ARB files
        reference_file: Name of the reference ARB file
        dry_run: If True, don't write changes to disk
    """
    # Load reference file
    reference_path = l10n_dir / reference_file
    if not reference_path.exists():
        print(f"❌ Error: Reference file {reference_file} not found!")
        return

    reference_data = load_arb_file(reference_path)
    reference_keys = list(reference_data.keys())

    print(f"📋 Reference file: {reference_file}")
    print(f"📊 Total keys in reference: {len(reference_keys)}")
    if dry_run:
        print(f"🔍 DRY RUN MODE - No files will be modified\n")
    else:
        print(f"✏️  WRITE MODE - Files will be modified\n")

    # Find all ARB files
    arb_files = sorted(l10n_dir.glob('intl_*.arb'))

    files_modified = 0
    files_unchanged = 0
    files_processed = 0

    for arb_file in arb_files:
        if arb_file.name == reference_file:
            print(f"⏭️  Skipping reference file: {arb_file.name}")
            continue  # Skip reference file

        files_processed += 1
        changed = normalize_arb_file(arb_file, reference_keys, dry_run)

        if changed:
            files_modified += 1
        else:
            files_unchanged += 1

    # Summary
    print(f"\n{'='*60}")
    print(f"Summary:")
    print(f"  Total files processed: {files_processed}")
    print(f"  Files modified: {files_modified}")
    print(f"  Files unchanged: {files_unchanged}")

    if dry_run and files_modified > 0:
        print(f"\n💡 This was a dry run. Run without --dry-run to apply changes.")
    elif files_modified > 0:
        print(f"\n✨ Successfully normalized {files_modified} file(s)!")
    else:
        print(f"\n🎉 All files already have the correct order!")


def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(
        description='Normalize ARB file entry order to match intl_en.arb'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Preview changes without modifying files'
    )

    args = parser.parse_args()

    # Get the l10n directory path
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    l10n_dir = project_root / 'src' / 'ui' / 'flutter_app' / 'lib' / 'l10n'

    if not l10n_dir.exists():
        print(f"❌ Error: l10n directory not found at {l10n_dir}")
        return

    normalize_all_arb_files(l10n_dir, dry_run=args.dry_run)


if __name__ == '__main__':
    main()
