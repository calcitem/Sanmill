#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
find_files_with_cjk.py

Recursively search a directory for files containing CJK characters (e.g., Chinese, Japanese, Korean).
Allows customization of encodings, included/excluded directories and file extensions, and verbose logging.
If include options are provided, they take precedence over exclusion settings.
Prints each matching file and the list of line numbers where CJK characters occur.
"""

import os
import re
import argparse
import logging
import sys

# Pattern to match CJK Unified Ideographs (Chinese, Japanese, Korean)
CJK_PATTERN = re.compile(r'[\u4e00-\u9fff]')


def setup_logging(verbose: bool):
    """Configure logging level and format."""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format='%(asctime)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )


def get_cjk_line_numbers(file_path: str, encodings: list[str]) -> list[int]:
    """
    Return a list of line numbers that contain CJK characters in the given file.

    Tries each encoding in order. Reads the file line by line to identify exact lines
    with CJK characters. Uses 'errors=strict' to skip invalid encodings.
    """
    for encoding in encodings:
        try:
            line_nums = []
            with open(file_path, 'r', encoding=encoding, errors='strict') as f:
                for i, line in enumerate(f, start=1):
                    if CJK_PATTERN.search(line):
                        logging.debug(
                            "Found CJK on line %d in '%s' using encoding '%s'",
                            i, file_path, encoding
                        )
                        line_nums.append(i)
            # Return list if any CJK lines found
            return line_nums
        except (UnicodeDecodeError, LookupError):
            logging.debug("Failed to decode '%s' with encoding '%s'", file_path, encoding)
            continue
        except Exception as e:
            logging.warning("Error reading '%s': %s", file_path, e)
            return []
    # All encodings failed or no lines detected
    return []


def find_files_with_cjk(
    root_dir: str,
    encodings: list[str],
    include_dirs: list[str],
    exclude_dirs: list[str],
    include_exts: list[str],
    exclude_exts: list[str]
) -> int:
    """
    Recursively search for files containing CJK characters,
    with include/exclude directory and extension filters.

    If include_dirs is non-empty, only those directories are searched (exclusions ignored).
    If include_exts is non-empty, only those file extensions are checked (exclusions ignored).
    Prints each matching file path once with its sorted line numbers.
    Returns count of files found.
    """
    total_found = 0
    for dirpath, dirnames, filenames in os.walk(root_dir):
        # Filter directories based on include/exclude settings
        if include_dirs:
            dirnames[:] = [d for d in dirnames if d in include_dirs]
        else:
            dirnames[:] = [d for d in dirnames if d not in exclude_dirs]

        for fname in filenames:
            ext = os.path.splitext(fname)[1].lower()
            # Filter file extensions
            if include_exts:
                if ext not in include_exts:
                    continue
            elif ext in exclude_exts:
                continue

            path = os.path.join(dirpath, fname)
            # Skip non-regular files and symbolic links
            if not os.path.isfile(path) or os.path.islink(path):
                continue

            # Retrieve line numbers with CJK characters
            lines = get_cjk_line_numbers(path, encodings)
            if lines:
                total_found += 1
                # Print file path once with comma-separated line numbers
                unique_lines = sorted(set(lines))
                line_list = ', '.join(str(num) for num in unique_lines)
                print(f"{path}: lines {line_list}")
    return total_found


def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Search for files containing CJK characters and print line numbers."
    )
    parser.add_argument(
        "directory",
        help="Directory to search"
    )
    parser.add_argument(
        "-e", "--encodings",
        nargs='+',
        default=["utf-8", "gbk", "big5"],
        help="List of encodings to try (default: utf-8 gbk big5)"
    )
    parser.add_argument(
        "-i", "--include-dirs",
        nargs='+',
        default=[],
        help="List of directory names to include (takes precedence over excludes)"
    )
    parser.add_argument(
        "-x", "--exclude-dirs",
        nargs='+',
        default=[".git", "__pycache__", "node_modules"],
        help="Directories to exclude from search"
    )
    parser.add_argument(
        "-I", "--include-exts",
        nargs='+',
        default=[],
        help="File extensions to include (takes precedence over excludes, e.g. .txt .md)"
    )
    parser.add_argument(
        "-X", "--exclude-exts",
        nargs='+',
        default=[
            ".png", ".jpg", ".jpeg", ".gif", ".zip",
            ".exe", ".dll", ".pdf", ".mp4", ".avi"
        ],
        help="File extensions to skip"
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Enable verbose debug logging"
    )
    return parser.parse_args()


def main():
    args = parse_args()
    setup_logging(args.verbose)

    root = os.path.abspath(args.directory)
    if not os.path.isdir(root):
        logging.error("Invalid directory: %s", root)
        sys.exit(1)

    logging.info("Searching directory: %s", root)
    found = find_files_with_cjk(
        root,
        encodings=args.encodings,
        include_dirs=args.include_dirs,
        exclude_dirs=args.exclude_dirs,
        include_exts=[e.lower() for e in args.include_exts],
        exclude_exts=[e.lower() for e in args.exclude_exts]
    )

    if found:
        logging.info("Found %d file(s) containing CJK characters.", found)
    else:
        logging.info("No files containing CJK characters were found.")


if __name__ == "__main__":
    main()
