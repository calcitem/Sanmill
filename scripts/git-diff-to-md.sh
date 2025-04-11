#!/bin/bash

# Script name: git-diff-to-md.sh
# Purpose: Extract full file paths from git diff and generate a diff-files.md with contents of .dart, .cpp, or .h files.

# Check if a commit ID is provided as an argument
if [ -z "$1" ]; then
    echo "Error: No commit ID provided."
    echo "Usage: $0 <Git Commit ID>"
    exit 1
fi

commit_id=$1

# Get the root directory of the Git repository
repo_root=$(git rev-parse --show-toplevel)
if [ $? -ne 0 ]; then
    echo "Error: Not in a Git repository."
    exit 1
fi

# Run git diff --stat to get the summary of changes
diff_stat_output=$(git diff "$commit_id" --stat)
if [ $? -ne 0 ]; then
    echo "Error: git diff --stat failed. Please check the commit ID."
    exit 1
fi

# Run git diff --name-only to get the full paths of modified files
diff_name_output=$(git diff "$commit_id" --name-only)
if [ $? -ne 0 ]; then
    echo "Error: git diff --name-only failed. Please check the commit ID."
    exit 1
fi

# Extract file paths from --stat output (for matching purposes, even if truncated)
stat_files=$(echo "$diff_stat_output" | grep '|' | awk -F' \\|' '{print $1}' | sed 's/^[ \t]*//;s/[ \t]*$//')

# Filter files from --stat that end with .dart, .cpp, or .h
stat_filtered_files=$(echo "$stat_files" | grep -E '\.(dart|cpp|h)$')

# Create or overwrite diff-files.md to start fresh
> diff-files.md

# Process each file from --stat output and match with full paths from --name-only
echo "$stat_filtered_files" | while read -r stat_file; do
    # Since stat_file might be truncated (e.g., .../file.dart), find the matching full path from --name-only
    # Use grep to match the ending part of the path (assuming unique file names within the repo)
    full_file=$(echo "$diff_name_output" | grep -E "$stat_file$" | head -n 1)
    
    if [ -n "$full_file" ]; then
        # Construct the full path using the repository root
        full_path="$repo_root/$full_file"
        
        # Verify that the file exists
        if [ -f "$full_path" ]; then
            # Extract the file extension to determine the language identifier
            extension="${full_file##*.}"
            case "$extension" in
                dart)
                    language="dart"
                    ;;
                cpp|h)
                    language="cpp"
                    ;;
            esac
            
            # Append the formatted content to diff-files.md
            echo "$full_file" >> diff-files.md
            echo "" >> diff-files.md          # Add blank line between filename and code block
            echo "\`\`\`$language" >> diff-files.md
            cat "$full_path" >> diff-files.md
            echo "\`\`\`" >> diff-files.md
            echo "" >> diff-files.md
        else
            echo "Warning: File $full_file does not exist at $full_path."
        fi
    else
        echo "Warning: Could not find full path for $stat_file in git diff --name-only output."
    fi
done

echo "Output written to diff-files.md"