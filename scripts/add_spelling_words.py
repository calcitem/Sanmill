#!/usr/bin/env python3
"""
Interactive script to add spelling words to expect.txt.
Opens vi editor for user input, then merges words into expect.txt and sorts.
"""

import os
import sys
import tempfile
import subprocess
from pathlib import Path

def get_editor():
    """Get the preferred editor from environment variables."""
    return os.environ.get('EDITOR', 'vi')

def read_file_lines(file_path):
    """Read lines from file, strip whitespace and filter empty lines."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return [line.strip() for line in f if line.strip()]
    except FileNotFoundError:
        print(f"Warning: {file_path} not found, will create new file...")
        return []

def write_file_lines(file_path, lines):
    """Write lines to file with proper line endings."""
    # Ensure directory exists
    file_path.parent.mkdir(parents=True, exist_ok=True)

    with open(file_path, 'w', encoding='utf-8') as f:
        for line in lines:
            f.write(line + '\n')

def open_editor_for_input():
    """Open editor for user to input words, return list of words."""
    # Create temporary file
    with tempfile.NamedTemporaryFile(mode='w+', suffix='.txt', delete=False) as temp_file:
        temp_file.write("# Enter spelling words to add (one per line)\n")
        temp_file.write("# Lines starting with # will be ignored\n")
        temp_file.write("# Save and exit when done\n\n")
        temp_file_path = temp_file.name

    try:
        # Get editor command
        editor = get_editor()

        # Open editor
        print(f"Opening {editor} for word input...")
        print("Enter words to add to expect.txt (one per line)")
        print("Save and exit when done.")

        # Call editor
        result = subprocess.run([editor, temp_file_path], check=True)

        # Read user input
        user_words = []
        with open(temp_file_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith('#'):
                    user_words.append(line)

        return user_words

    except subprocess.CalledProcessError:
        print("Editor was cancelled or failed.")
        return []
    except KeyboardInterrupt:
        print("\nOperation cancelled by user.")
        return []
    finally:
        # Clean up temporary file
        try:
            os.unlink(temp_file_path)
        except OSError:
            pass

def main():
    """Main function to handle the spelling word addition process."""
    print("=== Add Spelling Words to expect.txt ===")

    # Define file paths
    workspace_root = Path(__file__).parent.parent
    expect_file = workspace_root / '.github' / 'actions' / 'spelling' / 'expect.txt'

    print(f"Target file: {expect_file}")

    # Get user input via editor
    new_words = open_editor_for_input()

    if not new_words:
        print("No words entered. Exiting.")
        return

    print(f"Found {len(new_words)} new words:")
    for word in new_words:
        print(f"  - {word}")

    # Read existing expect.txt content
    existing_words = read_file_lines(expect_file)
    print(f"Current expect.txt has {len(existing_words)} words")

                # Combine all words
    all_words = existing_words + new_words

    # Remove exact duplicates (case-sensitive) using set
    unique_words = list(set(all_words))

    # Sort alphabetically (case-insensitive) while preserving exact case
    sorted_words = sorted(unique_words, key=str.lower)

    print(f"Total unique words after merge and deduplication: {len(sorted_words)}")

    # Write back to expect.txt
    write_file_lines(expect_file, sorted_words)

    print(f"Successfully updated {expect_file}")
    print("New words added and file sorted alphabetically!")

if __name__ == "__main__":
    main()
