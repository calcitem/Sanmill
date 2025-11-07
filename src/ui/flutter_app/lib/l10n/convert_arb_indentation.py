#!/usr/bin/env python3
"""
Convert ARB file indentation from 2 spaces to 4 spaces.

This script processes all ARB files in the l10n directory and converts their
indentation from 2 spaces to 4 spaces while preserving the JSON structure.
"""

import json
import os
import glob
from pathlib import Path


def convert_arb_indentation(file_path, indent_size=4):
    """
    Convert the indentation of an ARB file.

    Args:
        file_path: Path to the ARB file
        indent_size: Number of spaces for indentation (default: 4)
    """
    try:
        # Read the original file
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)

        # Write back with new indentation
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=indent_size, ensure_ascii=False)
            # Add newline at the end of file
            f.write('\n')

        print(f"✓ Converted: {os.path.basename(file_path)}")
        return True
    except Exception as e:
        print(f"✗ Error processing {file_path}: {e}")
        return False


def main():
    """Main function to process all ARB files."""
    # Get the directory where this script is located
    script_dir = Path(__file__).parent

    # Find all ARB files in the current directory
    arb_files = glob.glob(str(script_dir / "*.arb"))

    if not arb_files:
        print("No ARB files found in the current directory.")
        return

    print(f"Found {len(arb_files)} ARB files to convert...")
    print("-" * 60)

    success_count = 0
    fail_count = 0

    for arb_file in sorted(arb_files):
        if convert_arb_indentation(arb_file):
            success_count += 1
        else:
            fail_count += 1

    print("-" * 60)
    print(f"Conversion complete: {success_count} succeeded, {fail_count} failed")


if __name__ == "__main__":
    main()
