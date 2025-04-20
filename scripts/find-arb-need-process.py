#!/usr/bin/env python3
"""
find-arb-need-process.py: Clean entries from a .arb file that are not present in a git diff.

Usage:
    find-arb-need-process.py <git_commit_id> <file.arb>

This script will:
 1. Run `git diff <git_commit_id>` and save the output to diff.patch.
 2. Load the provided .arb file as JSON.
 3. For each translatable entry (key without leading '@'):
    - Check if its string value appears anywhere in diff.patch.
    - If not found, remove both the entry and its metadata (the '@' + key).
 4. Preserve locale metadata (keys starting with '@@').
 5. Write the cleaned JSON to a new file named <original>-cleaned.arb.
"""
import json
import subprocess
import sys
import os


def run_git_diff(commit_id, patch_path="diff.patch"):  # Run git diff and save to file
    """
    Execute `git diff <commit_id>` and write the output (decoded as UTF-8) to diff.patch.
    Falls back to replacing undecodable bytes.
    """
    try:
        # Capture raw bytes output to avoid encoding issues on Windows
        result = subprocess.run(
            ["git", "diff", commit_id],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
    except subprocess.CalledProcessError as e:
        sys.stderr.write(f"Error running git diff: {e.stderr.decode('utf-8', errors='replace')}\n")
        sys.exit(1)

    # Decode diff output, replacing invalid sequences
    try:
        diff_text = result.stdout.decode('utf-8')
    except UnicodeDecodeError:
        diff_text = result.stdout.decode('utf-8', errors='replace')

    # Write to patch file as UTF-8
    with open(patch_path, 'w', encoding='utf-8') as f:
        f.write(diff_text)

    return patch_path


def load_arb(file_path):  # Load arb JSON preserving order
    """
    Load a .arb file as an ordered dictionary.
    """
    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    return data


def clean_arb(data, diff_text):  # Remove entries whose values are not in diff
    """
    Given the original arb data and the diff text, return a new dict
    with only entries whose string values appear in the diff.patch,
    preserving locale metadata.
    """
    cleaned = {}

    for key, value in data.items():
        # Preserve locale metadata keys (e.g., "@@locale")
        if key.startswith('@@'):
            cleaned[key] = value
            continue

        # Skip metadata entries; handle them with their corresponding key
        if key.startswith('@'):
            continue

        # For each translatable string entry, check if its value is in diff
        if isinstance(value, str) and value in diff_text:
            # Keep the entry and its metadata
            cleaned[key] = value
            meta_key = '@' + key
            if meta_key in data:
                cleaned[meta_key] = data[meta_key]
        else:
            # Entry not found in diff; skip it
            sys.stderr.write(f"Removing entry '{key}' with value '{value}'\n")

    return cleaned


def write_cleaned_arb(cleaned_data, original_path):  # Write cleaned JSON back to file
    """
    Write the cleaned arb data to a new file with suffix '-cleaned.arb'.
    """
    base, ext = os.path.splitext(original_path)
    new_path = base + '-cleaned' + ext
    with open(new_path, 'w', encoding='utf-8') as f:
        json.dump(cleaned_data, f, ensure_ascii=False, indent=2)
    print(f"Cleaned .arb file written to: {new_path}")
    return new_path


def main():
    # Validate arguments
    if len(sys.argv) != 3:
        sys.stderr.write("Usage: find-arb-need-process.py <git_commit_id> <file.arb>\n")
        sys.exit(1)

    commit_id = sys.argv[1]
    arb_file = sys.argv[2]

    # Step 1: Generate diff.patch
    patch_file = run_git_diff(commit_id)

    # Step 2: Load diff content
    with open(patch_file, 'r', encoding='utf-8') as f:
        diff_text = f.read()

    # Step 3: Load .arb file
    arb_data = load_arb(arb_file)

    # Step 4: Clean entries
    cleaned_data = clean_arb(arb_data, diff_text)

    # Step 5: Write cleaned .arb
    write_cleaned_arb(cleaned_data, arb_file)


if __name__ == "__main__":
    main()
