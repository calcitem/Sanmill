#!/usr/bin/env python3
"""
Script to remove unwanted words from expect.txt.
Removes specified words and keeps the file sorted.
"""

from pathlib import Path

def read_file_lines(file_path):
    """Read lines from file, strip whitespace and filter empty lines."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return [line.strip() for line in f if line.strip()]
    except FileNotFoundError:
        print(f"Warning: {file_path} not found")
        return []

def write_file_lines(file_path, lines):
    """Write lines to file with proper line endings."""
    with open(file_path, 'w', encoding='utf-8') as f:
        for line in lines:
            f.write(line + '\n')

def main():
    """Main function to remove unwanted words from expect.txt."""
    print("=== Remove Unwanted Words from expect.txt ===")

    # Define file paths
    workspace_root = Path(__file__).parent.parent
    expect_file = workspace_root / '.github' / 'actions' / 'spelling' / 'expect.txt'

    # Words to be removed (from the check-spelling report)
    words_to_remove = {
        'alignas', 'alignof', 'appium', 'args', 'asm', 'async', 'bitand', 'bitor',
        'bool', 'compl', 'const', 'consteval', 'constinit', 'covariant', 'cygwin',
        'decltype', 'enum', 'equired', 'extern', 'foreach', 'goto', 'helloworld',
        'https', 'int', 'json', 'mixin', 'namespace', 'noexcept', 'nullptr',
        'patchlevel', 'Pfrome', 'plugins', 'reflexpr', 'rethrow', 'SHe', 'SIs',
        'sizeof', 'struct', 'SUr', 'typedef', 'typeid', 'typename', 'unregister',
        'ushort', 'var', 'wchar', 'xfile', 'xor'
    }

    print(f"Target file: {expect_file}")
    print(f"Words to remove: {len(words_to_remove)}")

    # Read existing content
    existing_words = read_file_lines(expect_file)
    print(f"Current expect.txt has {len(existing_words)} words")

    # Filter out unwanted words (case-sensitive comparison)
    filtered_words = []
    removed_words = []

    for word in existing_words:
        if word in words_to_remove:
            removed_words.append(word)
        else:
            filtered_words.append(word)

    # Sort the remaining words alphabetically (case-insensitive)
    sorted_words = sorted(filtered_words, key=str.lower)

    print(f"Removed {len(removed_words)} words:")
    for word in sorted(removed_words):
        print(f"  - {word}")

    print(f"Remaining words: {len(sorted_words)}")

    # Write back to expect.txt
    write_file_lines(expect_file, sorted_words)

    print(f"Successfully updated {expect_file}")
    print("Unwanted words removed and file sorted alphabetically!")

if __name__ == "__main__":
    main()
