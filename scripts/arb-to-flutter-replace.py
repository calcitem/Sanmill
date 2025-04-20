#!/usr/bin/env python3
import os
import sys
import json
import re

def load_arb_file(arb_file_path):
    """
    Load the ARB file as a JSON object.
    """
    with open(arb_file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    return data

def get_translation_mapping(arb_data):
    """
    Build a mapping from each translation string (value) to its key,
    excluding entries like '@@locale' and any keys starting with '@'.
    """
    mapping = {}
    for key, value in arb_data.items():
        if key == "@@locale" or key.startswith("@"):
            continue
        mapping[value] = key
    return mapping

def process_dart_file(file_path, translation_mapping, used_texts):
    """
    Read a Dart file, replace occurrences of each translation string (wrapped in double quotes)
    with S.of(context).<key>, using case-insensitive matching.
    Track which texts were replaced and overwrite the file if any replacements occurred.
    """
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    new_content = content
    modified = False

    # For each translation text and its key, replace case-insensitively
    for text, key in translation_mapping.items():
        # compile a regex to match the exact text inside double quotes, ignoring case
        pattern = re.compile(r'"{}"'.format(re.escape(text)), flags=re.IGNORECASE)
        # perform replacement and get the number of substitutions
        new_content, count = pattern.subn(f"S.of(context).{key}", new_content)
        if count > 0:
            used_texts.add(text)
            modified = True

    # if changes occurred, overwrite the file
    if modified:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Modified: {file_path}")

def process_dart_files(directory, translation_mapping, used_texts):
    """
    Recursively traverse the given directory to find all .dart files
    and process them for translation replacements.
    """
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.dart'):
                process_dart_file(os.path.join(root, file), translation_mapping, used_texts)

def main():
    """
    Main entry point:
    1. Read the ARB file path from command-line arguments.
    2. Load the ARB data and build the translation mapping.
    3. Process all Dart files under ../src/ui/flutter_app/lib relative to this script.
    4. Collect any translation entries that were not replaced and write them to unplaced.arb.
    """
    if len(sys.argv) < 2:
        print("Usage: python arb-to-flutter-replace.py <path_to_arb_file>")
        sys.exit(1)

    arb_file_path = sys.argv[1]
    arb_data = load_arb_file(arb_file_path)
    translation_mapping = get_translation_mapping(arb_data)

    # prepare a set to track which texts have been replaced
    used_texts = set()

    # target directory relative to this script's location
    script_dir = os.path.dirname(os.path.abspath(__file__))
    dart_directory = os.path.join(script_dir, "../src/ui/flutter_app/lib")

    process_dart_files(dart_directory, translation_mapping, used_texts)

    # determine which entries were not placed in any Dart file
    unplaced = {}
    for text, key in translation_mapping.items():
        if text not in used_texts:
            unplaced[key] = text
            print(f"Unplaced entry: {key} -> \"{text}\"")

    # write unplaced entries to unplaced.arb
    if unplaced:
        unplaced_path = os.path.join(script_dir, "unplaced.arb")
        with open(unplaced_path, 'w', encoding='utf-8') as f:
            json.dump(unplaced, f, ensure_ascii=False, indent=2)
        print(f"Wrote unplaced entries to {unplaced_path}")

if __name__ == "__main__":
    main()
