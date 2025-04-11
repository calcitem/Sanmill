##!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Merge various source files (C/C++, Python, Swift, Go, Objective-C, Dart, Shell, Perl, etc.)
into a single file. It removes the leading copyright block comment (if present)
and inserts a filename comment at the top of each file. Then, it adds an 80-character
commented separator line (matching the file's comment style) between files.

Example usage:
  python merge_files.py \
    --input ./src \
    --output merged_output.c \
    --ext h c cpp

  python merge_files.py \
    --paths file1.c file2.c ./another/*.c \
    --output merged_output.c \
    --ext c

Features and improvements:
  - Support multiple languages and corresponding comment styles.
  - Insert an 80-character comment line between files, matching the file's comment style.
  - Support passing either a directory (recursive) or multiple file paths/globs.
  - Robust error handling and logging.
  - Configurable log level and optional log file output.
  - Extensible filtering: skip files, skip directories, or specify custom extensions.
  - Simplified but resilient reading of source files in UTF-8 (with fallback).
  - Clear structure and docstrings to facilitate maintenance and expansion.
"""

import os
import sys
import argparse
import logging
from logging import handlers
from typing import List, Optional
import glob

# -----------------------------------------------------------------------------
# Global Defaults / Constants
# -----------------------------------------------------------------------------
DEFAULT_LOG_LEVEL = "INFO"

# For C/C++, Python, Swift, Go, Objective-C(m), Dart, Shell(sh), Perl(pl), etc.
SUPPORTED_EXTENSIONS = [
    "h", "c", "cpp",  # C/C++
    "py",             # Python
    "swift",          # Swift
    "go",             # Go
    "m",              # Objective-C
    "dart",           # Dart
    "sh",             # Shell
    "pl"              # Perl
]

# If needed, configure the subdirectories to skip
SKIP_DIRS = []

# Map different file extensions to the corresponding comment prefix
COMMENT_PREFIX_MAP = {
    "h": "//",
    "c": "//",
    "cpp": "//",
    "hpp": "//",    # Add if needed
    "m": "//",      # Objective-C
    "swift": "//",
    "go": "//",
    "dart": "//",
    "py": "#",
    "sh": "#",
    "pl": "#",
}

# -----------------------------------------------------------------------------
# Usage Function
# -----------------------------------------------------------------------------
def usage():
    """
    Display detailed usage instructions for this script in English.
    """
    usage_text = r"""
Usage:
    python merge_files.py --input <directory_path> --output <merged_output> [--ext ext1 ext2 ...]
        Recursively collects source files from the specified directory and merges them into <merged_output>.

    python merge_files.py --paths <file_path1> <file_path2> [...] --output <merged_output> [--ext ext1 ext2 ...]
        Collects source files from the given file paths or glob patterns and merges them into <merged_output>.

Options:
    --input <directory_path>
        Path to the input directory (recursive). Optional.

    --paths <file_path1> <file_path2> [...]
        Multiple file paths or glob patterns. Optional.

    --output <merged_output>
        Path to the merged output file. Required.

    --ext <ext1> <ext2> ...
        List of file extensions (without dot) to scan.
        Default is a predefined list of supported extensions.

    --log-level <level>
        Log level (DEBUG, INFO, WARNING, ERROR). Default is INFO.

    --log-file <log_file_path>
        Optional path to a log file. If not set, only stdout is used.

    --skip-dir <dir1> <dir2> ...
        Directories to skip, e.g., build, dist.

Description:
    This script merges various source files (.h, .c, .cpp, .py, .swift, .go, .m, .dart, .sh, .pl, etc.)
    into a single file, removing leading copyright headers (if present) and adding filename
    comments at the top of each file. It also inserts an 80-character commented separator line
    (matching the file's comment style) between files.

Examples:
    python merge_files.py --input ./src --output merged_output.c --ext h c cpp
    python merge_files.py --paths file1.c file2.c ./another/*.c --output merged_output.c --ext c
"""
    print(usage_text)


# -----------------------------------------------------------------------------
# Logging Setup
# -----------------------------------------------------------------------------
def setup_logger(log_level: str, log_file: Optional[str] = None) -> logging.Logger:
    """
    Configure and return a logger for this script.
    """
    logger = logging.getLogger("merge_files")
    logger.setLevel(getattr(logging, log_level.upper(), logging.INFO))

    # Console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(getattr(logging, log_level.upper(), logging.INFO))
    console_format = logging.Formatter(
        '[%(asctime)s] %(levelname)s - %(name)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    console_handler.setFormatter(console_format)
    logger.addHandler(console_handler)

    if log_file:
        file_handler = handlers.RotatingFileHandler(
            log_file, maxBytes=1_000_000, backupCount=3
        )
        file_handler.setLevel(getattr(logging, log_level.upper(), logging.INFO))
        file_format = logging.Formatter(
            '%(asctime)s [%(levelname)s] %(name)s - %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        file_handler.setFormatter(file_format)
        logger.addHandler(file_handler)

    return logger


# -----------------------------------------------------------------------------
# Utility Functions
# -----------------------------------------------------------------------------
def get_comment_prefix(ext: str) -> str:
    """
    Return the comment prefix for a given file extension.
    Default to '//' if the extension is unrecognized.
    """
    return COMMENT_PREFIX_MAP.get(ext.lower(), "//")


def get_separator_line(ext: str) -> str:
    """
    Return an 80-character comment line that uses the
    comment prefix for the specified extension.
    For example, if prefix = "//", the total line length will be 80 characters.
    """
    prefix = get_comment_prefix(ext)
    # Calculate how many '/' are needed to fill to ensure total length is 80
    prefix_len = len(prefix)
    # In some scripts, you can add a space after the comment symbol, e.g., "# ".
    # For strictly 80, we skip the space here.
    num_slashes = 80 - prefix_len
    if num_slashes < 1:
        # Defensive check to ensure there is at least 1 '/'
        num_slashes = 1
    return prefix + ("/" * num_slashes) + "\n"


def is_source_file(filename: str, valid_ext: List[str]) -> bool:
    """
    Determine if a file is considered a source file by matching its extension.
    """
    ext = os.path.splitext(filename.lower())[1].lstrip(".")
    return ext in valid_ext


def remove_leading_copyright(lines: List[str]) -> List[str]:
    """
    Remove the first block of comment lines if it contains 'Copyright'.
    """
    processed = []
    i = 0
    n = len(lines)

    block_comment_lines = []
    comment_block_detected = False

    # Detect the top comment block
    while i < n:
        line_stripped = lines[i].strip()
        if (line_stripped.startswith('//') or
            line_stripped.startswith('/*') or
            line_stripped.startswith('*') or
            line_stripped.startswith('*/') or
            line_stripped.startswith('#')):
            comment_block_detected = True
            block_comment_lines.append(lines[i])
            i += 1
        else:
            break

    if comment_block_detected:
        # Discard this block if it contains 'Copyright'
        has_copyright = any('copyright' in ln.lower() for ln in block_comment_lines)
        if not has_copyright:
            processed.extend(block_comment_lines)

    # Append the remainder of the file
    while i < n:
        processed.append(lines[i])
        i += 1

    return processed


def ensure_filename_comment(lines: List[str], filename: str, ext: str) -> List[str]:
    """
    Insert a comment line at the top indicating the filename if it isn't already present.
    """
    prefix = get_comment_prefix(ext)
    expected_comment_line = f'{prefix} {filename}\n'

    if not lines:
        return [expected_comment_line, '\n']

    first_line_stripped = lines[0].strip().lower()
    if first_line_stripped == (prefix + " " + filename).lower():
        # Already has the comment line
        return lines
    else:
        return [expected_comment_line, '\n'] + lines


def safe_read_lines(file_path: str, logger: logging.Logger) -> List[str]:
    """
    Read lines from a file in UTF-8. If a decoding error occurs, retry with 'replace'.
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return f.readlines()
    except UnicodeDecodeError:
        logger.warning("UnicodeDecodeError encountered. Retrying read in 'replace' mode: %s", file_path)
        try:
            with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
                return f.readlines()
        except Exception as e:
            logger.error("Failed to read file '%s' even in 'replace' mode: %s", file_path, e)
            return []
    except OSError as e:
        logger.error("Failed to read file '%s': %s", file_path, e)
        return []


def safe_write_lines(file_path: str, lines: List[str], logger: logging.Logger) -> None:
    """
    Write lines to the specified file in UTF-8.
    """
    try:
        with open(file_path, 'w', encoding='utf-8') as out:
            out.writelines(lines)
    except OSError as e:
        logger.error("Failed to write to file '%s': %s", file_path, e)
        raise


def collect_source_files_in_dir(
    root_dir: str,
    valid_ext: List[str],
    skip_dirs: Optional[List[str]],
    logger: logging.Logger
) -> List[str]:
    """
    Recursively collect all source files under root_dir that match `valid_ext`.
    Optionally skip directories listed in `skip_dirs`.
    """
    all_files = []
    for current_root, dirs, files in os.walk(root_dir):
        # If certain subdirectories need to be skipped
        if skip_dirs:
            dirs[:] = [d for d in dirs if d not in skip_dirs]

        for f in files:
            if is_source_file(f, valid_ext):
                full_path = os.path.join(current_root, f)
                all_files.append(full_path)

    all_files.sort()
    logger.info("Found %d source files under directory '%s'.", len(all_files), root_dir)
    return all_files


def collect_source_files_from_paths(
    paths: List[str],
    valid_ext: List[str],
    skip_dirs: Optional[List[str]],
    logger: logging.Logger
) -> List[str]:
    """
    Collect source files from a list of paths or glob patterns.
    Each path could be:
      - a directory (then we recurse like collect_source_files_in_dir)
      - a single file
      - a glob pattern
    Returns a sorted list of matching source files.
    """
    results = []
    for p in paths:
        expanded = glob.glob(p, recursive=True) if ("*" in p or "?" in p) else [p]
        if not expanded:
            logger.warning("No matches found for pattern/path: %s", p)
            continue

        for item in expanded:
            if os.path.isdir(item):
                # Recursively process the directory
                results.extend(collect_source_files_in_dir(item, valid_ext, skip_dirs, logger))
            else:
                if os.path.isfile(item):
                    if is_source_file(item, valid_ext):
                        results.append(os.path.abspath(item))
                else:
                    logger.warning("Path is not a file or directory: %s", item)

    # Remove duplicates
    results = list(set(results))
    results.sort()
    logger.info("Collected %d files from paths.", len(results))
    return results


def merge_files(source_files: List[str], output_file: str, logger: logging.Logger) -> None:
    """
    Merge the collected source files into one output file.
    For each file:
      - Remove the leading copyright statement.
      - Insert a "prefix filename" comment at the top.
      - Then append file contents.
      - If it's not the last file, insert a separator line.
    """
    merged_lines = []
    file_count = 0
    total_files = len(source_files)

    for idx, src_path in enumerate(source_files):
        filename = os.path.basename(src_path)
        ext = os.path.splitext(filename.lower())[1].lstrip(".")
        lines = safe_read_lines(src_path, logger)
        if not lines:
            logger.warning("Skipping empty/unreadable file: %s", src_path)
            continue

        # Remove the leading copyright statement
        lines = remove_leading_copyright(lines)
        # Insert a filename comment
        lines = ensure_filename_comment(lines, filename, ext)

        # Append the file contents to merged_lines
        merged_lines.extend(lines)

        # If it's not the last file, insert a separator line
        if idx < total_files - 1:
            merged_lines.append("\n")
            merged_lines.append(get_separator_line(ext))
            merged_lines.append("\n")

        file_count += 1

    # Write the merged content to the output file
    safe_write_lines(output_file, merged_lines, logger)
    logger.info("Merged %d files into '%s'.", file_count, output_file)


# -----------------------------------------------------------------------------
# Main Entrypoint
# -----------------------------------------------------------------------------
def main():
    """
    Main entry point for the merge_files script.
    """
    parser = argparse.ArgumentParser(
        description=(
            'Merge specified source files (.h, .c, .cpp, .py, .swift, .go, .m, '
            '.dart, .sh, .pl, etc.) into a single file, removing leading '
            'copyright headers and adding filename comments.'
        )
    )
    parser.add_argument('--input', default=None,
                        help='Path to the input directory (recursive). Optional.')
    parser.add_argument('--paths', nargs='*', default=[],
                        help='Multiple file paths or glob patterns. Optional.')
    parser.add_argument('--output', required=True,
                        help='Path to the merged output file.')
    parser.add_argument('--ext', nargs='*', default=SUPPORTED_EXTENSIONS,
                        help='List of file extensions (without dot) to scan.')
    parser.add_argument('--log-level', default=DEFAULT_LOG_LEVEL,
                        help='Log level (DEBUG, INFO, WARNING, ERROR). Default is INFO.')
    parser.add_argument('--log-file', default=None,
                        help='Optional path to a log file. If not set, only stdout is used.')
    parser.add_argument('--skip-dir', nargs='*', default=SKIP_DIRS,
                        help='Directories to skip (e.g., build, dist).')

    # If you want to display our custom usage when no arguments are given:
    if len(sys.argv) < 2:
        usage()
        sys.exit(1)

    args = parser.parse_args()

    # Setup logger
    logger = setup_logger(args.log_level, args.log_file)

    # Collect files
    all_source_files = []

    # If an input directory is specified, recursively gather files
    if args.input:
        if not os.path.isdir(args.input):
            logger.error("Input directory '%s' does not exist or is not a directory.", args.input)
            sys.exit(1)
        dir_files = collect_source_files_in_dir(
            root_dir=args.input,
            valid_ext=args.ext,
            skip_dirs=args.skip_dir,
            logger=logger
        )
        all_source_files.extend(dir_files)

    # If specific file paths or globs are specified, handle them
    if args.paths:
        path_files = collect_source_files_from_paths(
            paths=args.paths,
            valid_ext=args.ext,
            skip_dirs=args.skip_dir,
            logger=logger
        )
        all_source_files.extend(path_files)

    # Remove duplicates and sort
    all_source_files = list(set(all_source_files))
    all_source_files.sort()

    # Exit if no files were collected
    if not all_source_files:
        logger.warning("No source files found. Exiting.")
        sys.exit(0)

    # Merge
    merge_files(all_source_files, args.output, logger)


if __name__ == "__main__":
    main()
