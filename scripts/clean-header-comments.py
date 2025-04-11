import os
import sys
import time

# Get the current year
current_year = time.localtime().tm_year

def clean_file_header(file_path):
    """
    Clean up the header of a file by removing:
    1) If the file starts with a block comment (/* ... */) that contains
       the word 'Copyright', remove that entire block as the file header.
    2) Otherwise, if the file starts with multiple lines of // comments,
       remove them as before.
    3) Remove leading blank lines if there is no existing header comment.
    4) If there is a subsequent single line with `// filename.ext` (after
       a blank line), remove it as well to ensure we only keep one filename
       comment (the new one to be added).
    5) Insert a new header comment based on whether the filename contains
       the string 'perfect' or not.
    6) Ensure exactly one blank line before the original file content starts,
       and remove extra blank lines at the end of the file.
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()

        base_filename = os.path.basename(file_path)

        # 1) Check for block comment /* ... */ at the top
        block_comment_found = False
        remove_block_comment = False
        first_non_comment_line_index = 0

        # Skip leading blank lines
        while (first_non_comment_line_index < len(lines) and
               lines[first_non_comment_line_index].strip() == ""):
            first_non_comment_line_index += 1

        # Check if we have "/*" at the top
        if first_non_comment_line_index < len(lines):
            line_strip = lines[first_non_comment_line_index].lstrip()
            if line_strip.startswith("/*"):
                block_comment_found = True
                comment_start_idx = first_non_comment_line_index
                temp_idx = comment_start_idx
                # Collect all lines for this block comment
                block_comment_lines = []
                has_closing = False

                while temp_idx < len(lines):
                    block_comment_lines.append(lines[temp_idx])
                    if "*/" in lines[temp_idx]:
                        has_closing = True
                        break
                    temp_idx += 1

                # If we found a closing "*/", check if this block has 'Copyright'
                if has_closing:
                    block_comment_content = "".join(block_comment_lines)
                    if "Copyright" in block_comment_content:
                        remove_block_comment = True

                if remove_block_comment:
                    # Advance index beyond the block comment
                    first_non_comment_line_index = temp_idx + 1
                else:
                    # Not a recognized header comment
                    block_comment_found = False

        # 2) If no block comment removed, check for top lines of // comments
        if not remove_block_comment:
            start_idx_for_slashes = first_non_comment_line_index
            while (start_idx_for_slashes < len(lines) and
                   lines[start_idx_for_slashes].lstrip().startswith("//")):
                start_idx_for_slashes += 1

            if start_idx_for_slashes > first_non_comment_line_index:
                # Remove these lines
                first_non_comment_line_index = start_idx_for_slashes

        # 3) Remove leading blank lines after comment removal
        cleaned_lines = lines[first_non_comment_line_index:]
        idx = 0
        while idx < len(cleaned_lines) and cleaned_lines[idx].strip() == "":
            idx += 1
        cleaned_lines = cleaned_lines[idx:]

        # 4) If the next line after blank lines is something like `// filename.ext`, remove it.
        #    This ensures we only keep one filename line later (the new one we insert).
        if cleaned_lines:
            line_strip = cleaned_lines[0].lstrip()
            if line_strip.startswith("//"):
                # Extract text after '//'
                content_after_slash = line_strip[2:].strip()
                # If it contains the base filename, we remove it.
                if base_filename in content_after_slash:
                    cleaned_lines.pop(0)
                    # Remove any additional blank lines after popping
                    idx = 0
                    while idx < len(cleaned_lines) and cleaned_lines[idx].strip() == "":
                        idx += 1
                    cleaned_lines = cleaned_lines[idx:]

        # 5) Insert the new header comment
        if 'perfect' in base_filename.lower():
            new_header = [
                "// SPDX-License-Identifier: GPL-3.0-or-later\n",
                "// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner\n",
                f"// Copyright (C) 2019-{current_year} "
                "The Sanmill developers (see AUTHORS file)\n\n",
                f"// {base_filename}\n",
                "\n"  # exactly one blank line after the header
            ]
        else:
            new_header = [
                "// SPDX-License-Identifier: GPL-3.0-or-later\n",
                f"// Copyright (C) 2019-{current_year} "
                "The Sanmill developers (see AUTHORS file)\n\n",
                f"// {base_filename}\n",
                "\n"  # exactly one blank line after the header
            ]

        final_lines = new_header + cleaned_lines

        # 6) Remove trailing empty lines
        while final_lines and final_lines[-1].strip() == "":
            final_lines.pop()

        # Write the final content back to the file
        with open(file_path, 'w', encoding='utf-8') as f:
            f.writelines(final_lines)

        print(f"Successfully cleaned header for: {file_path}")
    except Exception as e:
        print(f"Failed to process file {file_path}: {e}")

def process_directory(directory, extensions):
    """
    Recursively process the specified directory, looking for files
    whose extension matches one of the items in `extensions` and
    cleaning their headers.
    """
    for root, dirs, files in os.walk(directory):
        for file in files:
            # Check if the file ends with any of the allowed extensions
            if any(file.endswith(ext) for ext in extensions):
                file_path = os.path.join(root, file)
                clean_file_header(file_path)

def main():
    """
    Main entry point for the script.

    Usage:
      python3 clean_header_comments.py <directory> [<file_extension>]

    If <file_extension> is provided (e.g., ".c"), the script will only
    process files with that extension. If <file_extension> is not provided,
    the script will process files with the following extensions:
      .h, .cpp, .dart, .m, .swift
    """
    if len(sys.argv) < 2 or len(sys.argv) > 3:
        print("Usage: python3 clean_header_comments.py <directory> [<file_extension>]")
        sys.exit(1)

    directory = sys.argv[1]

    if not os.path.isdir(directory):
        print(f"Error: {directory} is not a valid directory.")
        sys.exit(1)

    # If a single extension is provided, use it; otherwise use defaults
    if len(sys.argv) == 3:
        extension = sys.argv[2]
        extensions = [extension]
    else:
        extensions = [".h", ".cpp", ".dart", ".m", ".swift"]

    process_directory(directory, extensions)

if __name__ == "__main__":
    main()
