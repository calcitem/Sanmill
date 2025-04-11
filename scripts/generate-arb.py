import os
import re
import json

# Define the Flutter project directory
project_dir = '../src/ui/flutter_app/lib'  # Replace with your project path

# Regular expression to match string literals (single or double quotes)
# This pattern captures the quote symbol in group(1) and the inner text in group(2).
string_pattern = re.compile(r'''(['"])(.*?)\1''')

# A precise pattern to check if a string is used with S.of(context)
# For example: S.of(context).someKey("Your String")
# Explanation:
#   1) S\.of\(context\)\.    -> matches S.of(context).
#   2) \w+                   -> matches the method/key name (like someKey)
#   3) \(                    -> matches the opening parenthesis
#   4) \s*(["'])(.*?)\1\s*   -> matches a quoted string inside parentheses (with possible spaces)
#   5) \)                    -> matches the closing parenthesis
localized_call_pattern = r"S\.of\(context\)\.\w+\(\s*(['\"])(.*?)\1\s*\)"
compiled_localized_call_pattern = re.compile(localized_call_pattern)


def remove_comments(content):
    """
    Remove single-line (//) and block (/* */) comments from Dart file content.
    
    :param content: The original file content as a string.
    :return: The content with comments removed.
    """
    content_no_single = re.sub(r'//.*', '', content)  # Remove single-line comments
    content_no_comments = re.sub(r'/\*[\s\S]*?\*/', '', content_no_single)  # Remove block comments
    return content_no_comments


def extract_strings(file_path):
    """
    Extract all string literals from a Dart file after removing comments.
    Also return the line number and the line text for each literal.
    Skip empty strings.
    
    :param file_path: Path to the Dart file.
    :return: A tuple (list of (string literal, line number, line text) tuples,
                      the cleaned file content,
                      list of all cleaned lines).
    """
    with open(file_path, 'r', encoding='utf-8') as file:
        content = file.read()

    # Remove comments to avoid extracting strings from commented-out code
    cleaned_content = remove_comments(content)
    lines = cleaned_content.splitlines()
    extracted = []  # List of tuples: (string literal, line number, line text)
    for i, line in enumerate(lines):
        for match in string_pattern.finditer(line):
            literal = match.group(2)
            if literal.strip():
                extracted.append((literal, i, line))
    return extracted, cleaned_content, lines


def is_localized(string_literal, file_content):
    """
    Check if a given string literal is used inside a localized call,
    such as: S.of(context).someMethod("string_literal").
    
    :param string_literal: The extracted string literal.
    :param file_content: The entire file content as a string.
    :return: True if the string is found inside a localized call pattern, False otherwise.
    """
    escaped_str = re.escape(string_literal)  # Escape the string literal for safe regex use
    pattern = re.compile(
        rf"S\.of\(context\)\.\w+\(\s*(['\"]){escaped_str}\1\s*\)"
    )
    return bool(pattern.search(file_content))


def to_lower_camel_case(text):
    """
    Convert a given text to lowerCamelCase.
    Non-alphanumeric characters are removed.
    
    :param text: The original text.
    :return: The text converted to lowerCamelCase.
    """
    words = re.findall(r'\w+', text)
    if not words:
        return ""
    first_word = words[0].lower()
    other_words = [word.capitalize() for word in words[1:]]
    return first_word + "".join(other_words)


def generate_arb(unlocalized_strings):
    """
    Generate a dictionary representing ARB file contents from unlocalized strings.
    The key for each string is generated using lowerCamelCase, and the metadata is an empty object.
    
    :param unlocalized_strings: A collection of unlocalized string literals.
    :return: A JSON-compatible dictionary representing the ARB data.
    """
    arb_data = {
        "@@locale": "en",  # Default locale is English
    }
    for string in unlocalized_strings:
        key = to_lower_camel_case(string)  # Convert to lowerCamelCase
        arb_data[key] = string
        arb_data[f"@{key}"] = {}
    return arb_data


def main():
    """
    Main entry point of the script:
      1) Clear the contents of unlocalized_strings.arb if the file exists.
      2) Traverse the project directory and find all .dart files.
      3) Skip directories that contain "generated" in the path.
      4) Skip files whose filename contains "localization" (case-insensitive) or ".g.".
      5) Extract string literals from each file (after removing comments) along with their line number and text.
      6) Filter out strings based on various conditions (length, content, and context).
         For context, a combined string is created from the current line and the previous line (if available)
         and checked for the presence of any unwanted keywords.
      7) Check if each string is unlocalized.
      8) Generate an ARB file with the remaining unlocalized strings.
    """
    arb_filename = 'unlocalized_strings.arb'
    # Clear the ARB file content if it exists (or create a new empty file)
    with open(arb_filename, 'w', encoding='utf-8') as f:
        f.write("")

    unlocalized_strings = set()  # Use a set to avoid duplicates

    # Define a unified list of keywords (all in lowercase) to check in current or previous line.
    unified_keywords = [
        "logger", "print", "exception", "_handle", "error", "ruleset", "environmentconfig",
        "suffix", "no moves yet", "sanmill", "throw", "place to", "Step", "Quick Jump"
    ]

    # Traverse the project directory and process only Dart files
    for root, _, files in os.walk(project_dir):
        # Skip directories that contain "generated" (case-insensitive)
        if "generated" in root.lower():
            continue
        for file in files:
            # Skip files whose filename contains "localization" (case-insensitive) or ".g."
            if "localization" in file.lower() or ".g." in file:
                continue
            if file.endswith('.dart'):
                file_path = os.path.join(root, file)
                extracted, cleaned_content, lines = extract_strings(file_path)
                for s, lineno, line in extracted:
                    # Filter out strings containing any of these characters: - _ * $ [ ] /
                    if any(char in s for char in "-_*$[]/"):
                        continue
                    # Skip if the string is purely numeric or purely alphabetic
                    if s.isdigit() or s.isalpha():
                        continue
                    # Skip if string length is <= 2
                    if len(s) <= 2:
                        continue
                    # Skip if the string contains the word "null" (case-insensitive)
                    if "null" in s.lower():
                        continue
                    # Skip if string has >= 2 uppercase letters and no spaces
                    if (sum(1 for c in s if c.isupper()) >= 2) and (" " not in s):
                        continue
                    # Skip if string is all uppercase
                    if s.isupper():
                        continue
                    # Skip if string is all lowercase
                    if s.islower():
                        continue
                    # Skip if string consists entirely of symbols (no alphanumeric characters)
                    if not any(c.isalnum() for c in s):
                        continue
                    # Skip if string ends with a space
                    if s.endswith(" "):
                        continue
                    # Skip if the string does not contain any letter (A-Z or a-z)
                    if not re.search(r'[A-Za-z]', s):
                        continue
                    # Create a combined string from the current line and the previous line (if available)
                    combined_line = line.lower()
                    if lineno > 0:
                        combined_line += " " + lines[lineno - 1].lower()
                    # If any unified keyword is present in the combined line, skip the string.
                    if any(keyword in combined_line for keyword in unified_keywords):
                        continue
                    # Check if the string is unlocalized
                    if not is_localized(s, cleaned_content):
                        unlocalized_strings.add(s)

    # Generate ARB file if any unlocalized strings remain
    if unlocalized_strings:
        arb_data = generate_arb(unlocalized_strings)
        with open(arb_filename, 'w', encoding='utf-8') as arb_file:
            json.dump(arb_data, arb_file, ensure_ascii=False, indent=2)
        print(f"ARB file generated: {arb_filename}")
    else:
        print("No unlocalized strings found. ARB file not generated.")


if __name__ == '__main__':
    main()