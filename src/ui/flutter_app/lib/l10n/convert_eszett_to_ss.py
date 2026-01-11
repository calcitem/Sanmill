#!/usr/bin/env python3
"""
Convert Eszett (ß) to 'ss' in Swiss German ARB File

This script converts all occurrences of the German eszett character (ß) to 'ss'
in the Swiss German (de_CH) ARB file, as Swiss German traditionally uses 'ss'
instead of 'ß'.

Usage:
    python convert_eszett_to_ss.py [--check-only] [--file FILE]

Options:
    --check-only    Only check for ß characters without converting them
    --file FILE     Specify which ARB file to process (default: intl_de_CH.arb)
    
Example:
    python convert_eszett_to_ss.py                    # Convert de_CH file
    python convert_eszett_to_ss.py --check-only       # Only check
    python convert_eszett_to_ss.py --file intl_de.arb # Convert German file
"""

import sys
import argparse
from pathlib import Path


def count_eszett(text):
    """Count occurrences of eszett character."""
    return text.count('ß')


def find_eszett_contexts(text, context_chars=40):
    """Find and return contexts around eszett characters."""
    contexts = []
    lines = text.split('\n')
    
    for line_num, line in enumerate(lines, 1):
        if 'ß' in line:
            # Find all positions of ß in the line
            pos = 0
            while True:
                pos = line.find('ß', pos)
                if pos == -1:
                    break
                
                # Extract context around the character
                start = max(0, pos - context_chars)
                end = min(len(line), pos + context_chars + 1)
                context = line[start:end]
                
                contexts.append({
                    'line': line_num,
                    'position': pos,
                    'context': context,
                    'full_line': line
                })
                pos += 1
    
    return contexts


def convert_eszett_to_ss(text):
    """Replace all ß with ss."""
    return text.replace('ß', 'ss')


def process_file(file_path, check_only=False):
    """Process a single ARB file."""
    print(f"Processing: {file_path.name}")
    
    # Read file
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"  [ERROR] Failed to read file: {e}")
        return False
    
    # Count eszett characters
    eszett_count = count_eszett(content)
    
    if eszett_count == 0:
        print(f"  [OK] No eszett characters found")
        return True
    
    print(f"  Found {eszett_count} eszett character(s)")
    
    # Find contexts
    contexts = find_eszett_contexts(content)
    
    if check_only:
        print(f"  Showing locations:")
        for ctx in contexts:
            # Show line number only (avoid printing eszett in Windows console)
            print(f"    Line {ctx['line']}: Found eszett character")
        return False
    
    # Convert
    converted_content = convert_eszett_to_ss(content)
    
    # Verify conversion
    remaining = count_eszett(converted_content)
    if remaining > 0:
        print(f"  [ERROR] Conversion incomplete: {remaining} eszett characters remain")
        return False
    
    # Save file
    try:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(converted_content)
        print(f"  [OK] Successfully converted {eszett_count} eszett character(s) to 'ss'")
        return True
    except Exception as e:
        print(f"  [ERROR] Failed to save file: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Convert eszett (ß) to 'ss' in Swiss German ARB file"
    )
    parser.add_argument(
        '--check-only',
        action='store_true',
        help='Only check for eszett characters without converting them'
    )
    parser.add_argument(
        '--file',
        type=str,
        default='intl_de_CH.arb',
        help='ARB file to process (default: intl_de_CH.arb)'
    )
    
    args = parser.parse_args()
    
    # Get script directory
    script_dir = Path(__file__).parent
    file_path = script_dir / args.file
    
    if not file_path.exists():
        print(f"[ERROR] File not found: {args.file}")
        sys.exit(1)
    
    print("=" * 60)
    print("Swiss German Eszett to 'ss' Converter")
    print("=" * 60)
    print()
    
    # Process file
    success = process_file(file_path, args.check_only)
    
    print()
    print("=" * 60)
    
    if success:
        if args.check_only:
            print("[SUCCESS] File is valid (no eszett characters)")
        else:
            print("[SUCCESS] Conversion completed successfully")
    else:
        if args.check_only:
            print("[INFO] Eszett characters found (run without --check-only to convert)")
        else:
            print("[ERROR] Conversion failed")
        sys.exit(1)
    
    print("=" * 60)
    print()


if __name__ == '__main__':
    main()
