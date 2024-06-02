#!/bin/bash

# Determine the correct sed command based on the system (GNU or BSD)
SED_CMD="sed"
if command -v gsed &>/dev/null; then
    SED_CMD="gsed"
fi

# Initialize variables
filename=""
block=""

# Function to update the ARB file with the new block
update_file() {
    if [[ -n "$filename" && -f "$filename" ]]; then
        # Prepare the block for insertion
        # Remove any trailing comma at the end of the block
        block=$(echo "$block" | $SED_CMD '$ s/,\s*$//')

        # Remove the trailing comma before the last }
        block=$(echo "$block" | $SED_CMD '$ s/,\s*}/}/')

        # Use sed to add a comma to the last '}' on a line by itself, then add the new block
        $SED_CMD -i -e '$ s/}/},/' "$filename"
        echo "$block" >> "$filename"
        echo "}" >> "$filename"  # Add back the closing brace

        # Remove any line that is just "},"
        $SED_CMD -i '/^},$/d' "$filename"

        # Add comma to line ending with {} if necessary
        $SED_CMD -i '/^{[^}]*}$/!b;n;s/}$/},/' "$filename"

        # Check for lines ending with {} and add comma if necessary
        awk '
        {
            if (prev_line ~ /\{\}$/ && $0 != "}") {
                sub(/\{\}$/, "{},", prev_line)
            }
            if (NR > 1) {
                print prev_line
            }
            prev_line = $0
        }
        END {
            print prev_line
        }
        ' "$filename" > "${filename}.tmp" && mv "${filename}.tmp" "$filename"

        # Remove the trailing comma before the final closing brace if it exists
        $SED_CMD -i '$s/},/}/' "$filename"

        # Remove any comma before a single closing brace
        $SED_CMD -i '$!N;/,\n}/s/,//' "$filename"
    else
        echo "File not found: $filename"
    fi
}

# Read lines from new-items.txt
while IFS= read -r line; do
    # Detect and process file name
    if [[ "$line" =~ ^//[[:space:]]*([^[:space:]]+\.arb)$ ]]; then
        # If there is a pending update, perform it
        if [[ -n "$block" ]]; then
            # Remove trailing comma from the block before updating the file
            block=$(echo "$block" | $SED_CMD '$ s/,\s*$//')
            update_file
            # Reset block for the next section
            block=""
        fi
        # Set new filename from the comment
        filename="${BASH_REMATCH[1]}"
    elif [[ -z "$line" ]]; then  # Empty line
        # If line is empty and block is not, update the file
        if [[ -n "$block" ]]; then
            # Remove trailing comma from the block before updating the file
            block=$(echo "$block" | $SED_CMD '$ s/,\s*$//')
            update_file
            # Reset block after update
            block=""
        fi
    else  # Line is part of the content block
        # Accumulate lines to form the block
        block+="$line"$'\n'  # Add newline after each line
    fi
done < "new-items.txt"

# Handle the last block if it exists
if [[ -n "$block" ]]; then
    # Remove trailing comma from the block before updating the file
    block=$(echo "$block" | $SED_CMD '$ s/,\s*$//')
    update_file
fi
