#!/bin/bash

# Script to check if all ARB files have the same line count
# This ensures consistency across all localization files

ERROR_COUNT=0
LINE_COUNTS=()

echo "Checking ARB file line counts..."
echo ""

# Get all ARB files and their line counts
for arb_file in intl_*.arb; do
    if [[ ! -f "$arb_file" ]]; then
        continue
    fi

    line_count=$(wc -l < "$arb_file")
    LINE_COUNTS+=("$line_count:$arb_file")
    echo "  $arb_file: $line_count lines"
done

echo ""

# Check if all line counts are the same
if [[ ${#LINE_COUNTS[@]} -eq 0 ]]; then
    echo "❌ ERROR: No ARB files found"
    exit 1
fi

# Extract unique line counts
unique_counts=$(printf '%s\n' "${LINE_COUNTS[@]}" | cut -d: -f1 | sort -u | wc -l)

if [[ $unique_counts -eq 1 ]]; then
    # All files have the same line count
    first_count=$(echo "${LINE_COUNTS[0]}" | cut -d: -f1)
    echo "✅ All ARB files have the same line count: $first_count lines"
    exit 0
else
    # Files have different line counts
    echo "❌ ERROR: ARB files have different line counts!"
    echo ""
    
    # Group files by line count
    declare -A count_map
    for entry in "${LINE_COUNTS[@]}"; do
        count=$(echo "$entry" | cut -d: -f1)
        file=$(echo "$entry" | cut -d: -f2)
        count_map["$count"]="${count_map[$count]} $file"
    done
    
    # Display files grouped by line count
    for count in $(printf '%s\n' "${!count_map[@]}" | sort -n); do
        files="${count_map[$count]}"
        file_count=$(echo "$files" | wc -w)
        echo "  $count lines ($file_count file(s)):"
        for file in $files; do
            echo "    - $file"
        done
        echo ""
    done
    
    ERROR_COUNT=$unique_counts
    echo "❌ Found $ERROR_COUNT different line count(s)"
    exit 1
fi

