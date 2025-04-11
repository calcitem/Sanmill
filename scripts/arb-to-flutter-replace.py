#!/usr/bin/env python3
import os
import sys
import json

def load_arb_file(arb_file_path):
    """
    Load the ARB file as a JSON object.
    """
    with open(arb_file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    return data

def get_translation_mapping(arb_data):
    """
    Build a dictionary mapping each translation string (value) to its key,
    excluding special entries like '@@locale' and keys starting with '@'.
    """
    mapping = {}
    for key, value in arb_data.items():
        if key == "@@locale" or key.startswith("@"):
            continue
        mapping[value] = key
    return mapping

def process_dart_file(file_path, translation_mapping):
    """
    Read a Dart file, replace occurrences of each translation string (wrapped in double quotes)
    with S.of(context).<key>, and write the changes back if any replacements occurred.
    """
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    new_content = content
    # Replace each translation string (with double quotes) with the corresponding S.of(context).<key>
    for text, key in translation_mapping.items():
        # Search for the string enclosed in double quotes
        quoted_text = f'"{text}"'
        if quoted_text in new_content:
            new_content = new_content.replace(quoted_text, f"S.of(context).{key}")
    
    # If any replacements were made, update the file
    if new_content != content:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Modified: {file_path}")

def process_dart_files(directory, translation_mapping):
    """
    Recursively traverse the directory to find Dart files and process them.
    """
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.dart'):
                file_path = os.path.join(root, file)
                process_dart_file(file_path, translation_mapping)

def main():
    """
    Main entry point:
    1. Parse the ARB file from command-line argument.
    2. Build the translation mapping.
    3. Process all Dart files in the target directory.
    """
    if len(sys.argv) < 2:
        print("Usage: python arb-to-flutter-replace.py <path_to_arb_file>")
        sys.exit(1)
    
    arb_file_path = sys.argv[1]
    arb_data = load_arb_file(arb_file_path)
    translation_mapping = get_translation_mapping(arb_data)
    
    # Define the target directory relative to this script's location
    dart_directory = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../src/ui/flutter_app/lib")
    
    process_dart_files(dart_directory, translation_mapping)

if __name__ == "__main__":
    main()