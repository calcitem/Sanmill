#!/usr/bin/env python3
"""
Script to merge allow.txt into expect.txt and sort alphabetically.
This consolidates all spelling exceptions into the expect.txt file.
"""

import os
from pathlib import Path

def read_file_lines(file_path):
    """Read lines from file, strip whitespace and filter empty lines."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return [line.strip() for line in f if line.strip()]
    except FileNotFoundError:
        print(f"Warning: {file_path} not found, skipping...")
        return []

def write_file_lines(file_path, lines):
    """Write lines to file with proper line endings."""
    with open(file_path, 'w', encoding='utf-8') as f:
        for line in lines:
            f.write(line + '\n')

def main():
    # Define file paths
    spelling_dir = Path('../.github/actions/spelling')
    allow_file = spelling_dir / 'allow.txt'
    expect_file = spelling_dir / 'expect.txt'

    print("Merging spelling configuration files...")

    # Read existing content from both files
    allow_words = read_file_lines(allow_file)
    expect_words = read_file_lines(expect_file)

    print(f"Found {len(allow_words)} words in allow.txt")
    print(f"Found {len(expect_words)} words in expect.txt")

    # Combine and deduplicate words
    all_words = set(allow_words + expect_words)

    # Sort alphabetically (case-insensitive)
    sorted_words = sorted(all_words, key=str.lower)

    print(f"Total unique words after merge: {len(sorted_words)}")

    # Write sorted words to expect.txt
    write_file_lines(expect_file, sorted_words)
    print(f"Updated {expect_file}")

    # Clear allow.txt (keep file but make it empty)
    write_file_lines(allow_file, [])
    print(f"Cleared {allow_file}")

    print("Merge completed successfully!")

if __name__ == "__main__":
    main()
