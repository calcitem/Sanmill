#!/usr/bin/env bash

# Determine the correct sed command based on the system (GNU or BSD)
SED_CMD="sed"
if command -v gsed &>/dev/null; then
    SED_CMD="gsed"
fi

# Initialize variables
arb_filename=""
block=""

# Function to update the ARB file with the new block
update_file() {
    # 1) Remove trailing empty lines
    block=$(echo "$block" | $SED_CMD -e :a -e '/^[[:space:]]*$/{$d;N;ba}')

    # 2) Remove any trailing comma from the last line of block
    block=$(echo "$block" | $SED_CMD '$ s/,[[:space:]]*$//')

    # Check if the target ARB filename is set
    if [[ -z "$arb_filename" ]]; then
        echo "No ARB filename specified. Skipping update."
        return
    fi

    # If the file exists, we will append to it; if not, create a new file.
    if [[ -f "$arb_filename" ]]; then
        tmpfile=$(mktemp)

        # Remove the last line (which should be '}') and store the remainder
        $SED_CMD '$d' "$arb_filename" > "$tmpfile"

        # If tmpfile is not empty, ensure its last line ends with a comma
        if [[ -s "$tmpfile" ]]; then
            last_line=$(tail -n 1 "$tmpfile")
            if [[ "${last_line: -1}" != "," ]]; then
                $SED_CMD -i '$ s/[[:space:]]*$/,/' "$tmpfile"
            fi
        else
            # If empty, write an opening brace for a valid JSON object
            echo "{" > "$tmpfile"
        fi

        # Rebuild ARB file: existing content + block + closing brace
        cat "$tmpfile" > "$arb_filename"
        echo "$block" >> "$arb_filename"
        echo "}" >> "$arb_filename"
        rm "$tmpfile"
    else
        echo "File not found: $arb_filename. Creating a new ARB file."
        {
            echo "{"
            echo "$block"
            echo "}"
        } > "$arb_filename"
    fi
}

# Read lines from new-items.txt
while IFS= read -r line || [[ -n "$line" ]]; do
    # Detect a comment line with the ARB filename, e.g., // intl_en.arb
    if [[ "$line" =~ ^//[[:space:]]*([^[:space:]]+\.arb)$ ]]; then
        if [[ -n "$block" ]]; then
            update_file
            block=""
        fi
        arb_filename="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^[[:space:]]*$ ]]; then
        if [[ -n "$block" ]]; then
            update_file
            block=""
        fi
    else
        block+="$line"$'\n'
    fi
done < "new-items.txt"

# After the loop, if there's a remaining block, update the last ARB file
if [[ -n "$block" ]]; then
    update_file
fi

exit 0
