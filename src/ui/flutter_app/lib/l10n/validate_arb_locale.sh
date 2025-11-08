#!/bin/bash

# Script to validate that ARB file locale values match their filenames
# This ensures consistency between @@locale values and filename extensions

ERROR_COUNT=0

# Function to extract locale from filename
# Example: intl_de_CH.arb -> de_CH
extract_locale_from_filename() {
    local filename="$1"
    # Remove intl_ prefix and .arb suffix, then extract locale part
    local locale=$(echo "$filename" | sed 's/intl_//' | sed 's/\.arb$//')
    echo "$locale"
}

# Function to extract @@locale value from ARB file
extract_locale_from_file() {
    local file="$1"
    # Extract the @@locale value from line 2 (assuming standard format)
    local locale=$(sed -n '2p' "$file" | grep -oP '"@@locale":\s*"\K[^"]+' || echo "")
    echo "$locale"
}

# Function to normalize locale for comparison
# Convert to lowercase for comparison, but preserve case for display
normalize_locale() {
    local locale="$1"
    echo "$locale" | tr '[:upper:]' '[:lower:]'
}

echo "Validating ARB locale consistency..."
echo ""

# Process all ARB files
for arb_file in intl_*.arb; do
    if [[ ! -f "$arb_file" ]]; then
        continue
    fi

    filename_locale=$(extract_locale_from_filename "$arb_file")
    file_locale=$(extract_locale_from_file "$arb_file")

    if [[ -z "$file_locale" ]]; then
        echo "❌ ERROR: $arb_file - Could not extract @@locale value"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        continue
    fi

    # Normalize both for comparison (case-insensitive)
    normalized_filename=$(normalize_locale "$filename_locale")
    normalized_file=$(normalize_locale "$file_locale")

    if [[ "$normalized_filename" != "$normalized_file" ]]; then
        echo "❌ MISMATCH: $arb_file"
        echo "   Filename locale: $filename_locale"
        echo "   File @@locale:   $file_locale"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    else
        # Check if case matches exactly (for proper locale format)
        if [[ "$filename_locale" != "$file_locale" ]]; then
            echo "⚠️  CASE MISMATCH: $arb_file"
            echo "   Filename locale: $filename_locale"
            echo "   File @@locale:   $file_locale"
            echo "   (Values match case-insensitively, but case differs)"
        fi
    fi
done

echo ""
if [[ $ERROR_COUNT -eq 0 ]]; then
    echo "✅ All ARB files have consistent locale values!"
    exit 0
else
    echo "❌ Found $ERROR_COUNT error(s)"
    exit 1
fi

