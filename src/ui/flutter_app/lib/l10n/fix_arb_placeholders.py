#!/usr/bin/env python3
"""
Fix ARB Placeholder Metadata

This script automatically fixes missing placeholder metadata in ARB translation files
by copying the metadata from the English (intl_en.arb) file.

Usage:
    python fix_arb_placeholders.py [--check-only] [--file FILE]

Options:
    --check-only    Only check for issues without fixing them
    --file FILE     Only process the specified ARB file
    
Example:
    python fix_arb_placeholders.py                    # Fix all ARB files
    python fix_arb_placeholders.py --check-only       # Check all files
    python fix_arb_placeholders.py --file intl_de.arb # Fix only German file
"""

import json
import sys
import os
import argparse
from pathlib import Path


def load_arb_file(file_path):
    """Load ARB file and return parsed JSON data."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return json.loads(f.read())
    except Exception as e:
        print(f"Error loading {file_path}: {e}")
        return None


def save_arb_file(file_path, data):
    """Save ARB data to file with proper formatting."""
    try:
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=4)
        return True
    except Exception as e:
        print(f"Error saving {file_path}: {e}")
        return False


def find_keys_with_missing_metadata(arb_data):
    """Find keys that have placeholders but missing or empty metadata."""
    problematic_keys = []
    
    for key in arb_data:
        if key.startswith('@'):
            continue
        
        meta_key = '@' + key
        text = str(arb_data[key])
        
        # Check if text has placeholders
        if '{' in text and '}' in text:
            # Check if metadata is missing or empty
            if meta_key not in arb_data or arb_data[meta_key] == {}:
                problematic_keys.append(key)
            # Also check if metadata exists but missing placeholders field
            elif meta_key in arb_data and 'placeholders' not in arb_data[meta_key]:
                # Check if it really needs placeholders (not just {count,plural,...})
                # Extract placeholder names
                import re
                placeholders = re.findall(r'\{(\w+)(?:,|\})', text)
                if placeholders:
                    problematic_keys.append(key)
    
    return problematic_keys


def fix_arb_file(file_path, en_data, check_only=False):
    """Fix missing placeholder metadata in an ARB file."""
    arb_data = load_arb_file(file_path)
    if arb_data is None:
        return False
    
    problematic_keys = find_keys_with_missing_metadata(arb_data)
    
    if not problematic_keys:
        print(f"  [OK] No issues found")
        return True
    
    print(f"  Found {len(problematic_keys)} keys with missing metadata:")
    
    if check_only:
        for key in problematic_keys[:10]:
            text = str(arb_data[key])[:60]
            print(f"    - {key}: {text}...")
        if len(problematic_keys) > 10:
            print(f"    ... and {len(problematic_keys) - 10} more")
        return False
    
    # Fix the issues
    fixed_count = 0
    for key in problematic_keys:
        meta_key = '@' + key
        
        # Copy metadata from English file if available
        if meta_key in en_data and en_data[meta_key] != {}:
            arb_data[meta_key] = en_data[meta_key]
            fixed_count += 1
            print(f"    [+] Fixed: {key}")
        else:
            print(f"    [-] No metadata in English file for: {key}")
    
    if fixed_count > 0:
        if save_arb_file(file_path, arb_data):
            print(f"  [OK] Successfully fixed {fixed_count} keys")
            return True
        else:
            print(f"  [FAIL] Failed to save file")
            return False
    else:
        print(f"  [WARN] No keys were fixed")
        return False


def main():
    parser = argparse.ArgumentParser(
        description='Fix missing placeholder metadata in ARB translation files'
    )
    parser.add_argument(
        '--check-only',
        action='store_true',
        help='Only check for issues without fixing them'
    )
    parser.add_argument(
        '--file',
        type=str,
        help='Only process the specified ARB file'
    )
    
    args = parser.parse_args()
    
    # Get script directory
    script_dir = Path(__file__).parent
    
    # Load English ARB file as reference
    en_file = script_dir / 'intl_en.arb'
    print(f"Loading reference file: {en_file}")
    en_data = load_arb_file(en_file)
    
    if en_data is None:
        print("Error: Cannot load English ARB file")
        sys.exit(1)
    
    # Get list of ARB files to process
    if args.file:
        arb_files = [script_dir / args.file]
        if not arb_files[0].exists():
            print(f"Error: File not found: {args.file}")
            sys.exit(1)
    else:
        # Process all ARB files except English
        arb_files = sorted(script_dir.glob('intl_*.arb'))
        arb_files = [f for f in arb_files if f.name != 'intl_en.arb']
    
    print(f"\n{'Checking' if args.check_only else 'Processing'} {len(arb_files)} ARB file(s)...\n")
    
    # Process each file
    results = {}
    for arb_file in arb_files:
        print(f"Processing: {arb_file.name}")
        success = fix_arb_file(arb_file, en_data, args.check_only)
        results[arb_file.name] = success
        print()
    
    # Print summary
    print("=" * 60)
    print("SUMMARY")
    print("=" * 60)
    
    ok_files = [f for f, s in results.items() if s]
    issue_files = [f for f, s in results.items() if not s]
    
    if ok_files:
        print(f"\n[OK] Valid files ({len(ok_files)}):")
        for f in ok_files:
            print(f"  - {f}")
    
    if issue_files:
        print(f"\n[ISSUES] Files with issues ({len(issue_files)}):")
        for f in issue_files:
            print(f"  - {f}")
        
        if args.check_only:
            print("\nRun without --check-only to fix the issues.")
            sys.exit(1)
    else:
        if not args.check_only:
            print("\n[SUCCESS] All files processed successfully!")
        else:
            print("\n[SUCCESS] All files are valid!")
    
    print()


if __name__ == '__main__':
    main()
